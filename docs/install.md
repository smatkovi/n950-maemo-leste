# Installing Leste next to Harmattan

Leste gets its own partition (p4, 4 GiB) in the space that MyDocs gives up;
Harmattan's root (p2) and /home (p3) stay where they are. ubiboot, in the
OneNAND in place of Harmattan's kernel, offers both at power-on.

```
 p1  MyDocs (FAT32)   1024 .. 10076159        4.8 GiB, was 8.8 GiB
 p4  Leste (ext4)     10076160 .. 18464767    4 GiB, new
 p2  Harmattan root   18464768 .. 26853375    4 GiB, unchanged
 p3  Harmattan /home  26853376 .. 31047679    2 GiB, unchanged
```

## What ubiboot needs from p4

ubiboot (0.3.9, by juiceme) reads the kernel to boot from the partition of
the chosen system, with its own 2.6.32 kernel. That kernel mounts no ext4
with newer features (`64bit`, `metadata_csum`, `metadata_csum_seed`,
`orphan_file`; ubiboot's log shows "unsupported optional features"), which
a current `mkfs.ext4` sets by default. So `rootfs/build.sh` makes p4 with
exactly the features of Harmattan's own p2:

    has_journal ext_attr resize_inode dir_index filetype extent flex_bg
    sparse_super large_file huge_file uninit_bg dir_nlink extra_isize

and the installer refuses an image with any other feature. The same holds
for p3: Harmattan does not boot without a /home file system (the N950 at
hand had none there, so Harmattan rebooted into ubiboot each time); the
installer makes one, with p2's features, only when p3 has none.

ubiboot's entry for Leste (OS 5, "Maemo") points at p4:

    G_OS5_PARTITION=4
    G_OS5_1_FILE="/boot/Maemo/boot/zImage"       # p4:/boot/zImage
    G_OS5_INIT_CMDLINE_FILE="/boot/Maemo/boot/cmdline"
    G_OS5_INITSCRIPT="\/sbin\/init"

ubiboot links `/boot/<name>` to the mount of each system's partition, so
`/boot/Maemo/boot/zImage` is p4's `/boot/zImage`: the kernel with the
N950's device tree appended. Its command line comes from p4's
`/boot/cmdline` in full, since the one ubiboot would otherwise derive from
Harmattan's names the eMMC `mmcblk0`; Linux 6.18 names it `mmcblk1` (the
eMMC is on the second controller):

    root=/dev/mmcblk1p4 rootwait rw rootfstype=ext4 init=/sbin/init console=tty0

The kernel takes it from ubiboot's ATAGs (`ARM_ATAG_DTB_COMPAT`,
command line from the boot loader).

## Steps

1. **Build** (on a PC with sudo, qemu-user-static, debootstrap's tools):

       WORK=$HOME/n950-kernel bash kernel/build.sh
       curl -O https://maedevu.maemo.org/images/n900/20261019-excalibur/maemo-leste-excalibur-n900-20261019.img.xz
       xz -d maemo-leste-excalibur-n900-20261019.img.xz
       WORK=$HOME/n950-kernel SRC_IMG=maemo-leste-excalibur-n900-20261019.img \
           SSH_PUBKEY=$HOME/.ssh/id_ed25519.pub bash rootfs/build.sh

   or take `n950-leste-excalibur-<date>.img.xz` from the releases (no SSH
   key in it; root's password is `n950-leste`).

2. **ubiboot** must be installed already (its kernel in the OneNAND, its
   `ubiboot.conf` and `ubiboot-02.menus.cpio` in MyDocs' `boot/`), with
   `G_EXPORTED_PARTITONS="/dev/mmcblk0"`.

3. **Export the eMMC:** start the N950 with the USB cable to the PC plugged
   in. ubiboot then shows no menu and exports the whole eMMC as a USB disk
   (and offers telnet/SSH at 192.168.2.15). Find the disk on the PC
   (`lsblk`: 14.8 GiB, partitions 1-3) and unmount anything the desktop
   mounted from it.

4. **Install:**

       sudo bash install/n950-install.sh /dev/sdX n950-leste.img

   It checks that the disk is the N950 (size, Nokia's layout, Harmattan on
   p2), saves the partition table, the first MiB and all of MyDocs to
   `n950-backup-<time>/`, asks, then repartitions, makes MyDocs again and
   copies its files back, makes /home if it has none, writes Leste to p4
   and adds the "Maemo" entry to `ubiboot.conf`. Run again later (for a
   new image) it only rewrites p4 and the entry.

5. **Boot:** unplug, power on, pick "Maemo" in ubiboot's menu. With the USB
   cable in, Leste's USB network comes up at 192.168.2.15 (the PC gets
   192.168.2.100 by DHCP): `ssh root@192.168.2.15`. On its first boot
   Leste copies the N950's Wi-Fi NVS and Bluetooth firmware from Harmattan's
   partition (`n950-firmware`); nothing of Nokia's is in the image.

   If the image has `/boot/kolibri.bin` (the release images from
   leste-20261029 on), the "Maemo" entry has two lines, "Leste, Linux
   6.18" and "KolibriOS (test)", and ubiboot asks which one
   (`G_OS5_AUTOBOOT=0`); set it back to 1 in `ubiboot.conf` to go
   straight into Leste. KolibriOS: smatkovi/kolibrios-arm, `docs/n950.md`.

## First checks on the phone

- FM radio, with headphones plugged in (their cable is the antenna):
  `dmesg | grep -i wl1273` and `ls /dev/radio0` (the driver only loads
  and registers, the chip stays in reset), then `n950-fm-test scan` or
  `n950-fm-test <MHz>`: it switches the receiver on, prints the chip's
  RSSI, stereo and RDS once a second and switches it off again. I2C
  errors in `dmesg` there mean the chip did not leave reset: compare
  GPIO 179 and 43 in `/sys/kernel/debug/gpio` with
  `kernel/patches/0019`.
- FM sound, as the session's user: `n950-fm-test -k <MHz>`, then
  `n950-fm-audio on` (the AUX inputs as the TWL5031's capture, played by
  a PulseAudio loopback), `n950-fm-audio off`, `n950-fm-test off`. If
  nothing is heard, `FM_AUDIO=bypass` in `/etc/default/n950-fm` routes it
  inside the codecs without PulseAudio (mono), and `amixer -c N950`
  shows what is set. Then the "FM Radio" application.

## Not known yet

Nothing here has run on the phone. In particular: whether ubiboot's
kexec loads a 6.18 zImage with an appended device tree, how the X server's ManualUpdate behaves
on this panel, the FM radio (the reset line is GPIO 179 for boards after
revision 0x0324, as the N950 at hand reports 1124; earlier ones share
GPIO 26 with Bluetooth), and the charger: without a bq24153 driver the charger runs
in its default mode, so check the battery when Leste runs for long.
