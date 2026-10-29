#!/bin/bash
# Maemo Leste root filesystem for the N950, as an ext4 image for partition 4.
#
#   WORK=/path/to/work SRC_IMG=maemo-leste-excalibur-n900-<date>.img \
#       bash rootfs/build.sh
#
# Leste publishes no current N950 image, but the N900 one is the same
# userland on the same SoC family (OMAP3, armhf). The N900's device packages
# come out, hildon-meta-n950 goes in, and so do the kernel of kernel/build.sh
# (zImage with the N950's device tree appended, modules) and the files in
# rootfs/overlay. Needs sudo (loop mounts, chroot through qemu-arm-static).
#
# The file system gets exactly the features of Harmattan's own root file
# system (partition 2, as Nokia made it): ubiboot reads the kernel from this
# partition with its 2.6.32 kernel, which cannot mount anything newer.
#
# Output: $OUT (default $WORK/n950-leste.img), 4 GiB, the size of
# partition 4 that install/n950-install.sh creates.
#
# FM_DEB=<n950-fm .deb> takes apps/n950-fm from a local build instead of
# its release; KOLIBRI_BIN=<kolibrios-arm's build/n950/kernel.bin> puts
# KolibriOS at /boot/kolibri.bin, for ubiboot's second "Maemo" entry.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:?set WORK=<work directory of kernel/build.sh>}
SRC_IMG=${SRC_IMG:?set SRC_IMG=<Leste N900 image, uncompressed>}
OUT=${OUT:-$WORK/n950-leste.img}
SIZE_SECTORS=${SIZE_SECTORS:-8388608}		# 4 GiB, partition 4
ROOT_PW=${ROOT_PW:-n950-leste}
SSH_PUBKEY=${SSH_PUBKEY:-}
FM_DEB=${FM_DEB:-}
KOLIBRI_BIN=${KOLIBRI_BIN:-}
HOSTNAME_N950=${HOSTNAME_N950:-n950}
KOUT=$WORK/out
FS_UUID=${FS_UUID:-$(cat /proc/sys/kernel/random/uuid)}
# Harmattan's partition 2 (dumpe2fs -h of the factory image)
FEATURES=has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize
N900_PKGS="hildon-meta-n900 leste-config-n900 maemo-kernel-config-n900
	linux-image-omap gps-nokia-n900 wl1251-cal n900-powermanagement"

SRC=/mnt/n950-src
DST=/mnt/n950-dst
log() { echo ">> $*"; }

KREL=$(cat "$KOUT/include/config/kernel.release" 2>/dev/null) ||
	{ echo "no kernel in $KOUT, run kernel/build.sh first"; exit 1; }
[ -f "$KOUT/arch/arm/boot/zImage" ] &&
[ -f "$KOUT/arch/arm/boot/dts/ti/omap/omap3-n950.dtb" ] ||
	{ echo "zImage or omap3-n950.dtb missing in $KOUT"; exit 1; }

# Arch registers the dynamically linked qemu-arm, whose libraries are not in
# the chroot: while building, the static one takes its place.
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

log "empty image, $((SIZE_SECTORS / 2048)) MiB, Harmattan's ext4 features"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
truncate -s $((SIZE_SECTORS * 512)) "$OUT"
mkfs.ext4 -q -F -O none,$FEATURES -b 4096 -I 256 -L leste -U "$FS_UUID" \
	-E lazy_itable_init=0,lazy_journal_init=0 "$OUT"
tune2fs -c 0 -i 0 -o ^acl,^user_xattr "$OUT" > /dev/null
got=$(dumpe2fs -h "$OUT" 2>/dev/null | sed -n 's/^Filesystem features: *//p' | tr ' ' '\n' | sort | xargs)
want=$(echo "$FEATURES" | tr ',' '\n' | sort | xargs)
[ "$got" = "$want" ] || { echo "features differ: got '$got', want '$want'"; exit 1; }

