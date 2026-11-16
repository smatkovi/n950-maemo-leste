# Maemo Leste on the Nokia N9

The N9 (RM-696) is the N950's sibling: same SoC, GPU, modem, audio and
eMMC, but Wi-Fi on SDIO instead of SPI, an AMOLED panel (pyrenees) mounted
the other way round, no keyboard. The kernel is the N950's with
`omap3-n9.dtb` (kernel patches 0060, 0061); the userland is the N950's
image plus the Maliit on-screen keyboard.

## Build

    BASE_IMG=<N950 Leste image of rootfs/build.sh> \
    KSRC=<kernel tree> KOUT=<its build directory> \
    OUT=n9-leste.img bash rootfs/n9/build.sh

`OUT_SECTORS` sets the file system size (default 5120000 sectors, the
Alt_OS partition MOSLO creates). Documentation, manual pages and
translations other than German and English are left out
(`dpkg.cfg.d/01-n9-slim`).

## On-screen keyboard

Maliit 2 (`maliit-framework`, `maliit-keyboard`) on X11:
`Xsession.d/89n9-maliit` sets `QT_IM_MODULE=Maliit` for the session,
`Xsession.post/16n9-maliit-server` has dsme run `n9-maliit-server` (Qt's
xcb backend). EmbedLite's qtmozembed shows it for every focused web field.
GTK/Hildon programs keep hildon-input-method. `IM=him` in `/etc/n9-im`
switches Qt back. German first, English next (`90_n9-maliit.gschema.override`).

## Install (ubiboot)

With ubiboot exporting the eMMC over USB (`/dev/sdX`):

- partition 4 (Leste): `tools/write-verify.sh n9-leste.img /dev/sdX4`, then
  `resize2fs` to the partition if it is larger than the image
- partition 2 (Harmattan) `/boot`: the MeeGo kernel that survives ubiboot's
  kexec, `zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia` (`harmattan-kexec/`);
  the stock and open-mode kernels hang at the root mount after kexec
- partition 1 (MyDocs) `/boot`: `ubiboot-02.menus.cpio` and the
  `ubiboot.conf` that `ubiboot/n9-ubiboot-conf.py` makes from a working N950
  one (MeeGo default, Leste as "Nemo" on partition 4, a new SSH host key)

Harmattan mounts `/home` from partition 3; without a file system there it
does not come up.
