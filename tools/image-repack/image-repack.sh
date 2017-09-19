#!/bin/sh

function usage()
{
	echo "Usage: $self_path -i input_image -t image_type -o output_image"
	echo "Repack an OS image, supported image type: ISO"
}

function check_args()
{
	local iarg="$1"
	local oarg="$2"
	local targ="$3"

	if [ -z "$iarg" ] || [ -z "$oarg" ] || [ -z "$targ" ]; then
		usage
		return 1
	fi
}

function repack_qcow2()
{
	echo "repack $1 start"
	rootpart=`virt-filesystems -a $1 | grep root`
	mkdir -p /mnt/repack
	guestmount -a $1 -m $rootpart --rw /mnt/repack
	local copied_dir=/mnt/repack/ostree/deploy/euleros-antos-host/var/containers
	mkdir -p $copied_dir

	for files in `cat add-files`; do
		cp $files $copied_dir
	done

	sleep 10
    umount /mnt/repack
	rm -rf /mnt/repack
	echo "repack $1 finished"
}

function cleanup_exit()
{
	local mntDir=/mnt/repack
	local isoRoot=/tmp/iso-root

	cd /
	umount $mntDir >/dev/null 2>&1
	umount $isoRoot/LiveOS/squashfs-root/LiveOS/tmp >/dev/null 2>&1
	rm -rf $isoRoot
	exit 1
}

