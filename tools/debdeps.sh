#!/bin/bash
# Prints a Depends list for a staged root: the packages of SYSROOT (an armhf
# root with dpkg's database) holding the libraries the root's ELF files need
# and do not bring themselves.
#
#   tools/debdeps.sh ROOT SYSROOT
set -euo pipefail
ROOT=${1:?root}
SYSROOT=${2:?sysroot}
find "$ROOT" -type f -print0 | while IFS= read -r -d '' f; do
	[ "$(head -c4 "$f" | od -An -c | tr -d ' ')" = '177ELF' ] || continue
	llvm-readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'
done | sort -u | while read -r lib; do
	[ -n "$(find "$ROOT" -name "$lib" -print -quit)" ] && continue
	re=$(printf '%s' "$lib" | sed 's/[.+]/\\&/g')
	p=$(grep -l -E "/$re\$" "$SYSROOT"/var/lib/dpkg/info/*.list 2>/dev/null | head -1)
	if [ -n "$p" ]; then basename "$p" .list | sed 's/:armhf$//'
	else echo "unresolved: $lib" >&2; fi
done | sort -u | paste -sd, | sed 's/,/, /g'
