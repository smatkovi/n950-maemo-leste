#!/bin/bash
# FingerTerm, the touch terminal with its own keyboard (Esc, Tab, Ctrl, arrows,
# Enter in one screen with the terminal), as an armhf .deb for Maemo Leste on
# the N9, which has no hardware keyboard. Hildon's own on-screen keyboard is a
# full-screen one that hands its text over only when it closes, unusable for a
# terminal.
#
# Source: sailfishos/fingerterm (Qt 5, QtQuick 2, nothing of Sailfish needed),
# built in an armhf root that has qtbase5-dev and qtdeclarative5-dev.
#
#   SYSROOT=<armhf root> bash apps/fingerterm/build-deb.sh OUTDIR
#
# Needs sudo (chroot through qemu-arm-static), git and tools/mkdeb.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?usage: SYSROOT=<armhf root> build-deb.sh OUTDIR}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
URL=https://github.com/sailfishos/fingerterm
COMMIT=5c3495336895
UPSTREAM=1.5.0
VERSION=$UPSTREAM-n950.1
B=/build/fingerterm-n950

W=$(mktemp -d)
cleanup() {
	for m in dev/pts dev proc; do sudo -n umount "$SYSROOT/$m" 2>/dev/null || true; done
	sudo -n rm -rf "$SYSROOT$B"
	rm -rf "$W"
}
trap cleanup EXIT

git clone -q "$URL" "$W/src"
git -C "$W/src" checkout -q "$COMMIT"
rm -rf "$W/src/.git"

sudo -n rm -rf "$SYSROOT$B"
sudo -n mkdir -p "$SYSROOT/build"
sudo -n cp -a "$W/src" "$SYSROOT$B"
for m in proc dev dev/pts; do
	sudo -n mountpoint -q "$SYSROOT/$m" || sudo -n mount --bind "/$m" "$SYSROOT/$m"
done
sudo -n chroot "$SYSROOT" /bin/sh -ec "
	export LC_ALL=C
	cd $B
	/usr/lib/qt5/bin/qmake VERSION_STRING=$UPSTREAM DEPLOYMENT_PATH=/usr/share/fingerterm fingerterm.pro
	make -j$(nproc)
	make install INSTALL_ROOT=$B/root
	strip --strip-unneeded $B/root/usr/bin/fingerterm"

R=$W/root
mkdir -p "$R" "$W/DEBIAN"
sudo -n cp -a "$SYSROOT$B/root/." "$R/"
sudo -n chown -R "$(id -u):$(id -g)" "$R"
# the installed .desktop is Sailfish's; Hildon's menu reads its own
rm -rf "$R/usr/share/applications" "$R/usr/share/icons"
install -D -m 755 "$HERE/fingerterm-leste" "$R/usr/bin/fingerterm-leste"
install -D -m 644 "$HERE/fingerterm.desktop" "$R/usr/share/applications/hildon/fingerterm.desktop"
install -D -m 644 "$W/src/fingerterm.png" "$R/usr/share/icons/hicolor/64x64/apps/fingerterm.png"
install -D -m 644 "$W/src/COPYING" "$R/usr/share/doc/fingerterm/copyright"
cat > "$W/DEBIAN/control" <<CTL
Package: fingerterm
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: libc6, libqt5core5t64 | libqt5core5a, libqt5gui5t64 | libqt5gui5 | libqt5gui5-gles, libqt5qml5, libqt5quick5 | libqt5quick5-gles, qml-module-qtquick2, qml-module-qtquick-window2, fonts-dejavu-core
Section: x11
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: terminal with its own on-screen keyboard
 FingerTerm (sailfishos/fingerterm $COMMIT), a terminal for touch screens:
 the keyboard (Esc, Tab, Ctrl, Alt, arrows, Enter) shares the screen with
 the terminal and its keys go straight to the shell. For the Nokia N9 under
 Maemo Leste, which has no hardware keyboard.
CTL
mkdir -p "$OUT"
bash "$HERE/../../tools/mkdeb.sh" "$R" "$W/DEBIAN" "$OUT/fingerterm_${VERSION}_armhf.deb"
ls -l "$OUT/fingerterm_${VERSION}_armhf.deb"
