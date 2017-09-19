#!/bin/bash

set -x
set -e
set -o pipefail

cd /srv/isula-composer
git clone http://code.huawei.com/EulerOS/isula-composer.git
mv isula-composer/* . && rm -rf isula-composer
make clean && make all
./bin/mkimage -f config/atlas.yml

cd tools
tar czf image-repack.tar image-repack
xz -z image-repack.tar
mv image-repack.tar.xz /srv/isula-composer/output/antos_tmp/images
