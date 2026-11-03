# Booting Leste through MOSLO (works, 2026-11-02)

The N950 at hand refuses to flash any unsigned image ("Devicelock ON").
ubiboot cannot go into the OneNAND, and a direct NOLO boot of the 6.18
kernel from RAM stays dark. What works is MOSLO, booted from RAM by NOLO,
which then starts Leste's kernel from p4 by kexec.

## Steps (a PC is needed for every boot)

1. Switch the N950 off, start the flasher on the PC, then plug the cable
   in:

       flasher -k zImage-moslo -l -b

2. **Cable plugged in:** MOSLO exports p4 as a USB disk and gives a root
   shell at telnet 192.168.2.15. There a kernel can be started by hand:

       mount -o ro /dev/mmcblk0p4 /mnt
       kexec -l /mnt/boot/zImage-<version> --command-line="root=PARTUUID=00048046-04 rootwait rw rootfstype=ext4 init=/sbin/init console=tty0"
       kexec -e

   **Without the cable:** MOSLO starts p4's `/boot/bzImage` with
   `/boot/cmdline` by itself.

3. Leste's USB network comes up after about two minutes. On 2026-11-02
   `usb0` came up as 192.168.42.2, not as n950-usbnet's 192.168.2.15, so
   the way in is its IPv6 link-local address:

       ping -6 ff02::1%<interface>
       ssh root@fe80::...%<interface>

Kernel and modules go onto p4 through MOSLO's USB disk: the zImage with
the device tree appended into `/boot`, the modules into `/lib/modules`.
p4's ext4 has only Harmattan's features, so MOSLO's 2.6.32 kernel can
mount it.

## What it took (kernel/patches)

- **0020 (mmc core):** after the kexec the eMMC at times times out on its
  first data transfer (the EXT_CSD read, CMD8, -110). The kernel now tries
  a non-removable card again. Without the retry the boot waited for its
  root for ever.
- **0021:** the TWL5031 watchdog, which NOLO/MOSLO leave running and which
  cannot be stopped, is fed by the kernel until user space takes it (DSME
  does).
- **0022 (device tree):** the TWL5031's charger (BCI) is off; the N950
  charges through a bq2415x. With `twl4030_charger` bound, the N950 reset
  about 30 s after user space started. A modprobe blacklist was not enough,
  because the module gets loaded explicitly.
- **0023 (omapdrm):** on OMAP3 the planes are committed before the CRTC is
  enabled. For the N950's command-mode panel the first frame after
  switching the display on then either never went out (with a 10 s
  "flip_done timed out" on every following commit) or, sent with the
  overlay set up before the channel's stall mode, never finished
  ("Framedone not received") and froze the display for good. The planes
  of such a display are now committed again once it is on.
- **0024, 0025 (panel, device tree):** the panel turns the picture itself,
  as on Harmattan (address mode MY+MV, partial mode on the 854 visible
  rows), so Leste runs in landscape, 854x480, and the touchscreen's
  coordinates match the screen. X's omap driver cannot rotate on OMAP3.

The diagnostic kernel (`DIAG=1`, `kernel/diag-initramfs/README.md`) has
the display and a USB serial console built in. It showed the eMMC error
and Leste's whole boot.

## Open (2026-11-03)

- **No GPU yet; hildon-desktop draws in software and is slow.** The image
  carries the N900's PowerVR user space (`sgx-ddk-um-ti343x`, SGX530 1.2.1),
  the N950 has an SGX530 1.2.5: `SGXInit: Incompatible HW core rev (10205)
  and SW core rev (10201)`. TI's DDK 1.17.4948957 for the AM335x (`ti335x`,
  also 1.2.5) initializes the loaded `pvrsrvkm_omap3630_sgx530_125` when
  started by hand after the boot, but with it as the system's libraries
  the N950 hung during the boot.
- After the display was blanked, mce reported it on while X still had it
  off by DPMS (backlight on, picture black); `xset dpms force on` brought
  it back.
- `bq2415x_charger` is blacklisted on p4 and not yet tested
  (`/etc/modprobe.d/n950-test-chargers.conf`).
- n950-usbnet's address loses to the base image's `usb0` setup.
- Why NOLO cannot start the 6.18 kernel directly.
