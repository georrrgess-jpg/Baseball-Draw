#!/usr/bin/env python3
"""Generates the particle / decal textures used by src/vfx (assets/textures/vfx/).

Usage (from the repo root):
    python3 tools/art/vfx/make_vfx_textures.py

All textures are white RGB with the shape in alpha (shaders tint them), except where
noted: `flame` and `scorch` carry an extra mask in red, `noise` packs three tileable
noise layers in RGB. Requires numpy + Pillow. After regenerating, run
`godot --headless --path . --import` so Godot picks the files up.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "textures" / "vfx"
FONT = ROOT / "assets" / "fonts" / "Bangers-Regular.ttf"
RNG = np.random.default_rng(7)


def grid(n: int, m: int | None = None):
    m = m or n
    y, x = np.mgrid[0:m, 0:n].astype(np.float32)
    return (x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / m * 2.0 - 1.0


def save(name: str, alpha: np.ndarray, rgb: np.ndarray | None = None) -> None:
    a = np.clip(alpha, 0.0, 1.0)
    h, w = a.shape
    if rgb is None:
        rgb = np.ones((h, w, 3), np.float32)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"{name}.png", optimize=True)
    print("  wrote", name)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def tile_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """Periodic value noise (tiles seamlessly), smooth-interpolated."""
    rng = np.random.default_rng(seed)
    lat = rng.random((cells, cells)).astype(np.float32)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    fx = x / size * cells
    fy = y / size * cells
    ix = np.floor(fx).astype(int)
    iy = np.floor(fy).astype(int)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    x0, x1 = ix % cells, (ix + 1) % cells
    y0, y1 = iy % cells, (iy + 1) % cells
    a = lat[y0, x0] * (1 - tx) + lat[y0, x1] * tx
    b = lat[y1, x0] * (1 - tx) + lat[y1, x1] * tx
    return a * (1 - ty) + b * ty


def fbm(size: int, base: int, octaves: int, seed: int) -> np.ndarray:
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += tile_noise(size, base * (2 ** o), seed + o * 31) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def voronoi_edges(size: int, cells: int, seed: int) -> np.ndarray:
    """Tileable cellular noise: distance to the nearest cell border (crystal look)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, 2)).astype(np.float32)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    fx = x / size * cells
    fy = y / size * cells
    ix = np.floor(fx).astype(int)
    iy = np.floor(fy).astype(int)
    d1 = np.full((size, size), 9.0, np.float32)
    d2 = np.full((size, size), 9.0, np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = ix + ox
            cy = iy + oy
            p = pts[cy % cells, cx % cells]
            dx = cx + p[..., 0] - fx
            dy = cy + p[..., 1] - fy
            d = np.sqrt(dx * dx + dy * dy)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
    return d2 - d1


def supersample_draw(size: int, scale: int, draw_fn) -> np.ndarray:
    """Draws with PIL at a larger size and downsamples for anti-aliasing. Returns alpha 0..1."""
    big = Image.new("L", (size * scale, size * scale), 0)
    draw_fn(ImageDraw.Draw(big), size * scale)
    small = big.resize((size, size), Image.LANCZOS)
    return np.asarray(small, np.float32) / 255.0


# ---------------------------------------------------------------- particles

def make_glow():
    x, y = grid(128)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-r * r * 5.0) * 0.85 + np.exp(-r * r * 22.0) * 0.4
    a *= 1.0 - smoothstep(0.8, 1.0, r)
    save("glow", a)


def make_spark():
    w, h = 32, 128
    x, y = grid(w, h)
    across = np.exp(-(x * x) * 14.0)
    core = np.exp(-(x * x) * 90.0)
    # Bright head at the top (y=-1), tapering tail toward the bottom.
    along = smoothstep(1.0, -0.6, y) * smoothstep(-1.0, -0.75, y)
    a = (across * 0.55 + core) * along
    save("spark", a)


def make_star():
    x, y = grid(128)
    r = np.sqrt(x * x + y * y)
    rays = np.exp(-np.abs(x) * 28.0) * np.exp(-np.abs(y) * 2.6) + np.exp(-np.abs(y) * 28.0) * np.exp(-np.abs(x) * 2.6)
    diag_x = (x + y) * 0.7071
    diag_y = (x - y) * 0.7071
    rays2 = (np.exp(-np.abs(diag_x) * 30.0) * np.exp(-np.abs(diag_y) * 5.5) + np.exp(-np.abs(diag_y) * 30.0) * np.exp(-np.abs(diag_x) * 5.5)) * 0.45
    core = np.exp(-r * r * 30.0)
    a = np.clip(rays + rays2 + core * 1.2, 0, 1) * (1.0 - smoothstep(0.85, 1.0, r))
    save("star", a)


