#!/usr/bin/env python3
"""Draws Icon.tga: two diamonds of buttons, the selected one lit, on a dark badge.
Run from the addon folder. Needs Pillow. WoW reads uncompressed 32-bit TGA with power-of-two sides."""
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 64
SS = 8  # supersampling
S = SIZE * SS


def rounded(draw, cx, cy, half, radius, fill):
    draw.rounded_rectangle((cx - half, cy - half, cx + half, cy + half), radius=radius, fill=fill)


def diamond(draw, cx, cy, spread, half, fill):
    for dx, dy in ((-spread, 0), (spread, 0), (0, -spread), (0, spread)):
        rounded(draw, cx + dx, cy + dy, half, half * 0.45, fill)


def main(path):
    image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    margin = 1.5 * SS
    draw.rounded_rectangle((margin, margin, S - margin, S - margin), radius=11 * SS,
                           fill=(16, 24, 44, 255), outline=(214, 170, 72, 255), width=2 * SS)

    left, right, middle = 17.5 * SS, 46.5 * SS, 32 * SS
    spread, half = 7.4 * SS, 4 * SS

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    diamond(ImageDraw.Draw(glow), right, middle, spread, half * 1.3, (255, 190, 70, 150))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(2 * SS)))

    draw = ImageDraw.Draw(image)
    diamond(draw, left, middle, spread, half, (120, 150, 190, 255))
    diamond(draw, right, middle, spread, half, (255, 214, 110, 255))

    image.resize((SIZE, SIZE), Image.LANCZOS).save(path, rle=False)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Icon.tga")
