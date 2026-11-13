#!/bin/bash
# Builds clang's PGO runtime (libclang_rt.profile.a) for armhf, which Arch's
# compiler-rt does not ship, from compiler-rt's lib/profile of the installed
# clang's release. Install it where clang looks for it:
#
#   SYSROOT=<armhf root> bash browser/embedlite-n950/pgo/build-profile-runtime.sh OUTDIR
#   sudo install -D -m 644 OUTDIR/libclang_rt.profile.a \
#       "$(clang -print-resource-dir)/lib/arm-unknown-linux-gnueabihf/libclang_rt.profile.a"
set -euo pipefail
OUT=$(realpath -m "${1:?outdir}")
SYSROOT=$(cd "${SYSROOT:?set SYSROOT=<armhf root>}" && pwd)
V=$(clang --version | sed -n 's/.*clang version \([0-9.]*\).*/\1/p' | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/lib/profile" "$W/include/profile" "$OUT"
for p in compiler-rt/lib/profile compiler-rt/include/profile; do
	curl -fsSL "https://api.github.com/repos/llvm/llvm-project/contents/$p?ref=llvmorg-$V" |
		python3 -c 'import json, sys; [print(e["download_url"]) for e in json.load(sys.stdin) if e["type"] == "file"]'
done | while read -r u; do curl -fsSL -o "$W/${u#*compiler-rt/}" "$u"; done
F=(--target=arm-unknown-linux-gnueabihf -march=armv7-a -mfpu=neon -mfloat-abi=hard -mthumb
   --sysroot="$SYSROOT" -O2 -fPIC -fno-profile-instr-generate -fvisibility=hidden -I"$W/include"
   -DCOMPILER_RT_HAS_ATOMICS=1 -DCOMPILER_RT_HAS_FCNTL_LCK=1 -DCOMPILER_RT_HAS_FLOCK=1 -DCOMPILER_RT_HAS_UNAME=1)
cd "$W"
for f in InstrProfiling InstrProfilingInternal InstrProfilingBuffer InstrProfilingMerge \
         InstrProfilingMergeFile InstrProfilingNameVar InstrProfilingVersionVar InstrProfilingWriter \
         InstrProfilingPlatformLinux InstrProfilingPlatformOther GCDAProfiling InstrProfilingFile \
         InstrProfilingUtil InstrProfilingValue; do
	clang "${F[@]}" -c "lib/profile/$f.c" -o "$f.o"
done
clang++ "${F[@]}" -nostdinc++ -fno-exceptions -fno-rtti -c lib/profile/InstrProfilingRuntime.cpp -o InstrProfilingRuntime.o
llvm-ar rcs "$OUT/libclang_rt.profile.a" ./*.o
echo "built $OUT/libclang_rt.profile.a for clang $V"