def make_smoke():
    size = 256
    cell = 128
    alpha = np.zeros((size, size), np.float32)
    shade = np.ones((size, size, 3), np.float32)
    n_hi = fbm(cell, 4, 4, 11)
    for i in range(4):
        cx, cy = (i % 2) * cell, (i // 2) * cell
        x, y = grid(cell)
        rng = np.random.default_rng(100 + i)
        a = np.zeros((cell, cell), np.float32)
        light = np.zeros((cell, cell), np.float32)
        for _ in range(7):
            bx, by = rng.uniform(-0.25, 0.25, 2)
            br = rng.uniform(0.36, 0.56)
            d2 = ((x - bx) ** 2 + (y - by) ** 2) / (br * br)
            blob = np.exp(-d2 * 1.6)
            a = np.maximum(a, blob)
            light += blob * np.clip(0.6 - (y - by) * 0.8 - (x - bx) * 0.3, 0, 1.2)
        n = np.roll(np.roll(n_hi, i * 37, 0), i * 53, 1)
        a = a * (0.55 + 0.75 * n)
        a = smoothstep(0.12, 0.85, a)
        r = np.sqrt(x * x + y * y)
        a *= 1.0 - smoothstep(0.75, 0.98, r)
        lit = np.clip(0.62 + 0.3 * light / (light.max() + 1e-6) + (n - 0.5) * 0.3, 0, 1)
        alpha[cy:cy + cell, cx:cx + cell] = a
        shade[cy:cy + cell, cx:cx + cell] = lit[..., None]
    save("smoke", alpha, shade)


def make_flame():
    w, h = 128, 192
    x, y = grid(w, h)
    # u: 0 at the bottom .. 1 at the top. Round base, licking tip.
    u = (1.0 - y) * 0.5
    width = 0.82 * np.sqrt(np.clip(u / 0.16, 0, 1)) * np.clip(1.0 - u, 0, 1) ** 1.15
    d = np.abs(x) / np.maximum(width, 1e-3)
    body = (1.0 - smoothstep(0.5, 1.0, d)) * smoothstep(0.0, 0.05, u)
    core = (1.0 - smoothstep(0.0, 0.7, d)) * smoothstep(0.7, 0.12, u)
    rgb = np.dstack([np.clip(core, 0, 1), np.ones_like(core), np.ones_like(core)])
    save("flame", body, rgb)


def make_noise():
    size = 256
    r = fbm(size, 4, 5, 3)
    g = fbm(size, 8, 4, 17)
    v = voronoi_edges(size, 8, 5)
    b = np.clip(v / (v.max() + 1e-6), 0, 1)
    for ch in (r, g):
        ch -= ch.min()
        ch /= ch.max() + 1e-6
    rgb = np.dstack([r, g, b])
    save("noise", np.ones_like(r), rgb)


def make_ring():
    x, y = grid(256)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-((r - 0.86) ** 2) / (2 * 0.035 ** 2)) + np.exp(-((r - 0.86) ** 2) / (2 * 0.11 ** 2)) * 0.35
    a *= 1.0 - smoothstep(0.97, 1.0, r)
    save("ring", a)


# ---------------------------------------------------------------- decals

def make_scorch():
    size = 256
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    n = fbm(size, 4, 5, 41)
    n2 = fbm(size, 8, 3, 43)
    blot = smoothstep(0.95, 0.35, r + (n - 0.5) * 0.65)
    a = blot * (0.7 + 0.3 * n2)
    # Glowing cracks (red channel): thin cellular borders inside the blot.
    v = voronoi_edges(size, 6, 47)
    cracks = (1.0 - smoothstep(0.0, 0.07, v)) * smoothstep(0.75, 0.2, r + (n - 0.5) * 0.4)
    rgb = np.dstack([np.clip(cracks, 0, 1), np.ones_like(a), np.ones_like(a)])
    save("scorch", a, rgb)


