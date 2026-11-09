#!/usr/bin/env python3
"""Draws the crossbar theme art into Media/. Run from the addon folder. Needs Pillow and NumPy.
WoW reads uncompressed 32-bit TGA with power-of-two sides. Most images are white with an alpha
shape, so the addon can tint them; the slot fills carry their own colors."""
import os
import numpy as np
from PIL import Image

SIZE = 256
OUT = "Media"


def grid():
    """Distance of each pixel centre from the middle, in units of the half size (edge = 1)."""
    coords = (np.arange(SIZE) + 0.5) / SIZE * 2 - 1
    x, y = np.meshgrid(coords, coords)
    return x, y, np.sqrt(x * x + y * y)


def rounded_square_distance(x, y, radius):
    """Signed distance to a rounded square of half size 1 and the given corner radius (negative inside)."""
    qx = np.abs(x) - (1 - radius)
    qy = np.abs(y) - (1 - radius)
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - radius


def smooth(edge0, edge1, value):
    t = np.clip((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


AA = 1.5 / SIZE * 2  # anti-aliasing width in grid units


# Art from tried and dropped designs, not written so it does not ship.
SKIP = {"bezel_square", "frame_slate", "gloss", "orb_bezel", "orb_inner", "orb_sheen", "rsquare_gloss",
        "shadow_square", "slate_mask"}


def save(name, rgb, alpha):
    if name in SKIP:
        return
    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    for channel in range(3):
        rgba[..., channel] = np.clip(rgb[channel] * 255, 0, 255) if np.ndim(rgb[channel]) else int(rgb[channel] * 255)
    rgba[..., 3] = np.clip(alpha * 255, 0, 255)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name + ".tga"), rle=False)


WHITE = (1, 1, 1)


