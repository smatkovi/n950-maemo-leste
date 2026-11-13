#!/bin/bash
# Builds a binary .deb from a staged root without dpkg (ar, tar, xz):
#
#   tools/mkdeb.sh ROOT CONTROL-DIR OUT.deb
#
# CONTROL-DIR holds control and optionally postinst, prerm, postrm, conffiles.
# Installed-Size and md5sums are computed; everything is owned by root.
set -euo pipefail
ROOT=$(cd "${1:?root}" && pwd)
CTL=$(cd "${2:?control dir}" && pwd)
OUT=$(realpath -m "${3:?out.deb}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/control"
cp -a "$CTL"/. "$T/control/"
size=$(du -sk --apparent-size "$ROOT" | cut -f1)
grep -q '^Installed-Size:' "$T/control/control" ||
	sed -i "/^Description:/i Installed-Size: $size" "$T/control/control"
(cd "$ROOT" && find . -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 -r md5sum) > "$T/control/md5sums"
chmod 644 "$T/control/control" "$T/control/md5sums"
for s in postinst prerm postrm preinst; do
	[ -e "$T/control/$s" ] && chmod 755 "$T/control/$s"
done
TAR=(tar --owner=0 --group=0 --numeric-owner --sort=name --mtime=@"${SOURCE_DATE_EPOCH:-$(date +%s)}")
"${TAR[@]}" -C "$T/control" -cf - . | xz -9 > "$T/control.tar.xz"
"${TAR[@]}" -C "$ROOT" -cf - . | xz -T0 -6 > "$T/data.tar.xz"
echo 2.0 > "$T/debian-binary"
rm -f "$OUT"
(cd "$T" && ar rcD "$OUT" debian-binary control.tar.xz data.tar.xz)
ls -l "$OUT"