function repack_iso()
{
	local inImage=$1
	local outImage=$2
	local curDir=`pwd`
	local mntDir=/mnt/repack
	local isoRoot=/tmp/iso-root
	local need_recreate=0

	# Just allow one image-repack task running in a machine
	cnt=`pgrep image-repack | wc -l`
	if [ $cnt -gt 2 ]; then
		echo "Error: another image-repack is already running, abort!!"
		exit 1
	fi

	file_info=`file $inImage`
	if [ -z "`echo $file_info | grep "ISO"`" ]; then
		echo "Error: Invalid input image"
		exit 1
	fi

	# cleanup beforehand
	umount $mntDir >/dev/null 2>&1
	umount $isoRoot/LiveOS/squashfs-root/LiveOS/tmp >/dev/null 2>&1
	rm -rf $isoRoot
	rm -rf rootfs-tmp*

	type unsquashfs >/dev/null 2>&1 || { echo "Please install squashfs-tools package"; exit 1; }
	type ostree >/dev/null 2>&1 || { echo "Please install ostree package"; exit 1; }
	type mkisofs >/dev/null 2>&1 || { echo "Please install genisoimage package"; exit 1; }
	type implantisomd5 >/dev/null 2>&1 || { echo "Please install isomd5sum package"; exit 1; }

	echo "repack ${inImage} start"
	mkdir -p $mntDir
	mkdir -p $isoRoot

	cd $curDir
	mount ${inImage} $mntDir
	cp -rf $mntDir/* $isoRoot || { umount $mntDir; exit 1; }
	cd $isoRoot/LiveOS
	unsquashfs squashfs.img || { umount $mntDir; exit 1; }
	cd $isoRoot/LiveOS/squashfs-root/LiveOS/
	mkdir tmp
	mount rootfs.img tmp

	# determine if we need to adjust ISO rootfs size
	cd tmp
	# orig_size is the original rootfs size
	orig_size=$(du -h --max-depth=1 | awk 'END {print}' | awk 'END {print $1}')
	cd $curDir/rootfs
	# append_size is the space size needed to be append to the original rootfs
	append_size=$(du -h --max-depth=1 | awk 'END {print}' | awk 'END {print $1}')
	# set margin size to 700M
	margin_size=700
	# count_M is the total needed disk space($orig_size+$append_size+$margin_size)
	# Now calculate $count_M
	count_M=0
	if [ ! -z `echo $append_size | grep G` ]; then
		size=$(echo $append_size | sed 's/G//')
		append_M=`printf "%1.f\n" $(echo "$size * 1024" | bc)`
		if [ ! -z `echo $orig_size | grep G` ]; then
			size=$(echo $orig_size | sed 's/G//')
			orig_M=`printf "%1.f\n" $(echo "$size * 1024" | bc)`
		elif [ ! -z `echo $orig_size | grep M` ]; then
			size=$(echo $orig_size | sed 's/M//')
			orig_M=`printf "%1.f\n" $size`
		fi
		count_M=`expr $append_M + $orig_M + $margin_size`
		need_recreate=1
	elif [ ! -z `echo $append_size | grep M` ]; then
		size=$(echo $append_size | sed 's/M//')
		if [ $size -gt 400 ]; then
			count_M=`expr 3 \* 1024`
			need_recreate=1
		fi
	fi

	# determine if $count_M exceeds the maximum ISO space size(4.7G)
	iso_max_size=`printf "%1.f\n" $(echo "4.7 * 1024" | bc)`
	if [ $count_M -gt $iso_max_size ]; then
		allowed_max_size=`printf "%1.f\n" $(echo "2.6 * 1024" | bc)`
		echo "Error: exceed the maximum allowed ISO space, max: $iso_max_size M, needed: $count_M M"
		echo "You are allowed to append: $allowed_max_size M size maximumly!!!"
		cleanup_exit
	fi

	cd $isoRoot/LiveOS/squashfs-root/LiveOS/
	if [ $need_recreate -eq 1 ]; then
		mkdir root
		dd if=/dev/zero of=root.img bs=1M count=$count_M
		if [ $? != 0 ]; then
			echo "Error: dd create disk file failed"
			cleanup_exit
		fi
		echo "y" | mkfs.ext4 root.img
		mount root.img root
		cp -rf tmp/. root/
		umount tmp
		umount root
		rm -rf root
		rm rootfs.img
		mv root.img rootfs.img
		mount rootfs.img tmp
	fi

	cd tmp/install/ostree
	ref=$(ostree refs)
	commit=$(ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree log $ref | grep ^commit | cut -f 2 -d ' ')
	version=$(ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree log $ref | grep Version | cut -f 2 -d ' ')
	ostag=$(cat $isoRoot/EFI/BOOT/grub.cfg | grep search | sed -e 's/search --no-floppy --set=root -l //g' | sed -e "s/'//g")

	cd $isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree
	ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree export $commit > $curDir/rootfs-tmp.tar
	if [ $? != 0 ]; then
		echo "Error: ostree export failed"
		cleanup_exit
	fi
	cd $curDir

	# create yum configuration file
	echo "[main]" >> yum.conf
	echo "cachedir=/var/yum/cache" >> yum.conf
	echo "reposdir=${curDir}" >> yum.conf
	echo "http_caching=none" >> yum.conf
	echo "keepcache=0" >> yum.conf
	echo "debuglevel=2" >> yum.conf
	echo "pkgpolicy=newest" >> yum.conf
	echo "tolerant=1" >> yum.conf
	echo "exactarch=1" >> yum.conf
	echo "obsoletes=1" >> yum.conf
	echo "plugins=0" >> yum.conf
	echo "deltarpm=0" >> yum.conf
	echo "metadata_expire=1800" >> yum.conf

	mkdir rootfs-tmp
	tar xvf rootfs-tmp.tar -C rootfs-tmp
	if [ $? != 0 ]; then
		echo "Error: decompress rootfs failed"
		cleanup_exit
	fi
	cd rootfs-tmp/var/lib
	ln -s ../../usr/share/rpm rpm
	cd $curDir
	for pkg in `cat add-pkgs`; do
		yum install -y --config=yum.conf --installroot=$curDir/rootfs-tmp $pkg
		if [ $? != 0 ]; then
			echo "Error: yum install package failed"
			cleanup_exit
		fi
		if [ ! -z `echo $pkg | grep dhcp` ]; then
			cp -rf $curDir/rootfs-tmp/var/lib/dhcpd $curDir/rootfs-tmp/etc/dhcp/
			echo "L /var/lib/dhcpd - - - - ../../etc/dhcp/dhcpd" >> $curDir/rootfs-tmp/usr/lib/tmpfiles.d/rpm-ostree-1-autovar.conf
			rm -rf $curDir/rootfs-tmp/var/lib/dhcpd
		fi
	done
	yum --config=yum.conf --installroot=$curDir/rootfs-tmp clean all

	# Adjust etc contents if available
	if [ -d rootfs-tmp/etc/ ]; then
		cp -rf rootfs-tmp/etc/* rootfs-tmp/usr/etc/
		rm -rf rootfs-tmp/etc/
	fi

	# cleanup
	rm -f rootfs-tmp/var/lib/rpm
	rm -rf rootfs-tmp/var/yum/cache
	rm -f yum.conf
	rm -f rootfs-tmp.tar

	if [ -s del-files ]; then
		for file in `cat del-files`; do
			rm -rf rootfs-tmp/$file
		done
	fi
	rm -rf $isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree/*
	ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree init --mode=archive-z2
	if [ $? != 0 ]; then
		echo "Error: ostree init failed"
		cleanup_exit
	fi
	ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree commit \
		--branch=${ref} --add-metadata-string=version=${version} \
		--tree=dir=${curDir}/rootfs-tmp --tree=dir=${curDir}/rootfs
	if [ $? != 0 ]; then
		echo "Error: ostree commit failed"
		cleanup_exit
	fi
	ostree --repo=$isoRoot/LiveOS/squashfs-root/LiveOS/tmp/install/ostree summary -u
	if [ $? != 0 ]; then
		echo "Error: ostree summary failed"
		cleanup_exit
	fi

	rm -rf rootfs-tmp

	cd $isoRoot/LiveOS/squashfs-root/LiveOS/
	umount tmp
	rm -rf tmp
	cd ../..
	rm squashfs.img
	mksquashfs squashfs-root squashfs.img -comp xz
	if [ $? != 0 ]; then
		echo "Error: mksquashfs failed"
		cleanup_exit
	fi
	rm -rf squashfs-root/
	cd $isoRoot
	rm isolinux/boot.cat
	cd ${curDir}
	mkisofs -o ${outImage} -c isolinux/boot.cat -b isolinux/isolinux.bin -boot-load-size 4 -boot-info-table \
	-no-emul-boot -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -R -J -V "$ostag" \
	-T -graft-points isolinux=$isoRoot/isolinux/ images/pxeboot=$isoRoot/images/pxeboot/ \
	LiveOS=$isoRoot/LiveOS/ EFI/BOOT=$isoRoot/EFI/BOOT/ images/efiboot.img=$isoRoot/images/efiboot.img
	if [ $? != 0 ]; then
		echo "Error: mkisofs generate ISO failed"
		rm -f ${outImage}
		cleanup_exit
	fi

	# add md5 checksum
	implantisomd5 ${outImage}

	umount $mntDir
	rm -rf $mntDir
	rm -rf $isoRoot
}

while getopts "i:o:t:" option 2>/dev/null
do
		case $option in
        i)
                input=$OPTARG
                ;;
        o)
				output=$OPTARG
                ;;
        t)
				type=$OPTARG
                ;;
        *)
                usage
                exit 1
                ;;
        esac
done

check_args $input $output $type
[ $? != 0 ] && exit 1

if [ "$type" == "iso" ]; then
	repack_iso $input $output
else
	echo "Error: Invalid input image"
	usage
	exit 1
fi
