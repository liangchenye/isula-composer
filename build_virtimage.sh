#!/bin/bash

VERSION=iSula-1.0-B001.$( date  +%Y%m%d_%H%M%S )
BaseDir=$(pwd)
MountDir=${BaseDir}/isula_output
BuildDir=${MountDir}/build
LogFile=${BuildDir}/log
mkdir -p ${BuildDir}/installer
OstreeRepoDir=${MountDir}/repo && mkdir -p $OstreeRepoDir
ln -s ${OstreeRepoDir} ${BuildDir}/repo
isempty=0


set -x
set -e
set -o pipefail

cd ${MountDir}/repo 
python -m SimpleHTTPServer 45678 &
cd ${MountDir}/lorax
python -m SimpleHTTPServer 45679 &

rm -f /var/lib/imagefactory/storage/*

imagefactory --debug base_image --file-parameter install_script ${BaseDir}/isula-cloud.ks ${BaseDir}/isula.tdl --parameter generate_icicle false

cd /var/lib/imagefactory/storage/
mv *.body ${VERSION}.qcow2
tar -cjf ${VERSION}.tar.bz2 *.qcow2
mv *.tar.bz2 *.qcow2 ${MountDir}/images/

rm -f /var/lib/imagefactory/storage/*
cd ${MountDir}
imagefactory --debug base_image --file-parameter install_script ${BaseDir}/isula-vagrant.ks ${BaseDir}/isula.tdl --parameter generate_icicle false | tee build.log
UUID=$((tail -4 build.log | head -n 1) | awk '{print $2;}')

imagefactory --debug target_image --id ${UUID} vsphere  | tee build.log
VIRTUALBOX_UUID=$((tail -4 build.log | head -n 1) | awk '{print $2;}')

imagefactory --debug target_image --parameter vsphere_ova_format vagrant-virtualbox --id ${VIRTUALBOX_UUID} ova | tee build.log
VIRTUALBOX_OVA_UUID=$((tail -4 build.log | head -n 1) | awk '{print $2;}')
mv /var/lib/imagefactory/storage/${VIRTUALBOX_OVA_UUID}.body ${MountDir}/images/${VERSION}-vagrant-virtualbox.box

imagefactory --debug target_image --id ${UUID} rhevm  | tee build.log
LIBVRIT_UUID=$((tail -4 build.log | head -n 1) | awk '{print $2;}')

imagefactory --debug target_image --parameter vsphere_ova_format vagrant-libvirt --id ${LIBVRIT_UUID} ova | tee build.log
LIBVIRT_OVA_UUID=$((tail -4 build.log | head -n 1) | awk '{print $2;}')
mv /var/lib/imagefactory/storage/${LIBVIRT_OVA_UUID}.body ${MountDir}/images/${VERSION}-vagrant-libvirt.box
rm -rf build.log

exit 0

