package main

import (
	"bufio"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	log "github.com/sirupsen/logrus"
)

var (
	rootDir       string
	rootfsDir     string
	cacheDir      = "/var/yum/cache"
	yumConf       string
	yumRepo       string
	createYumRepo = false
	ostreeRepo    string
	supportedImg  = "iso"
	haveOstree    = false
	buildLock     string
)

func signalListen() {
	c := make(chan os.Signal)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	for {
		sig := <-c
		cleanUp()
		log.Fatalf("Get signal: %v", sig)
	}
}

// Process the build arguments and execute build
func build(configFile string, outputType string, BaseDir string) {
	var err error
	var config []byte
	var rootfs AddonRootfs

	// Only one building instance is allowed in one compose project
	buildLock = BaseDir + "/../" + ".lock"
	_, err = os.Stat(buildLock)
	if err == nil {
		cleanUp()
		log.Fatalf("Please check %s, another building process is in progress, abort!!", buildLock)
	}

	// Create the lock file
	_, err = os.Create(buildLock)
	if err != nil {
		cleanUp()
		log.Fatalf("Could not create lock file, exiting.")
	}

	// Signal handling
	go signalListen()

	// Convert final config file to byte stream
	config, err = ioutil.ReadFile(configFile)
	if err != nil {
		cleanUp()
		log.Fatalf("Cannot open config file: %s, err: %v", configFile, err)
	}

	// extract product name so as to generate specific image name
	fileName := filepath.Base(configFile)
	prodName := strings.Replace(fileName, ".yml", "", 1)

	// Parse final yaml configuration file
	rootfs, err = NewAddonConfig(config)
	if err != nil {
		cleanUp()
		log.Fatalf("Invalid config: %v", err)
	}

	// sanity check the output image type
	if len(outputType) == 0 && len(rootfs.Outputs) == 0 {
		log.Fatal("Output image type is not specified")
	} else if len(outputType) == 0 && len(rootfs.Outputs) != 0 {
		outputType = rootfs.Outputs[0]
	}
	if strings.Contains(supportedImg, outputType) == false {
		cleanUp()
		log.Fatalf("Unsupported image type, supported is: %s", supportedImg)
	}
	log.Infof("output type: %s", outputType)

	// Initialize the global variables
	baseyml := BaseDir + "/../config/" + rootfs.InitRootfs.File
	rootDir = BaseDir + "/../"
	rootfsDir = rootDir + "rootfs-tmp"
	ostreeRepo = rootDir + "repo"
	var baseroot BaseRootfs
	var baseconfig []byte

	// Convert base config file to byte stream
	baseconfig, err = ioutil.ReadFile(baseyml)
	if err != nil {
		cleanUp()
		log.Fatalf("Cannot open config file: %s, err: %v", baseyml, err)
	}

	// Parse base yaml configuration file
	baseroot, err = NewBaseConfig(baseconfig)
	if err != nil {
		cleanUp()
		log.Fatalf("Invalid config: %v", err)
	}

	// create YUM conf file
	err = createYumconf()
	if err != nil {
		cleanUp()
		log.Fatalf("Could not create Yum config file: %v", err)
	}

	// Compose base rootfs by installing configured rpm packages
	err = composeBaseRootfs(baseroot)
	if err != nil {
		cleanUp()
		log.Fatalf("Could not compose base rootfs: %v, %v", baseroot, err)
	}

	// additional rpm packages added to the base rootfs
	err = composeFinalRootfs(rootfs)
	if err != nil {
		cleanUp()
		log.Fatalf("Could not compose final rootfs: %v, %v", rootfs, err)
	}

	// Cleanup yum cache
	err = yumCleanCache()
	if err != nil {
		cleanUp()
		log.Fatalf("Cleanup yum cache failed: %v", err)
	}

	var cmdline string
	if rootfs.Kernel.Cmdline != "" {
		cmdline = rootfs.Kernel.Cmdline
	} else {
		cmdline = baseroot.Kernel.Cmdline
	}

	// Generate OS images
	if haveOstree {
		err = ComposeOstree()
		if err != nil {
			cleanUp()
			log.Fatalf("Compose ostree failed")
		}

		err = OutputOstreeImage(prodName, cmdline)
		if err != nil {
			cleanUp()
			log.Fatalf("Generate ostree image failed")
		}
	}

	// do some cleanup work
	cleanUp()
}

