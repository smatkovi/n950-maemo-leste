#!/bin/bash
# Call audio for the N950: cmt_pulse from Leste's libcmtspeechdata. While
# ofono reports a call (org.ofono.AudioSettings "Active", from its n900
# plugin), cmt_pulse moves the modem's speech frames between /dev/cmt_speech
# and PulseAudio (PipeWire here): the downlink to the default sink, the
# uplink from the default source, 8 kHz mono. sphone switches the card to a
# "Voice Call" profile for the call (rootfs/overlay/usr/share/alsa/ucm2).
#
# Builds cmt_pulse in an armhf root (a chroot through qemu-arm-static) and
# packs it as libcmtspeechdata, with only cmt_pulse, its start in the X
# session (dsmetool restarts it) and the udev rule that lets the session
# open /dev/cmt_speech (group audio; the node is root-only otherwise).
#
#   SYSROOT=<armhf root with gcc, make, git, libpulse-dev, libdbus-1-dev> \
#     bash apps/cmt-pulse/build-deb.sh OUTDIR
#
# Needs sudo (chroot) and qemu-arm-static on the PC.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?usage: SYSROOT=<armhf root> build-deb.sh OUTDIR}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
URL=https://github.com/maemo-leste/libcmtspeechdata
REV=c584598
VERSION=0.1.2.6-1+n950.1
B=/root/build/libcmtspeechdata-n950

mounted=()
cleanup() {
	for m in "${mounted[@]}"; do sudo -n umount "$SYSROOT/$m" 2>/dev/null || true; done
	sudo -n rm -rf "$SYSROOT$B"
	rm -rf "${W:-}"
}
trap cleanup EXIT
for m in proc dev; do
	sudo -n mountpoint -q "$SYSROOT/$m" && continue
	sudo -n mount --bind "/$m" "$SYSROOT/$m"
	mounted=("$m" "${mounted[@]}")
done
sudo -n chroot "$SYSROOT" /bin/sh -ec "
	rm -rf $B; git clone -q $URL $B; cd $B; git checkout -q $REV
	make -s libcmtspeech.a cmt_pulse"

W=$(mktemp -d)
R=$W/root
mkdir -p "$R/usr/bin" "$R/etc/X11/Xsession.d" "$R/lib/udev/rules.d" "$W/DEBIAN" "$OUT"
sudo -n cat "$SYSROOT$B/cmt_pulse" > "$R/usr/bin/cmt_pulse"
sudo -n cat "$SYSROOT$B/debian/xsession" > "$R/etc/X11/Xsession.d/96libcmtspeechdata"
chmod 755 "$R/usr/bin/cmt_pulse" "$R/etc/X11/Xsession.d/96libcmtspeechdata"
llvm-strip --strip-unneeded "$R/usr/bin/cmt_pulse"
install -m 644 "$HERE/60-cmt-speech.rules" "$R/lib/udev/rules.d/"

cat > "$W/DEBIAN/control" <<CTL
Package: libcmtspeechdata
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: $(bash "$HERE/../../tools/debdeps.sh" "$R" "$SYSROOT"), dsme, udev
Section: misc
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: call audio for Nokia modems (cmt_pulse), N950 build
 cmt_pulse from Leste's libcmtspeechdata ($REV): while ofono has a call
 active it carries the modem's speech data between /dev/cmt_speech and
 PulseAudio or PipeWire. Started in the X session through dsmetool; a
 udev rule gives the group audio access to /dev/cmt_speech.
CTL
cat > "$W/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v udevadm >/dev/null; then
	udevadm control --reload 2>/dev/null || true
	udevadm trigger --subsystem-match=misc --sysname-match=cmt_speech 2>/dev/null || true
fi
SH
bash "$HERE/../../tools/mkdeb.sh" "$R" "$W/DEBIAN" "$OUT/libcmtspeechdata_${VERSION}_armhf.deb"
