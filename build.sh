#!/bin/sh

usage() {
	echo "Usage:
-a|--arch	Architecture to create rootfs for.
"
	exit
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		;;
	-a | --arch)
		[ -n "$2" ] && ARCH=$2 shift || usage
		;;
	-f | --file)
		[ -n "$2" ] && CONFFILE=$2 shift || usage
	esac
	shift
done

TARGET_CPU=$(dpkg-architecture -a $ARCH -qDEB_HOST_GNU_CPU)
LOG="build.$ARCH.log"

mount_chroot() {
	sudo mount -o bind /dev $1/dev
	sudo mount -t proc /proc $1/proc
	sudo mount -t sysfs -o nosuid,nodev,noexec sysfs $1/sys
}

umount_chroot() {
	sudo umount -l $1/dev
	sudo umount -l $1/proc
	sudo umount -l $1/sys
}

do_chroot() {
	mount_chroot rootfs-$ARCH

	DEBIAN_FRONTEND=noninteractive \
	DEBCONF_NONINTERACTIVE_SEEN="true" \
	DEBCONF_NOWARNINGS="true" \
	LC_ALL=C \
	LANGUAGE=C \
	LANG=C \
	sudo chroot rootfs-$ARCH /bin/sh -c "$@"

	umount_chroot rootfs-$ARCH
}

if [ -f multistrap.gpg ]; then
    rm multistrap.gpg
fi

if [ -d rootfs-$ARCH ]; then
	sudo rm rootfs-$ARCH -rf
fi

bootstrap() {
	# Import keys from keyserver
	mkdir -p rootfs-$ARCH/etc/apt/trusted.gpg.d

	fakeroot cp /usr/share/keyrings/debian-archive-keyring.gpg rootfs-$ARCH/etc/apt/trusted.gpg
	gpg --no-default-keyring --keyring $PWD/rootfs-$ARCH/etc/apt/trusted.gpg --receive-keys A81E075ABEC80A7E

	# Bootstrap system
	sudo  multistrap -f  $CONFFILE -a $ARCH -d rootfs-$ARCH
}

hooks() {
	for hook in hooks/*.chroot; do
		echo "Running: $hook"

 		cat $hook | \
		LC_ALL=C \
		LANGUAGE=C \
		LANG=C \
		sudo chroot rootfs-$ARCH
	done
}

configure() {
	if command -v qemu-$TARGET_CPU-static; then
		sudo cp $(command -v qemu-${TARGET_CPU}-static) rootfs-$ARCH/usr/bin/
	fi

	# Configure system
	do_chroot "/var/lib/dpkg/info/dash.preinst"
	do_chroot "dpkg --configure -a"
	
	[ -f roootfs-$ARCH/usr/bin/qemu-$TARGET_CPU-static ] && rm sudo rm roootfs-$ARCH/usr/bin/qemu-$TARGET_CPU-static
}

compress() {
	FILENAME="halium-debian-rootfs_$(date +%Y%m%d)_$ARCH.tar.gz"

	(cd "rootfs-$ARCH" && sudo tar -c *) | gzip -9 --rsyncable > $FILENAME
	chmod 644 "$FILENAME"
}

#############################################
# Start of build																							#
#############################################

# Create log file
echo "I: The build will happen quietly. If you need to debug a problem, see build.$ARCH.log"
echo > $LOG

# Bootstrap
echo "I: Bootstrapping system"
bootstrap >> $LOG 2>&1

# Configure
echo "I: Configuring"
configure >> $LOG 2>&1

echo "I: Running hooks"
hooks >> $LOG 2>&1

echo "I: Creating tarball"
compress >> $LOG 2>&1
