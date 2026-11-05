#!/usr/bin/env python3
"""Draws tools/logo.png, the project logo for CurseForge: the addon icon's two diamonds over "XIV".
Run from the addon folder. Needs Pillow and the Liberation Serif font."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_icon import diamond

SIZE = 1024
SS = 2  # supersampling
S = SIZE * SS
FONT = "/usr/share/fonts/liberation/LiberationSerif-Bold.ttf"

NAVY_CENTRE = (30, 44, 78)
NAVY_EDGE = (10, 15, 30)
GOLD = (214, 170, 72, 255)
LIT = (255, 214, 110, 255)
UNLIT = (120, 150, 190, 255)


def background():
    """A soft spotlight behind the lit buttons, fading to the badge's navy."""
    small = Image.new("RGB", (256, 256))
    pixels = small.load()
    for y in range(256):
        for x in range(256):
            distance = min(1, (((x - 128) ** 2 + (y - 110) ** 2) ** 0.5) / 180)
            pixels[x, y] = tuple(round(c + (e - c) * distance) for c, e in zip(NAVY_CENTRE, NAVY_EDGE))
    return small.resize((S, S), Image.BICUBIC).convert("RGBA")


def main(path):
    image = background()
    draw = ImageDraw.Draw(image)
    margin = S * 0.035
    draw.rounded_rectangle((margin, margin, S - margin, S - margin), radius=S * 0.13,
                           outline=GOLD, width=round(S * 0.016))

    left, right, middle = S * 0.29, S * 0.71, S * 0.36
    spread, half = S * 0.105, S * 0.056

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    diamond(ImageDraw.Draw(glow), right, middle, spread, half * 1.3, (255, 190, 70, 170))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.03)))

    draw = ImageDraw.Draw(image)
    diamond(draw, left, middle, spread, half, UNLIT)
    diamond(draw, right, middle, spread, half, LIT)

    font = ImageFont.truetype(FONT, round(S * 0.33))
    draw.text((S / 2, S * 0.76), "XIV", font=font, fill=LIT, anchor="mm")

    image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB").save(path, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "tools/logo.png")