def _crack_lines(draw: ImageDraw.ImageDraw, S: int, rng, n_main: int, length: float, width: float):
    c = S / 2

    def branch(x, y, ang, ln, w, depth):
        steps = int(ln / (S * 0.02)) + 2
        for _ in range(steps):
            ang += rng.normal(0, 0.28)
            nx = x + math.cos(ang) * S * 0.02
            ny = y + math.sin(ang) * S * 0.02
            draw.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
            x, y = nx, ny
            w *= 0.93
            if depth < 2 and rng.random() < 0.12:
                branch(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0), ln * 0.45, w * 0.8, depth + 1)
            if math.hypot(x - c, y - c) > S * 0.49:
                return

    for i in range(n_main):
        ang = i / n_main * math.tau + rng.normal(0, 0.2)
        r0 = S * rng.uniform(0.02, 0.08)
        branch(c + math.cos(ang) * r0, c + math.sin(ang) * r0, ang, S * length * rng.uniform(0.6, 1.0), width, 0)


def make_cracks():
    rng = np.random.default_rng(23)
    size = 512
    a = supersample_draw(size, 2, lambda d, S: _crack_lines(d, S, rng, 11, 0.5, S * 0.012))
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    # Crater bowl in the red channel (darkest near the centre).
    bowl = smoothstep(0.42, 0.0, r)
    rgb = np.dstack([bowl, np.ones_like(a), np.ones_like(a)])
    save("cracks", np.clip(a * 1.2, 0, 1), rgb)


def make_frost():
    rng = np.random.default_rng(5)
    size = 512

    def draw(d: ImageDraw.ImageDraw, S: int):
        c = S / 2

        def dendrite(x, y, ang, ln, w, depth):
            seg = S * 0.012
            steps = int(ln / seg)
            for s in range(steps):
                nx = x + math.cos(ang) * seg
                ny = y + math.sin(ang) * seg
                d.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
                x, y = nx, ny
                ang += rng.normal(0, 0.05)
                w = max(1.0, w * 0.97)
                if depth < 2 and s % 3 == 2:
                    for sgn in (-1, 1):
                        if rng.random() < 0.8:
                            dendrite(x, y, ang + sgn * math.radians(60), ln * rng.uniform(0.15, 0.3), w * 0.7, depth + 1)
                if math.hypot(x - c, y - c) > S * 0.49:
                    return

        for i in range(14):
            ang = i / 14 * math.tau + rng.normal(0, 0.1)
            dendrite(c, c, ang, S * rng.uniform(0.35, 0.5), S * 0.006, 0)
        for _ in range(40):
            ang = rng.uniform(0, math.tau)
            rr = S * rng.uniform(0.1, 0.45)
            dendrite(c + math.cos(ang) * rr, c + math.sin(ang) * rr, rng.uniform(0, math.tau), S * rng.uniform(0.04, 0.12), S * 0.004, 1)

    lines = supersample_draw(size, 2, draw)
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    v = voronoi_edges(size, 10, 9)
    cells = 1.0 - smoothstep(0.0, 0.05, v)
    n = fbm(size, 4, 4, 77)
    a = np.clip(lines * 1.1 + cells * 0.35 + n * 0.25, 0, 1)
    # Red channel: spread order (0 at centre .. 1 at the rim, with a noisy edge) for the growth animation.
    order = np.clip(r + (n - 0.5) * 0.35, 0, 1)
    rgb = np.dstack([order, np.ones_like(a), np.ones_like(a)])
    save("frost", a, rgb)


def make_runes():
    rng = np.random.default_rng(13)
    size = 512

    def draw(d: ImageDraw.ImageDraw, S: int):
        c = S / 2
        lw = int(S * 0.008)

        def circle(rad, w):
            d.ellipse([c - rad, c - rad, c + rad, c + rad], outline=255, width=w)

        circle(S * 0.49, lw * 2)
        circle(S * 0.455, lw)
        circle(S * 0.33, lw)
        circle(S * 0.305, int(lw * 0.7))
        # Rune band between 0.335 and 0.45.
        n = 24
        for i in range(n):
            a0 = i / n * math.tau
            cxr, cyr = c + math.cos(a0) * S * 0.392, c + math.sin(a0) * S * 0.392
            s = S * 0.035
            tang = a0 + math.pi / 2
            ux, uy = math.cos(tang), math.sin(tang)
            vx, vy = math.cos(a0), math.sin(a0)
            pts = [(-1, -1), (1, -1), (1, 1), (-1, 1), (0, -1), (0, 1), (-1, 0), (1, 0), (0, 0)]
            for _ in range(3):
                p1 = pts[rng.integers(len(pts))]
                p2 = pts[rng.integers(len(pts))]
                if p1 == p2:
                    continue
                q1 = (cxr + (p1[0] * ux + p1[1] * vx) * s, cyr + (p1[0] * uy + p1[1] * vy) * s)
                q2 = (cxr + (p2[0] * ux + p2[1] * vx) * s, cyr + (p2[0] * uy + p2[1] * vy) * s)
                d.line([q1, q2], fill=255, width=lw)
        # Inner hexagram + spokes.
        for k in range(2):
            pts = []
            for i in range(3):
                a0 = i / 3 * math.tau + k * math.pi / 3 - math.pi / 2
                pts.append((c + math.cos(a0) * S * 0.3, c + math.sin(a0) * S * 0.3))
            d.polygon(pts, outline=255, width=lw)
        circle(S * 0.15, lw)
        for i in range(12):
            a0 = i / 12 * math.tau
            d.line([(c + math.cos(a0) * S * 0.455, c + math.sin(a0) * S * 0.455), (c + math.cos(a0) * S * 0.49, c + math.sin(a0) * S * 0.49)], fill=255, width=lw)

    a = supersample_draw(size, 2, draw)
    glow = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
    save("runes", np.clip(a + glow * 0.6, 0, 1))