func composeBaseRootfs(baseroot BaseRootfs) error {
	err := os.MkdirAll(rootfsDir, 0766)
	if err != nil {
		log.Infof("Could not create rootfs directory [%s]: %v", rootfsDir, err)
		return err
	}

	log.Infof("Yum install packages for baserootfs...")
	pkgList := append(baseroot.AddPackages, "kernel")
	err = yumInstallPkg(pkgList)
	if err != nil {
		log.Infof("Yum install packages failed: %v", err)
		return err
	}

	err = appendRootfs(baseroot.Files.Add)
	if err != nil {
		log.Infof("append file to base rootfs failed: %v", err)
		return err
	}

	err = tailorBaseRootfs(baseroot)
	if err != nil {
		log.Infof("Tailor base rootfs failed: %v", err)
		return err
	}

	return nil
}

func tailorBaseRootfs(rootfs BaseRootfs) error {
	log.Infof("Begin to tailor base rootfs")
	// chroot to rootfs environment
	root, err := os.Open("/")
	defer root.Close()
	if err != nil {
		log.Infof("Failed to open root dir: %v", err)
		return err
	}

	err = syscall.Chroot(rootfsDir)
	if err != nil {
		log.Infof("Failed to chroot to %s, err: %v", rootfsDir, err)
		return err
	}

	// uninstall rpm packages
	rpm, err := exec.LookPath("rpm")
	if err != nil {
		log.Infof("Failed to find rpm tool: %v", err)
		return err
	}
	var rpmlist string
	for _, pkg := range rootfs.RmPackages {
		cmd := exec.Command(rpm, "-qa")
		stdout, err := cmd.StdoutPipe()
		defer stdout.Close()
		_ = cmd.Start()
		output, err := ioutil.ReadAll(stdout)
		if err != nil {
			log.Infof("Failed to getcommand output: %v", err)
			return err
		}
		rpmlist = string(output)

		// Filter the non-existed rpm packages
		if strings.Contains(rpmlist, pkg) == false {
			continue
		}
		commandLine := []string{"-e", "--nodeps", pkg}
		cmd = exec.Command(rpm, commandLine...)
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not uninstall package: %s, %v", pkg, err)
			return err
		}
	}

	// extract kernel version in case kernel module tailoring
	out, err := exec.Command("rpm", "-q", "kernel").Output()
	if err != nil {
		log.Infof("Failed to execute kernel rpm search command: %v", err)
		return err
	}
	kversion := string(out)
	kversion = strings.Replace(kversion, "kernel-", "", 1)
	kversion = strings.Replace(kversion, "\n", "", -1)

	// delete files and directories
	remove, err := exec.LookPath("rm")
	if err != nil {
		log.Infof("Failed to find rm tool: %v", err)
		return err
	}
	for _, file := range rootfs.Files.Remove {
		// convert kernel module wildcard path to correct path
		if strings.Contains(file, ".*") == true {
			file = strings.Replace(file, ".*", kversion, 1)
		}

		commandLine := []string{"-rf", file}
		cmd := exec.Command(remove, commandLine...)
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not delete file: %s, %v", file, err)
			return err
		}
	}

	// exit the chroot environment
	err = root.Chdir()
	if err != nil {
		log.Infof("Failed to Chdir: %v", err)
		return err
	}
	err = syscall.Chroot(".")
	if err != nil {
		log.Infof("Failed to chroot back: %v", err)
		return err
	}

	return nil
}

