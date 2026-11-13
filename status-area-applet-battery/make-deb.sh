#!/bin/bash
# Packs the patched applet as a .deb that replaces Leste's package.
#
#   SYSROOT=<armhf root> bash status-area-applet-battery/make-deb.sh DESTDIR VERSION OUTDIR
#
# DESTDIR: `make install DESTDIR=...` of the patched source tree (configured
# with --prefix=/usr --libdir=/usr/lib/arm-linux-gnueabihf).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
D=$(cd "${1:?destdir}" && pwd)
VERSION=${2:?version, e.g. 1.5.9-1+5m7n950.1}
OUT=$(realpath -m "${3:?outdir}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
R=$W/root
L=usr/lib/arm-linux-gnueabihf/hildon-desktop
mkdir -p "$R/$L" "$R/usr/share/applications/hildon-status-menu" "$R/etc/gconf/schemas" "$W/DEBIAN" "$OUT"
install -m 644 "$D/$L/status-area-applet-battery.so" "$R/$L/"
llvm-strip --strip-unneeded "$R/$L/status-area-applet-battery.so"
install -m 644 "$D"/usr/share/applications/hildon-status-menu/status-area-applet-battery.desktop \
	"$R/usr/share/applications/hildon-status-menu/"
# where Leste's package has it, a conffile
install -m 644 "$(find "$D" -name status-area-applet-battery.schemas | head -1)" "$R/etc/gconf/schemas/"
echo /etc/gconf/schemas/status-area-applet-battery.schemas > "$W/DEBIAN/conffiles"
for s in 48x48 scalable; do
	mkdir -p "$R/usr/share/icons/hicolor/$s/hildon"
	install -m 644 "$HERE"/icons/$s/hildon/*.png "$R/usr/share/icons/hicolor/$s/hildon/"
done
cat > "$W/DEBIAN/control" <<CTL
Package: status-area-applet-battery
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: $(bash "$HERE/../tools/debdeps.sh" "$R" "$SYSROOT" 2>/dev/null), libhildondesktop1, libprofile0, osso-dsm-ui-l10n-mr0, osso-clock-l10n-mr0, mediaplayer-l10n-mr0, osso-sounds-ui, profiled (>= 0.0.3), upower
Section: x11
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: status area battery applet
 Battery applet for the status area. This will show the battery information.
 .
 N950 build: while charging, the charge level with a lightning bolt instead
 of an animation that reloaded its icon every second.
CTL
# as Leste's maintainer scripts: a failing gconf-schemas does not fail the install
cat > "$W/DEBIAN/postinst" <<'SH'
#!/bin/sh
if [ "$1" = configure ]; then
	gconf-schemas --register status-area-applet-battery.schemas
	[ -x /usr/bin/gtk-update-icon-cache ] && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
fi
SH
cat > "$W/DEBIAN/prerm" <<'SH'
#!/bin/sh
case "$1" in
remove|upgrade|deconfigure) gconf-schemas --unregister status-area-applet-battery.schemas ;;
esac
SH
bash "$HERE/../tools/mkdeb.sh" "$R" "$W/DEBIAN" "$OUT/status-area-applet-battery_${VERSION}_armhf.deb"
