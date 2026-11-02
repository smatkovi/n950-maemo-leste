#!/bin/bash
# Boot the diagnostic kernel (DIAG=1 kernel/build.sh) from RAM through
# NOLO: nothing is written to the phone. Start this, then plug the N950
# in while it is off (or switch it on with the cable in); flasher waits for
# NOLO.
#
#   WORK=/path/to/work bash kernel/ramboot.sh [STAGE] [more kernel options]
#
# STAGE: n950.reset=STAGE (kernel/patches/diag/0003): a warm reset at that
# point of the boot, the only sign of life before the display and USB
# drivers. If the phone starts again (NOLO, then Harmattan) the boot got
# there; if it stays dark, it hung before. Stages: 1 after setup_arch,
# 2 mm_core_init, 3 sched_init, 4 init_IRQ, 5 time_init, 6 console_init,
# 7 before rest_init, 8 kernel_init_freeable, 10-17 after each initcall
# level (pure, core, postcore, arch, subsys, fs, device, late), 20 before
# init. Without STAGE (or with "-"): no reset, a plain diagnostic boot.
# ZIMAGE=... boots another image (e.g. one built with
# KCPPFLAGS=-DN950_RESET_EARLY=1 or 2).
set -euo pipefail
WORK=${WORK:?set WORK=<work directory>}
ZIMAGE=${ZIMAGE:-$WORK/out-diag/arch/arm/boot/zImage-dtb}
stage=${1:--}
[ $# -gt 0 ] && shift
[ -f "$ZIMAGE" ] || { echo "no $ZIMAGE"; exit 1; }
cmdline="root=PARTUUID=00048046-04 rootwait rw rootfstype=ext4 init=/sbin/init"
[ "$stage" != - ] && cmdline="$cmdline n950.reset=$stage"
[ $# -gt 0 ] && cmdline="$cmdline $*"
echo ">> $ZIMAGE"
echo ">> $cmdline"
echo ">> now plug the N950 in (switched off)"
exec sudo flasher -k "$ZIMAGE" -l -b"$cmdline"