func composeFinalRootfs(rootfs AddonRootfs) error {
	log.Infof("Yum install packages for Finalrootfs...")
	err := yumInstallPkg(rootfs.AddPackages)
	if err != nil {
		log.Infof("Yum install packages failed: %v", err)
		return err
	}

	for _, feature := range rootfs.Features {
		var pkgList []string
		fileName := rootDir + "features/" + feature + ".conf"
		fd, err := os.Open(fileName)
		defer fd.Close()
		if err != nil {
			log.Infof("Could not open file: %v", err)
			return err
		}

		buf := bufio.NewReader(fd)
		for {
			line, err := buf.ReadString('\n')
			if err != nil {
				if err == io.EOF {
					break
				}
				return err
			}
			line = strings.Replace(line, "\n", "", -1)
			pkgList = append(pkgList, line)
		}

		err = yumInstallPkg(pkgList)
		if err != nil {
			log.Infof("Yum install packages failed: %s, %v", pkgList, err)
			return err
		}

		if feature == "ostree" {
			haveOstree = true
		}
	}

	err = appendRootfs(rootfs.Files.Add)
	if err != nil {
		log.Infof("append file to final rootfs failed: %v", err)
		return err
	}

	err = tailorFinalRootfs(rootfs)
	if err != nil {
		log.Infof("Tailor final rootfs failed: %v", err)
		return err
	}

	return nil
}

func appendRootfs(fileList [][]string) error {
	log.Infof("append files to rootfs: %s", fileList)
	for _, file := range fileList {
		cmd := exec.Command("cp", file[0], rootfsDir+file[1])
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err := cmd.Run()
		if err != nil {
			log.Infof("Could not append files: %v", err)
			return err
		}
	}
	return nil
}

// There are much redundant codes between tailorBaseRootfs and tailorFinalRootfs, need to
// optimize in the future.
func tailorFinalRootfs(rootfs AddonRootfs) error {
	log.Infof("Begin to tailor final rootfs")
	// chroot to rootfs environment
	root, err := os.Open("/")
	defer root.Close()
	if err != nil {
		log.Infof("Failed to open root dir: %v", err)
		return err
	}

	err = syscall.Chroot(rootfsDir)
	if err != nil {
		log.Infof("Failed to chroot to %s, err: %v", rootfsDir, err)
		return err
	}

	// Remove unneeded locale data from /usr/lib/locale (only keep en_US.utf8) so as to save space
	cmd := exec.Command("/bin/sh", "-c", `localedef --list-archive | grep -v -i ^en_US.utf8 | xargs localedef --delete-from-archive`)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Start()
	cmd.Run()
	cmd.Wait()
	cmd = exec.Command("/bin/sh", "-c", `mv /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl`)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Infof("Could not move locale file: %v", err)
		return err
	}
	cmd = exec.Command("/bin/sh", "-c", `build-locale-archive`)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		log.Infof("Could not build locale archive: %v", err)
		return err
	}

	// Remove unneeded locale data from /usr/share/locale
	keepLocale := "en_US zh_CN"
	dirList, err := ioutil.ReadDir("/usr/share/locale")
	if err != nil {
		log.Infof("Could not get directory list from locale: %v", err)
		return err
	}
	for _, dir := range dirList {
		if strings.Contains(keepLocale, dir.Name()) == true {
			continue
		}
		cmd = exec.Command("rm", "-rf", "/usr/share/locale/"+dir.Name())
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not delete directory: %s %v", dir.Name(), err)
			return err
		}
	}

	// uninstall rpm packages
	rpm, err := exec.LookPath("rpm")
	if err != nil {
		log.Infof("Failed to find rpm tool: %v", err)
		return err
	}

	var rpmlist string
	for _, pkg := range rootfs.RmPackages {
		cmd := exec.Command(rpm, "-qa")
		stdout, err := cmd.StdoutPipe()
		defer stdout.Close()
		_ = cmd.Start()
		output, err := ioutil.ReadAll(stdout)
		if err != nil {
			log.Infof("Failed to getcommand output: %v", err)
			return err
		}
		rpmlist = string(output)

		// Filter the non-existed rpm packages
		if strings.Contains(rpmlist, pkg) == false {
			continue
		}
		commandLine := []string{"-e", "--nodeps", pkg}
		cmd = exec.Command(rpm, commandLine...)
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not uninstall package: %s, %v", pkg, err)
			return err
		}
	}

	// extract kernel version in case kernel module tailoring
	out, err := exec.Command(rpm, "-q", "kernel").Output()
	if err != nil {
		log.Infof("Failed to execute kernel rpm search command: %v", err)
		return err
	}
	kversion := string(out)
	kversion = strings.Replace(kversion, "kernel-", "", 1)
	kversion = strings.Replace(kversion, "\n", "", -1)

	// delete files and directories
	remove, err := exec.LookPath("rm")
	if err != nil {
		log.Infof("Failed to find rm tool: %v", err)
		return err
	}

	for _, file := range rootfs.Files.Remove {
		// convert kernel module wildcard path to correct path
		if strings.Contains(file, ".*") == true {
			file = strings.Replace(file, ".*", kversion, 1)
		}

		commandLine := []string{"-rf", file}
		cmd := exec.Command(remove, commandLine...)
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not delete file: %s, %v", file, err)
			return err
		}
	}

	// exit the chroot environment
	err = root.Chdir()
	if err != nil {
		log.Infof("Failed to Chdir: %v", err)
		return err
	}
	err = syscall.Chroot(".")
	if err != nil {
		log.Infof("Failed to chroot back: %v", err)
		return err
	}

	return nil
}

