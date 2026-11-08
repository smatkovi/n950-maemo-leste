# Harmattan 2.6.32 after kexec: the boot tracer

ubiboot (and MOSLO) can `kexec` the Maemo Leste 6.18 kernel on the N950, but
every Harmattan 2.6.32 kernel — stock, openmode_l2fix, openmode_icachefix —
goes black within a second and leaves nothing behind: no mtdoops record, no
USB, no screen. The same stock kernel boots when NOLO starts it from mtd2.
The N950 has no serial console reachable without a 1.8 V adapter on the test
pads, so every attempt so far failed invisibly.

This directory makes the early boot visible without a UART. The kernel here
is Nokia's `kernel-2.6.32-20115101+0m7` (2.6.32.48-dfl61, the Harmattan
source drop) with two patches, built with the Harmattan SDK's CodeSourcery
2009q3 toolchain, the one Nokia used.

| File | What |
| --- | --- |
| `patches/0001-decompressor-icache-btb-invalidate.patch` | the "icachefix" in source form (I-cache + branch predictor invalidate at `cache_on`); did not help on its own |
| `patches/0002-n950tr-boot-tracer.patch` | the tracer: progress markers from the first instruction of the zImage to the exec of `/sbin/preinit` |
| `build-tracer.sh` | configure (`rm581_defconfig` + KEXEC + ATAGS_PROC), build, patch the self-checksum, copy to `~/n950/zImage_2.6.32.48-n950tr1` |
| `n950tr-csum.py` | writes the image checksum into the zImage header (the decompressor verifies itself with it) |
| `n950tr-test.sh` | one test run from the ubiboot maintenance shell: erase mtd3, upload the kernel to RAM, kexec |
| `n950tr-read.sh` | after the reset: read the markers back from mtd3 and RAM and decode them |
| `ubiboot-telnet.py` | runs commands in ubiboot's maintenance telnet shell (it needs CRLF line endings) |

Build: `./build-tracer.sh` (about 3 minutes on 4 cores). The tree must have
`kernel/timeconst.pl` fixed for a modern perl (`defined(@val)` → `@val`).

## How the tracer works

Each stage writes to two places that can be read back after the device has
reset (`arch/arm/include/asm/n950trace.h` in the patch has the details):

