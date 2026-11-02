# Maemo Leste on the Nokia N950

Maemo Leste (Devuan-based continuation of Maemo 5) dual-booted next to
MeeGo Harmattan on the Nokia N950 (RM-680, OMAP3630): what mainline Linux and
Leste lack for this phone, as patches on Leste's own kernel, and how to build
and boot it.

**Status: everything here builds, nothing is tested on the phone yet.**

## What is here

| Path | What |
| --- | --- |
| `kernel/patches/` | patches on Leste's kernel (`leste-upstream-forks/droid4-linux`, branch `leste/maemo-6.18.y`, Linux 6.18) |
| `kernel/config/n950.config` | config fragment on top of Leste's `linux-image-omap` configuration |
| `kernel/build.sh` | fetches the tree, applies the patches, builds zImage, the N950 device tree and modules |
| `rootfs/build.sh` | Leste's root file system for partition 4: Leste's N900 image (same SoC family) with the N900 packages swapped for `hildon-meta-n950`, this kernel, `rootfs/overlay` (USB network, Wi-Fi/Bluetooth files from Harmattan, X for the command-mode panel) |
| `install/n950-install.sh` | from a PC, on the eMMC as ubiboot exports it: shrinks MyDocs, adds partition 4 with Leste, makes Harmattan's /home if missing, adds Leste to `ubiboot.conf` |
| `docs/install.md` | the layout, what ubiboot needs, the steps |
| `docs/boot-moslo.md` | **what boots today:** MOSLO from RAM, then Leste by kexec (2026-11-02), and what is still open |
| `gps/` | GPS through Harmattan's `nped` and `positioningd` in a chroot, bridged to gpsd (`harmattan-gps`, `positioningd-gpsd.py`) |
| `apps/n950-fm/` | FM radio for Hildon (the Pro1X's `pro1x-fm` for the N950's receiver), `n950-fm-audio` for its sound, `n950-fm-test` for a shell; `apps/build-deb.sh` builds it as an armhf .deb in a chroot of a Leste image |

## Status

| Part | State |
| --- | --- |
| Display | OMAP DSI FIFO thresholds for the manually updated panel (`0001`), panel orientation from the device tree and the 854 visible lines of the Himalaya panel (`0002`, `0003`) |
| Touchscreen, LEDs, sensors, fuel gauge | device tree for the maXTouch, LP5523 (channels 0-5 the keyboard light, 8 the white LED, as Harmattan's mce drives them), LIS302DL accelerometer, AK8974 compass, bq27521; OneNAND read-only so the boot loader is never writable from Leste (`0004`) |
| Proximity and light | BH1770GLC/SFH7770 device tree support and node (`0005`, `0006`) |
| Audio | TLV320DAC33 device tree support, a machine driver for TWL5031 + TLV320DAC33 + TPA6140A2 on one card, device tree nodes (`0007` to `0011`). Headphone plug detection as a switch (`SW_HEADPHONE_INSERT`, TWL5031 GPIO 0 as in Nokia's board file, `0015`); headset microphones and the headset button run through the TWL5031 ACI block, which has no mainline driver. |
| GPS (BCM4751) | driver with Nokia's interface, binding lines for wakeup and HOST_REQ, device tree node (`0012` to `0014`); see below |
| Keyboard | Nokia's own layouts (`nokia_vndr/rm-680` from Harmattan's xkeyboard-config, whose key codes match the device tree's keymap), compiled at session start in Leste's layout (`rootfs/overlay`); the keyboard light through Leste's mce (`70-n950.ini`) |
| FM radio (WL1273) | `radio-wl1273` back from v6.17 with device tree support, the N950's node: I2C3 0x22, interrupt GPIO 43, reset GPIO 179 (`0016` to `0019`); `/dev/radio0`. The sound: the chip's analog output into the TWL5031's AUXL/AUXR (Nokia's audio configuration 4), recorded by the TWL5031 and played through a PulseAudio loopback (`n950-fm-audio`), as Harmattan's audio policy does; the receiver's firmware patch comes from Harmattan at first boot |
| Charger (bq24153a) | left out on purpose until it can be tested on the phone |

GPS: the BCM4751's protocol is proprietary and has no free implementation.
The `bcm4751-gps` driver offers Nokia's own interface (`/dev/bcm4751-gps`
for raw I2C transfers, `enable`, `wakeup` and `hostreq` in the I2C device's
sysfs directory `3-a1fa`), so that Harmattan's GPS stack from the MeeGo
partition might be run under Leste. Without it the chip can be powered,
but nothing turns its data into positions. Whether Harmattan's stack runs
this way is open until it is tried on the phone.

