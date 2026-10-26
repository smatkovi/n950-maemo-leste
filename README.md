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
| `docs/` | hardware status, boot paths, test plan |

## Plan

1. Device tree nodes for the hardware that has drivers already: touchscreen,
   LP5523 LEDs, bq24153a charger, bq27521 fuel gauge, AK8974 compass,
   accelerometer through IIO, TLV320DAC33, TPA6140A2, OneNAND read-only
   (so that the boot loader is never writable from Leste), ramoops.
2. Small driver changes: device tree matching for TLV320DAC33 and the
   BH1770GLC proximity/light sensor.
3. The display: the OMAP DSI FIFO workaround for command-mode panels with
   manual updates (Sebastian Reichel's), orientation of the panel.
4. Audio: a machine driver for TWL5031, TLV320DAC33 and TPA6140A2.
5. GPS (BCM4751): a driver in the kernel's GNSS subsystem (power, reset,
   the serial link as `/dev/gnss0`). The chip's protocol is proprietary and
   has no free implementation, so positions do not arrive with this alone.
6. Booting: tethered over USB into RAM first (nothing is flashed), later
   ubiboot from the eMMC's fourth partition.

Firmware and calibration data from Harmattan (WLAN NVS, Bluetooth
`ti1273.bin`, touchscreen configuration) are never part of this repository.

## License

The kernel patches are GPL-2.0 like the kernel; the scripts are MIT.
