package main

import (
	"os"
	"os/exec"

	log "github.com/sirupsen/logrus"
)

// OutputOstreeImage generates OS ISO image of ostree version
func OutputOstreeImage(prodName string, cmdline string) error {
	imageDir := rootDir + "output"
	err := os.MkdirAll(imageDir, 0766)
	if err != nil {
		log.Errorf("Create output directory failed: %v", err)
		return err
	}

	// Run lorax shell script to generate the ISO image
	loraxSh := rootDir + "tools/lorax/lorax.sh"
	cmd := exec.Command("/bin/sh", loraxSh, imageDir, prodName, cmdline, *repoAddr)
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		log.Errorf("Could not run lorax script: %v", err)
		return err
	}

	return nil
}
