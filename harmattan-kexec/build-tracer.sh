#!/bin/bash
# Build the Harmattan 2.6.32 kernel with the n950tr boot tracer.
#
# Source: Nokia's kernel-2.6.32 (package kernel_2.6.32-20115101+0m7, that is
# 2.6.32.48-dfl61), with the patches from patches/ applied.
# Toolchain: CodeSourcery 2009q3 from the Harmattan SDK (MADDE), the one
# Nokia built the device kernels with.
#
#   KSRC=<tree> OUT=<build dir> ./build-tracer.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KSRC=${KSRC:-$HOME/ps/harmattan-src/kernel_2.6.32-20115101+0m7/kernel-2.6.32}
OUT=${OUT:-$HOME/ps/n950-harmattan-build/tr1}
TC=${TC:-$HOME/QtSDK/Madde/toolchains/arm-2009q3-67-arm-none-linux-gnueabi-x86_64-unknown-linux-gnu/arm-2009q3-67}
DEST=${DEST:-$HOME/n950}
NAME=${NAME:-zImage_2.6.32.48-n950tr1}
JOBS=${JOBS:-$(nproc)}

export PATH="$TC/bin:$PATH"
export ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi-

cd "$KSRC"
mkdir -p "$OUT"

echo "=== configure (rm581_defconfig = N950, + KEXEC + ATAGS_PROC) ==="
make O="$OUT" rm581_defconfig >/dev/null
sed -i -e 's/^# CONFIG_KEXEC is not set/CONFIG_KEXEC=y/' \
       -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-dfl61-n950tr"/' \
       -e 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' \
       "$OUT/.config"
grep -q '^CONFIG_KEXEC=y' "$OUT/.config" || echo 'CONFIG_KEXEC=y' >>"$OUT/.config"
grep -q '^CONFIG_ATAGS_PROC=y' "$OUT/.config" || echo 'CONFIG_ATAGS_PROC=y' >>"$OUT/.config"
yes "" | make O="$OUT" oldconfig >/dev/null || true   # yes gets SIGPIPE
grep -E '^CONFIG_(KEXEC|ATAGS_PROC|LOCALVERSION|PAGE_OFFSET|KERNEL_LZO)' "$OUT/.config"

echo "=== build zImage with $JOBS jobs ==="
make O="$OUT" -j"$JOBS" zImage 2>&1 | tee "$OUT/build.log" | grep -E "error|Error|warning: .*n950|^  (LD|OBJCOPY|LZO).*zImage|^  AS .*head" || true
test -f "$OUT/arch/arm/boot/zImage"

echo "=== patch self-checksum ==="
cp "$OUT/arch/arm/boot/zImage" "$OUT/$NAME"
python3 "$HERE/n950tr-csum.py" "$OUT/$NAME"
python3 "$HERE/n950tr-csum.py" --check "$OUT/$NAME"

mkdir -p "$DEST"
cp "$OUT/$NAME" "$DEST/$NAME"
echo "=== done ==="
echo "kernel release: $(cat "$OUT/include/config/kernel.release")"
ls -l "$DEST/$NAME"
md5sum "$DEST/$NAME"
