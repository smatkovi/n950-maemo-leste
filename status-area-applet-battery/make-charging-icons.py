#!/usr/bin/env python3
"""Battery charging icons for Leste's status-area-applet-battery on the N950:
Leste's statusarea_battery_fullNN icons with a lightning bolt drawn over the
battery body, for a static charging indicator instead of the animation.

  make-charging-icons.py SRC DST
SRC holds Leste's icons as installed (scalable/hildon/*.png, 48x48/hildon/*.png),
DST receives statusarea_battery_chargingNN.png in the same layout.
"""
import os
import sys

from PIL import Image, ImageDraw

LEVELS = (13, 25, 38, 50, 63, 75, 88, 100)
# the bolt in the battery body's box, (0,0) top left .. (1,1) bottom right
BOLT = [(0.70, 0.02), (0.04, 0.60), (0.44, 0.60), (0.26, 0.98),
        (0.98, 0.36), (0.56, 0.36), (0.86, 0.02)]
SCALE = 8


def body_box(im):
    """The battery body below the terminal: opaque bounding box, top cut by the cap."""
    a = im.getchannel("A")
    x0, y0, x1, y1 = a.getbbox()
    w = x1 - x0
    # the cap is narrower than the body: skip rows narrower than 80 % of the width
    top = y0
    for y in range(y0, y1):
        row = [a.getpixel((x, y)) for x in range(x0, x1)]
        if sum(1 for v in row if v > 128) >= 0.8 * w:
            top = y
            break
    inset = max(1, round(w * 0.10))
    return x0 + inset, top + inset, x1 - inset, y1 - inset


def add_bolt(im):
    x0, y0, x1, y1 = body_box(im)
    big = Image.new("RGBA", (im.width * SCALE, im.height * SCALE), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pts = [((x0 + px * (x1 - x0)) * SCALE, (y0 + py * (y1 - y0)) * SCALE) for px, py in BOLT]
    outline = max(SCALE * 6 // 10, round((x1 - x0) * SCALE * 0.05))
    d.polygon(pts, fill=(255, 225, 77, 255), outline=(32, 32, 32, 255), width=outline)
    bolt = big.resize(im.size, Image.LANCZOS)
    out = im.copy()
    out.alpha_composite(bolt)
    return out


def main(src, dst):
    for size_dir in ("scalable/hildon", "48x48/hildon"):
        os.makedirs(os.path.join(dst, size_dir), exist_ok=True)
        for level in LEVELS:
            im = Image.open(os.path.join(src, size_dir, "statusarea_battery_full%d.png" % level)).convert("RGBA")
            add_bolt(im).save(os.path.join(dst, size_dir, "statusarea_battery_charging%d.png" % level))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