def make_clock():
    size = 512

    def draw(d: ImageDraw.ImageDraw, S: int):
        c = S / 2
        lw = int(S * 0.008)
        d.ellipse([c - S * 0.49, c - S * 0.49, c + S * 0.49, c + S * 0.49], outline=255, width=lw * 3)
        d.ellipse([c - S * 0.43, c - S * 0.43, c + S * 0.43, c + S * 0.43], outline=255, width=lw)
        for i in range(60):
            a0 = i / 60 * math.tau
            major = i % 5 == 0
            r0 = S * (0.36 if major else 0.40)
            w = lw * (3 if major else 1)
            d.line([(c + math.cos(a0) * r0, c + math.sin(a0) * r0), (c + math.cos(a0) * S * 0.43, c + math.sin(a0) * S * 0.43)], fill=255, width=w)
        d.ellipse([c - S * 0.03, c - S * 0.03, c + S * 0.03, c + S * 0.03], fill=255)

    a = supersample_draw(size, 2, draw)
    glow = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), np.float32) / 255.0
    save("clock", np.clip(a + glow * 0.5, 0, 1))


def make_web():
    size = 256

    def draw(d: ImageDraw.ImageDraw, S: int):
        c = S / 2
        lw = int(S * 0.012)
        n = 10
        angs = [i / n * math.tau for i in range(n)]
        for a0 in angs:
            d.line([(c, c), (c + math.cos(a0) * S * 0.48, c + math.sin(a0) * S * 0.48)], fill=255, width=lw)
        for k in range(1, 6):
            rad = S * 0.48 * k / 5.4
            pts = []
            for i in range(n + 1):
                a0 = angs[i % n]
                a1 = angs[(i + 1) % n] if i < n else angs[0]
                pts.append((c + math.cos(a0) * rad, c + math.sin(a0) * rad))
                # Sagging midpoint between spokes.
                am = a0 + math.tau / n / 2
                pts.append((c + math.cos(am) * rad * 0.9, c + math.sin(am) * rad * 0.9))
            d.line(pts[:-1], fill=255, width=lw, joint="curve")

    a = supersample_draw(size, 3, draw)
    save("web", a)


