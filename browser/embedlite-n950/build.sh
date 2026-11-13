#!/bin/bash
# Cross-builds Gecko ESR 153 with EmbedLite for the Nokia N950 (armhf) on an
# x86_64 PC, the engine of the N950 browser.
#
#   SRC=<packaging>/gecko-dev SYSROOT=<armhf root> \
#       bash browser/embedlite-n950/build.sh [configure|build|install DESTDIR]
#
# SRC: the Mozilla tree inside a checkout of the packaging repository
# (github smatkovi/gecko-dev, embedding/embedlite next to gecko-dev, which
# mobile/sailfishos points at), with the EmbedLite patch stack on top of the
# Firefox ESR source. SYSROOT: a Leste/Devuan excalibur armhf root with Qt 5,
# GTK 3, X11, PulseAudio and the compiler runtime installed. Host tools:
# clang/lld, cbindgen, node, python3, sccache, and a rustup toolchain with
# thumbv7neon-unknown-linux-gnueabihf (RUSTUP_TOOLCHAIN_BIN). The build
# directory is $SRC/../obj-embedlite-n950 (mozconfig).
#
# After installing a new build on the phone, run gen-shader-cache.sh there
# (as root): it compiles every WebRender program once on the SGX530 and puts
# them next to libxul (shader-cache), from where each profile's cache is
# refilled when the build changes. Without it the first page after an update
# waits minutes for programs to compile.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "${SRC:?set SRC=<packaging>/gecko-dev}" && pwd)
export SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
export RUSTUP_TOOLCHAIN_BIN=${RUSTUP_TOOLCHAIN_BIN:-$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin}
export MOZCONFIG=$HERE/mozconfig
export PKG_CONFIG_SYSROOT_DIR=$SYSROOT
export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/arm-linux-gnueabihf/pkgconfig:$SYSROOT/usr/share/pkgconfig
export MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none
# EmbedLite's build runs Qt tools on the host
export QT_QPA_PLATFORM=minimal
JOBS=${JOBS:-$(nproc --all)}

[ -d "$("$RUSTUP_TOOLCHAIN_BIN/rustc" --print sysroot)/lib/rustlib/thumbv7neon-unknown-linux-gnueabihf" ] || {
	echo "the Rust toolchain in $RUSTUP_TOOLCHAIN_BIN lacks thumbv7neon-unknown-linux-gnueabihf" >&2
	exit 1
}
[ -e "$SRC/mobile/sailfishos/app.mozbuild" ] || {
	echo "$SRC/mobile/sailfishos does not lead to embedding/embedlite" >&2
	exit 1
}

cd "$SRC"
case ${1:-build} in
configure) ./mach configure ;;
build)
	./mach build -j"$JOBS"
	./mach build faster FASTER_RECURSIVE_MAKE=1 -j"$JOBS"
	;;
install)
	make -C "$SRC/../obj-embedlite-n950/mobile/sailfishos/installer" install \
		DESTDIR="${2:?install needs DESTDIR}"
	# Sailfish uses the system's NSS and NSPR, this engine its own (Leste's
	# are older than Gecko 153 needs): next to libxul, found through its rpath
	for l in nspr4 plc4 plds4 nss3 nssutil3 smime3 ssl3 softokn3 freebl3 freeblpriv3; do
		install -m 755 "$SRC/../obj-embedlite-n950/dist/bin/lib$l.so" \
			"$2/usr/lib/arm-linux-gnueabihf/xulrunner-qt5-153.6.0/"
	done
	# libxul.pc links -lxul from the SDK directory
	ln -sf ../../../xulrunner-qt5-153.6.0/libxul.so \
		"$2/usr/lib/arm-linux-gnueabihf/xulrunner-qt5-devel-153.6.0/sdk/lib/libxul.so"
	;;
*) echo "usage: build.sh [configure|build|install DESTDIR]" >&2; exit 2 ;;
esac