def main():
    os.makedirs(OUT, exist_ok=True)
    x, y, r = grid()

    # Circle shapes: masks, a thin crisp ring, a soft glow ring, an inner shadow, a gloss.
    disc = 1 - smooth(0.985 - AA, 0.985, r)
    save("circle_mask", WHITE, disc)
    ring = smooth(0.86 - AA, 0.86, r) * (1 - smooth(0.985 - AA, 0.985, r))
    save("ring", WHITE, ring)
    glow = np.exp(-((r - 0.82) / 0.13) ** 2) * (r < 1.0)
    save("ring_glow", WHITE, glow)
    inner = smooth(0.72, 0.985, r) ** 2 * disc * 0.8
    save("inner_shadow", (0, 0, 0), inner)
    gloss_shape = np.exp(-((x / 0.75) ** 2 + ((y + 0.42) / 0.38) ** 2) * 2.2)
    save("gloss", WHITE, gloss_shape * disc * 0.55)

    # Rounded squares: mask, ring, inner shadow, gloss.
    d = rounded_square_distance(x / 0.985, y / 0.985, 0.32)
    square = 1 - smooth(-AA, 0, d)
    save("rsquare_mask", WHITE, square)
    square_ring = smooth(-0.13 - AA, -0.13, d) * square
    save("rsquare_ring", WHITE, square_ring)
    save("rsquare_inner_shadow", (0, 0, 0), smooth(-0.22, 0, d) ** 2 * square * 0.8)
    save("rsquare_gloss", WHITE, gloss_shape * square * 0.5)
    save("rsquare_glow", WHITE, np.exp(-((d + 0.08) / 0.12) ** 2) * (d < 0.12))

    save("ring_thin", WHITE, smooth(0.93 - AA, 0.93, r) * (1 - smooth(0.985 - AA, 0.985, r)))
    double = (smooth(0.95 - AA, 0.95, r) * (1 - smooth(0.985 - AA, 0.985, r))
              + smooth(0.86 - AA, 0.86, r) * (1 - smooth(0.885 - AA, 0.885, r)))
    save("ring_double", WHITE, double)
    save("rsquare_ring_thin", WHITE, smooth(-0.065 - AA, -0.065, d) * square)
    save("rsquare_ring_double", WHITE, (smooth(-0.05 - AA, -0.05, d)
                                        + smooth(-0.15 - AA, -0.15, d) * (1 - smooth(-0.12 - AA, -0.12, d))) * square)

    # Plain squares (Classic, Minimal, Forever's D-pad slots): borders with barely rounded corners.
    q = rounded_square_distance(x / 0.985, y / 0.985, 0.06)
    plain = 1 - smooth(-AA, 0, q)
    save("square_ring_thin", WHITE, smooth(-0.065 - AA, -0.065, q) * plain)
    save("square_ring", WHITE, smooth(-0.13 - AA, -0.13, q) * plain)
    save("square_ring_double", WHITE, (smooth(-0.05 - AA, -0.05, q)
                                       + smooth(-0.15 - AA, -0.15, q) * (1 - smooth(-0.12 - AA, -0.12, q))) * plain)
    save("square_glow", WHITE, np.exp(-((q + 0.08) / 0.12) ** 2) * (q < 0.12))

    # Bezels: thick metal rings, lit from the top. In color, not tinted. The icon sits inside 0.80.
    light = np.clip((1 - y) / 2, 0, 1)  # 1 at the top, 0 at the bottom
    metal = [0.13 + 0.42 * light ** 1.5, 0.135 + 0.43 * light ** 1.5, 0.15 + 0.47 * light ** 1.5]
    band = smooth(0.80 - AA, 0.80, r) * (1 - smooth(0.985 - AA, 0.985, r))
    edge_dark = 1 - 0.65 * (np.exp(-((r - 0.81) / 0.018) ** 2) + np.exp(-((r - 0.975) / 0.015) ** 2))
    save("bezel_round", [c * edge_dark for c in metal], band)
    qb = rounded_square_distance(x / 0.985, y / 0.985, 0.14)
    sq_band = (1 - smooth(-AA, 0, qb)) * smooth(-0.17 - AA, -0.17, qb)
    sq_dark = 1 - 0.65 * (np.exp(-((qb + 0.165) / 0.018) ** 2) + np.exp(-((qb + 0.01) / 0.015) ** 2))
    save("bezel_square", [c * sq_dark for c in metal], sq_band)

    # Orb bezel: a rounded metal tube around the icon, lit from the top, in grey so it can be tinted.
    # The icon sits inside 0.78; a dark gap separates it from the bezel, and a thin dark line edges it.
    t = np.clip((r - 0.78) / (0.985 - 0.78), 0, 1)
    tube = 1 - (2 * t - 1) ** 2
    shade = 0.16 + 0.34 * light * tube + 0.10 * tube
    shade = shade + 0.45 * np.exp(-((t - 0.32) / 0.11) ** 2) * light ** 2.5      # specular on top
    shade = shade + 0.12 * np.exp(-((t - 0.65) / 0.12) ** 2) * (1 - light) ** 3  # bounce light below
    shade = shade * (1 - 0.8 * np.exp(-((r - 0.785) / 0.012) ** 2))              # gap at the icon
    shade = shade * (1 - 0.7 * np.exp(-((r - 0.978) / 0.010) ** 2))              # outer edge
    band = smooth(0.775 - AA, 0.775, r) * (1 - smooth(0.985 - AA, 0.985, r))
    save("orb_bezel", [np.clip(shade, 0, 1)] * 3, band)
    # A shadow the bezel casts onto the icon, and a faint sheen across the icon's top.
    icon_disc = 1 - smooth(0.78 - AA, 0.78, r)
    save("orb_inner", (0, 0, 0), smooth(0.5, 0.78, r) ** 2.2 * icon_disc * 0.9)
    sheen = np.exp(-((x / 0.62) ** 2 + ((y + 0.38) / 0.30) ** 2) * 2.5) * (y < 0.05)
    save("orb_sheen", WHITE, sheen * icon_disc * 0.22)

    # Slate: a crisp black frame with a faint light line just inside it. The icon sits inside 0.88.
    qs = rounded_square_distance(x / 0.985, y / 0.985, 0.08)
    outer = (1 - smooth(-AA, 0, qs)) * smooth(-0.11 - AA, -0.11, qs)
    hair = smooth(-0.13 - AA, -0.13, qs) * (1 - smooth(-0.11 - AA, -0.11, qs))
    alpha = np.clip(outer + hair * 0.35, 0, 1)
    shade = np.where(hair > outer, 1.0, 0.02)
    save("frame_slate", [shade, shade, shade], alpha)
    save("slate_mask", WHITE, 1 - smooth(-AA, 0, rounded_square_distance(x / 0.985, y / 0.985, 0.05)))

    # Soft drop shadows, drawn larger than the slot and a little lower.
    save("shadow_round", (0, 0, 0), np.exp(-((np.maximum(r - 0.55, 0)) / 0.22) ** 2) * 0.85)
    qq = rounded_square_distance(x / 0.75, y / 0.75, 0.2)
    save("shadow_square", (0, 0, 0), np.exp(-((np.maximum(qq, 0)) / 0.3) ** 2) * 0.85)

    angle = np.arctan2(y, x)

    # Hex: pointy-top hexagons with slightly rounded corners. Full height, 0.87 of the width.
    def hex_distance(px, py, size):
        qx, qy = np.abs(px), np.abs(py)
        return np.maximum(qx, qx * 0.5 + qy * 0.866) - size
    hd = hex_distance(x, y, 0.86 * 0.97 - 0.04) - 0.04
    hexm = 1 - smooth(-AA, 0, hd)
    save("hex_mask", WHITE, hexm)
    save("hex_ring", WHITE, smooth(-0.07 - AA, -0.07, hd) * hexm)
    save("hex_inner", (0, 0, 0), smooth(-0.3, 0, hd) ** 2 * hexm * 0.85)
    save("hex_glow", WHITE, np.exp(-((hd + 0.03) / 0.08) ** 2) * (hd < 0.15))
    # The cluster: a large flat-top hexagon, dark inside with a fine edge and a second inner edge.
    cd = hex_distance(y, x, 0.86 * 0.97)
    inside = 1 - smooth(-AA, 0, cd)
    edge = smooth(-0.02 - AA, -0.02, cd) * inside
    inner_edge = smooth(-0.075 - AA, -0.075, cd) * (1 - smooth(-0.065 - AA, -0.065, cd))
    save("hex_cluster_fill", (0.02, 0.025, 0.04), inside * (0.55 + 0.35 * smooth(-0.8, 0, cd)))
    save("hex_cluster_edge", WHITE, np.clip(edge + inner_edge * 0.45, 0, 1))

    # Sigil: an engraved double ring with four studs for each slot, and a ring of runes per group.
    studs = np.zeros_like(r)
    for a0 in (0, np.pi / 2, np.pi, -np.pi / 2):
        sx, sy = 0.92 * np.cos(a0), 0.92 * np.sin(a0)
        dd = np.abs(x - sx) + np.abs(y - sy)
        studs = np.maximum(studs, 1 - smooth(0.075 - AA, 0.075, dd))
    rings = (smooth(0.90 - AA, 0.90, r) * (1 - smooth(0.94 - AA, 0.94, r))
             + 0.8 * smooth(0.80 - AA, 0.80, r) * (1 - smooth(0.825 - AA, 0.825, r)))
    save("sigil_ring", WHITE, np.clip(rings + studs, 0, 1))
    ticks_small = (np.abs(((angle / (2 * np.pi) * 64) % 1) - 0.5) > 0.42) * smooth(0.905, 0.91, r) * (1 - smooth(0.935, 0.94, r))
    ticks_big = (np.abs(((angle / (2 * np.pi) * 8) % 1) - 0.5) > 0.47) * smooth(0.87, 0.875, r) * (1 - smooth(0.955, 0.96, r))
    outer = smooth(0.955 - AA, 0.955, r) * (1 - smooth(0.968 - AA, 0.968, r))
    inner = smooth(0.89 - AA, 0.89, r) * (1 - smooth(0.9 - AA, 0.9, r))
    dots = np.zeros_like(r)
    for k in range(8):
        a0 = (k + 0.5) * np.pi / 4
        dd = np.sqrt((x - 0.925 * np.cos(a0)) ** 2 + (y - 0.925 * np.sin(a0)) ** 2)
        dots = np.maximum(dots, 1 - smooth(0.018 - AA, 0.018, dd))
    save("sigil_cluster", WHITE, np.clip(outer + inner + ticks_small * 0.6 + ticks_big + dots, 0, 1))

    # Holo: corner brackets on a faint frame for each slot; a dashed ring with arcs for each group.
    hq = rounded_square_distance(x / 0.985, y / 0.985, 0.18)
    frame_line = smooth(-0.05 - AA, -0.05, hq) * (1 - smooth(-AA, 0, hq))
    corners = ((np.abs(x) > 0.45) & (np.abs(y) > 0.45)).astype(float)
    thick = smooth(-0.1 - AA, -0.1, hq) * (1 - smooth(-AA, 0, hq))
    save("holo_brackets", WHITE, np.clip(thick * corners + frame_line * 0.3, 0, 1))
    dashes = (((angle / (2 * np.pi) * 48) % 1) < 0.55).astype(float)
    ring1 = smooth(0.945 - AA, 0.945, r) * (1 - smooth(0.958 - AA, 0.958, r)) * dashes
    arcs = smooth(0.965 - AA, 0.965, r) * (1 - smooth(0.985 - AA, 0.985, r)) * (np.abs(((angle / (np.pi / 2)) % 1) - 0.5) < 0.12)
    ring2 = 0.35 * smooth(0.86 - AA, 0.86, r) * (1 - smooth(0.868 - AA, 0.868, r))
    save("holo_cluster", WHITE, np.clip(ring1 * 0.7 + arcs + ring2, 0, 1))
    lines = ((np.arange(SIZE) // 16) % 2 == 0).astype(float)[:, None] * np.ones((1, SIZE))
    save("holo_scan", (0.25, 0.75, 0.95), 0.10 + 0.12 * lines)

    # Ink: a brushed ring around each slot and an ink wash behind each group, with fixed random noise.
    rng = np.random.default_rng(7)
    def noise(cells, seed_scale=1.0):
        small = rng.random((cells, cells))
        return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.BICUBIC)) / 255.0
    def angular_noise(waves):
        total = np.zeros_like(angle)
        for k in range(1, waves + 1):
            total += np.sin(angle * k + rng.random() * 6.28) / k
        return total / 2
    wobble = angular_noise(9)
    centre = 0.9 + 0.025 * wobble
    width = 0.07 + 0.035 * angular_noise(5)
    brush = np.exp(-((r - centre) / np.maximum(width, 0.02)) ** 4)
    streaks = 0.65 + 0.35 * noise(48)
    save("ink_ring", (0.02, 0.02, 0.025), np.clip(brush * streaks * 1.15, 0, 1) * (r < 1))
    edge_r = 0.82 + 0.06 * angular_noise(11)
    wash = (1 - smooth(edge_r - 0.12, edge_r + 0.04, r)) * (0.7 + 0.3 * noise(10))
    splats = np.zeros_like(r)
    for _ in range(14):
        a0 = rng.random() * 6.28; d0 = 0.86 + rng.random() * 0.1; s0 = 0.008 + rng.random() * 0.02
        dd = np.sqrt((x - d0 * np.cos(a0)) ** 2 + (y - d0 * np.sin(a0)) ** 2)
        splats = np.maximum(splats, 1 - smooth(s0 - AA, s0, dd))
    save("ink_wash", (0.02, 0.02, 0.03), np.clip(wash * 0.9 + splats * 0.8, 0, 1))

    # Cluster backgrounds: a soft vignette and a thin ring.
    save("vignette", (0.02, 0.02, 0.03), (1 - smooth(0.15, 1.0, r)) ** 1.3 * 0.95)
    save("cluster_ring", WHITE, smooth(0.94 - AA, 0.94, r) * (1 - smooth(0.965 - AA, 0.965, r)))
    save("cluster_glow", WHITE, np.exp(-((r - 0.62) / 0.3) ** 2) * (1 - smooth(0.9, 1.0, r)))
    save("cluster_double", WHITE, smooth(0.95 - AA, 0.95, r) * (1 - smooth(0.97 - AA, 0.97, r))
         + 0.6 * smooth(0.90 - AA, 0.90, r) * (1 - smooth(0.915 - AA, 0.915, r)))
    save("cluster_ring_glow", WHITE, np.exp(-((r - 0.93) / 0.045) ** 2))
    save("cluster_disc", (0.03, 0.035, 0.05), (1 - smooth(0.955 - AA, 0.955, r)) * (0.75 + 0.25 * r))

    # Slot fills, in color: a deep radial and a frosted glass with a lit top.
    t = np.clip(r, 0, 1)
    deep = [0.17 * (1 - t) + 0.03 * t, 0.19 * (1 - t) + 0.035 * t, 0.25 * (1 - t) + 0.05 * t]
    save("slot_deep", deep, np.full_like(r, 0.95))
    v = (y + 1) / 2  # 0 at the top, 1 at the bottom
    frost = [0.42 * (1 - v) + 0.10 * v, 0.47 * (1 - v) + 0.12 * v, 0.58 * (1 - v) + 0.17 * v]
    save("slot_frost", frost, 0.55 * (1 - v) + 0.85 * v)


if __name__ == "__main__":
    main()
