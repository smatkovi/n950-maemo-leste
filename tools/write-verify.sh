#!/bin/bash
# Write an image to a block device in chunks and read every chunk back
# from the device itself (O_DIRECT, past the page cache), rewriting a chunk
# whose MD5 differs. For the phones' USB mass-storage export (ubiboot,
# MOSLO: Linux 2.6.32's file-storage gadget), which once corrupted long
# writes on the N950.
#
#   write-verify.sh IMAGE DEVICE [CHUNK_MIB]
#
# The device must be at least as large as the image; the rest of it is left
# as it is. Needs sudo.
set -euo pipefail
IMG=${1:?usage: write-verify.sh IMAGE DEVICE [CHUNK_MIB]}
DEV=${2:?usage: write-verify.sh IMAGE DEVICE [CHUNK_MIB]}
CH=${3:-64}
size=$(stat -c %s "$IMG")
devsize=$(sudo -n blockdev --getsize64 "$DEV")
[ "$size" -le "$devsize" ] || { echo "$IMG ($size B) is larger than $DEV ($devsize B)"; exit 1; }
[ $((size % 1048576)) -eq 0 ] || { echo "$IMG is not a whole number of MiB"; exit 1; }
mib=$((size / 1048576))
n=$(((mib + CH - 1) / CH))

chunk_md5() {	# file|device, chunk index, extra dd flag
	local cnt=$CH
	[ $((($2 + 1) * CH)) -gt "$mib" ] && cnt=$((mib - $2 * CH))
	sudo -n dd if="$1" bs=1M skip=$(($2 * CH)) count=$cnt $3 status=none | md5sum | cut -d' ' -f1
}
write_chunk() {
	local cnt=$CH
	[ $((($1 + 1) * CH)) -gt "$mib" ] && cnt=$((mib - $1 * CH))
	sudo -n dd if="$IMG" of="$DEV" bs=1M skip=$(($1 * CH)) seek=$(($1 * CH)) count=$cnt \
		oflag=direct conv=notrunc,fsync status=none
}

echo "writing $mib MiB in $n chunks of $CH MiB to $DEV"
t0=$(date +%s)
for ((i = 0; i < n; i++)); do
	write_chunk $i
	printf '\r  %d/%d' $((i + 1)) $n
done
echo "  ($(( $(date +%s) - t0 )) s)"
sudo -n blockdev --flushbufs "$DEV"

bad=0
for ((i = 0; i < n; i++)); do
	want=$(chunk_md5 "$IMG" $i "")
	ok=0
	for try in 1 2 3 4; do
		got=$(chunk_md5 "$DEV" $i iflag=direct)
		[ "$got" = "$want" ] && { ok=1; break; }
		echo "  chunk $i differs (try $try), writing it again"
		write_chunk $i
	done
	[ $ok = 1 ] || { echo "  chunk $i still differs"; bad=$((bad + 1)); }
	printf '\r  verified %d/%d' $((i + 1)) $n
done
echo
[ $bad = 0 ] && echo "OK: $mib MiB on $DEV match $IMG" || { echo "FAILED: $bad chunks differ"; exit 1; }
