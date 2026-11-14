#!/bin/bash
# Leste's WLAN module for icd2 (libicd-network-wpasupplicant 0.1.20) with the
# patches in this directory, as an armhf .deb that replaces Leste's package.
#
# Builds in an armhf root (a chroot through qemu-arm-static) that has gcc,
# make, autoconf, automake, libtool, pkg-config, git, libglib2.0-dev,
# libdbus-glib-1-dev and libgconf2-dev. Leste's own -dev packages are not
# needed: their headers come from Leste's sources on GitHub (fixed
# revisions), libicd_log is built from icd2's source for linking only,
# libwpa_client from wpa_supplicant 2.10, OpenSSL's headers (which
# maemosec_certman.h includes) from Devuan's libssl-dev, unpacked only.
#
#   SYSROOT=<armhf root> bash icd2-wlan/build-deb.sh OUTDIR
#
# Needs sudo (chroot), curl, git and tools/mkdeb.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?usage: SYSROOT=<armhf root> build-deb.sh OUTDIR}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
VERSION=0.1.20+5m7n950.2
ICD_VERSION=0.99.1
GH=https://github.com/maemo-leste
SRCS="libicd-network-wpasupplicant:bee40ad46692 icd2:c3e9ae13f3f4
	icd2-osso-ic-dev:acf440d9d3f2 connui-common:4c6a4e1eb453
	maemo-security-certman:12197ea20c99"
WPA=https://w1.fi/releases/wpa_supplicant-2.10.tar.gz
WPA_SHA256=20df7ae5154b3830355f8ab4269123a87affdea59fe74fe9292a91d0d7e17b2f
B=/root/build/icd2-wlan-n950

W=$(mktemp -d)
mounted=()
cleanup() {
	for m in "${mounted[@]}"; do sudo -n umount "$SYSROOT/$m" 2>/dev/null || true; done
	sudo -n rm -rf "$SYSROOT$B"
	rm -rf "$W"
}
trap cleanup EXIT

