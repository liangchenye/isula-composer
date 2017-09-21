# isula composer [![Build Status](https://travis-ci.org/isula/isula-composer.svg?branch=master)](https://travis-ci.org/isula/isula-composer) [![Go Report Card](https://goreportcard.com/badge/github.com/isula/isula-composer)](https://goreportcard.com/report/github.com/isula/isula-composer)


##Introduction
  Isula-composer is a tool for building a light ostree-based container OS installing image from a yaml config file. It provides a convenient way to customize a host system for deploying on massive private or public cloud. Here are two main features of an isula host: ostree for controlling the filesystem, and docker for deploying applications. Isula should be a good choice for cloud service deployer as infrastructure.

##Usage
```bash
bin/mkimage -f configfile
```
  Here our recommanded config files are saved in **./config** dir, including a base config file and addition config files. For customizing, just change the options in addition config files. Defaultly, isula-composer use huawei software repository and output an .img image. Using **-r** and **-t** options can respectively modify the repository and the image type. Try **-h** option to get more information.


##Tools
  Additionally, isula-composer provides some tools for varieties of usages. 
####image-repack.sh
  Decompress an **.iso** image, install or uninstall some packages, and compress it again.
