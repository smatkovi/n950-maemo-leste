#!/bin/bash
# Maemo Leste for the Nokia N9 (RM-696), made from an N950 image of
# rootfs/build.sh: same userland, the N9's kernel (zImage with omap3-n9.dtb
# appended, modules), the packages released since the base image, the
# Maliit on-screen keyboard (the N9 has no hardware keyboard) and today's
# rootfs/overlay.
#
#   BASE_IMG=<N950 Leste ext4 image> KSRC=<kernel tree> KOUT=<its build dir> \
#   OUT=<N9 image> bash rootfs/n9/build.sh
#
# The image has the size of the N9's Alt_OS partition (partition 4,
# 5120000 sectors, 2.4 GiB; OUT_SECTORS for another one): built in a larger
# work image, then copied into a fresh file system of that size with 1 %
# reserved for root. /etc/boot.d/05-resize-root grows it at the first boot
# if the partition is larger. To fit, documentation, manual pages and
# translations other than German and English are left out
# (dpkg.cfg.d/01-n9-slim keeps them out).
#
# MODULE_OVERRIDES="<file.ko>=<path below /lib/modules/KREL> ..." replaces
# built modules (e.g. an omap3-isp.ko without kernel patch 0058, as the N950
# runs it). Needs sudo (loop mounts, chroot through qemu-arm-static).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
BASE_IMG=${BASE_IMG:?set BASE_IMG=<N950 Leste image>}
KSRC=${KSRC:?set KSRC=<kernel source tree>}
KOUT=${KOUT:?set KOUT=<kernel build directory>}
OUT=${OUT:?set OUT=<output image>}
WORK_SECTORS=${WORK_SECTORS:-6291456}	# 3 GiB while building
OUT_SECTORS=${OUT_SECTORS:-5120000}	# Alt_OS, partition 4
MODULE_OVERRIDES=${MODULE_OVERRIDES:-}
HOSTNAME_N9=${HOSTNAME_N9:-n9}
FS_UUID=${FS_UUID:-$(cat /proc/sys/kernel/random/uuid)}
DTB=omap3-n9.dtb
# Harmattan's partition 2 (dumpe2fs -h), which ubiboot's 2.6.32 can read
FEATURES=has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize
# The N950's command line: the running OMAP watchdog is taken over and fed
# (ubiboot leaves it running), as on the N950
CMDLINE="root=/dev/mmcblk1p4 rootwait rw rootfstype=ext4 init=/sbin/init console=tty0 omap_wdt.early_enable=1 mitigations=off cgroup_disable=memory"
GH=https://github.com/smatkovi/n950-maemo-leste/releases/download

SRC=/mnt/n9-src
DST=/mnt/n9-dst
WIMG=$OUT.work
log() { echo ">> $*"; }

KREL=$(cat "$KOUT/include/config/kernel.release")
[ -f "$KOUT/arch/arm/boot/zImage" ] && [ -f "$KOUT/arch/arm/boot/dts/ti/omap/$DTB" ] ||
	{ echo "zImage or $DTB missing in $KOUT"; exit 1; }

# as in rootfs/build.sh: the static qemu-arm while building
ARM_MAGIC='\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00'
ARM_MASK='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'
BINFMT_SWITCHED=0
binfmt_use_static() {
	[ -x /usr/bin/qemu-arm-static ] || { echo "qemu-arm-static missing"; exit 1; }
	if [ -e /proc/sys/fs/binfmt_misc/qemu-arm ] &&
	   grep -q 'interpreter /usr/bin/qemu-arm-static' /proc/sys/fs/binfmt_misc/qemu-arm; then
		return 0
	fi
	[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] &&
		sudo -n sh -c 'echo 0 > /proc/sys/fs/binfmt_misc/qemu-arm'
	sudo -n sh -c "echo ':n950-arm:M::$ARM_MAGIC:$ARM_MASK:/usr/bin/qemu-arm-static:PF' > /proc/sys/fs/binfmt_misc/register"
	BINFMT_SWITCHED=1
}
binfmt_restore() {
	[ "$BINFMT_SWITCHED" = 1 ] || return 0
	[ -e /proc/sys/fs/binfmt_misc/n950-arm ] &&
		sudo -n sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/n950-arm'
	[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] &&
		sudo -n sh -c 'echo 1 > /proc/sys/fs/binfmt_misc/qemu-arm'
	BINFMT_SWITCHED=0
}
in_target() {
	sudo -n chroot "$DST" /usr/bin/env -i HOME=/root \
		PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive \
		LC_ALL=C /bin/bash -c "$1"
}
cleanup() {
	set +e
	binfmt_restore
	for m in "$DST/dev/pts" "$DST/dev" "$DST/proc" "$DST" "$SRC"; do
		mountpoint -q "$m" && sudo -n umount -l "$m"
	done
}
trap cleanup EXIT