1. **OneNAND, block 80 = mtd3 ("log") offset 0x40000.** Stage *n* unlocks
   the block and programs page *n* of it: header `"N9TR"` (reads as `RT9N`
   in a hexdump), stage, aux0, aux1, then the pattern `0xA500|n`. The chip
   is driven directly through its memory-mapped registers at GPMC CS0
   (0x04000000), the same UNLOCK and PROG sequences `onenand_base.c` uses,
   with bounded waits. Programming an erased page needs no driver, no
   interrupts, no MMU and survives anything, including a battery pull.
   mtdoops (this tree's `find_next_position` has no magic check) takes the
   page-16 header for a record and continues in block 81, so it never
   erases block 80.
2. **RAM at 0x9F000000** (8 words: magic, bitmask of stages, last stage,
   aux0, aux1, counter, OneNAND CTRL_STATUS after the last PROG, WP_STATUS
   after the last UNLOCK). Only useful if DDR keeps its contents through
   the TWL5031 watchdog reset — unknown, cheap to try. The kernel reserves
   the page and maps it uncached, so if the tracer kernel ever reaches user
   space the record is also readable from there via `/dev/mem`.

The decompressor also **checksums its own image** as its second act: all
words from `start` to `_edata`, compared with the value `n950tr-csum.py`
stored at offset 0x30 of the zImage. Stage 2 means intact, stage 31 means
the copy kexec made is corrupt (aux0 = computed, aux1 = expected).

### Stages = page numbers

| Page | Where | Meaning |
| --- | --- | --- |
| 1 | decompressor | first instructions of the zImage ran |
| 2 / 31 | decompressor | image checksum OK / **corrupt** |
| 3 | decompressor | caches + MMU on (`cache_on` returned) |
| 4 | decompressor | about to decompress (aux0 = 1: relocating path) |
| 5 | decompressor | decompressed (aux0 = length) |
| 6 | decompressor | caches off, jumping to the kernel (aux0 = entry, aux1 = atags) |
| 26 | decompressor | `error()` — bad LZO stream or similar |
| 7 | head.S | `stext`: kernel entry |
| 8 | head.S | processor + machine recognised, page tables built |
| 9 | head.S | `__v7_setup` done, about to turn the MMU on |
| 10 | head.S | MMU on, jumping to `start_kernel` |
| 28 / 29 / 30 | head.S | unknown processor / unknown machine ID / early error loop |
| 11 | C | `start_kernel` |
| 12 / 13 | C | before / after `paging_init` |
| 14 | C | after `setup_arch` |
| 15 / 16 / 17 / 18 | C | after `mm_init` / `init_IRQ` / `time_init` / `console_init` |
| 19 / 20 | C | `rest_init` / `kernel_init` |
| 21 | C | before `do_basic_setup` (all initcalls) |
| 22 / 23 | C | `omap3_pm_init` entry / exit (aux0 = return value) |
| 24 | C | after `do_basic_setup` |
| 25 | C | `init_post`: about to exec init — the kernel booted |
| 27 | C | `die()`: kernel oops (aux0 = error, aux1 = pc) |
| 0 | C | `panic()` |

The highest page written is how far the kernel got. A gap tells where it
died: pages 1 and 2 but no 3 → it dies in `cache_on`; up to 6 but no 7 →
the jump to the decompressed kernel; 31 → kexec corrupted the image.

## Why the self-checksum: a theory that fits all the facts

The 2.6.32 kexec implementation (`cpu_v7_reset` is a plain `mov pc, r0`)
jumps to `relocate_new_kernel` **with the MMU on**. `setup_mm_for_reboot()`
only identity-maps user space, i.e. physical addresses below `TASK_SIZE`.
ubiboot's kernel (IKCONFIG extracted from `zImage_2.6.32.54-ubiboot-02`) has
`CONFIG_PAGE_OFFSET=0xB0000000`, so `TASK_SIZE` = 0xAF000000, while the
N950's RAM runs from 0x80000000 to 0xBEA00000. Any kexec source page above
0xAF000000 is read through the kernel's linear map instead and copies the
wrong data. The page allocator hands out high pages first. Whether the
copied zImage is intact is therefore a matter of luck — which would explain
why 6.18 sometimes works and 2.6.32 never has, and why every outcome so far
was silent. Stage 31 would confirm it; the fix would then be in the kexec
*host* (ubiboot's kernel: turn the MMU off in `cpu_reset`, or boot it with
`mem=752M`), not in the Harmattan kernel at all.

## Running a test

The device must be in ubiboot's maintenance mode (USB connected when ubiboot
starts). On the PC `sudo dhclient <usb interface>`; the device is
`G_IP_ADDRESS` from `ubiboot.conf` (192.168.2.15 with the deployed
configuration, 192.168.0.15 when ubiboot runs without one).

```
./n950tr-test.sh ~/n950/zImage_2.6.32.48-n950tr1 192.168.2.15
```

first programs page 63 of block 80 by hand with `devmem`, the very
sequence the tracer uses (this proves the chip address, the register
offsets, the page addressing and the lock state from ubiboot's shell
before any kernel is involved — expected: WP_STATUS 0x0004, CTRL_STATUS
without bit 10, the page reads `52 54 39 4e 63 00 00 00`), then erases
mtd3 (`flash_erase /dev/mtd3 0 8`), sends the zImage into `/tmp` (RAM only
— the 2.6.32 stack hangs on sustained network + eMMC traffic), loads it
with ubiboot's own command line (`/proc/original_cmdline`, as
`select_os_animated.sh` does) and runs `kexec -e`. The screen goes black.
Wait for the TWL5031 watchdog to reset the phone (about 30 s) or pull the
battery, boot into maintenance mode again and run

```
./n950tr-read.sh 192.168.2.15
```

which reads the RAM record first (ubiboot's kernel treats that page as
free memory) and then the pages found in block 80, and decodes both. To put the
tracer in the boot menu instead, copy it to partition 2 `/boot/` and add a
`G_OS2_3_LABEL`/`G_OS2_3_FILE` line to `ubiboot.conf`.

Neither script has run against the phone yet (written 2026-11-08 without
the device attached); the device-side commands are the ones used by hand on
2026-11-07/08.

## Status

- 2026-11-08: tracer built, **run on the phone, and the black screen diagnosed.**
  The kexec'd Harmattan kernel reaches stage 24 (end of `do_basic_setup`) with no
  panic and the image checksum intact — it is not a kexec death but a hang at the
  **eMMC root mount** (`prepare_namespace` waiting for `/dev/mmcblk0p2`), the same
  eMMC-after-kexec timeout Leste fixes with patch 0020. Patch `0003` adds that retry
  to 2.6.32; `~/n950/zImage_2.6.32.48-n950tr-mmc` (md5 `70b6cd1b`) carries the fix and
  the tracer. See **HANDOVER-boot-from-ubiboot.md** for booting both OSes.
