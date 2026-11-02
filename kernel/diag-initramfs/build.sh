#!/bin/bash
# The diagnostic kernel's initramfs (kernel/diag-initramfs/init): an armhf
# busybox with its libraries and the init script, as a directory and a
# gen_init_cpio list for the kernel's CONFIG_INITRAMFS_SOURCE.
#
#   BUSYBOX_ROOT=<a root with sbin/busybox and lib/> OUT=<dir> \
#       bash kernel/diag-initramfs/build.sh
#
# then DIAG=1 INITRAMFS="$OUT/root $OUT/nodes.list" bash kernel/build.sh.
# MOSLO's initrd has such a busybox (1.21, linked against glibc in lib/).
# The initramfs is built into the kernel because MOSLO's kexec (2012) puts
# an external one where the decompressed 6.18 kernel overwrites it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${BUSYBOX_ROOT:?set BUSYBOX_ROOT=<root with sbin/busybox and lib/>}
OUT=${OUT:?set OUT=<output directory>}
R=$OUT/root
rm -rf "${R:?}"
mkdir -p "$R"/{bin,sbin,dev,proc,sys,lib,mnt,tmp}
cp "$SRC/sbin/busybox" "$R/bin/busybox"
for l in $(readelf -d "$SRC/sbin/busybox" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
	cp -L "$SRC/lib/$l" "$R/lib/"
done
install -m 755 "$HERE/init" "$R/init"
printf '%s\n' 'nod /dev/console 0600 0 0 c 5 1' > "$OUT/nodes.list"
echo "$R $OUT/nodes.list"
