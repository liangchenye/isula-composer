#!/bin/bash

ImageDir=$1
ProdName=$2
Cmdline=$3
RepoAddr=$4

for x in $(seq 0 18); do
  path=/dev/loop${x}
  if ! test -b ${path}; then mknod -m660 ${path} b 7 ${x}; fi
done

rm -rf ${ImageDir}/antos_tmp/lorax
echo 'Running: lorax --nomacboot'
lorax --nomacboot --add-template=${ImageDir}/../tools/lorax/lorax.tmpl \
--add-template-var=ostree_repo=file:///${ImageDir}/../repo \
--add-template-var=kern_cmdline="${Cmdline}" \
--logfile=${ImageDir}/../lorax.log \
-p "EulerOS V2.0SP3" -v iSula -r 1 --isfinal --buildarch=x86_64 \
-s ${RepoAddr} \
${ImageDir}/antos_tmp/lorax
rm -rf ${ImageDir}/antos_tmp/images
mkdir ${ImageDir}/antos_tmp/images

VERSION=EulerOS_V200R005C00_standard_ostree_$( date  +%Y%m%d_%H%M%S )

cp ${ImageDir}/antos_tmp/lorax/images/boot.iso ${ImageDir}/antos_tmp/images/${VERSION}.iso
cd ${ImageDir}/antos_tmp/images/

find .  -type f | grep -v '.*SUMS$' | xargs sha256sum > SHA256SUMS
cd ${ImageDir}/antos_tmp

rm -rf *.tar.xz

exit 0
