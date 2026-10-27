#!/bin/bash
# Puts Maemo Leste next to Harmattan on the N950's eMMC, from a PC.
#
#   sudo bash install/n950-install.sh /dev/sdX n950-leste.img [--yes]
#
# /dev/sdX is the N950's whole eMMC as ubiboot's maintenance mode exports it
# over USB (G_EXPORTED_PARTITONS="/dev/mmcblk0" in ubiboot.conf, USB cable
# plugged in while ubiboot starts). The script refuses any other disk: the
# size and the partition layout must be the N950's (16 GB eMMC, Nokia's
# layout), and partition 2 must hold Harmattan.
#
# What it changes:
#   p1 MyDocs (FAT32)  shrunk from 8.8 to 4.8 GiB; its files are saved to
#                      $BACKUP first and copied back (the file system is
#                      made again, as Harmattan's own secure-clean makes it)
#   p4 (new, 4 GiB)    Maemo Leste, written from the image of rootfs/build.sh,
#                      in the space MyDocs gives up, before Harmattan's p2
#   p3 /home           made only if it has no file system (Harmattan does
#                      not boot without it); with p2's ext4 features
#   ubiboot.conf       on MyDocs: the "Maemo" entry (OS 5) boots Leste
# p2 (Harmattan) is not touched. The old partition table and the first MiB
# of the disk are saved to $BACKUP too.
set -euo pipefail
DEV=${1:?usage: n950-install.sh /dev/sdX n950-leste.img [--yes]}
IMG=${2:?usage: n950-install.sh /dev/sdX n950-leste.img [--yes]}
YES=${3:-}
BACKUP=${BACKUP:-$PWD/n950-backup-$(date +%Y%m%d-%H%M%S)}

# The N950's eMMC and Nokia's layout (sectors of 512 bytes)
DISK_SECTORS=31047680
P1_START=1024
P1_OLD_SIZE=18463744
P2_START=18464768; P2_SIZE=8388608
P3_START=26853376; P3_SIZE=4194304
P4_SIZE=8388608
P4_START=$((P2_START - P4_SIZE))
P1_NEW_SIZE=$((P4_START - P1_START))
MNT=/mnt/n950-install

die() { echo "n950-install: $*" >&2; exit 1; }
log() { echo ">> $*"; }
part() {	# /dev/sdX1, or /dev/loop0p1 for a test on a disk image
	case $DEV in *[0-9]) echo "${DEV}p$1" ;; *) echo "${DEV}$1" ;; esac
}
[ "$(id -u)" = 0 ] || die "run as root"
case $([ -b "$DEV" ] && lsblk -dno TYPE "$DEV") in disk|loop) ;; *) die "$DEV is not a disk" ;; esac
[ -f "$IMG" ] || die "no image $IMG"

cleanup() {
	set +e
	mountpoint -q "$MNT" && umount "$MNT"
	rmdir "$MNT" 2>/dev/null
}
trap cleanup EXIT

log "checking that $DEV is the N950"
[ "$(blockdev --getsz "$DEV")" = "$DISK_SECTORS" ] ||
	die "$DEV has $(blockdev --getsz "$DEV") sectors, the N950's eMMC $DISK_SECTORS"
for p in $(lsblk -nlo NAME "$DEV" | tail -n +2); do
	findmnt -n "/dev/$p" > /dev/null && die "/dev/$p is mounted, unmount it first"
done
table=$(sfdisk -d "$DEV")
entry() {	# entry <n>: "<start> <size> <type>" of partition n, or empty
	echo "$table" | sed -n "s|^$(part "$1") *: *start= *\([0-9]*\), *size= *\([0-9]*\), *type=\([0-9a-f]*\).*|\1 \2 \3|p"
}
[ "$(entry 2)" = "$P2_START $P2_SIZE 83" ] || die "partition 2 is not where Harmattan's is: $(entry 2)"
[ "$(entry 3)" = "$P3_START $P3_SIZE 83" ] || die "partition 3 is not Harmattan's /home: $(entry 3)"
case "$(entry 1) / $(entry 4)" in
"$P1_START $P1_OLD_SIZE c / ")
	STATE=new ;;
"$P1_START $P1_NEW_SIZE c / $P4_START $P4_SIZE 83")
	STATE=again ;;
*)	die "unexpected layout: p1 '$(entry 1)', p4 '$(entry 4)'" ;;
esac
mkdir -p "$MNT"
mount -o ro "$(part 2)" "$MNT"
[ -x "$MNT/sbin/preinit" ] && [ -f "$MNT/etc/init/mount-home.conf" ] ||
	die "partition 2 does not look like Harmattan"
P2_FEATURES=$(dumpe2fs -h "$(part 2)" 2>/dev/null | sed -n 's/^Filesystem features: *//p')
umount "$MNT"
log "  N950 found, partition 2 is Harmattan (ext4: $P2_FEATURES)"