log "work image, $((WORK_SECTORS / 2048)) MiB, Harmattan's ext4 features"
mkdir -p "$(dirname "$OUT")"
rm -f "$WIMG" "$OUT"
truncate -s $((WORK_SECTORS * 512)) "$WIMG"
mkfs.ext4 -q -F -O none,$FEATURES -b 4096 -I 256 -L leste -U "$FS_UUID" \
	-E lazy_itable_init=0,lazy_journal_init=0 "$WIMG"
tune2fs -c 0 -i 0 -o ^acl,^user_xattr "$WIMG" > /dev/null
sudo -n mkdir -p "$SRC" "$DST"
sudo -n mount -o ro,noload,loop "$BASE_IMG" "$SRC"
sudo -n mount -o loop "$WIMG" "$DST"

log "copying the N950 image (without its kernel and modules)"
sudo -n rsync -aHAX --numeric-ids \
	--exclude='/usr/lib/modules/*' --exclude='/lib/modules/*' \
	--exclude='/boot/zImage*' --exclude='/boot/bzImage*' --exclude='/boot/config-*' \
	--exclude='/boot/cmdline*' --exclude='/boot/kolibri.bin' \
	"$SRC/" "$DST/"

log "kernel $KREL with $DTB appended, modules"
sudo -n mkdir -p "$DST/boot"
cat "$KOUT/arch/arm/boot/zImage" "$KOUT/arch/arm/boot/dts/ti/omap/$DTB" |
	sudo -n tee "$DST/boot/zImage-$KREL" > /dev/null
sudo -n ln -sf "zImage-$KREL" "$DST/boot/zImage"
sudo -n cp "$KOUT/.config" "$DST/boot/config-$KREL"
sudo -n make -s -C "$KSRC" O="$KOUT" ARCH=arm LLVM=1 \
	INSTALL_MOD_PATH="$DST" INSTALL_MOD_STRIP=1 DEPMOD=true modules_install
for o in $MODULE_OVERRIDES; do
	sudo -n install -m 644 "${o%%=*}" "$DST/lib/modules/$KREL/${o#*=}"
done
echo "$CMDLINE" | sudo -n tee "$DST/boot/cmdline" > /dev/null

log "fstab, host name"
sudo -n tee "$DST/etc/fstab" > /dev/null <<EOF
# N9: Leste on partition 4 (Alt_OS); ubiboot reads /boot/zImage from here.
UUID=$FS_UUID	/	ext4	defaults,noatime,errors=remount-ro	0	1
tmpfs /tmp tmpfs nosuid,nodev,mode=1777,size=64M 0 0
none /sys/kernel/debug debugfs defaults 0 0
# MyDocs, shared with Harmattan (FAT32, partition 1)
/dev/mmcblk1p1	/home/user/MyDocs	vfat	nofail,noatime,utf8,uid=1000,gid=1000,shortname=mixed,dmask=022,fmask=133	0	0
EOF
echo "$HOSTNAME_N9" | sudo -n tee "$DST/etc/hostname" > /dev/null
sudo -n sed -i -E "s/\bn950\b/$HOSTNAME_N9/g" "$DST/etc/hosts"

