#!/bin/bash
# Prepare Nokia's pristine PR1.3 kernel source for the N950 mmc-fix build and build it.
#
# The nemomobile tree (kernel-pr13) has Nokia's Aegis LSM removed, and Harmattan's
# userland (aegisfs, aegis-session, libcreds) reboots the device without it — see
# HANDOVER-boot-from-ubiboot.md, 2026-11-09 ~08:30.  So the kernel that boots MeeGo
# must come from Nokia's own source: kernel_2.6.32-20121301+0m8 (Harmattan SDK sources
# ISO, maemo.cloud-7.de/HARM/N9/1.3/cdrom.iso), extracted to
# ~/ps/harmattan-src/dl-nokia-pr13/kernel-2.6.32.
#
# Steps: git baseline of the tree as shipped, branch n950-mmcfix, the perl host fix
# (0005), the mmc retry (0003) and the decompressor cache fix (0004) as commits, then
# build-pr13.sh with that tree.  Nokia's tree needs none of 0006/0007/0008.
#
#   ./prep-nokia-tree.sh            # prepare + build
#   ./prep-nokia-tree.sh prep-only  # just the git setup and the patches
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
KSRC=${KSRC:-$HOME/ps/harmattan-src/dl-nokia-pr13/kernel-2.6.32}
OUT=${OUT:-$HOME/ps/n950-harmattan-build/pr13-nokia}
NAME=${NAME:-zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia}

cd "$KSRC"
grep -q '^EXTRAVERSION = .54' Makefile || { echo "$KSRC is not the 2.6.32.54 tree"; exit 1; }
[ -d security/aegis ] || { echo "$KSRC has no security/aegis - that is not Nokia's tree"; exit 1; }

if [ ! -d .git ]; then
	git init -q
	git add -A . >/dev/null
	git commit -q -m "Nokia kernel_2.6.32-20121301+0m8 source as shipped (Harmattan PR1.3)"
fi
git checkout -q -B n950-mmcfix

if grep -q 'defined(@val)' kernel/timeconst.pl; then
	sed -i 's/if (!defined(@val)) {/if (!@val) {/' kernel/timeconst.pl
	git commit -q -am "timeconst.pl: drop defined(@array), rejected by perl >= 5.22 (host build fix)"
fi
apply() {   # $1 = patch file, $2 = commit subject
	if patch -p1 -R --dry-run -s <"$1" >/dev/null 2>&1; then echo "already applied: $(basename "$1")"; return; fi
	patch -p1 --dry-run -s <"$1" || { echo "does not apply: $1"; exit 1; }
	patch -p1 -s <"$1"
	git add -A . >/dev/null; git commit -q -m "$2"
}
apply "$HERE/patches/0003-mmc-retry-emmc-after-kexec.patch" "mmc: core: retry the non-removable eMMC after a kexec (N950 black screen)"
apply "$HERE/patches/0004-decompressor-invalidate-icache-btb-before-cache-on.patch" "arm: decompressor: invalidate I-cache and branch predictor before enabling caches (kexec)"
echo "--- tree ready:"; git log --oneline | head -5

[ "${1:-}" = prep-only ] && exit 0
cd "$HERE"
KSRC="$KSRC" OUT="$OUT" NAME="$NAME" ./build-pr13.sh all
echo "next: python3 $HERE/crc-compare.py $OUT/Module.symvers   (must again be 91/91)"
echo "      ./boot-from-ubiboot.sh deploy-pr13 ~/n950/$NAME && ./boot-from-ubiboot.sh meego-pr13 ~/n950/$NAME"
