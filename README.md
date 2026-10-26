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

## Status

| Part | State |
| --- | --- |
| Display | OMAP DSI FIFO thresholds for the manually updated panel (`0001`), panel orientation from the device tree and the 854 visible lines of the Himalaya panel (`0002`, `0003`) |
| Touchscreen, LEDs, sensors, fuel gauge | device tree for the maXTouch, LP5523, LIS302DL accelerometer, AK8974 compass, bq27521; OneNAND read-only so the boot loader is never writable from Leste (`0004`) |
| Proximity and light | BH1770GLC/SFH7770 device tree support and node (`0005`, `0006`) |
| Audio | TLV320DAC33 device tree support, a machine driver for TWL5031 + TLV320DAC33 + TPA6140A2 on one card, device tree nodes (`0007` to `0011`). No headset detection: that runs through the TWL5031 ACI block, which has no driver. |
| GPS (BCM4751) | in progress, see below |
| Charger (bq24153a) | left out on purpose until it can be tested on the phone |

GPS: the BCM4751's protocol is proprietary and has no free implementation.
The driver being written here offers Nokia's own interface
(`/dev/bcm4751-gps`, `enable`/`hostreq`/`wakeup` in sysfs), so that
Harmattan's GPS stack from the MeeGo partition might be run under Leste.
Whether that works is open until it is tried on the phone.

Booting: tethered over USB into RAM first (nothing is flashed), later
ubiboot with Leste on its own partition next to Harmattan.

Firmware and calibration data from Harmattan (WLAN NVS, Bluetooth
`ti1273.bin`, touchscreen configuration) are never part of this repository.

## License

The kernel patches are GPL-2.0 like the kernel; the scripts are MIT.
