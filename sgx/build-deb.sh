#!/bin/bash
# The N950's PowerVR user space as an armhf .deb, sgx-ddk-um-n950.
#
#   OUT=<dir> [TI=<clone of omap5-sgx-ddk-um-linux>] bash sgx/build-deb.sh
#
# The N950's SGX530 is revision 1.2.5; Leste's sgx-ddk-um-ti343x carries the
# N900's user space (1.2.1), which the kernel module refuses. TI's DDK
# 1.17.4948957 build for the AM335x (ti335x) is for the same SGX530 1.2.5.
# The package puts its GPU libraries and pvrsrvctl in place of
# sgx-ddk-um-ti343x's (dpkg-divert, so removing it brings those back).
# Leste's own libdbm, pvrsrvinit and the library links stay those of
# sgx-ddk-um-ti343x: TI's libdbm accepts only the AM335x's display driver
# (tilcdc), Leste's the N950's (omapdrm).
#
# Without TI the script fetches TI's repository (only the files it needs)
# into $OUT/ti-src. The files are checked against the sums of the ones
# tested on an N950. No packaging tools beyond tar, xz and ar are needed.
set -euo pipefail
OUT=${OUT:?set OUT=<directory for the .deb>}
TI=${TI:-}
URL=https://git.ti.com/git/graphics/omap5-sgx-ddk-um-linux.git
BRANCH=1.17.4948957/mesa/glibc-2.35
COMMIT=84a396a4fb379f10931421e489ac8a199d6a9f2c
REL=targetfs/ti335x_linux/lws-generic/release
PKG=sgx-ddk-um-n950
VERSION=1.17.4948957-n950.1
LIBDIR=usr/lib/arm-linux-gnueabihf
log() { echo ">> $*"; }

# file in TI's release tree, sha256 of the version tested on the N950
FILES=(
	"usr/bin/pvrsrvctl c2adbdf3aaa13edc9461264f2ce78bb7053ee29f159bd35534ccf6e58e75037d"
	"usr/lib/libGLESv1_PVR_MESA.so.1.17.4948957 3838c56888967bda42b3d5bb412cec17890bcc251b453ac598698199638bb3f7"
	"usr/lib/libGLESv2_PVR_MESA.so.1.17.4948957 d5c3d8ffaf66a00b794a053609abfd3d2a28bb9ad82e39835796bf0037e5664b"
	"usr/lib/libPVRScopeServices.so.1.17.4948957 e76fd84b680133433a91775dc516bb729fa2f7f71550f4ab481c4ca1ce7ebd15"
	"usr/lib/libglslcompiler.so.1.17.4948957 724f104da6e5a2e9a600aafe703edf02c1035971a13d2e7162cbbaef76a561a4"
	"usr/lib/libpvr2d.so.1.17.4948957 7a54f6746cbb7ea711efde0e2105c0df9c1cf1ed18f6f374277294d622470891"
	"usr/lib/libpvr_dri_support.so.1.17.4948957 b7267e4436bc220cc5a291fd60c3cc9133660750172f7a7f6d6aa5d23e07becf"
	"usr/lib/libsrv_init.so.1.17.4948957 1ffaea6766c81c5d2a73d726ca30d7f9bcd37c9fbd0d32f2b3ec507705146aac"
	"usr/lib/libsrv_um.so.1.17.4948957 97ad164587f09b2dd75079e75d98a17f51bcbf049cd3727d7a790895f7856072"
	"usr/lib/libusc.so.1.17.4948957 42fc3803dfdd5f3518fbe631be3c7bc1b1ca2046d1e7892daa09ea04d1ac3a6c"
)

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
if [ -z "$TI" ]; then
	TI=$OUT/ti-src
	if [ ! -d "$TI/.git" ]; then
		log "fetch TI's $BRANCH (no blobs but the ones needed)"
		git init -q "$TI"
		git -C "$TI" remote add origin "$URL"
		git -C "$TI" fetch -q --filter=blob:none origin "$BRANCH"
		git -C "$TI" sparse-checkout set --no-cone "/$REL/" /LICENSE
	fi
	git -C "$TI" checkout -q "$COMMIT"
