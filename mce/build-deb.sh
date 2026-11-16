#!/bin/bash
# Leste's mce 1.10.19 with the patches in this directory, as mce
# 1.10.19+5m7n950.1 (mce, mce-dev, mce-dbgsym).
#
# The source is maemo-leste/mce at d326052, the 1.10.19 that Leste ships as
# 1.10.19+5m7. Patches 0001-0003 go on top; 0004 is upstream since 1.10.19
# (b48b461) and only mattered for builds from older trees.
#
#   SYSROOT=<armhf root with mce's build dependencies> bash mce/build-deb.sh OUTDIR
#
# The root is entered with chroot (qemu-arm-static through binfmt on a PC);
# it needs Leste's -dev packages that debian/control names (libdsme,
# osso-systemui, ...). Needs sudo, git.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?usage: SYSROOT=<armhf root> build-deb.sh OUTDIR}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
URL=https://github.com/maemo-leste/mce
COMMIT=d326052
VERSION=1.10.19+5m7n950.1
B=/build/mce-n950

W=$(mktemp -d)
cleanup() {
	for m in dev/pts dev proc; do sudo -n umount "$SYSROOT/$m" 2>/dev/null || true; done
	rm -rf "$W"
}
trap cleanup EXIT

git clone -q "$URL" "$W/mce"
git -C "$W/mce" checkout -q "$COMMIT"
for p in "$HERE"/patches/000[123]-*.patch; do
	git -C "$W/mce" apply "$p"
done
{
	cat <<EOF
mce ($VERSION) unstable; urgency=medium

  * N950/N9 (github.com/smatkovi/n950-maemo-leste, mce/patches):
  * lock-tklock: optionally a power-key press wakes and unlocks at once
    ([PowerKey] PowerKeyUnlocks, off by default)
  * display: the first unblank after boot never writes brightness -1 (the
    display stayed dark after the first lock)
  * display: a brightness fade towards the current brightness never steps
    by 0 (it rewrote the brightness every 10 ms for ever)

 -- Sebastian Matkovich <smatkovi@users.noreply.github.com>  Mon, 16 Nov 2026 10:05:00 +0100

EOF
	cat "$W/mce/debian/changelog"
} > "$W/changelog"
mv "$W/changelog" "$W/mce/debian/changelog"
rm -rf "$W/mce/.git"

sudo -n rm -rf "$SYSROOT$B" "$SYSROOT"/build/mce*_"$VERSION"_*
sudo -n mkdir -p "$SYSROOT/build"
sudo -n cp -a "$W/mce" "$SYSROOT$B"
for m in proc dev dev/pts; do
	sudo -n mountpoint -q "$SYSROOT/$m" || sudo -n mount --bind "/$m" "$SYSROOT/$m"
done
sudo -n chroot "$SYSROOT" /bin/sh -ec "
	export LC_ALL=C DEB_BUILD_OPTIONS=parallel=$(nproc)
	cd $B
	dpkg-checkbuilddeps
	dpkg-buildpackage -b -us -uc > ../mce-n950-build.log 2>&1"
mkdir -p "$OUT"
for f in "$SYSROOT"/build/mce*_"$VERSION"_armhf.deb; do
	sudo -n cat "$f" > "$OUT/${f##*/}"
done
ls -l "$OUT"/mce*_"$VERSION"_armhf.deb