What Harmattan's `nped` (the positioning engine, it computes the fixes
itself) needs from Leste, from reading its binary:

- the sysfs files of Nokia's driver at `3-01fa`, its old name for the
  device; under 6.18 it is `3-a1fa`, so `nped` needs that path changed in
  a local copy. It opens all three files read-write, `hostreq` included,
  which the driver allows for that reason.
- a phonet interface `phonet0` (it binds a phonet socket for the modem's
  assistance and stops without one).
- Harmattan's own libraries throughout (its loader and eglibc 2.10), so
  it runs in a chroot of Harmattan's partition.

It hands out positions over its socket `/var/run/nped/nped.socket` to
Harmattan's `positioningd`; its D-Bus name only serves network-initiated
SUPL. So the bridge to gpsd talks to `positioningd` instead, whose client
interface is open (Harmattan's QtMobility Location): `gps/`, see
[gps/README.md](gps/README.md).

Booting: ubiboot with Leste on its own partition (p4, 4 GiB, taken from
MyDocs) next to Harmattan, see [docs/install.md](docs/install.md). The file
systems ubiboot reads get exactly the ext4 features of Harmattan's own root
partition, since ubiboot's 2.6.32 kernel mounts nothing newer. For a first test,
a tethered boot into RAM (`flasher -k`, nothing flashed) needs no
partition at all.

Firmware and calibration data from Harmattan (WLAN NVS, Bluetooth
`ti1273.bin`, touchscreen configuration) are never part of this repository.

## Diagnostic kernel

    DIAG=1 WORK=$HOME/n950-kernel bash kernel/build.sh

builds a variant of the same kernel (version `-diag`) whose boot can be
watched before any root file system is mounted: `kernel/config/diag.config`
on top of `n950.config`, output in `$WORK/out-diag`, the release build left
alone. Built in: omapdrm with DSI, the panel (`panel-dsi-cm`) and fbcon
(landscape, `fbcon=rotate:3`); musb with the TWL4030 PHY and the serial
gadget with its console (`console=ttyGS0`, the PC's `/dev/ttyACM*`); a
1 MiB log; `ignore_loglevel panic=0` and the consoles appended to whatever
the boot loader passes (`CONFIG_CMDLINE_EXTEND`). Two patches go only into
this variant (`kernel/patches/diag/`):

- the N950's TWL5031 watchdog cannot be stopped (Harmattan logs "HACK:
  TWL5031 WDT can't be disabled" on every boot of the phone at hand), and
  mainline only writes 0 to it, so the phone resets at most 30 s after the
  boot loader's last kick; the patch has the watchdog core keep it fed;
- the panel's own backlight starts at brightness 0, which leaves the screen
  dark until user space sets one; the patch starts it at full brightness.

Boot it from RAM (nothing is written to the phone), the phone off and the
USB cable in:

    sudo flasher -k $HOME/n950-kernel/out-diag/arch/arm/boot/zImage-dtb -l \
        -b"root=PARTUUID=00048046-04 rootwait rw rootfstype=ext4 init=/sbin/init console=ttyGS0,115200 console=tty0"

and read the log on the PC as soon as the gadget appears, since its console
keeps only 8 KiB until the PC reads (ModemManager must not grab the port):

    until [ -e /dev/serial/by-id/*diag*Gadget_Serial* ]; do sleep 0.2; done
    stty -F /dev/serial/by-id/*diag*Gadget_Serial* raw -echo
    cat /dev/serial/by-id/*diag*Gadget_Serial* | tee n950-diag.log

Its modules are not built, those on p4 do not match it, and the serial
gadget holds the USB controller, so the image's USB network does not come
up. After a panic or a hard hang nothing feeds the watchdog, so the screen
stays for 15 to 30 s before the phone resets: film it.

## License

The kernel patches are GPL-2.0 like the kernel; the scripts are MIT.
