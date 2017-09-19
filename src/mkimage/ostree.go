package main

import (
	"fmt"
	"os"
	"os/exec"
	"time"

	log "github.com/sirupsen/logrus"
)

// ComposeOstree repo base on the generated rootfs
func ComposeOstree() error {
	log.Infof("Processing rootfs for ostree usage")
	// Need to adjust the rootfs to meet ostree needs
	copy, err := exec.LookPath("cp")
	if err != nil {
		log.Errorf("Could not find cp tool: %v", err)
		return err
	}
	commandLine := []string{"-rf", rootfsDir + "/etc", rootfsDir + "/usr/"}
	cmd := exec.Command(copy, commandLine...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Errorf("failed to copy etc files, %v", err)
		return err
	}

	delete, err := exec.LookPath("rm")
	if err != nil {
		log.Errorf("Could not find rm tool: %v", err)
		return err
	}
	commandLine = []string{"-rf", rootfsDir + "/etc"}
	cmd = exec.Command(delete, commandLine...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Errorf("failed to delete etc directory, %v", err)
		return err
	}

	csumSh := rootDir + "tools/ostree/update_rootfs.sh"
	cmd = exec.Command("/bin/sh", csumSh, rootfsDir)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Errorf("failed to update kernel and initrd file names, %v", err)
		return err
	}

	err = os.MkdirAll(ostreeRepo, 0766)
	if err != nil {
		log.Errorf("Could not create ostree repo directory: %v", err)
		return err
	}

	ostree, err := exec.LookPath("ostree")
	if err != nil {
		log.Errorf("Could not find ostree tool: %v", err)
		return err
	}

	log.Infof("Initialize ostree repo")
	commandLine = []string{"--repo=" + ostreeRepo, "init", "--mode=archive-z2"}
	cmd = exec.Command(ostree, commandLine...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Errorf("Could not initialize ostree repo, %v", err)
		return err
	}

	log.Infof("ostree commit rootfs....")
	now := time.Now()
	year, mon, day := now.Date()
	hour, min, sec := now.Clock()
	tagTime := fmt.Sprintf("%d%02d%02d_%02d%02d%02d", year, mon, day, hour, min, sec)
	commandLine = []string{"--repo=" + ostreeRepo, "commit", "--branch=euleros-antos-host/2/x86_64/standard",
		"--add-metadata-string=version=En-CloudOSversion-" + tagTime, "--tree=dir=" + rootfsDir}
	cmd = exec.Command(ostree, commandLine...)
	cmd.Stderr = os.Stderr
	cmd.Stdout = os.Stdout
	err = cmd.Run()
	if err != nil {
		log.Errorf("Could not run ostree commit: %v", err)
		return err
	}

	return nil
}
