#!/usr/bin/env python3
"""Generate the PlotName AI app icon.

Produces a 1024x1024 RGB PNG (no alpha — App Store rejects transparency in the
marketing icon). The artwork is a white manga page with a classic right-to-left
panel layout (コマ割り) and a speech bubble, plus an AI sparkle, on an
indigo→violet gradient. Full-bleed; iOS applies the rounded-rect mask.

Run from the repo root:
    python3 Scripts/generate_plotname_icon.py
"""

from __future__ import annotations

import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "PlotNameAI", "ios", "PlotNameAI", "Resources",
    "Assets.xcassets", "AppIcon.appiconset",
)

# Brand palette: indigo → violet (AI creative tool).
TOP = (88, 86, 214)       # indigo (iOS systemIndigo)
BOTTOM = (142, 68, 173)   # violet
INK = (58, 50, 140)       # panel line ink (deep indigo)
WHITE = (255, 255, 255)
PAPER = (252, 252, 255)


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


def rounded_rect(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def sparkle(draw, cx, cy, r, color):
    """4-point star (AI sparkle)."""
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = r if i % 2 == 0 else r * 0.32
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    draw.polygon(pts, fill=color)


def main():
    img = gradient(SIZE)

    # --- soft page shadow --------------------------------------------------
    shadow = Image.new("L", (SIZE, SIZE), 0)
    sd = ImageDraw.Draw(shadow)
    page = (250, 138, 774, 886)  # portrait manga page (B5-ish ratio)
    sd.rounded_rectangle(
        (page[0] + 14, page[1] + 22, page[2] + 14, page[3] + 22), 28, fill=110
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    dark = Image.new("RGB", (SIZE, SIZE), (18, 22, 60))
    img = Image.composite(dark, img, shadow)

    d = ImageDraw.Draw(img)

    # --- the page -----------------------------------------------------------
    rounded_rect(d, page, 28, fill=PAPER)

    # --- panel layout (right-to-left manga koma) ----------------------------
    m = 44            # page margin
    g = 26            # gutter
    w = 16            # line width
    x0, y0, x1, y1 = page[0] + m, page[1] + m, page[2] - m, page[3] - m

    row1_h = 190
    row2_h = 260
    # row 3 takes the rest

    def panel(box):
        rounded_rect(d, box, 10, outline=INK, width=w)

    # Row 1: full-width establishing panel.
    panel((x0, y0, x1, y0 + row1_h))

    # Row 2: two panels, the RIGHT one bigger (read right-to-left).
    r2y0 = y0 + row1_h + g
    split = x0 + (x1 - x0) * 0.42  # left panel 42%, right 58%
    panel((split + g / 2, r2y0, x1, r2y0 + row2_h))       # right (big)
    panel((x0, r2y0, split - g / 2, r2y0 + row2_h))       # left (small)

    # Row 3: full-width climax panel with a speech bubble.
    r3y0 = r2y0 + row2_h + g
    panel((x0, r3y0, x1, y1))

    # Speech bubble inside row 3 (right side — first in reading order).
    # コマ内に完全に収める（前版はページ下端をはみ出していた）。
    bw, bh = 200, 88
    bx1 = x1 - 40
    bx0 = bx1 - bw
    by0 = r3y0 + 26
    by1 = by0 + bh                       # r3y0+114 << y1 なのでコマ内に収まる
    d.ellipse((bx0, by0, bx1, by1), outline=INK, width=w - 2, fill=PAPER)
    # bubble tail (down-left, kept inside the panel)
    tail_tip = (bx0 + 8, min(by1 + 26, y1 - 14))
    d.polygon(
        [(bx0 + 56, by1 - 12), tail_tip, (bx0 + 104, by1 - 4)],
        fill=PAPER,
    )
    d.line([(bx0 + 56, by1 - 10), tail_tip], fill=INK, width=w - 4)
    d.line([tail_tip, (bx0 + 104, by1 - 6)], fill=INK, width=w - 4)

    # Speed lines in the row-2 right panel (action feel).
    p_x0, p_x1 = split + g / 2 + 34, x1 - 34
    p_y0 = r2y0 + 40
    for i in range(5):
        t = i / 4
        lx0 = p_x0 + (p_x1 - p_x0) * 0.55 * t
        ly = p_y0 + i * 38
        d.line([(lx0, ly), (p_x1, ly + 10)], fill=INK, width=8)

    # --- AI sparkles ---------------------------------------------------------
    sparkle(d, page[0] - 62, page[1] + 40, 66, WHITE)
    sparkle(d, page[2] + 52, page[3] - 96, 44, WHITE)
    sparkle(d, page[0] - 30, page[3] - 30, 26, WHITE)

    # --- write out -----------------------------------------------------------
    os.makedirs(OUT_DIR, exist_ok=True)
    out_png = os.path.join(OUT_DIR, "AppIcon1024.png")
    img.save(out_png, "PNG")

    contents = {
        "images": [
            {
                "filename": "AppIcon1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")
    print(f"wrote {out_png}")


if __name__ == "__main__":
    main()
