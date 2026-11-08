#!/usr/bin/env python3
"""Patch the self-checksum into a zImage built with the n950tr boot tracer.

The decompressor (arch/arm/boot/compressed/head.S) sums all 32-bit words of
its own image from `start` to `_edata`, with the checksum word itself counted
as zero, and compares the result with the word stored at offset 0x30 (the
word after the standard zImage header; offset 0x34 holds the marker "N9TR").

Usage: n950tr-csum.py zImage            patch in place and verify
       n950tr-csum.py --check zImage    verify only
"""
import struct
import sys

CSUM_OFF = 0x30
MARK_OFF = 0x34


def word_sum(data, skip_off):
    total = 0
    for off in range(0, len(data), 4):
        if off == skip_off:
            continue
        total += struct.unpack_from("<I", data, off)[0]
    return total & 0xFFFFFFFF


def main():
    check_only = sys.argv[1] == "--check"
    path = sys.argv[-1]
    data = bytearray(open(path, "rb").read())
    if len(data) % 4:
        sys.exit("zImage length %d is not a multiple of 4" % len(data))
    if struct.unpack_from("<I", data, 0x24)[0] != 0x016F2818:
        sys.exit("no zImage magic at 0x24")
    if data[MARK_OFF:MARK_OFF + 4] != b"N9TR":
        sys.exit("no N9TR marker at 0x34: not a tracer zImage")
    stored = struct.unpack_from("<I", data, CSUM_OFF)[0]
    expected = word_sum(data, CSUM_OFF)
    if check_only:
        print("stored 0x%08x computed 0x%08x %s"
              % (stored, expected, "OK" if stored == expected else "MISMATCH"))
        sys.exit(0 if stored == expected else 1)
    struct.pack_into("<I", data, CSUM_OFF, expected)
    open(path, "wb").write(data)
    # verify the way the decompressor does it: sum of everything minus the
    # field equals the field
    total = 0
    for off in range(0, len(data), 4):
        total += struct.unpack_from("<I", data, off)[0]
    total = (total - expected) & 0xFFFFFFFF
    assert total == expected, "self-check failed after patching"
    print("checksum 0x%08x written to %s (%d bytes)" % (expected, path, len(data)))


if __name__ == "__main__":
    main()
