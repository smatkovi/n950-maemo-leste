#!/bin/bash
# Build the module-compatible Harmattan PR1.3 kernel for the N950:
# 2.6.32.54-dfl61-20121301 with the eMMC-after-kexec retry (patch 0003) and the
# decompressor cache fix (patch 0004), nothing else.  The stock modules on p2
# (/lib/modules/2.6.32.54-dfl61-20121301, CONFIG_MODVERSIONS=y) can only be loaded
# by a kernel with the same release string AND the same exported-symbol CRCs, so the
# config is rm581_defconfig untouched except for the fixed LOCALVERSION.  Compare the
# CRCs with crc-compare.py before deploying anything.
#
# Source: github nemomobile/kernel-adaptation-n950-n9, branch mer-n9-2.6.32-20121301,
# cloned to ~/ps/harmattan-src/kernel-pr13/src, local branch n950-mmcfix with the
# patches 0005 (host perl fix), 0003 and 0004 applied as commits.
# Toolchain: CodeSourcery 2009q3 from the Harmattan SDK (MADDE), as Nokia used.
#
#   KSRC=<tree> OUT=<build dir> ./build-pr13.sh [zImage|modules|all]   (default all)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KSRC=${KSRC:-$HOME/ps/harmattan-src/kernel-pr13/src}
OUT=${OUT:-$HOME/ps/n950-harmattan-build/pr13}
TC=${TC:-$HOME/QtSDK/Madde/toolchains/arm-2009q3-67-arm-none-linux-gnueabi-x86_64-unknown-linux-gnu/arm-2009q3-67}
DEST=${DEST:-$HOME/n950}
RELEASE=2.6.32.54-dfl61-20121301
NAME=${NAME:-zImage_$RELEASE-mmcfix}
JOBS=${JOBS:-$(nproc)}
WHAT=${1:-all}

export PATH="$TC/bin:$PATH"
export ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi-

cd "$KSRC"
mkdir -p "$OUT"

echo "=== configure: rm581_defconfig, LOCALVERSION fixed to -dfl61-20121301 ==="
make O="$OUT" rm581_defconfig >/dev/null
sed -i -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-dfl61-20121301"/' \
       -e 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' \
       "$OUT/.config"
yes "" | make O="$OUT" oldconfig >/dev/null || true   # yes gets SIGPIPE
grep -E '^CONFIG_(LOCALVERSION|MODVERSIONS|PREEMPT|MODULE_UNLOAD|KEXEC|IKCONFIG|OMAP_IOMMU)' "$OUT/.config" || true
# the only differences to Nokia's defconfig must be the fixed LOCALVERSION and symbols new to this tree
diff <(grep -E '^(CONFIG|# CONFIG)' arch/arm/configs/rm581_defconfig | sort) <(grep -E '^(CONFIG|# CONFIG)' "$OUT/.config" | sort) | grep '^[<>]' | grep -v LOCALVERSION || true
make O="$OUT" -s prepare >"$OUT/build-prepare.log" 2>&1 || { tail -5 "$OUT/build-prepare.log"; echo "make prepare failed"; exit 1; }
REL=$(cat "$OUT/include/config/kernel.release" 2>/dev/null || true)
echo "kernel release: $REL"
[ "$REL" = "$RELEASE" ] || { echo "release string is '$REL', expected '$RELEASE' - modprobe would look in the wrong /lib/modules dir"; exit 1; }

build() {   # $1 = make target(s)
	echo "=== make $1 with $JOBS jobs ==="
	if ! make O="$OUT" -j"$JOBS" $1 >"$OUT/build-$1.log" 2>&1; then
		grep -E "error|Error" "$OUT/build-$1.log" | head -20
		echo "BUILD FAILED, see $OUT/build-$1.log"; exit 1
	fi
	grep -cE '^\s*warning|: warning:' "$OUT/build-$1.log" | xargs -I{} echo "{} warnings (see the log)"
}

if [ "$WHAT" = zImage ] || [ "$WHAT" = all ]; then
	rm -f "$OUT/arch/arm/boot/zImage" "$OUT/arch/arm/boot/compressed/vmlinux"
	build zImage
	test -f "$OUT/arch/arm/boot/zImage"
	mkdir -p "$DEST"
	cp "$OUT/arch/arm/boot/zImage" "$DEST/$NAME"
	echo "=== zImage: $DEST/$NAME"; ls -l "$DEST/$NAME"; md5sum "$DEST/$NAME"
fi

if [ "$WHAT" = modules ] || [ "$WHAT" = all ]; then
	build modules
	rm -rf "$OUT/stage"
	make O="$OUT" -s INSTALL_MOD_PATH="$OUT/stage" INSTALL_MOD_STRIP=1 modules_install >"$OUT/build-modules_install.log" 2>&1
	echo "=== modules staged in $OUT/stage/lib/modules/$REL: $(find "$OUT/stage" -name '*.ko' | wc -l) .ko"
	echo "vermagic: $(modinfo -F vermagic "$(find "$OUT/stage" -name 'g_nokia.ko' | head -1)" 2>/dev/null)"
fi

echo "=== Module.symvers: $OUT/Module.symvers ($(wc -l < "$OUT/Module.symvers") lines)"
echo "next: python3 $HERE/crc-compare.py $OUT/Module.symvers [stock modules dir]"