off=$(sfdisk -J "$SRC_IMG" | python3 -I -c '
import json, sys
p = json.load(sys.stdin)["partitiontable"]["partitions"]
print(max(p, key=lambda e: e["size"])["start"] * 512)')
sudo -n mkdir -p "$SRC" "$DST"
sudo -n mount -o ro,loop,offset="$off" "$SRC_IMG" "$SRC"
sudo -n mount -o loop "$OUT" "$DST"

log "copying Leste (without the N900's swap file)"
sudo -n rsync -aHAX --numeric-ids --exclude=/swap "$SRC/" "$DST/"

log "kernel $KREL with the N950's device tree appended, modules"
sudo -n mkdir -p "$DST/boot"
cat "$KOUT/arch/arm/boot/zImage" "$KOUT/arch/arm/boot/dts/ti/omap/omap3-n950.dtb" |
	sudo -n tee "$DST/boot/zImage-$KREL" > /dev/null
sudo -n ln -sf "zImage-$KREL" "$DST/boot/zImage"
sudo -n cp "$KOUT/.config" "$DST/boot/config-$KREL"
sudo -n make -s -C "$WORK/linux" O="$KOUT" ARCH=arm LLVM=1 \
	INSTALL_MOD_PATH="$DST" INSTALL_MOD_STRIP=1 DEPMOD=true modules_install

log "fstab, host name, root access"
sudo -n tee "$DST/etc/fstab" > /dev/null <<EOF
# N950: Leste on partition 4; ubiboot reads /boot/zImage from here.
UUID=$FS_UUID	/	ext4	defaults,noatime,errors=remount-ro	0	1
/dev/zram1 /tmp     ext4 defaults,strictatime 0 0
/dev/zram2 /var/tmp ext4 defaults,relatime    0 0
none /sys/kernel/debug debugfs defaults 0 0
# MyDocs, shared with Harmattan (FAT32, partition 1)
/dev/mmcblk1p1	/home/user/MyDocs	vfat	nofail,noatime,utf8,uid=1000,gid=1000,shortname=mixed,dmask=022,fmask=133	0	0
EOF
sudo -n install -d -o 1000 -g 1000 "$DST/home/user/MyDocs"
echo "$HOSTNAME_N950" | sudo -n tee "$DST/etc/hostname" > /dev/null
sudo -n sed -i "s/\bleste\b/$HOSTNAME_N950/g" "$DST/etc/hosts"
if [ -n "$SSH_PUBKEY" ]; then
	sudo -n install -d -m 0700 "$DST/root/.ssh"
	sudo -n install -m 0600 "$SSH_PUBKEY" "$DST/root/.ssh/authorized_keys"
fi

log "N900 packages out, hildon-meta-n950 in (chroot, qemu-arm)"
binfmt_use_static
sudo -n mount -t proc proc "$DST/proc"
sudo -n mount --bind /dev "$DST/dev"
sudo -n mount --bind /dev/pts "$DST/dev/pts"
sudo -n mv "$DST/etc/resolv.conf" "$DST/etc/resolv.conf.n950-build"
sudo -n cp -L /etc/resolv.conf "$DST/etc/resolv.conf"
# No /sys in the chroot, no services, and udevadm a no-op: package scripts
# that run "udevadm trigger" would otherwise reach this PC's devices.
in_target "dpkg-divert --quiet --local --rename --add /usr/bin/udevadm &&
	ln -s /bin/true /usr/bin/udevadm &&
	printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d"
# Leste's device component: n950 instead of n900
in_target "sed -i -E 's|^(deb .*maedevu\.maemo\.org/leste .*) n900\$|\1 n950|' /etc/apt/sources.list"
in_target "apt-get -q update"
# The SGX530's user space came in with hildon-meta-n900; the N950 has the
# same GPU, so it stays when that goes.
in_target "apt-mark manual \$(dpkg-query -W -f='\${db:Status-Abbrev} \${Package}\n' \
	'sgx-ddk-um-*' libgles1 libgles2 libegl1 libegl-mesa0 2>/dev/null | awk '/^ii/ {print \$2}')"
in_target "apt-get -q -y purge \$(for p in $(echo $N900_PKGS); do
		dpkg-query -W -f='\${db:Status-Abbrev} \${Package}\n' \$p 2>/dev/null; done |
		awk '/^ii/ {print \$2}')"