log "checking the image"
[ "$(stat -c %s "$IMG")" -le $((P4_SIZE * 512)) ] || die "$IMG is larger than 4 GiB"
img_features=$(dumpe2fs -h "$IMG" 2>/dev/null | sed -n 's/^Filesystem features: *//p')
for f in $img_features; do
	case " $P2_FEATURES " in *" $f "*) ;; *)
		die "the image has the ext4 feature $f, which Harmattan's p2 lacks (ubiboot could not read it)" ;;
	esac
done
e2fsck -fn "$IMG" > /dev/null || die "$IMG has file system errors"

echo
echo "About to change $DEV ($STATE):"
[ "$STATE" = new ] &&
	echo "  - shrink MyDocs (p1) to $((P1_NEW_SIZE / 2048)) MiB: its files go to $BACKUP and back"
echo "  - write Maemo Leste to p4 ($((P4_SIZE / 2048)) MiB), all of p4 is overwritten"
echo "  - make /home (p3) if it has no file system"
echo "  - add Leste to ubiboot.conf"
if [ "$YES" != --yes ]; then
	read -r -p "Type YES to go on: " answer
	[ "$answer" = YES ] || die "nothing changed"
fi

mkdir -p "$BACKUP"
log "backup in $BACKUP"
echo "$table" > "$BACKUP/partition-table.sfdisk"
dd if="$DEV" of="$BACKUP/first-mib.bin" bs=1M count=1 status=none
mount -o ro "$(part 1)" "$MNT"
tar -C "$MNT" -cf "$BACKUP/mydocs.tar" .
umount "$MNT"
log "  MyDocs: $(du -h "$BACKUP/mydocs.tar" | cut -f1)"

if [ "$STATE" = new ]; then
	log "new partition table"
	label=$(echo "$table" | sed -n 's/^label-id: *//p')
	# PARTUUID needs a disk identifier; Nokia's is 0
	[ "$label" = 0x00000000 ] && label=0x$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')
	sfdisk --no-reread --no-tell-kernel "$DEV" <<EOF
label: dos
label-id: $label
unit: sectors

$(part 1) : start=$P1_START, size=$P1_NEW_SIZE, type=c
$(part 2) : start=$P2_START, size=$P2_SIZE, type=83
$(part 3) : start=$P3_START, size=$P3_SIZE, type=83
$(part 4) : start=$P4_START, size=$P4_SIZE, type=83
EOF
	partx -u "$DEV" || blockdev --rereadpt "$DEV"
	udevadm settle
	log "MyDocs again (as secure-clean makes it) with its files"
	mkfs.vfat -F 32 -R 38 -s 128 -n "Nokia N950" "$(part 1)" > /dev/null
	mount -o utf8,shortname=mixed "$(part 1)" "$MNT"
	tar -C "$MNT" --no-same-owner -xf "$BACKUP/mydocs.tar"
	umount "$MNT"
fi

# (blkid -p alone succeeds on any partition: it reports the table entry)
if [ -z "$(blkid -p -o value -s TYPE "$(part 3)" 2>/dev/null)" ]; then
	log "/home (p3) has no file system: making one with p2's features"
	mke2fs -q -t ext4 -O "none,$(echo "$P2_FEATURES" | tr ' ' ',')" -b 4096 -I 256 \
		-J size=8 -E stripe-width=8 "$(part 3)"
	tune2fs -c 0 -i 0 "$(part 3)" > /dev/null
fi

log "Leste to p4"
dd if="$IMG" of="$(part 4)" bs=4M conv=fsync status=progress
e2fsck -fy "$(part 4)" > /dev/null || [ $? -le 1 ] || die "e2fsck on p4 failed"

log "ubiboot.conf"
mount -o utf8,shortname=mixed "$(part 1)" "$MNT"
conf=$MNT/boot/ubiboot.conf
if [ -f "$conf" ]; then
	cp "$conf" "$BACKUP/ubiboot.conf"
	set_key() {	# set_key KEY VALUE (VALUE already quoted as needed)
		if grep -q "^$1=" "$conf"; then
			sed -i "s|^$1=.*|$1=$2|" "$conf"
		else
			echo "$1=$2" >> "$conf"
		fi
	}
	set_key G_OS5_NAME '"Maemo"'
	set_key G_OS5_PARTITION 4
	set_key G_OS5_NUM 1
	set_key G_OS5_AUTOBOOT 1
	set_key G_OS5_AUTOLOCATION '""'
	set_key G_OS5_INITSCRIPT '"\\/sbin\\/init"'
	set_key G_OS5_INIT_CMDLINE_FILE '"/boot/Maemo/boot/cmdline"'
	set_key G_OS5_INIT_CMDLINE_APPENDS '""'
	set_key G_OS5_1_LABEL '"Leste, Linux 6.18"'
	set_key G_OS5_1_FILE '"/boot/Maemo/boot/zImage"'
	diff "$BACKUP/ubiboot.conf" "$conf" || true
else
	echo "no ubiboot.conf on MyDocs: install ubiboot first, then run this again"
fi
umount "$MNT"
sync
log "done. Backup: $BACKUP"
