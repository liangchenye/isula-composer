package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	log "github.com/sirupsen/logrus"
)

var (
	defaultLogFormatter = &log.TextFormatter{}
	// BaseDir represents the working directory
	BaseDir  string
	repoAddr *string
)

// infoFormatter overrides the default format for Info() log events to
// provide an easier to read output
type infoFormatter struct {
}

func (f *infoFormatter) Format(entry *log.Entry) ([]byte, error) {
	if entry.Level == log.InfoLevel {
		return append([]byte(entry.Message), '\n'), nil
	}
	return defaultLogFormatter.Format(entry)
}

func getCurrentDirectory() (string, error) {
	dir, err := filepath.Abs(filepath.Dir(os.Args[0]))
	if err != nil {
		log.Fatal("Failed to get current directory")
		return "", err
	}
	return strings.Replace(dir, "\\", "/", -1), nil
}

func main() {
	BaseDir, err := getCurrentDirectory()
	if err != nil {
		os.Exit(1)
	}

	flagQuiet := flag.Bool("q", false, "Quiet execution")
	flagVerbose := flag.Bool("v", false, "Verbose execution")
	configFile := flag.String("f", "", "Specify a YAML config file")
	outputType := flag.String("t", "", "Specify output image type")
	repoAddr = flag.String("r", "http://isulahub.com:8081/repo/2.2-rc3/",
		"Specify Yum repo address")
	flagHelp := flag.Bool("h", false, "help message")

	// Set up logging
	log.SetFormatter(new(infoFormatter))
	log.SetLevel(log.InfoLevel)

	flag.Parse()

	if *flagHelp {
		flag.Usage()
		os.Exit(0)
	}

	if *configFile == "" {
		fmt.Printf("Error: You must specify a YAML config file using: -f\n")
		flag.Usage()
		os.Exit(1)
	}

	if *flagQuiet && *flagVerbose {
		fmt.Printf("Can't set quiet and verbose flag at the same time\n")
		os.Exit(1)
	}
	if *flagQuiet {
		log.SetLevel(log.ErrorLevel)
	}
	if *flagVerbose {
		// Switch back to the standard formatter
		log.SetFormatter(defaultLogFormatter)
		log.SetLevel(log.DebugLevel)
	}

	log.Infof("Use yaml file: %s", *configFile)

	// kick the main build process
	build(*configFile, *outputType, BaseDir)
}
