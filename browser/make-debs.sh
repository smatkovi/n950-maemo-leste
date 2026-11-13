#!/bin/bash
# Packs the N950 browsers as armhf .debs for a release (tools/mkdeb.sh, no
# dpkg needed). Dependencies are the packages of SYSROOT (the armhf root the
# browsers were built against) that hold the libraries the binaries need.
#
#   SYSROOT=<armhf root> bash browser/make-debs.sh embedlite VERSION OUTDIR
#     STAGE        engine installed by embedlite-n950/build.sh install
#     COMPONENTS   embedlite-components installed (mozembedlite-next153)
#     QTMOZEMBED   qtmozembed build tree (src/, qmlplugin5/)
#     SHELL_BIN    the shell built from embedlite-n950/shell
#     SHADER_CACHE .tgz of shader-cache/ made by gen-shader-cache.sh on the phone
#
#   SYSROOT=<armhf root> bash browser/make-debs.sh firefox VERSION OUTDIR
#     FF_TARBALL   firefox-n950 package (firefox-n950/build.sh package)
#     SHADER_CACHE .tgz of shader-cache/ made by files/gen-shader-cache.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WHAT=${1:?usage: make-debs.sh embedlite|firefox VERSION OUTDIR}
VERSION=${2:?version}
OUT=$(realpath -m "${3:?outdir}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
LIB=usr/lib/arm-linux-gnueabihf
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
R=$W/root
mkdir -p "$R" "$W/DEBIAN" "$OUT"

depends() { bash "$HERE/../tools/debdeps.sh" "$1" "$SYSROOT"; }

strip_elves() {
	find "$1" -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) -print0 |
	while IFS= read -r -d '' f; do
		if [ "$(head -c4 "$f" | od -An -c | tr -d ' ')" = '177ELF' ]; then llvm-strip --strip-unneeded "$f"; fi
	done
}

case $WHAT in
embedlite)
	G=$LIB/xulrunner-qt5-153.6.0
	mkdir -p "$R/$G" "$R/$LIB/qt5/qml/Qt5MozillaNext153" "$R/usr/bin" \
		"$R/usr/share/applications/hildon" \
		"$R/usr/share/icons/hicolor/48x48/apps" "$R/usr/share/icons/hicolor/64x64/apps"
	cp -a "${STAGE:?}/$G"/. "$R/$G/"
	tar -xzf "${SHADER_CACHE:?}" -C "$R/$G"
	cp -a "${COMPONENTS:?}/$LIB/mozembedlite-next153" "$R/$LIB/"
	cp -a "${QTMOZEMBED:?}"/src/libqt5embedwidget-next153.so.1* "$R/$LIB/"
	cp -a "$QTMOZEMBED"/qmlplugin5/libqmlmozembedpluginqt5.so "$QTMOZEMBED"/qmlplugin5/qmldir \
		"$R/$LIB/qt5/qml/Qt5MozillaNext153/"
	install -m 755 "${SHELL_BIN:?}" "$R/usr/bin/embedlite-shell"
	install -m 644 "$HERE/embedlite-n950/shell/embedlite-shell.desktop" "$R/usr/share/applications/hildon/"
	install -m 644 "$HERE/embedlite-n950/shell/embedlite-shell-48.png" "$R/usr/share/icons/hicolor/48x48/apps/embedlite-shell.png"
	install -m 644 "$HERE/embedlite-n950/shell/embedlite-shell-64.png" "$R/usr/share/icons/hicolor/64x64/apps/embedlite-shell.png"
	strip_elves "$R"
	cat > "$W/DEBIAN/control" <<CTL
Package: embedlite-n950
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: $(depends "$R")
Recommends: sgx-ddk-um-n950
Section: web
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: Gecko ESR 153 browser engine (EmbedLite) and test shell for the N950
 The EmbedLite engine with WebRender on the SGX530 (OpenGL ES 2.0), its
 Qt 5 binding qtmozembed and QML plugin, and "Browser (EmbedLite)", a
 minimal browser shell: address line, back/forward/reload, settings for
 animations and edge anti-aliasing. WebRender's shader programs come
 compiled for the SGX530.
CTL
	;;
firefox)
	mkdir -p "$R/opt" "$R/usr/bin" "$R/usr/share/applications/hildon" \
		"$R/usr/share/icons/hicolor/48x48/apps" "$R/usr/share/icons/hicolor/64x64/apps"
	tar -xJf "${FF_TARBALL:?}" -C "$R/opt"
	F=$HERE/firefox-n950/files
	install -m 644 "$F/n950-lowmem.js" "$F/n950-touch.js" "$R/opt/firefox-n950/defaults/pref/"
	sh "$F/fetch-extensions.sh" "$R/opt/firefox-n950" >/dev/null
	[ -n "${SHADER_CACHE:-}" ] && tar -xzf "$SHADER_CACHE" -C "$R/opt/firefox-n950"
	install -m 755 "$F/firefox-n950" "$R/usr/bin/firefox-n950"
	install -m 644 "$F/firefox-n950.desktop" "$R/usr/share/applications/hildon/"
	for s in 48 64; do
		install -m 644 "$R/opt/firefox-n950/browser/chrome/icons/default/default$s.png" \
			"$R/usr/share/icons/hicolor/${s}x$s/apps/firefox-n950.png"
	done
	cat > "$W/DEBIAN/control" <<CTL
Package: firefox-n950
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <smatkovi@users.noreply.github.com>
Depends: $(depends "$R"), wmctrl
Recommends: sgx-ddk-um-n950
Section: web
Priority: optional
Homepage: https://github.com/smatkovi/n950-maemo-leste
Description: Firefox ESR 153, slim build for the N950
 Firefox ESR with WebRender on the SGX530 (OpenGL ES 2.0), touch input
 through XInput 2, settings for the N950's 1 GB of memory, a full-screen
 window without tab strip, and the add-ons uBO Lite, I still don't care
 about cookies and No animations (each can be switched off in about:addons).
 Installed in /opt/firefox-n950; started as "Firefox (N950)".
CTL
	;;
*) echo "make-debs.sh: embedlite or firefox" >&2; exit 2 ;;
esac
cat > "$W/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e
[ -x /usr/bin/gtk-update-icon-cache ] && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
SH
bash "$HERE/../tools/mkdeb.sh" "$R" "$W/DEBIAN" "$OUT/$WHAT-n950_${VERSION}_armhf.deb"
