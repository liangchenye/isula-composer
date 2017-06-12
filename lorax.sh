#!/bin/bash

ImageDir=$1

for x in $(seq 0 6); do
  path=/dev/loop${x}
  if ! test -b ${path}; then mknod -m660 ${path} b 7 ${x}; fi
done
rm -rf ${ImageDir}/isula_output/lorax

echo 'Running: lorax --nomacboot'
lorax --nomacboot --add-template=${ImageDir}/lorax.tmpl -p "EulerOS iSula" -v 2 -r 1 --isfinal \
--buildarch=x86_64 \
-s http://www.isula.org/isula \
${ImageDir}/isula_output/lorax
rm -rf ${ImageDir}/isula_output/images
mkdir ${ImageDir}/isula_output/images

VERSION=euleros-isula-2
TAG=$( date  +%Y-%m-%d-%H-%M-%S )

cp ${ImageDir}/isula_output/lorax/images/boot.iso ${ImageDir}/isula_output/images/${VERSION}-${TAG}.iso
cd ${ImageDir}/isula_output/images/

cd ${ImageDir}/isula_output/
rm -rf *.tar.xz

tar cvf ${VERSION}-${TAG}_PXE.tar lorax/
xz -z ${VERSION}-${TAG}_PXE.tar
mv *_PXE.tar.xz images/
