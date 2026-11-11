#!/bin/bash
# Install the kernel built by kernel/build.sh on a running Leste over ssh
# (USB link, root@192.168.42.2 by default): /boot/zImage-<release> with the
# N950's device tree appended, the modules under /lib/modules/<release>, and
# the /boot/zImage symlink moved to it. The previous kernel stays in /boot;
# its name is kept in /boot/zImage.previous so it can be switched back from
# ubiboot's maintenance shell (ln -sf) if the new one does not boot.
# /boot/cmdline is not touched.
#
#   WORK=~/ps/n950-kernel bash kernel/deploy-ssh.sh [root@host]
#
# SSH_OPTS adds ssh options, e.g. over Wi-Fi with the USB address's host key:
#   SSH_OPTS="-o HostKeyAlias=192.168.42.2" ... deploy-ssh.sh root@<wlan ip>
set -euo pipefail
WORK=${WORK:?set WORK=<work directory used for build.sh>}
O=$WORK/out
T=${1:-root@192.168.42.2}
KH=${KNOWN_HOSTS:-$HOME/.ssh/known_hosts.n950-leste}
read -r -a XOPT <<< "${SSH_OPTS:-}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o UserKnownHostsFile="$KH" "${XOPT[@]}" "$T")
REL=$(cat "$O/include/config/kernel.release")
B=$O/arch/arm/boot
STAGE=$O/stage-$REL
echo "== $REL"
[ -f "$B/zImage" ] && [ -f "$B/dts/ti/omap/omap3-n950.dtb" ]
cat "$B/zImage" "$B/dts/ti/omap/omap3-n950.dtb" > "$O/zImage-$REL"
rm -rf "$STAGE"
make -C "$WORK/linux" O="$O" ARCH=arm LLVM=1 CC="ccache clang" -s \
     INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install
echo "== $(find "$STAGE" -name '*.ko' | wc -l) modules staged, zImage $(stat -c %s "$O/zImage-$REL") bytes"
echo "== copying to $T"
scp -q -o BatchMode=yes -o UserKnownHostsFile="$KH" "${XOPT[@]}" "$O/zImage-$REL" "$T:/boot/zImage-$REL"
tar -C "$STAGE/lib/modules" -cf - "$REL" | "${SSH[@]}" "tar -C /lib/modules -xf - && depmod $REL && echo modules installed"
"${SSH[@]}" "set -e; cd /boot
md5sum zImage-$REL | cut -c1-12
prev=\$(readlink zImage || true); echo \"\$prev\" > zImage.previous
ln -sfn zImage-$REL zImage
echo \"/boot/zImage -> \$(readlink zImage)   (previous: \$prev)\"
sync"
echo "== done. Reboot into ubiboot and pick Leste; the old kernel is still in /boot."
