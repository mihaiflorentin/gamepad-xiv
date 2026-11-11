#!/usr/bin/env python3
"""Draws the tutorial's controller and the glow behind a highlighted button.

Media/controller.tga: a generic gamepad, shaded to look solid: triggers, bumpers, a raised D-pad,
four button sockets, two sticks and three small middle buttons. No brand shapes or logos. The tutorial
puts the game's own button icons for the controller in use on top, at the positions in POS below
(the same numbers as BUTTON_POSITIONS in Tutorial.lua, in a 512 x 256 layout).
Media/tutorial_glow.tga: a soft white disc, tinted and pulsed behind a button to press.

Run from the addon folder. Needs Pillow. WoW reads uncompressed 32-bit TGA with power-of-two sides."""
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 512, 256          # layout units, as in Tutorial.lua
OUT = 2                  # the texture is 1024 x 512
SS = 3                   # supersampling on top of that
K = OUT * SS
Wp, Hp = W * K, H * K

POS = {
    "LT": (136, 22), "RT": (376, 22), "LB": (136, 60), "RB": (376, 60),
    "DPAD": (134, 112), "FACE": (378, 112), "LS": (204, 168), "RS": (308, 168),
    "BACK": (222, 104), "START": (290, 104),
}


def s(*v):
    return tuple(int(round(x * K)) for x in v)


def mask():
    return Image.new("L", (Wp, Hp), 0)


def blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r * K))


def vgradient(top, bottom):
    """A full-size RGBA image going from colour `top` to `bottom`."""
    g = Image.new("RGBA", (Wp, Hp))
    d = ImageDraw.Draw(g)
    for y in range(Hp):
        t = y / (Hp - 1)
        d.line([(0, y), (Wp, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return g


def paint(base, fill, m):
    """Lays `fill` (a colour or an RGBA image) over `base` through mask `m`."""
    layer = Image.new("RGBA", (Wp, Hp), fill) if isinstance(fill, tuple) else fill.copy()
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), m))
    return Image.alpha_composite(base, layer)


def shade(base, m, light=60, dark=80, depth=6):
    """Makes the shape in `m` look raised: lighter along its top edge, darker along its bottom edge."""
    up = ImageChops.offset(m, 0, int(depth * K))
    down = ImageChops.offset(m, 0, -int(depth * K))
    hi = blur(ImageChops.subtract(m, up), depth * 0.6)
    lo = blur(ImageChops.subtract(m, down), depth * 0.6)
    base = paint(base, (255, 255, 255, light), ImageChops.multiply(hi, m))
    return paint(base, (0, 0, 0, dark), ImageChops.multiply(lo, m))


def body_mask():
    m = mask()
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(s(70, 64, 442, 178), radius=58 * K, fill=255)
    d.ellipse(s(148, 118, 364, 210), fill=255)            # belly between the grips
    d.ellipse(s(52, 92, 200, 250), fill=255)              # left grip
    d.ellipse(s(312, 92, 460, 250), fill=255)             # right grip
    return blur(m, 0.6)