in_target "apt-get -q -y -o Dpkg::Options::=--force-confold install hildon-meta-n950"
# openmediaplayer from Leste's extras; the N900's games Chess and Marbles
# from their repositories' releases (free pictures in place of Nokia's).
# Not Mahjong: it needs osso-sounds-game-mahjong or libre-mahjong-sounds,
# which excalibur does not have, and its pictures (osso-graphics-game-
# mahjong) are Nokia's.
in_target "apt-get -q -y install openmediaplayer"
GH=https://github.com/smatkovi
for deb in osso-chess-ui/releases/download/v1.8.3-2%2Bleste1/osso-chess-ui_1.8.3-2+leste1_armhf.deb \
	osso-lmarbles/releases/download/v1.6.38-2%2Bleste1/osso-lmarbles_1.6.38-2+leste1_armhf.deb; do
	sudo -n curl -sfL -o "$DST/tmp/${deb##*/}" "$GH/$deb"
	in_target "apt-get -q -y install /tmp/${deb##*/} && rm -f /tmp/${deb##*/}"
done
# The FM radio (apps/n950-fm): its release, or a local build
FM_URL=$GH/n950-maemo-leste/releases/download/n950-fm-0.1.0/n950-fm_0.1.0_armhf.deb
if [ -n "$FM_DEB" ]; then
	sudo -n cp "$FM_DEB" "$DST/tmp/n950-fm.deb"
else
	sudo -n curl -sfL -o "$DST/tmp/n950-fm.deb" "$FM_URL"
fi
in_target "apt-get -q -y install /tmp/n950-fm.deb && rm -f /tmp/n950-fm.deb"
in_target "apt-get -q -y --purge autoremove && apt-get clean"
in_target "echo 'root:$ROOT_PW' | chpasswd"
in_target "for s in wl1251-cal gps-nokia-n900; do rc-update del \$s sysinit; rc-update del \$s default; done 2>/dev/null; true"
# The N950's own NVS replaces the package's generic one (n950-firmware)
in_target "dpkg-divert --quiet --local --rename --add /lib/firmware/ti-connectivity/wl1271-nvs.bin"

log "N950 files (rootfs/overlay)"
sudo -n rsync -rlpt --chown=root:root "$REPO/rootfs/overlay/" "$DST/"
# GPS through Harmattan's stack (gps/README.md), started by hand
sudo -n install -D -m 755 "$REPO/gps/positioningd-gpsd.py" "$DST/usr/lib/n950-gps/positioningd-gpsd.py"
sudo -n install -D -m 755 "$REPO/gps/harmattan-gps" "$DST/usr/sbin/harmattan-gps"
sudo -n install -D -m 755 "$REPO/gps/harmattan-gps.initd" "$DST/etc/init.d/harmattan-gps"
sudo -n install -D -m 644 "$REPO/gps/harmattan-gps.conf" "$DST/etc/dbus-1/system.d/harmattan-gps.conf"
in_target "rc-update add n950-firmware boot && rc-update add n950-usbnet default"
in_target "depmod $KREL"
in_target "rm /usr/bin/udevadm && dpkg-divert --quiet --local --rename --remove /usr/bin/udevadm &&
	rm -f /usr/sbin/policy-rc.d"
sudo -n mv "$DST/etc/resolv.conf.n950-build" "$DST/etc/resolv.conf"

if [ -n "$KOLIBRI_BIN" ]; then
	log "KolibriOS at /boot/kolibri.bin (ubiboot starts it like a zImage)"
	sudo -n install -m 644 "$KOLIBRI_BIN" "$DST/boot/kolibri.bin"
fi

log "boot command line for ubiboot (/boot/cmdline)"
# The eMMC is the second controller (mmc2, DT alias mmc1): mmcblk1.
echo "root=/dev/mmcblk1p4 rootwait rw rootfstype=ext4 init=/sbin/init console=tty0" |
	sudo -n tee "$DST/boot/cmdline" > /dev/null

sudo -n sh -c "df -h $DST | tail -1"
cleanup
trap - EXIT
e2fsck -fn "$OUT" > /dev/null
log "done: $OUT (UUID $FS_UUID, kernel $KREL)"
