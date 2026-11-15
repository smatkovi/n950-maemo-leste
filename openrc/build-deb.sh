#!/bin/bash
# Devuan's openrc 0.56-1 with the patch in this directory, as armhf .debs
# that replace it on the phone (openrc, librc1t64, libeinfo1).
#
# Builds in an armhf root (a chroot through qemu-arm-static) that has
# build-essential, devscripts, equivs and a deb-src line for excalibur.
#
#   SYSROOT=<armhf root> bash openrc/build-deb.sh OUTDIR
#
# Needs sudo (chroot) and qemu-arm-static on the PC.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?usage: SYSROOT=<armhf root> build-deb.sh OUTDIR}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
VERSION=0.56-1+n950.1
B=/root/build/openrc-n950

mounted=()
cleanup() {
	for m in "${mounted[@]}"; do sudo -n umount "$SYSROOT/$m" 2>/dev/null || true; done
	sudo -n rm -rf "$SYSROOT$B"
}
trap cleanup EXIT
for m in proc dev; do
	sudo -n mountpoint -q "$SYSROOT/$m" && continue
	sudo -n mount --bind "/$m" "$SYSROOT/$m"
	mounted=("$m" "${mounted[@]}")
done
sudo -n rm -rf "$SYSROOT$B"
sudo -n mkdir -p "$SYSROOT$B/patches"
sudo -n cp "$HERE/patches"/*.patch "$SYSROOT$B/patches/"
sudo -n chroot "$SYSROOT" /bin/bash -ec "
	export DEBIAN_FRONTEND=noninteractive LC_ALL=C
	grep -q '^deb-src .*excalibur main' /etc/apt/sources.list ||
		echo 'deb-src https://pkgmaster.devuan.org/merged excalibur main' >> /etc/apt/sources.list
	apt-get -qq update
	apt-get -qq -y install build-essential devscripts equivs >/dev/null
	cd $B
	apt-get -qq source openrc=0.56-1
	cd openrc-0.56
	for p in $B/patches/*.patch; do
		cp \$p debian/patches/
		echo \$(basename \$p) >> debian/patches/series
		patch -p1 < \$p
	done
	DEBEMAIL=smatkovi@users.noreply.github.com DEBFULLNAME='Sebastian Matkovich' \
		dch -v $VERSION --distribution excalibur --force-distribution \
		'N950: sysinit uses the dependency cache on bare metal (saves ~12 s per boot)'
	mk-build-deps -i -r -t 'apt-get -qq -y --no-install-recommends' debian/control >/dev/null
	DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc -j\$(nproc) >/dev/null 2>&1
"
mkdir -p "$OUT"
for p in openrc librc1t64 libeinfo1; do
	sudo -n cat "$SYSROOT$B/${p}_${VERSION}_armhf.deb" > "$OUT/${p}_${VERSION}_armhf.deb"
done
echo "built in $OUT:"; ls -1 "$OUT"/*_"${VERSION}"_armhf.deb
