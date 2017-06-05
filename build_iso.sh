#!/bin/bash

VERSION=euleros-isula-2.$( date  +%Y-%m-%d-%H-%M-%S )-devel
BaseDir=$(pwd)
MountDir=${BaseDir}/isula_output
BuildDir=${MountDir}/build
LogFile=${BuildDir}/log
mkdir -p ${BuildDir}/installer
OstreeRepoDir=${MountDir}/repo && mkdir -p $OstreeRepoDir
isempty=0

set -x
set -e
set -o pipefail

# setup build environment
cp -f ${BaseDir}/iSula-Base.repo /etc/yum.repos.d/
#yum -y install ostree rpm-ostree lorax docker libvirt epel-release
yum -y install ostree rpm-ostree lorax

## create repo in BuildDir, this will fail w/o issue if already exists
if ! test -d ${BuildDir}/repo/objects; then
    ostree --repo=${MountDir}/repo init --mode=archive-z2
    isempty=1
else
    isempty=0
fi

## compose a new tree, based on defs in euleros-isula-host.json
rpm-ostree compose --repo=${OstreeRepoDir} tree --force-nocache --add-metadata-string=version=${VERSION}${TAG} ${BaseDir}/euleros-isula-host.json |& tee ${BuildDir}/log.compose
ostree --repo=${OstreeRepoDir} summary -u

chmod -R a+r ${OstreeRepoDir}/objects

echo 'Stage-1 done, you can now sign the repo, or just run stage2 '

cd ${OstreeRepoDir}
python -m SimpleHTTPServer 45678&
id1=$!
sleep 10

echo 'stage2 start...'
cd ${BaseDir}
source ./lorax.sh ${BaseDir}

kill -9 ${id1}
exit 0