fi
[ "$(git -C "$TI" rev-parse HEAD)" = "$COMMIT" ] ||
	{ echo "$TI is not at $COMMIT"; exit 1; }

W=$OUT/$PKG-build
rm -rf "$W"
mkdir -p "$W/root/$LIBDIR" "$W/root/usr/bin" "$W/root/usr/share/doc/$PKG" "$W/control"

# The installed paths, for the diversions
DIVERTED=()
for entry in "${FILES[@]}"; do
	f=${entry% *}
	sum=${entry#* }
	echo "$sum  $TI/$REL/$f" | sha256sum --quiet -c -
	case $f in
	usr/bin/*) dst=usr/bin/${f##*/}; mode=755 ;;
	*) dst=$LIBDIR/${f##*/}; mode=644 ;;
	esac
	install -m "$mode" "$TI/$REL/$f" "$W/root/$dst"
	DIVERTED+=("/$dst")
done

{
	echo "$PKG: TI's PowerVR SGX DDK 1.17.4948957 user space, ti335x build,"
	echo "from $URL"
	echo "(branch $BRANCH, commit $COMMIT, $REL), unmodified."
	echo "It is licensed for use with TI devices only; the N950's OMAP3630 is one."
	echo
	cat "$TI/LICENSE"
} > "$W/root/usr/share/doc/$PKG/copyright"
chmod 644 "$W/root/usr/share/doc/$PKG/copyright"

cat > "$W/control/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: armhf
Maintainer: Sebastian Matkovich <sebastian.matkovich@gmail.com>
Depends: sgx-ddk-um-ti343x (>= 1.17.4948957)
Section: libs
Priority: optional
Installed-Size: $(du -sk "$W/root" | cut -f1)
Description: PowerVR SGX530 1.2.5 user space for the Nokia N950
 TI's DDK 1.17.4948957 for the AM335x (ti335x), the same SGX530 revision as
 the N950's OMAP3630, in place of the GPU libraries and pvrsrvctl of
 sgx-ddk-um-ti343x (the N900's revision 1.2.1, which the kernel module
 refuses). Leste's libdbm and pvrsrvinit stay in use. The GPU starts with
 its new user space on the next boot.
EOF

list=${DIVERTED[*]}
cat > "$W/control/preinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = install ] || [ "\$1" = upgrade ]; then
	for f in $list; do
		dpkg-divert --quiet --package $PKG --add --rename --divert "\$f.ti343x" "\$f"
	done
fi
EOF
cat > "$W/control/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = abort-install ] || [ "\$1" = disappear ]; then
	for f in $list; do
		dpkg-divert --quiet --package $PKG --remove --rename --divert "\$f.ti343x" "\$f"
	done
fi
EOF
cat > "$W/control/postinst" <<'EOF'
#!/bin/sh
set -e
[ "$1" = configure ] && ldconfig
exit 0
EOF
chmod 755 "$W/control/preinst" "$W/control/postrm" "$W/control/postinst"
(cd "$W/root" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | sort |
	xargs md5sum) > "$W/control/md5sums"

TAR=(tar --owner=0 --group=0 --numeric-owner --sort=name --mtime=@0)
"${TAR[@]}" -C "$W/control" -cJf "$W/control.tar.xz" .
"${TAR[@]}" -C "$W/root" -cJf "$W/data.tar.xz" ./usr
echo 2.0 > "$W/debian-binary"
DEB=$OUT/${PKG}_${VERSION}_armhf.deb
rm -f "$DEB"
(cd "$W" && ar -rcD "$DEB" debian-binary control.tar.xz data.tar.xz)
rm -rf "$W"
log "$DEB"