func yumInstallPkg(pkgList []string) error {
	yum, err := exec.LookPath("yum")
	if err != nil {
		log.Infof("Could not find yum tool: %v", err)
		return err
	}

	for _, pkg := range pkgList {
		commandLine := []string{"install", "-y", "--config=" + yumConf, "--installroot=" + rootfsDir, pkg}
		cmd := exec.Command(yum, commandLine...)
		cmd.Stderr = os.Stderr
		cmd.Stdout = os.Stdout
		err = cmd.Run()
		if err != nil {
			log.Infof("Could not install package: %s, %v", pkg, err)
			return err
		}
		os.RemoveAll(rootfsDir + rootDir)
	}

	return nil
}

// Clean up yum cache
func yumCleanCache() error {
	yum, err := exec.LookPath("yum")
	if err != nil {
		log.Infof("Could not find yum tool: %v", err)
		return err
	}
	commandLine := []string{"--config=" + yumConf, "--installroot=" + rootfsDir, "clean", "all"}
	cmd := exec.Command(yum, commandLine...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Infof("Clean up yum cache failed: %v", err)
		return err
	}

	os.RemoveAll(rootfsDir + cacheDir)

	return nil
}

func cleanUp() {
	os.RemoveAll(rootfsDir)
	os.Remove(yumConf)
	if createYumRepo {
		os.Remove(yumRepo)
	}
	os.Remove(ostreeRepo)
	os.Remove(buildLock)
}

func createYumconf() error {
	yumRepo = filepath.Join(rootDir, "isula.repo")
	// Create isula.repo if not existed
	_, err := os.Stat(yumRepo)
	if err != nil && os.IsNotExist(err) {
		out, err := os.Create(yumRepo)
		if err != nil {
			return err
		}
		out.WriteString("[base]\n")
		out.WriteString("name=base\n")
		out.WriteString("baseurl=" + *repoAddr + "\n")
		out.WriteString("enable=1\n")
		out.WriteString("gpgcheck=0\n")

		createYumRepo = true
	}

	yumConf = filepath.Join(rootDir, "yum.conf")
	out, err := os.Create(yumConf)
	if err != nil {
		return err
	}

	out.WriteString("[main]\n")
	out.WriteString("cachedir=" + cacheDir + "\n")
	out.WriteString("reposdir=" + rootDir + "\n")
	out.WriteString("http_caching=none\n")
	out.WriteString("keepcache=0\n")
	out.WriteString("debuglevel=2\n")
	out.WriteString("pkgpolicy=newest\n")
	out.WriteString("tolerant=1\n")
	out.WriteString("exactarch=1\n")
	out.WriteString("obsoletes=1\n")
	out.WriteString("plugins=0\n")
	out.WriteString("deltarpm=0\n")
	out.WriteString("metadata_expire=1800\n")

	return nil
}
