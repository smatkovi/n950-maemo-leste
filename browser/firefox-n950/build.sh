#!/bin/bash
# Cross-builds the slim Firefox ESR for the Nokia N950 (armhf) on an x86_64 PC.
#
#   SRC=<firefox-153.x source> SYSROOT=<armhf root> \
#       bash browser/firefox-n950/build.sh [patch|configure|build|package]
#
# SRC: an unpacked Firefox ESR source (archive.mozilla.org, checked against
# its SHA512SUMS). SYSROOT: a Leste/Devuan excalibur armhf root with GTK 3,
# X11, D-Bus, PulseAudio and the compiler runtime (libgcc/libstdc++ -dev)
# installed, e.g. the chroot apps are built in. Host tools: clang and lld,
# cbindgen, node, python3, and a rustup toolchain with the target
# thumbv7neon-unknown-linux-gnueabihf (RUSTUP_TOOLCHAIN_BIN, default the
# stable one in ~/.rustup; the system's Rust stays untouched). The build
# directory is $SRC/../obj-n950 (mozconfig).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "${SRC:?set SRC=<firefox source>}" && pwd)
export SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
export RUSTUP_TOOLCHAIN_BIN=${RUSTUP_TOOLCHAIN_BIN:-$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin}
export MOZCONFIG=$HERE/mozconfig
# the target's pkg-config files, paths inside the sysroot
export PKG_CONFIG_SYSROOT_DIR=$SYSROOT
export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/arm-linux-gnueabihf/pkgconfig:$SYSROOT/usr/share/pkgconfig
# mach's Python packages from the source tree, nothing from the network
export MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none

"$RUSTUP_TOOLCHAIN_BIN/rustc" --print target-list | grep -qx thumbv7neon-unknown-linux-gnueabihf
[ -d "$("$RUSTUP_TOOLCHAIN_BIN/rustc" --print sysroot)/lib/rustlib/thumbv7neon-unknown-linux-gnueabihf" ] || {
	echo "the Rust toolchain in $RUSTUP_TOOLCHAIN_BIN lacks thumbv7neon-unknown-linux-gnueabihf" >&2
	exit 1
}

cd "$SRC"
case ${1:-build} in
patch)
	# WebRender's OpenGL ES 2.0 path (PowerVR SGX530), once per source tree
	for p in "$HERE"/patches/*.patch; do
		patch -p1 --forward --no-backup-if-mismatch -s < "$p"
	done
	;;
configure) ./mach configure ;;
build) ./mach build ;;
package) ./mach package ;;
*) echo "usage: build.sh [patch|configure|build|package]" >&2; exit 2 ;;
esac
