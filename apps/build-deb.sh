#!/bin/bash
# Builds one of apps/ as an armhf .deb for Leste, in a chroot of a Leste
# image (rootfs/build.sh's, or Leste's N900 image) through qemu-arm-static.
#
#   IMG=n950-leste.img OUT=out-dir [UPPER=dir] bash apps/build-deb.sh n950-fm
#
# The image stays untouched: its root is mounted read-only under an
# overlay whose upper directory (UPPER, default $OUT/chroot) keeps the
# build dependencies for the next run. Needs sudo, qemu-user-static.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:?usage: IMG=<image> OUT=<dir> bash apps/build-deb.sh <app>}
IMG=${IMG:?set IMG=<Leste image>}
OUT=${OUT:?set OUT=<directory for the .deb>}
UPPER=${UPPER:-$OUT/chroot}
SRC_DIR=$REPO/apps/$APP
[ -f "$SRC_DIR/debian/control" ] || { echo "no apps/$APP/debian/control"; exit 1; }
LOWER=/mnt/n950-deb-lower
ROOT=/mnt/n950-deb-root
log() { echo ">> $*"; }

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
cleanup() {
	set +e
	binfmt_restore
	for m in "$ROOT/mnt/src" "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/proc" "$ROOT" "$LOWER"; do
		mountpoint -q "$m" && sudo -n umount -l "$m"
	done
}
trap cleanup EXIT

mkdir -p "$OUT"
sudo -n mkdir -p "$LOWER" "$ROOT" "$UPPER/upper" "$UPPER/work"
off=$(sfdisk -J "$IMG" 2>/dev/null | python3 -I -c '
import json, sys
p = json.load(sys.stdin)["partitiontable"]["partitions"]
print(max(p, key=lambda e: e["size"])["start"] * 512)' 2>/dev/null || echo 0)
sudo -n mount -o ro,loop,offset="$off" "$IMG" "$LOWER"
sudo -n mount -t overlay overlay \
	-o lowerdir="$LOWER",upperdir="$UPPER/upper",workdir="$UPPER/work" "$ROOT"
sudo -n mount -t proc proc "$ROOT/proc"
sudo -n mount --bind /dev "$ROOT/dev"
sudo -n mount --bind /dev/pts "$ROOT/dev/pts"
sudo -n mkdir -p "$ROOT/mnt/src"
sudo -n mount --bind "$SRC_DIR" "$ROOT/mnt/src"
sudo -n cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
binfmt_use_static

log "build dependencies of $APP"
deps=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "$SRC_DIR/debian/control" |
	sed '1s/^Build-Depends://; /^[A-Z]/d' | tr ',' '\n' |
	sed 's/([^)]*)//g; s/|.*//; s/^ *//; s/ *$//' | grep -v '^$' | xargs)
sudo -n chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	DEBIAN_FRONTEND=noninteractive LC_ALL=C /bin/bash -c "
	set -e
	apt-get -q update > /dev/null 2>&1 || true
	apt-get -q -y --no-install-recommends install build-essential fakeroot $deps > /tmp/deps.log 2>&1 ||
		{ tail -20 /tmp/deps.log; exit 1; }"

log "dpkg-buildpackage $APP"
sudo -n chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LC_ALL=C /bin/bash -c "
	set -e
	rm -rf /root/build && mkdir -p /root/build && cp -a /mnt/src /root/build/$APP
	cd /root/build/$APP
	dpkg-buildpackage -b -us -uc > ../build.log 2>&1 || { tail -30 ../build.log; exit 1; }
	ls ../*.deb"
# root's home is not readable from outside: the copy runs as root
sudo -n sh -c "cp '$ROOT'/root/build/*.deb '$ROOT'/root/build/build.log '$OUT'/ &&
	chown $(id -u):$(id -g) '$OUT'/*.deb '$OUT'/build.log"
ls "$OUT"/*.deb
