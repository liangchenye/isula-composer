#!/bin/sh

BaseDir=$1

cd ${BaseDir}/boot
vmlinuz=$(find . -name vmlinuz*)
initrd=$(find . -name initramfs*)
mkdir initrd-tmp
cd initrd-tmp
/usr/lib/dracut/skipcpio ../${initrd} | zcat | cpio -di
rm ../${initrd}
cp ${BaseDir}/usr/lib/systemd/system/ostree-prepare-root.service usr/lib/systemd/system/
mkdir usr/lib/ostree
cp ${BaseDir}/usr/lib/ostree/ostree-prepare-root usr/lib/ostree/
sed -i '/AllowIsolate/i\Requires=ostree-prepare-root.service' usr/lib/systemd/system/initrd-switch-root.service
sed -i '/AllowIsolate/i\After=ostree-prepare-root.service' usr/lib/systemd/system/initrd-switch-root.service
find . | cpio -c -o > ../${initrd}
cd ..
rm -rf initrd-tmp
gzip ${initrd}
mv ${initrd}.gz ${initrd}
bootcsum=$(cat ${vmlinuz} ${initrd} | sha256sum | cut -f 1 -d ' ')
mv ${vmlinuz} ${vmlinuz}-${bootcsum}
mv ${initrd} ${initrd}-${bootcsum}

cd ${BaseDir}
mkdir sysroot
ln -s sysroot/ostree ostree
rm -rf home
ln -s var/home home
rm -rf media
ln -s run/media media
rm -rf mnt
ln -s var/mnt mnt
rm -rf root
ln -s var/roothome root
rm -rf srv
ln -s var/srv srv
rm -rf tmp
ln -s sysroot/tmp tmp
mkdir usr/share/rpm
cp -rf var/lib/rpm/* usr/share/rpm/
rm -rf var/lib/rpm/
mkdir -p usr/lib/ostree-boot
cp -rf boot/* usr/lib/ostree-boot/

# add kernel.printk sysctl setting
echo "kernel.printk=4 4 1 7" >> usr/etc/sysctl.conf

# add OSTREE_VERSION in /etc/os-release to identify ostree version EulerOS
ostree_version=$(cat usr/etc/os-release | grep VERSION= | cut -f 2 -d '=')
echo "OSTREE_VERSION=$ostree_version" >> usr/etc/os-release

# store local ostree repo in /var/local/repo
sed -i '2c url=file:///var/local/repo' usr/etc/ostree/remotes.d/euleros-antos-host.conf
sed -i 's/euleros-antos-host\/7/euleros-antos-host\/2/g' usr/etc/ostree/remotes.d/euleros-antos-host.conf

cp ../tools/ostree/rpm-ostree* usr/lib/tmpfiles.d/

# Some rpm package may install files in /opt like sysmonitor-kmod, need to handle this case
if [ "`ls -A opt`" != "" ]; then
	DIR_LIST=$(ls -A opt)
	mkdir -p usr/opt
	cp -rf opt/. usr/opt/
	rm -rf opt
	ln -s var/opt opt
	for file in $DIR_LIST; do
		echo "L /opt/$file - - - - /usr/opt/$file" >> usr/lib/tmpfiles.d/rpm-ostree-1-autovar.conf
	done
else
	rm -rf opt
	ln -s var/opt opt
fi

cp ../tools/ostree/group usr/lib/
cp ../tools/ostree/passwd usr/lib/
cp ../tools/ostree/isula-ostree-service.sh usr/sbin/
chmod 500 usr/sbin/isula-ostree-service.sh

sed -i '/spooler/a\\/var\/log\/isula-ostree.log' usr/etc/logrotate.d/syslog

# disable selinux currently to workaround one login problem
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' usr/etc/selinux/config
