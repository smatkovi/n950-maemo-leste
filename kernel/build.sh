#!/bin/bash
# Leste's kernel for the N950 with this repository's patches.
#
#   WORK=/path/to/work bash kernel/build.sh [make targets]
#
# Clones Leste's kernel (droid4-linux, leste/maemo-6.18.y) into $WORK/linux,
# puts kernel/patches/*.patch on a branch "n950" (git am), takes the
# configuration of Leste's linux-image-omap package with
# kernel/config/n950.config merged on top, and builds out of tree in
# $WORK/out with clang (LLVM=1) through ccache. Default targets: zImage,
# the N950's device tree, the modules.
#
#   DIAG=1 WORK=/path/to/work bash kernel/build.sh
#
# builds the diagnostic variant instead (README, "Diagnostic kernel"):
# kernel/patches/diag/*.patch on top of the others, kernel/config/diag.config
# merged last, in $WORK/out-diag; zImage and device tree only, and
# arch/arm/boot/zImage-dtb there is the zImage with the device tree
# appended, for a boot from RAM.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:?set WORK=<work directory>}
BRANCH=leste/maemo-6.18.y
URL=https://git.maemo.org/leste-upstream-forks/droid4-linux.git
# Leste's package, for its configuration
KDEB=https://maedevu.maemo.org/leste/pool/main/o/omap-linux/linux-image-omap_6.18.51.1-1+5m7_armhf.deb
JOBS=${JOBS:-$(nproc)}
K=$WORK/linux
O=$WORK/out
DIAG=${DIAG:-}
FRAGMENTS=("$REPO/kernel/config/n950.config")
PATCHES=("$REPO"/kernel/patches/*.patch)
if [ -n "$DIAG" ]; then
	O=$WORK/out-diag
	FRAGMENTS+=("$REPO/kernel/config/diag.config")
	PATCHES+=("$REPO"/kernel/patches/diag/*.patch)
fi
log() { echo ">> $*"; }
mkdir -p "$WORK" "$O"

if [ ! -d "$K/.git" ]; then
	log "clone $BRANCH"
	git clone -q --depth 1 --single-branch -b "$BRANCH" "$URL" "$K"
fi
log "patches"
git -C "$K" checkout -q -B n950 "origin/$BRANCH"
for p in "${PATCHES[@]}"; do
	[ -f "$p" ] || continue
	git -C "$K" -c user.name=build -c user.email=build@localhost \
	    am -q --committer-date-is-author-date "$p"
done

if [ ! -f "$WORK/config-base" ]; then
	log "configuration of Leste's linux-image-omap"
	tmp=$(mktemp -d)
	curl -sSf -o "$tmp/k.deb" "$KDEB"
	(cd "$tmp" && bsdtar -xf k.deb && tar -xf data.tar.* ./boot)
	cp "$tmp"/boot/config-* "$WORK/config-base"
	rm -rf "${tmp:?}"
fi
MAKE=(make -C "$K" O="$O" ARCH=arm LLVM=1 CC="ccache clang" -j"$JOBS")
cp "$WORK/config-base" "$O/.config"
"$K/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" \
    "${FRAGMENTS[@]}" > "$O/merge.log"
"${MAKE[@]}" olddefconfig > /dev/null
if [ $# -eq 0 ]; then
	if [ -n "$DIAG" ]; then
		set -- zImage ti/omap/omap3-n950.dtb
	else
		set -- zImage ti/omap/omap3-n950.dtb modules
	fi
fi
log "make $*"
"${MAKE[@]}" "$@"
if [ -n "$DIAG" ]; then
	B=$O/arch/arm/boot
	cat "$B/zImage" "$B/dts/ti/omap/omap3-n950.dtb" > "$B/zImage-dtb"
	log "$B/zImage-dtb ($(cat "$O/include/config/kernel.release"))"
fi