# sources, on this side (the chroot needs no access to GitHub)
for s in $SRCS; do
	name=${s%%:*} rev=${s##*:}
	git clone -q "$GH/$name" "$W/src/$name"
	git -C "$W/src/$name" checkout -q "$rev"
done
for p in "$HERE"/0*.patch; do
	git -C "$W/src/libicd-network-wpasupplicant" apply "$p"
done
curl -fsSL -o "$W/wpa.tar.gz" "$WPA"
echo "$WPA_SHA256  $W/wpa.tar.gz" | sha256sum -c --quiet
mkdir -p "$W/src/wpa"
tar -xzf "$W/wpa.tar.gz" -C "$W/src/wpa" --strip-components=1 \
	wpa_supplicant-2.10/src/common wpa_supplicant-2.10/src/utils

# headers as Leste's -dev packages install them
I=$W/stage/inc
mkdir -p "$I/icd/support" "$I/connui" "$W/stage/pc" "$W/stage/lib"
cp "$W"/src/icd2/icd/*.h "$I/icd/"
sed "s/@PACKAGE_VERSION@/$ICD_VERSION/" "$W/src/icd2/icd/network_api.h.in" > "$I/icd/network_api.h"
cp "$W"/src/icd2/support/*.h "$I/icd/support/"
cp "$W"/src/icd2-osso-ic-dev/include/*.h "$I/"
cp "$W"/src/connui-common/include/wlancond*.h "$I/"
cp "$W/src/connui-common/include/libicd-network-wlan-dev.h" "$I/connui/"
cp "$W"/src/maemo-security-certman/include/*.h "$I/"
cp "$W/src/wpa/src/common/wpa_ctrl.h" "$I/"
cat > "$W/stage/pc/icd2.pc" <<EOF
icdplugindir=/usr/lib/icd2

Name: icd2
Description: icd2 module API (maemo-leste/icd2 $ICD_VERSION)
Version: $ICD_VERSION
Requires: glib-2.0
Cflags: -I$B/stage/inc -I$B/stage/inc/icd
Libs: -L$B/stage/lib -licd_log
EOF
cat > "$W/stage/pc/maemosec-certman.pc" <<EOF
Name: maemosec-certman
Description: certificate manager headers (maemo-leste/maemo-security-certman)
Version: 0
Cflags: -I$B/stage/inc -I$B/stage/ssl/usr/include -I$B/stage/ssl/usr/include/arm-linux-gnueabihf
EOF

for m in proc dev; do
	sudo -n mountpoint -q "$SYSROOT/$m" && continue
	sudo -n mount --bind "/$m" "$SYSROOT/$m"
	mounted=("$m" "${mounted[@]}")
done
sudo -n rm -rf "$SYSROOT$B"
sudo -n mkdir -p "$SYSROOT$B"
sudo -n cp -a "$W/src" "$W/stage" "$SYSROOT$B/"
sudo -n chroot "$SYSROOT" /bin/sh -ec "
	export LC_ALL=C
	cd $B/stage
	mkdir ssl
	(cd ssl; apt-get -qq download libssl-dev 2>/dev/null; dpkg-deb -x libssl-dev_*.deb .)
	mkdir cfg
	printf '#define PACKAGE \"icd2\"\n#define VERSION \"$ICD_VERSION\"\n' > cfg/config.h
	gcc -O2 -fPIC -shared -Wl,-soname,libicd_log.so.1 -I cfg -I inc/icd \
		\$(pkg-config --cflags glib-2.0) -o lib/libicd_log.so.1 $B/src/icd2/support/icd_log.c
	ln -s libicd_log.so.1 lib/libicd_log.so
	cd $B/src/wpa
	for f in src/common/wpa_ctrl.c src/utils/os_unix.c; do
		gcc -O2 -fPIC -c -Isrc -Isrc/utils -DCONFIG_CTRL_IFACE -DCONFIG_CTRL_IFACE_UNIX \$f
	done
	ar rcs $B/stage/lib/libwpa_client.a wpa_ctrl.o os_unix.o
	cd $B/src/libicd-network-wpasupplicant
	autoreconf -fi >/dev/null 2>&1
	PKG_CONFIG_PATH=$B/stage/pc ./configure -q --prefix=/usr
	make -s WPA_CLIENT_LIBS=$B/stage/lib/libwpa_client.a"

S=$B/src/libicd-network-wpasupplicant
R=$W/root
D=$R/usr/share/doc/libicd-network-wpasupplicant
mkdir -p "$R/usr/lib/icd2" "$D" "$W/DEBIAN" "$OUT"
sudo -n cat "$SYSROOT$S/src/.libs/libicd_network_wpasupplicant.so" > "$R/usr/lib/icd2/libicd_network_wpasupplicant.so"
chmod 644 "$R/usr/lib/icd2/libicd_network_wpasupplicant.so"
llvm-strip --strip-unneeded "$R/usr/lib/icd2/libicd_network_wpasupplicant.so"
cp "$W/src/libicd-network-wpasupplicant/debian/copyright" "$D/"
{
	cat <<EOF
libicd-network-wpasupplicant ($VERSION) unstable; urgency=medium

  * N950 (github.com/smatkovi/n950-maemo-leste, icd2-wlan/): let
    wpa_supplicant reconnect for 15 s after the AP drops the station before
    the connection is closed

 -- Sebastian Matkovich <smatkovi@users.noreply.github.com>  $(date -R)

EOF
	cat "$W/src/libicd-network-wpasupplicant/debian/changelog"
} | gzip -9n > "$D/changelog.gz"
for s in postinst prerm; do
	cp "$W/src/libicd-network-wpasupplicant/debian/libicd-network-wpasupplicant.$s" "$W/DEBIAN/$s"
done
cat > "$W/DEBIAN/control" <<CTL
Package: libicd-network-wpasupplicant
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: icd2 (>= 0.55), gconf-service, libc6 (>= 2.34), libgconf-2-4 (>= 3.2.5), libglib2.0-0t64 (>= 2.40.0), libicd2, icd2-network-wpasupplicant-config, libicd-network-ipv4
Section: net
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: ICd2 plugin for WLAN networking
 The WLAN plugin for ICd2 that provides WLAN networking. N950 build: when
 the access point drops the connection, wpa_supplicant gets 15 s to
 reconnect before icd2 closes it, so a drop costs well under a second
 instead of about 12.
CTL
bash "$HERE/../tools/mkdeb.sh" "$R" "$W/DEBIAN" "$OUT/libicd-network-wpasupplicant_${VERSION}_armhf.deb"
