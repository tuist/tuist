#!/usr/bin/env python3
"""Bake the community-grid Tuist burst (tuist-dither-data.js) from the brand mark.

Input: the mono brand mark rasterized on a transparent background at the
artwork size, e.g. with headless Chrome:

  printf '<img src="tuist-logo-mono-light.svg" width="568" height="568">' > r.html
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --default-background-color=00000000 --window-size=568,568 \
    --screenshot=mark.png r.html

Then: python3 bake_tuist_dither.py mark.png > ../js/hooks/tuist-dither-data.js

The silhouette is sampled on a 2px cell grid and only its outline is kept:
the cells within OUTLINE cells of the edge (a filled mark is ~47k particles,
which makes the hover physics crawl; the outline is a few thousand). Those
cells carry a vertical four-shade gradient (darkest at the top, lightest at
the bottom) that steps through half-shade plateaus, ordered-dithered with an
8x8 Bayer matrix the way the original Figma "bayer8 / mono6" export was.
Every cell is its own particle (the packed format allows wider runs, but
merging cells into bars makes the hover scatter move whole streaks instead
of dots), one 32-bit word each: cellX | cellY << 9 | cellWidth << 18 |
shade << 27, little-endian, base64. The filled silhouette goes along as
`fill`, per-row spans in the same word layout, for the backdrop the hook
paints under the particles so the grid lines don't show through the mark.
"""

import base64
import math
import struct
import sys

from PIL import Image

CELL = 2
SHADES = 4
OUTLINE = 2  # outline thickness, in cells
BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]


def gradient_level(t):
    """Shade level 3 (top) -> 0 (bottom) with half-shade plateaus."""
    k = 2 * (SHADES - 1) * (1 - t)
    base = math.floor(k)
    frac = k - base
    # Hold each half-step for most of its span and blend only near the edges.
    frac = min(1.0, max(0.0, (frac - 0.5) / 0.4 + 0.5))
    return (base + frac) / 2


def main(path):
    img = Image.open(path).convert("RGBA")
    width, height = img.size
    alpha = img.getchannel("A").load()
    cols, rows = width // CELL, height // CELL
    covered = [
        [
            sum(alpha[cx * CELL + i, cy * CELL + j] for i in range(CELL) for j in range(CELL))
            >= 255 * CELL * CELL / 2
            for cx in range(cols)
        ]
        for cy in range(rows)
    ]

    def edge(cx, cy):
        for dy in range(-OUTLINE, OUTLINE + 1):
            for dx in range(-OUTLINE, OUTLINE + 1):
                if dx * dx + dy * dy > OUTLINE * OUTLINE:
                    continue
                nx, ny = cx + dx, cy + dy
                if not (0 <= nx < cols and 0 <= ny < rows) or not covered[ny][nx]:
                    return True
        return False

    words = []
    for cy in range(rows):
        t = cy / max(1, rows - 1)
        level = gradient_level(t)
        for cx in range(cols):
            if not covered[cy][cx] or not edge(cx, cy):
                continue
            lo = math.floor(level)
            threshold = (BAYER8[cy % 8][cx % 8] + 0.5) / 64
            shade = min(SHADES - 1, lo + (1 if level - lo > threshold else 0))
            words.append(cx | (cy << 9) | (1 << 18) | (shade << 27))
    fill = []
    for cy in range(rows):
        cx = 0
        while cx < cols:
            if not covered[cy][cx]:
                cx += 1
                continue
            start = cx
            while cx < cols and covered[cy][cx]:
                cx += 1
            fill.append(start | (cy << 9) | ((cx - start) << 18))
    data = base64.b64encode(struct.pack("<%dI" % len(words), *words)).decode()
    fill_data = base64.b64encode(struct.pack("<%dI" % len(fill), *fill)).decode()
    print(
        f"""/*
 * Generated from the brand mark by assets/marketing/scripts/bake_tuist_dither.py
 * — do not edit by hand.
 *
 * Each 32-bit little-endian word packs one particle on the artwork's 2px
 * cell grid: cellX (9 bits) | cellY << 9 | cellWidth << 18 | shade << 27
 * (0 = lightest .. 3 = darkest). Every particle is a single cell (width 1);
 * multiply cells by 2 for px. `fill` holds the filled silhouette as per-row
 * spans in the same layout (shade unused), for the backdrop.
 */

export const TUIST_DITHER = {{
  width: {width},
  height: {height},
  cell: {CELL},
  runs: {len(words)},
  data: "{data}",
  fillRuns: {len(fill)},
  fill: "{fill_data}",
}};"""
    )


if __name__ == "__main__":
    main(sys.argv[1])