def controller():
    img = Image.new("RGBA", (Wp, Hp), (0, 0, 0, 0))

    # Triggers behind the body.
    for key in ("LT", "RT"):
        x, y = POS[key]
        m = mask()
        ImageDraw.Draw(m).rounded_rectangle(s(x - 34, y - 16, x + 34, y + 30), radius=16 * K, fill=255)
        m = blur(m, 0.5)
        img = paint(img, vgradient((92, 94, 104), (40, 41, 48)), m)
        img = shade(img, m, light=70, dark=60, depth=4)

    body = body_mask()
    # A soft shadow under the whole controller.
    img = paint(img, (0, 0, 0, 150), blur(ImageChops.offset(body, 0, int(8 * K)), 9))

    # Bumpers on the top edge.
    for key in ("LB", "RB"):
        x, y = POS[key]
        m = mask()
        ImageDraw.Draw(m).rounded_rectangle(s(x - 46, y - 13, x + 46, y + 13), radius=13 * K, fill=255)
        m = blur(m, 0.5)
        img = paint(img, vgradient((104, 106, 116), (46, 47, 54)), m)
        img = shade(img, m, light=80, dark=70, depth=3)

    # The body: a vertical gradient, a broad sheen near the top, edges that turn away into shadow.
    img = paint(img, vgradient((72, 74, 84), (28, 29, 35)), body)
    sheen = mask()
    ImageDraw.Draw(sheen).ellipse(s(110, 58, 402, 140), fill=255)
    img = paint(img, (255, 255, 255, 34), ImageChops.multiply(blur(sheen, 18), body))
    inner = blur(ImageChops.subtract(body, body.filter(ImageFilter.MinFilter(int(9 * K) | 1))), 3)
    img = paint(img, (0, 0, 0, 120), ImageChops.multiply(inner, body))
    img = shade(img, body, light=70, dark=90, depth=5)
    rim = ImageChops.subtract(body, body.filter(ImageFilter.MinFilter(int(2 * K) | 1)))
    img = paint(img, (190, 192, 205, 110), rim)

    def socket(cx, cy, r, depth=0.55):
        """A round hollow in the body, with a faint light lip on its lower edge."""
        nonlocal img
        m = mask()
        ImageDraw.Draw(m).ellipse(s(cx - r, cy - r, cx + r, cy + r), fill=255)
        m = blur(m, 0.4)
        img = paint(img, (18, 19, 23, int(255 * depth)), m)
        lip = mask()
        ImageDraw.Draw(lip).ellipse(s(cx - r, cy - r + 2, cx + r, cy + r + 2), fill=255)
        img = paint(img, (255, 255, 255, 40), ImageChops.multiply(ImageChops.subtract(m, blur(lip, 1)), m))

    # D-pad: a recessed well, then a raised cross.
    dx, dy = POS["DPAD"]
    socket(dx, dy, 40, 0.45)
    m = mask()
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(s(dx - 12, dy - 36, dx + 12, dy + 36), radius=5 * K, fill=255)
    d.rounded_rectangle(s(dx - 36, dy - 12, dx + 36, dy + 12), radius=5 * K, fill=255)
    m = blur(m, 0.4)
    img = paint(img, (0, 0, 0, 120), blur(ImageChops.offset(m, 0, int(3 * K)), 2.5))
    img = paint(img, vgradient((70, 72, 80), (36, 37, 43)), m)
    img = shade(img, m, light=70, dark=80, depth=3)

    # Face buttons: a well with four round sockets.
    fx, fy = POS["FACE"]
    socket(fx, fy, 42, 0.35)
    for ox, oy in ((0, -26), (0, 26), (-26, 0), (26, 0)):
        socket(fx + ox, fy + oy, 14, 0.75)

    # Sticks: a deep socket and a domed cap with a ring of grip.
    for key in ("LS", "RS"):
        x, y = POS[key]
        socket(x, y, 27, 0.85)
        m = mask()
        ImageDraw.Draw(m).ellipse(s(x - 20, y - 20, x + 20, y + 20), fill=255)
        m = blur(m, 0.4)
        img = paint(img, (0, 0, 0, 130), blur(ImageChops.offset(m, 0, int(3 * K)), 3))
        img = paint(img, vgradient((84, 86, 96), (30, 31, 37)), m)
        dome = mask()
        ImageDraw.Draw(dome).ellipse(s(x - 13, y - 15, x + 9, y + 3), fill=255)
        img = paint(img, (255, 255, 255, 46), ImageChops.multiply(blur(dome, 5), m))
        ring = mask()
        ImageDraw.Draw(ring).ellipse(s(x - 20, y - 20, x + 20, y + 20), outline=255, width=int(2.5 * K))
        img = paint(img, (12, 12, 15, 150), ImageChops.multiply(ring, m))

    # Three small middle buttons: two pills and a round one below them.
    for key in ("BACK", "START"):
        x, y = POS[key]
        m = mask()
        ImageDraw.Draw(m).rounded_rectangle(s(x - 10, y - 6, x + 10, y + 6), radius=6 * K, fill=255)
        m = blur(m, 0.3)
        img = paint(img, (24, 25, 30, 255), m)
        img = shade(img, m, light=50, dark=40, depth=2)
    socket((POS["BACK"][0] + POS["START"][0]) / 2, 140, 9, 0.7)

    return img.resize((W * OUT, H * OUT), Image.Resampling.LANCZOS)


def glow(size=64):
    sz = size * SS
    img = Image.new("L", (sz, sz), 0)
    ImageDraw.Draw(img).ellipse((sz * 0.22, sz * 0.22, sz * 0.78, sz * 0.78), fill=255)
    img = img.filter(ImageFilter.GaussianBlur(sz * 0.09)).resize((size, size), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(img)
    return out


if __name__ == "__main__":
    controller().save("Media/controller.tga")
    glow().save("Media/tutorial_glow.tga")
    print("wrote Media/controller.tga (1024 x 512) and Media/tutorial_glow.tga")
