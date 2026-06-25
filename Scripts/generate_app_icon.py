#!/usr/bin/env python3
"""Generate the ProjectStock app icon.

Produces a 1024x1024 RGB PNG (no alpha — App Store rejects transparency in the
marketing icon). The artwork is a stylised QR glyph (three finder patterns plus
a deterministic data field) in white on the brand-blue gradient, evoking the
app's QR-driven inventory purpose. The icon is full-bleed; iOS applies the
rounded-rect mask at display time.

Run from the repo root:
    python3 Scripts/generate_app_icon.py
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "ProjectStock", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)

# Brand palette (matches AccentColor.colorset ~ #2173D9).
TOP = (46, 134, 230)      # lighter blue
BOTTOM = (20, 84, 184)    # deeper blue
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    """Diagonal top-left -> bottom-right brand gradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    maxd = (size - 1) * 2
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(TOP, BOTTOM, (x + y) / maxd)
    return img


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def finder(draw, ox, oy, m):
    """A QR finder pattern: 7x7 modules drawn as nested rounded squares."""
    outer = (ox, oy, ox + 7 * m, oy + 7 * m)
    rounded(draw, outer, radius=m * 1.6, fill=WHITE)
    inner = (ox + m, oy + m, ox + 6 * m, oy + 6 * m)
    # punch the ring by painting the gradient color back — but we have no source
    # here, so the caller composites a mask instead. (handled in main)
    return outer, inner


def main():
    base = gradient(SIZE)

    # Build the white artwork on a separate layer so we can carve the finder
    # rings cleanly with a mask, then composite over the gradient.
    art = Image.new("L", (SIZE, SIZE), 0)  # alpha mask for white ink
    d = ImageDraw.Draw(art)

    # Module grid: 11x11 within a centred content area.
    grid = 11
    content = int(SIZE * 0.70)
    m = content // grid
    span = m * grid
    origin = (SIZE - span) // 2
    gap = max(2, m // 10)

    def cell(col, row, on=True):
        x0 = origin + col * m + gap
        y0 = origin + row * m + gap
        x1 = origin + (col + 1) * m - gap
        y1 = origin + (row + 1) * m - gap
        d.rounded_rectangle((x0, y0, x1, y1), radius=(m - 2 * gap) * 0.32,
                            fill=255 if on else 0)

    # Deterministic data field (fixed bitmap so builds are reproducible).
    DATA = [
        "00000000000",
        "00000010100",
        "00011011000",
        "00010001100",
        "00011100100",
        "00001011000",
        "00100010100",
        "00010101000",
        "00000000000",
        "00000000000",
        "00000000000",
    ]
    for r, line in enumerate(DATA):
        for c, ch in enumerate(line):
            if ch == "1":
                cell(c, r, on=True)

    # Three finder patterns (TL, TR, BL) drawn as ring + centre dot.
    def finder_at(col, row):
        x0 = origin + col * m
        y0 = origin + row * m
        # outer 7x7 rounded square
        d.rounded_rectangle((x0, y0, x0 + 7 * m, y0 + 7 * m),
                            radius=m * 1.7, fill=255)
        # carve inner ring (5x5) back to transparent
        d.rounded_rectangle((x0 + m, y0 + m, x0 + 6 * m, y0 + 6 * m),
                            radius=m * 1.1, fill=0)
        # centre 3x3 dot
        d.rounded_rectangle((x0 + 2 * m, y0 + 2 * m, x0 + 5 * m, y0 + 5 * m),
                            radius=m * 0.8, fill=255)

    finder_at(0, 0)
    finder_at(grid - 7, 0)
    finder_at(0, grid - 7)

    # Soft drop shadow for depth.
    shadow = art.filter(ImageFilter.GaussianBlur(SIZE // 90))
    shadow_rgb = Image.new("RGB", (SIZE, SIZE), (10, 40, 90))
    base.paste(shadow_rgb, (0, SIZE // 110), shadow.point(lambda v: int(v * 0.35)))

    # White ink.
    white = Image.new("RGB", (SIZE, SIZE), WHITE)
    base.paste(white, (0, 0), art)

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "AppIcon.png")
    base.save(out, "PNG")
    # Strip any alpha defensively (App Store requirement).
    Image.open(out).convert("RGB").save(out, "PNG")
    print("wrote", os.path.relpath(out))


if __name__ == "__main__":
    main()