def make_chain():
    w, h = 64, 256
    big = Image.new("L", (w * 4, h * 4), 0)
    d = ImageDraw.Draw(big)
    W, H = w * 4, h * 4
    links = 4
    lh = H / links
    for i in range(links):
        y0 = i * lh
        if i % 2 == 0:
            d.ellipse([W * 0.18, y0 - lh * 0.12, W * 0.82, y0 + lh * 1.12], outline=255, width=int(W * 0.13))
        else:
            d.rounded_rectangle([W * 0.42, y0 - lh * 0.15, W * 0.58, y0 + lh * 1.15], radius=W * 0.08, fill=255)
    a = np.asarray(big.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    x, _ = grid(w, h)
    shade = np.clip(0.75 + 0.25 * np.cos(x * 2.2), 0, 1)
    save("chain", a, np.dstack([shade, shade, shade]))


def make_icons():
    cell = 64
    S = cell * 4
    big = Image.new("L", (S * 4, S * 4), 0)
    d = ImageDraw.Draw(big)

    def box(i):
        return (i % 4) * S, (i // 4) * S

    # 0: five-point star
    x0, y0 = box(0)
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = S * (0.44 if k % 2 == 0 else 0.19)
        pts.append((x0 + S / 2 + math.cos(a) * rr, y0 + S / 2 + math.sin(a) * rr))
    d.polygon(pts, fill=255)
    # 1: question mark
    x0, y0 = box(1)
    font = ImageFont.truetype(str(FONT), int(S * 0.95))
    d.text((x0 + S / 2, y0 + S / 2), "?", font=font, fill=255, anchor="mm")
    # 2: reticle
    x0, y0 = box(2)
    cx, cy = x0 + S / 2, y0 + S / 2
    lw = int(S * 0.06)
    d.ellipse([cx - S * 0.36, cy - S * 0.36, cx + S * 0.36, cy + S * 0.36], outline=255, width=lw)
    d.ellipse([cx - S * 0.06, cy - S * 0.06, cx + S * 0.06, cy + S * 0.06], fill=255)
    for a in range(4):
        ang = a * math.pi / 2
        d.line([(cx + math.cos(ang) * S * 0.2, cy + math.sin(ang) * S * 0.2), (cx + math.cos(ang) * S * 0.48, cy + math.sin(ang) * S * 0.48)], fill=255, width=lw)
    # 3: snowflake
    x0, y0 = box(3)
    cx, cy = x0 + S / 2, y0 + S / 2
    for a in range(6):
        ang = a * math.pi / 3
        ex, ey = cx + math.cos(ang) * S * 0.44, cy + math.sin(ang) * S * 0.44
        d.line([(cx, cy), (ex, ey)], fill=255, width=int(S * 0.05))
        for t in (0.55, 0.78):
            bx, by = cx + math.cos(ang) * S * 0.44 * t, cy + math.sin(ang) * S * 0.44 * t
            for s in (-1, 1):
                a2 = ang + s * math.radians(45)
                d.line([(bx, by), (bx + math.cos(a2) * S * 0.12, by + math.sin(a2) * S * 0.12)], fill=255, width=int(S * 0.04))
    # 4: chain link
    x0, y0 = box(4)
    d.rounded_rectangle([x0 + S * 0.28, y0 + S * 0.08, x0 + S * 0.72, y0 + S * 0.92], radius=S * 0.2, outline=255, width=int(S * 0.1))
    # 5: padlock
    x0, y0 = box(5)
    d.arc([x0 + S * 0.28, y0 + S * 0.08, x0 + S * 0.72, y0 + S * 0.58], 180, 360, fill=255, width=int(S * 0.09))
    d.line([(x0 + S * 0.32, y0 + S * 0.33), (x0 + S * 0.32, y0 + S * 0.45)], fill=255, width=int(S * 0.09))
    d.line([(x0 + S * 0.68, y0 + S * 0.33), (x0 + S * 0.68, y0 + S * 0.45)], fill=255, width=int(S * 0.09))
    d.rounded_rectangle([x0 + S * 0.18, y0 + S * 0.42, x0 + S * 0.82, y0 + S * 0.92], radius=S * 0.08, fill=255)
    d.ellipse([x0 + S * 0.45, y0 + S * 0.57, x0 + S * 0.55, y0 + S * 0.67], fill=0)
    d.rectangle([x0 + S * 0.48, y0 + S * 0.62, x0 + S * 0.52, y0 + S * 0.78], fill=0)
    # 6: chevron up
    x0, y0 = box(6)
    for k in range(2):
        oy = k * S * 0.28
        d.line([(x0 + S * 0.15, y0 + S * 0.5 + oy), (x0 + S * 0.5, y0 + S * 0.18 + oy), (x0 + S * 0.85, y0 + S * 0.5 + oy)], fill=255, width=int(S * 0.11), joint="curve")
    # 7: diamond gem
    x0, y0 = box(7)
    cx = x0 + S / 2
    top = [(cx - S * 0.32, y0 + S * 0.3), (cx - S * 0.18, y0 + S * 0.12), (cx + S * 0.18, y0 + S * 0.12), (cx + S * 0.32, y0 + S * 0.3)]
    d.polygon(top + [(cx, y0 + S * 0.9)], outline=255, width=int(S * 0.05))
    d.line([(cx - S * 0.32, y0 + S * 0.3), (cx + S * 0.32, y0 + S * 0.3)], fill=255, width=int(S * 0.04))
    d.line([(cx - S * 0.12, y0 + S * 0.3), (cx, y0 + S * 0.9), (cx + S * 0.12, y0 + S * 0.3)], fill=255, width=int(S * 0.03))
    # 8: lightning glyph
    x0, y0 = box(8)
    d.polygon([(x0 + S * 0.58, y0 + S * 0.04), (x0 + S * 0.22, y0 + S * 0.56), (x0 + S * 0.47, y0 + S * 0.56), (x0 + S * 0.36, y0 + S * 0.96),
               (x0 + S * 0.8, y0 + S * 0.4), (x0 + S * 0.54, y0 + S * 0.4)], fill=255)
    # 9: musical / shout arcs
    x0, y0 = box(9)
    for k in range(3):
        rr = S * (0.18 + k * 0.13)
        d.arc([x0 + S * 0.2 - rr, y0 + S / 2 - rr, x0 + S * 0.2 + rr, y0 + S / 2 + rr], -50, 50, fill=255, width=int(S * 0.07))
    # 10: eye
    x0, y0 = box(10)
    d.chord([x0 + S * 0.06, y0 + S * 0.2, x0 + S * 0.94, y0 + S * 1.0], 200, 340, outline=255, width=int(S * 0.06))
    d.chord([x0 + S * 0.06, y0 + S * 0.0, x0 + S * 0.94, y0 + S * 0.8], 20, 160, outline=255, width=int(S * 0.06))
    d.ellipse([x0 + S * 0.36, y0 + S * 0.36, x0 + S * 0.64, y0 + S * 0.64], fill=255)
    # 11: spiral (confusion)
    x0, y0 = box(11)
    pts = []
    for k in range(120):
        t = k / 119
        a = t * math.tau * 2.2
        rr = S * 0.42 * t
        pts.append((x0 + S / 2 + math.cos(a) * rr, y0 + S / 2 + math.sin(a) * rr))
    d.line(pts, fill=255, width=int(S * 0.07), joint="curve")
    # 12: plus (heal / buff)
    x0, y0 = box(12)
    d.rounded_rectangle([x0 + S * 0.38, y0 + S * 0.12, x0 + S * 0.62, y0 + S * 0.88], radius=S * 0.06, fill=255)
    d.rounded_rectangle([x0 + S * 0.12, y0 + S * 0.38, x0 + S * 0.88, y0 + S * 0.62], radius=S * 0.06, fill=255)
    # 13: baseball
    x0, y0 = box(13)
    d.ellipse([x0 + S * 0.1, y0 + S * 0.1, x0 + S * 0.9, y0 + S * 0.9], outline=255, width=int(S * 0.06))
    d.arc([x0 - S * 0.2, y0 + S * 0.15, x0 + S * 0.45, y0 + S * 0.85], -60, 60, fill=255, width=int(S * 0.04))
    d.arc([x0 + S * 0.55, y0 + S * 0.15, x0 + S * 1.2, y0 + S * 0.85], 120, 240, fill=255, width=int(S * 0.04))
    # 14: shield
    x0, y0 = box(14)
    d.polygon([(x0 + S * 0.5, y0 + S * 0.06), (x0 + S * 0.88, y0 + S * 0.2), (x0 + S * 0.82, y0 + S * 0.6), (x0 + S * 0.5, y0 + S * 0.95),
               (x0 + S * 0.18, y0 + S * 0.6), (x0 + S * 0.12, y0 + S * 0.2)], outline=255, width=int(S * 0.07))
    # 15: broken shield (armor break)
    x0, y0 = box(15)
    d.polygon([(x0 + S * 0.5, y0 + S * 0.06), (x0 + S * 0.88, y0 + S * 0.2), (x0 + S * 0.82, y0 + S * 0.6), (x0 + S * 0.5, y0 + S * 0.95),
               (x0 + S * 0.18, y0 + S * 0.6), (x0 + S * 0.12, y0 + S * 0.2)], outline=255, width=int(S * 0.07))
    d.line([(x0 + S * 0.52, y0 + S * 0.08), (x0 + S * 0.42, y0 + S * 0.38), (x0 + S * 0.58, y0 + S * 0.55), (x0 + S * 0.47, y0 + S * 0.93)], fill=0, width=int(S * 0.08))
    a = np.asarray(big.resize((cell * 4, cell * 4), Image.LANCZOS), np.float32) / 255.0
    save("icons", a)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (make_glow, make_spark, make_star, make_smoke, make_flame, make_noise, make_ring, make_scorch, make_cracks,
               make_frost, make_runes, make_clock, make_web, make_chain, make_icons):
        fn()


if __name__ == "__main__":
    main()
