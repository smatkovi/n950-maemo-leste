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

## Status

| Part | State |
| --- | --- |
| Display | OMAP DSI FIFO thresholds for the manually updated panel (`0001`), panel orientation from the device tree and the 854 visible lines of the Himalaya panel (`0002`, `0003`) |
| Touchscreen, LEDs, sensors, fuel gauge | device tree for the maXTouch, LP5523, LIS302DL accelerometer, AK8974 compass, bq27521; OneNAND read-only so the boot loader is never writable from Leste (`0004`) |
| Proximity and light | BH1770GLC/SFH7770 device tree support and node (`0005`, `0006`) |
| Audio | TLV320DAC33 device tree support, a machine driver for TWL5031 + TLV320DAC33 + TPA6140A2 on one card, device tree nodes (`0007` to `0011`). No headset detection: that runs through the TWL5031 ACI block, which has no driver. |
| GPS (BCM4751) | driver with Nokia's interface, binding lines for wakeup and HOST_REQ, device tree node (`0012` to `0014`); see below |
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

It hands out positions over its socket `/var/run/nped/nped.socket`
(Harmattan's `positioningd` is the client there); its D-Bus name only
serves network-initiated SUPL. The socket protocol is not decoded yet, so
there is no bridge to gpsd so far.

Booting: ubiboot with Leste on its own partition (p4, 4 GiB, taken from
MyDocs) next to Harmattan, see [docs/install.md](docs/install.md). The file
systems ubiboot reads get exactly the ext4 features of Harmattan's own root
partition, since ubiboot's 2.6.32 kernel mounts nothing newer. For a first test,
a tethered boot into RAM (`flasher -k`, nothing flashed) needs no
partition at all.

Firmware and calibration data from Harmattan (WLAN NVS, Bluetooth
`ti1273.bin`, touchscreen configuration) are never part of this repository.

## License

The kernel patches are GPL-2.0 like the kernel; the scripts are MIT.