log "chroot (qemu-arm)"
binfmt_use_static
sudo -n mount -t proc proc "$DST/proc"
sudo -n mount --bind /dev "$DST/dev"
sudo -n mount --make-rslave "$DST/dev"
sudo -n mount --bind /dev/pts "$DST/dev/pts"
sudo -n mv "$DST/etc/resolv.conf" "$DST/etc/resolv.conf.n9-build"
sudo -n cp -L /etc/resolv.conf "$DST/etc/resolv.conf"
in_target "dpkg-divert --quiet --local --rename --add /usr/bin/udevadm &&
	ln -s /bin/true /usr/bin/udevadm &&
	printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d"

log "documentation, manual pages and other languages out"
sudo -n install -D -m 644 "$HERE/dpkg.cfg.d/01-n9-slim" "$DST/etc/dpkg/dpkg.cfg.d/01-n9-slim"
in_target "find /usr/share/doc -mindepth 1 ! -type d ! -name copyright -delete
	find /usr/share/doc -mindepth 1 -type d -empty -delete
	rm -rf /usr/share/man/* /usr/share/info/*
	find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name de ! -name 'de_*' \
		! -name en ! -name 'en_*' ! -name locale.alias -exec rm -rf {} +"

log "packages released since the base image, Maliit"
# maedevu may be unreachable: the base image's lists still name its packages
in_target "apt-get -q update" || log "apt-get update failed in part, going on with the old lists"
debs=
while read -r d; do
	case $d in ''|'#'*) continue ;; esac
	f=${d##*/}
	sudo -n curl -sfL -o "$DST/tmp/$f" "$GH/$(echo "${d%/*}" | sed 's/+/%2B/g')/$f"
	debs="$debs /tmp/$f"
done < "$REPO/rootfs/release-debs"
# the N9's own: FingerTerm, a terminal with its own keyboard
f=fingerterm_1.5.0-n950.1_armhf.deb
sudo -n curl -sfL -o "$DST/tmp/$f" "$GH/fingerterm-1.5.0-n950.1/$f"
debs="$debs /tmp/$f"
in_target "apt-get -q -y --no-install-recommends -o Dpkg::Options::=--force-confold install $debs maliit-framework maliit-keyboard wmctrl"
# Nothing depends on these, and the N9 has no use for them: Vulkan (the
# SGX530 has none) and an English speech-recognition model no program uses
in_target "apt-get -q -y purge mesa-vulkan-drivers pocketsphinx-en-us"
in_target "rm -f $debs; apt-get -q -y --purge autoremove; apt-get clean"
sudo -n install -D -m 755 "$HERE/n9-maliit-server" "$DST/usr/bin/n9-maliit-server"
sudo -n install -D -m 644 "$HERE/Xsession.d/89n9-maliit" "$DST/etc/X11/Xsession.d/89n9-maliit"
sudo -n install -D -m 644 "$HERE/Xsession.post/16n9-maliit-server" "$DST/etc/X11/Xsession.post/16n9-maliit-server"
sudo -n install -D -m 644 "$HERE/90_n9-maliit.gschema.override" "$DST/usr/share/glib-2.0/schemas/90_n9-maliit.gschema.override"
in_target "glib-compile-schemas /usr/share/glib-2.0/schemas"
# Hildon's own on-screen keyboard for GTK/Hildon programs (terminal, Wi-Fi
# password, ...): Leste's defaults suit devices with a keyboard (current
# plugin hildon_keyboard_assistant, use_finger_kb unset = off), and then a
# tap never brings up hildon_western_fkb.
G="gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults"
in_target "$G --type bool --set /apps/osso/inputmethod/use_finger_kb true &&
	$G --type string --set /apps/osso/inputmethod/input_method_plugin hildon_western_fkb"

log "N950 files (rootfs/overlay), the N9's Wi-Fi modules"
sudo -n rsync -rlpt --chown=root:root "$REPO/rootfs/overlay/" "$DST/"
sudo -n install -m 644 "$HERE/modules-load.d/n950-wifi.conf" "$DST/etc/modules-load.d/n950-wifi.conf"
# personalisation (the default theme at first boot, theme changes) through
# /usr/lib/n950/personalisation, which keeps it working with /tmp on tmpfs
in_target "dpkg-divert --quiet --local --rename --divert /usr/bin/personalisation.real --add /usr/bin/personalisation &&
	ln -sf /usr/lib/n950/personalisation /usr/bin/personalisation"
sudo -n install -D -m 755 "$REPO/gps/positioningd-gpsd.py" "$DST/usr/lib/n950-gps/positioningd-gpsd.py"
sudo -n install -D -m 755 "$REPO/gps/harmattan-gps" "$DST/usr/sbin/harmattan-gps"
sudo -n install -D -m 755 "$REPO/gps/harmattan-gps.initd" "$DST/etc/init.d/harmattan-gps"
sudo -n install -D -m 644 "$REPO/gps/harmattan-gps.conf" "$DST/etc/dbus-1/system.d/harmattan-gps.conf"
in_target "rc-update add n950-firmware boot && rc-update add n950-usbnet default"
# rootfs/build.sh's service list (the openrc package just installed would
# otherwise bring them back from /etc/rc2.d)
in_target "mv /etc/X11/Xsession.post/01maemo-xinput-sounds-start /etc/X11/Xsession.post/01maemo-xinput-sounds-start.disabled 2>/dev/null; rc-update del exim4 default 2>/dev/null; true"
in_target "for s in dundee:default haveged:default rsync:default console-setup.sh:default keyboard-setup.sh:sysinit; do rc-update del \${s%%:*} \${s##*:}; done 2>/dev/null; true"
in_target "for s in dundee haveged rsync console-setup.sh exim4; do update-rc.d \$s disable; done 2>/dev/null; true"
in_target "grep -q '^#n950 ' /etc/inittab || sed -i -E 's/^([2-6]:23:respawn:\\/sbin\\/getty .*)\$/#n950 \\1/' /etc/inittab"
in_target "for f in /usr/share/gvfs/remote-volume-monitors/afc.monitor /usr/share/gvfs/remote-volume-monitors/goa.monitor /usr/share/gvfs/remote-volume-monitors/gphoto2.monitor /usr/share/gvfs/remote-volume-monitors/mtp.monitor /usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service /usr/share/dbus-1/services/org.freedesktop.portal.Documents.service /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service /usr/share/dbus-1/services/org.freedesktop.impl.portal.PermissionStore.service /usr/share/dbus-1/services/org.a11y.Bus.service; do [ -e \$f ] && dpkg-divert --quiet --local --rename --divert \$f.n950-off --add \$f; done; true"
in_target "depmod $KREL"
in_target "rm /usr/bin/udevadm && dpkg-divert --quiet --local --rename --remove /usr/bin/udevadm &&
	rm -f /usr/sbin/policy-rc.d"
sudo -n mv "$DST/etc/resolv.conf.n9-build" "$DST/etc/resolv.conf"
sudo -n sh -c "df -h $DST | tail -1"
cleanup
trap - EXIT

# (resize2fs -M cannot shrink this file system: it estimates nearly its
# whole size, so the tree is copied instead)
log "into a $((OUT_SECTORS / 2048)) MiB file system (Alt_OS)"
truncate -s $((OUT_SECTORS * 512)) "$OUT"
mkfs.ext4 -q -F -O none,$FEATURES -b 4096 -I 256 -L leste -U "$FS_UUID" -m 1 \
	-E lazy_itable_init=0,lazy_journal_init=0 "$OUT"
tune2fs -c 0 -i 0 -o ^acl,^user_xattr "$OUT" > /dev/null
sudo -n mount -o ro,loop "$WIMG" "$SRC"
sudo -n mount -o loop "$OUT" "$DST"
trap cleanup EXIT
sudo -n rsync -aHAX --numeric-ids "$SRC/" "$DST/"
sudo -n sh -c "df -h $DST | tail -1"
cleanup
trap - EXIT
e2fsck -fn "$OUT" > /dev/null
rm -f "$WIMG"
log "done: $OUT ($((OUT_SECTORS / 2048)) MiB, UUID $FS_UUID, kernel $KREL)"
