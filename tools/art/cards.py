"""Card illustrations (512x384, no frame/text), card back and frame glow.

Every card is painted at 2x (1024x768) from layered procedural elements and
downsampled. Shared language: dark navy/charcoal backdrop, light in the card's
category colour, comic ink outlines, halftone accents, speed lines, bloom and
grain. Rarity raises the 'energy' (particles, rays, glow intensity).
"""
from __future__ import annotations

import json
import math
import sys
import zlib

import numpy as np

from artlib.baseball import render_ball
from artlib.core import (CATEGORY, PAL, RARITY, ROOT, TEX_DIR, add, blank, blur, darken, fft_noise, from_mask,
                         gradient_map, grid, hexrgb, lighten, mix_hex, opaque, over, place, radial, rasterize, save,
                         smoothstep, solid, svg_doc)
from artlib import fx, scene, props

W, H = 1024, 768
OUT = TEX_DIR / "cards"
LEVEL = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}
INK = "#070D17"


def load_cards():
    return json.loads((ROOT / "data" / "cards.json").read_text())["cards"]


class Card:
    def __init__(self, info):
        self.info = info
        self.id = info["id"]
        self.cat = info["category"]
        self.rarity = info["rarity"]
        self.col = CATEGORY[self.cat]
        self.rcol = RARITY[self.rarity]
        self.lv = LEVEL[self.rarity]
        self.seed = zlib.crc32(self.id.encode()) % 10000
        self.img = solid(H, W, PAL["navy_dark"])

    # compositing shortcuts -------------------------------------------------
    def over(self, layer, k=1.0):
        self.img = over(self.img, layer, k)

    def add(self, layer, k=1.0):
        self.img = add(self.img, layer, k)

    def svg(self, body, defs="", k=1.0):
        lay = rasterize(svg_doc(W, H, body, defs), W, H)
        self.over(lay, k)
        return lay

    def place(self, layer, x, y, mode="over", k=1.0):
        self.img = place(self.img, layer, x, y, mode, k)

    def glow(self, layer_or_mask, sigma, color=None, k=1.0):
        a = layer_or_mask[..., 3] if layer_or_mask.ndim == 3 else layer_or_mask
        if color is None:
            g = blur(layer_or_mask, sigma)
        else:
            g = from_mask(blur(a, sigma), color)
        self.add(g, k)

    def rng(self, salt=0):
        return np.random.default_rng(self.seed + salt)


# ---------------------------------------------------------------------------
# Shared backdrop / finishing
# ---------------------------------------------------------------------------
def backdrop(c: Card, focus=(W * 0.5, H * 0.45), burst=True, halftone=True, glow_r=0.55,
             top=PAL["navy_dark"], bottom=PAL["charcoal"], glow_k=0.32, color=None, bokeh=24):
    color = color or c.col
    x, y = grid(H, W)
    t = y / H
    rgb = hexrgb(top)[None, None] * (1 - t[..., None]) + hexrgb(bottom)[None, None] * t[..., None]
    d = np.sqrt(((x - focus[0]) / (W * glow_r)) ** 2 + ((y - focus[1]) / (H * glow_r)) ** 2)
    rgb += hexrgb(color) * (np.exp(-d * d * 2.2) * glow_k)[..., None]
    rgb += hexrgb(darken(color, 0.55)) * (np.exp(-d * d * 0.5) * 0.08)[..., None]
    c.img = opaque(np.clip(rgb, 0, 1))
    if burst:
        b = fx.radial_burst(W, H, focus[0], focus[1], n=30 + 6 * c.lv, seed=c.seed, color=lighten(color, 0.3),
                            r0=60, spread=0.55, opacity=(0.02, 0.07))
        c.add(b, 1.0)
    if bokeh:
        add_bokeh(c, color, n=bokeh)
    if halftone:
        add_halftone(c, color)


def field_floor(c: Card, hz, top, kind="grass", seed=0, cam_h=2.0, light=None, fog_col="#1E1A2A", fog_far=40):
    """Perspective ground below screen line `top` (horizon at hz) composited over the image."""
    g = scene.Ground(W, H, hz, cam_h=cam_h)
    if kind == "grass":
        rgb = g.grass(seed=c.seed + seed, light="#1F4A2C", dark="#163A22", stripe=2.4)
    else:
        rgb = g.dirt(seed=c.seed + seed, base=("#24130D", "#432617", "#653A24", "#8E5534"))
    if light is not None:
        X0, Z0, r, col, k = light
        pool = g.light_pool(X0, Z0, r)
        rgb = rgb * (0.5 + 0.9 * pool[..., None]) + hexrgb(col) * (pool * k)[..., None]
    fog = g.fog(fog_far)[..., None]
    rgb = rgb * (1 - fog) + hexrgb(fog_col) * fog
    m = np.clip(g.y - top + 0.5, 0, 1)
    c.over(from_mask(m, rgb))
    return g


def add_bokeh(c: Card, color=None, n=26, region=(0, 0, W, H * 0.75), k=1.0, size=(14, 60)):
    """Out-of-focus stadium lights for depth."""
    color = color or c.col
    rng = c.rng(77)
    body = []
    for i in range(n):
        x, y = rng.uniform(region[0], region[2]), rng.uniform(region[1], region[3])
        r = rng.uniform(*size)
        col = [color, "#FFE6B8", "#FFFFFF", lighten(color, 0.4)][rng.integers(4)]
        op = rng.uniform(0.03, 0.13)
        body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{col}" fill-opacity="{op:.2f}"/>'
                    f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * 0.93:.1f}" fill="none" stroke="{col}" '
                    f'stroke-opacity="{op * 0.8:.2f}" stroke-width="{r * 0.1:.1f}"/>')
    lay = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(blur(lay, 3.0), k)


def stadium_layer(c: Card, base_y, rim=None, color="#09111E", towers=2, seed=0, hs=1.0, glow=1.0, lamp_col="#FFE9B0",
                  bottom=None):
    body, lamps = scene.stadium_svg(W, H, base_y, seed=c.seed + seed, color=color, rim=rim or c.col, towers=towers,
                                    height_scale=hs, bottom=bottom)
    c.svg(body)
    if glow:
        c.add(scene.lamp_glow(W, H, lamps, lamp_col), 0.8 * glow)
    return lamps


def add_halftone(c: Card, color=None, corners=((1.0, 0.0), (0.0, 1.0)), k=0.16, spacing=11):
    color = color or c.col
    x, y = grid(H, W)
    field = np.zeros((H, W), np.float32)
    for cx, cy in corners:
        d = np.sqrt(((x - cx * W) / W) ** 2 + ((y - cy * H) / H) ** 2)
        field = np.maximum(field, smoothstep(0.55, 0.0, d))
    m = fx.halftone_mask(W, H, field * 0.85, spacing=spacing, angle_deg=30)
    c.add(from_mask(m, color), k)


def finish(c: Card, bloom=1.0, vignette=0.55, sparkle=True):
    img = c.img
    rgb = img[..., :3]
    lum = rgb.max(-1)
    bright = rgb * smoothstep(0.62, 1.0, lum)[..., None]
    b1 = blur(bright, 8)
    b2 = blur(bright, 30)
    rgb = rgb + (b1 * 0.22 + b2 * 0.16) * bloom * (1 + 0.12 * c.lv)
    if sparkle and c.lv >= 3:
        sp = fx.particles(W, H, 18 + 10 * (c.lv - 3), c.seed + 501, region=(40, 40, W - 40, H - 40),
                          color=["#FFFFFF", lighten(c.rcol, 0.4)], size=(1.5, 3.5), sparkle_frac=0.7,
                          opacity=(0.5, 1.0))
        rgb = rgb + sp[..., :3] * 0.9
    # grade: pull deep shadows toward brand navy so every card shares the same dark base
    lum2 = rgb.max(-1)
    sh = smoothstep(0.38, 0.0, lum2)[..., None] * 0.45
    rgb = rgb * (1 - sh) + hexrgb("#0E1A2B") * sh * (0.6 + lum2[..., None])
    v = fx.vignette_alpha(H, W, strength=vignette, inner=0.35, outer=1.25)
    rgb = rgb * (1 - v[..., None]) + hexrgb(PAL["navy_dark"]) * v[..., None] * 0.6
    # soft shoulder above 0.8 so hot highlights roll off instead of clipping flat
    rgb = np.maximum(rgb, 0)
    rgb = np.where(rgb < 0.8, rgb, 0.8 + 0.2 * (1 - np.exp(-(rgb - 0.8) / 0.2)))
    rgb = rgb + fx.grain(H, W, c.seed, 0.012)[..., None]
    c.img = opaque(np.clip(rgb, 0, 1))


def rim_mask(mask, direction, width):
    """Edge band of `mask` on the side facing `direction` (dx, dy)."""
    dx, dy = direction
    n = math.hypot(dx, dy)
    sx, sy = int(round(-dx / n * width)), int(round(-dy / n * width))
    shifted = np.roll(np.roll(mask, sy, 0), sx, 1)
    return np.clip(mask - shifted, 0, 1)


def ball(c: Card, diam, x, y, rot=(0.6, 0.5, 0.3), rim=None, glow=0.0, glow_col=None, **kw):
    b = render_ball(diam, rot=rot, rim=rim or lighten(c.col, 0.15), bounce=kw.pop("bounce", c.col), **kw)
    if glow:
        g = blank(int(diam * 3), int(diam * 3))
        g = place(g, b, g.shape[1] / 2, g.shape[0] / 2)
        c.place(from_mask(blur(g[..., 3], diam * 0.25), glow_col or c.col), x, y, "add", glow)
    c.place(b, x, y)
    return b


def motion_trail(c: Card, x0, y0, x1, y1, width, color, k=1.0, core="#FFFFFF", blur_s=6):
    """Tapered comet trail from (x0,y0) (tail) to (x1,y1) (head)."""
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    body = (f'<path d="M{x0:.1f},{y0:.1f} L{x1 + nx * width / 2:.1f},{y1 + ny * width / 2:.1f} '
            f'L{x1 - nx * width / 2:.1f},{y1 - ny * width / 2:.1f}Z" fill="{color}"/>')
    lay = rasterize(svg_doc(W, H, body), W, H)
    c.add(blur(lay, blur_s * 3), 0.8 * k)
    c.add(blur(lay, blur_s), 0.9 * k)
    body2 = (f'<path d="M{x0 + dx * 0.3:.1f},{y0 + dy * 0.3:.1f} L{x1 + nx * width * 0.2:.1f},{y1 + ny * width * 0.2:.1f} '
             f'L{x1 - nx * width * 0.2:.1f},{y1 - ny * width * 0.2:.1f}Z" fill="{core}"/>')
    c.add(blur(rasterize(svg_doc(W, H, body2), W, H), blur_s * 0.6), 0.8 * k)


# ---------------------------------------------------------------------------
# Painters
# ---------------------------------------------------------------------------
PAINTERS = {}


def painter(fn):
    PAINTERS[fn.__name__] = fn
    return fn


@painter
def power_throw(c: Card):
    fxc, fyc = W * 0.60, H * 0.47
    backdrop(c, focus=(fxc, fyc), glow_k=0.38)
    stadium_layer(c, H * 0.86, seed=1, hs=0.8, glow=0.5)
    # streaks converging behind the ball
    c.add(fx.speed_lines(W, H, 196, n=60, seed=c.seed, color=lighten(c.col, 0.55), length=(0.25, 0.7),
                         width=(2, 9), region=(-200, 120, W * 0.62, H - 120), opacity=(0.12, 0.55)), 0.9)
    # sonic-boom rings around the flight axis
    body = []
    for i, (rx, op, wd) in enumerate([(230, 0.9, 9), (300, 0.5, 6), (370, 0.25, 4)]):
        body.append(fx.ring_svg(fxc - 70 - i * 70, fyc + 18 + i * 14, rx * 0.28, rx, wd, "#FFFFFF", op, -16))
    rings = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(rings[..., 3], 9), c.col), 1.0)
    c.over(rings, 0.9)
    # comet streaks
    rng = c.rng(5)
    for i in range(7):
        off = rng.uniform(-90, 90)
        motion_trail(c, -80, fyc + 150 + off * 1.4, fxc - 40, fyc + off * 0.35, rng.uniform(30, 110),
                     c.col if i % 2 else "#FFB089", 0.35, blur_s=3)
    ball(c, 320, fxc + 20, fyc - 10, rot=(0.7, 0.35, 0.5), glow=0.55, rim_strength=1.0,
         rim_dir=(-0.8, -0.3, -0.2), light=(0.35, 0.7, 0.6))
    c.add(fx.particles(W, H, 40, c.seed + 3, region=(0, 100, W * 0.62, H - 100),
                       color=["#FFFFFF", lighten(c.col, 0.4)], size=(1.5, 4), sparkle_frac=0.2), 1.0)
    finish(c)


@painter
def curveball(c: Card):
    backdrop(c, focus=(W * 0.62, H * 0.55))
    # strike-zone grid in the background
    zx, zy, zw, zh = W * 0.48, H * 0.30, 300, 360
    grid_body = f'<rect x="{zx}" y="{zy}" width="{zw}" height="{zh}" fill="{c.col}" fill-opacity="0.06" stroke="{lighten(c.col, 0.3)}" stroke-opacity="0.35" stroke-width="4"/>'
    for k in (1, 2):
        grid_body += (f'<line x1="{zx + zw * k / 3}" y1="{zy}" x2="{zx + zw * k / 3}" y2="{zy + zh}" stroke="{lighten(c.col, 0.3)}" stroke-opacity="0.22" stroke-width="3"/>'
                      f'<line x1="{zx}" y1="{zy + zh * k / 3}" x2="{zx + zw}" y2="{zy + zh * k / 3}" stroke="{lighten(c.col, 0.3)}" stroke-opacity="0.22" stroke-width="3"/>')
    c.svg(grid_body)
    p0, p1, p2, p3 = (-60, H * 0.16), (W * 0.42, H * 0.00), (W * 0.66, H * 0.36), (W * 0.64, H * 0.66)
    pts = props.bezier(p0, p1, p2, p3, 160)
    outer = props.taper_path(pts, 4, 150, 1.3)
    defs = props.lin_grad("ct", [(0, c.col, 0.0), (0.5, "#4FA3FF", 0.7), (1, "#BFD9FF", 1.0)], 0, 0, 1, 0.6)
    tl = rasterize(svg_doc(W, H, f'<path d="{outer}" fill="url(#ct)"/>', defs), W, H)
    c.add(blur(tl, 24), 1.0)
    c.over(blur(tl, 1.5), 0.85)
    inner = props.taper_path(pts, 1, 50, 1.3)
    c.add(blur(rasterize(svg_doc(W, H, f'<path d="{inner}" fill="#FFFFFF"/>'), W, H), 2), 0.9)
    # side motion lines following the curve
    body = []
    for off, op in ((-95, 0.5), (95, 0.45), (-140, 0.25), (140, 0.25)):
        q = props.bezier(p0, p1, p2, p3, 160)[60:150]
        d = np.gradient(q, axis=0)
        d /= np.linalg.norm(d, axis=1, keepdims=True)
        nrm = np.stack([-d[:, 1], d[:, 0]], 1)
        t = np.linspace(0, 1, len(q))[:, None]
        q = q + nrm * off * t
        body.append(f'<path d="{props.taper_path(q, 1, 7)}" fill="#FFFFFF" fill-opacity="{op}"/>')
    c.svg("".join(body))
    bx, by = pts[-1]
    arcs = "".join(
        f'<path d="M{bx + math.cos(a) * 165:.1f},{by + math.sin(a) * 165:.1f} A165,165 0 0 1 '
        f'{bx + math.cos(a + 1.0) * 165:.1f},{by + math.sin(a + 1.0) * 165:.1f}" fill="none" stroke="#DCE6FF" '
        f'stroke-width="8" stroke-linecap="round"/>' for a in (0.5, 2.6, 4.7))
    al = rasterize(svg_doc(W, H, arcs), W, H)
    c.add(from_mask(blur(al[..., 3], 8), "#4FA3FF"), 1.0)
    c.over(al)
    ball(c, 240, bx, by, rot=(1.2, 0.2, 1.0), glow=0.5, glow_col="#4FA3FF", rim="#9FC4FF",
         rim_dir=(-0.7, -0.6, -0.2), light=(0.4, 0.75, 0.5))
    finish(c)


@painter
def heat_wave(c: Card):
    hz = H * 0.40
    g = scene.Ground(W, H, hz, cam_h=1.3)
    x, y = grid(H, W)
    rgb = gradient_map(np.clip(y / hz, 0, 1), [(0, "#0A0F1C"), (0.6, "#24121F"), (1.0, "#5A2418")])
    dirt = g.dirt(seed=c.seed, base=("#24130D", "#432617", "#653A24", "#8E5534"))
    pool = g.light_pool(-1.2, 7.5, 4.5)
    dirt = dirt * (0.45 + 1.2 * pool[..., None]) + hexrgb("#FF6A2A") * (pool * 0.28)[..., None]
    rgb = rgb * (1 - g.mask[..., None]) + dirt * g.mask[..., None]
    fog = g.fog(34)[..., None]
    rgb = rgb * (1 - fog) + hexrgb("#5A2418") * fog
    c.img = opaque(np.clip(rgb, 0, 1))
    stadium_layer(c, hz + 2, rim="#FF7A3A", seed=3, hs=0.55, glow=0.6, bottom=hz + 3)
    add_bokeh(c, "#FF7A3A", n=14, region=(0, 0, W, hz))
    add_halftone(c, corners=((1.0, 0.0),), k=0.14)
    # the ball skims along a ground path (far-left -> near-right); a wall of fire rises behind it
    P0, P1 = np.array([-6.5, 16.0]), np.array([2.4, 3.4])
    tb = 0.84
    rng = c.rng(11)
    tongues = []
    for t in np.linspace(0.0, tb + 0.03, 90):
        P = P0 + (P1 - P0) * t
        gx, gy = g.project(P[0], P[1])
        sc = g.scale_at(P[1])
        hm = (0.45 + 1.5 * min(1.0, t / tb) ** 1.2) * rng.uniform(0.6, 1.25)
        if t > tb:
            hm *= 0.6
        tongues.append((gx + rng.uniform(-0.3, 0.3) * sc, gy + rng.uniform(0, 0.15) * sc, hm * sc * rng.uniform(0.7, 1.15),
                        0.55 * sc * rng.uniform(0.8, 1.3), rng.uniform(-24, -6), rng.uniform(-0.8, 0.8)))
    tongues.sort(key=lambda q: q[1])          # far first
    fl = rasterize(svg_doc(W, H, fx.flames_svg(tongues)), W, H)
    c.add(from_mask(blur(fl[..., 3], 30), "#FF5A1F"), 0.9)
    c.add(from_mask(blur(fl[..., 3], 8), "#FF8A2A"), 0.5)
    c.add(from_mask(blur(np.roll(fl[..., 3], 50, 0) * g.mask, 45), "#FF6A2A"), 0.7)
    c.over(fl)
    # flaming ball at the head of the wave
    Pb = P0 + (P1 - P0) * (tb + 0.02)
    bx, _ = g.project(Pb[0], Pb[1])
    by = g.horizon + g.focal * (g.cam_h - 2.0) / Pb[1]
    Pt = P0 + (P1 - P0) * (tb - 0.25)
    tx, _ = g.project(Pt[0], Pt[1])
    ty = g.horizon + g.focal * (g.cam_h - 2.0) / Pt[1]
    travel = math.degrees(math.atan2(by - ty, bx - tx))
    bd = 170
    tg = fx.fireball_tongues(bx, by, bd / 2, travel, n=20, length=4.2, seed=c.seed, spread=38)
    fb = rasterize(svg_doc(W, H, fx.flames_svg(tg)), W, H)
    c.add(from_mask(blur(fb[..., 3], 26), "#FF4A1A"), 0.9)
    c.over(fb)
    ball(c, bd, bx, by, rot=(0.4, 0.8, 0.2), glow=0.9, glow_col="#FF7A2A", rim="#FFB347", rim_strength=1.1,
         rim_dir=(-math.cos(math.radians(travel)), math.sin(math.radians(travel)), -0.2), light=(0.5, 0.6, 0.6))
    c.add(fx.particles(W, H, 80 + 20 * c.lv, c.seed + 7, region=(0, 0, W, H * 0.85),
                       color=["#FFD27A", "#FF8A3A", "#FFFFFF"], size=(1.2, 3.5), sparkle_frac=0.15), 1.0)
    finish(c)


@painter
def splitter(c: Card):
    ox, oy = W * 0.20, H * 0.56
    backdrop(c, focus=(W * 0.55, H * 0.5))
    stadium_layer(c, H * 0.90, seed=2, hs=0.7, glow=0.4)
    # incoming trail into the split point
    motion_trail(c, -120, oy + 60, ox, oy, 150, c.col, 0.8)
    # split flash
    c.add(fx.light_rays(W, H, ox, oy, 22, c.seed + 1, lighten(c.col, 0.4), spread=0.5, opacity=(0.05, 0.22)), 1.0)
    fl = blank(H, W)
    fl[..., 3] = np.exp(-(radial(H, W, ox, oy, 90) ** 2))
    fl[..., :3] = fl[..., 3:4] * hexrgb("#FFE2C0")
    c.add(fl, 1.0)
    ends = []
    for i, ang in enumerate(np.linspace(-38, 38, 5)):
        a = math.radians(ang)
        L = 560 + 60 * (1 - abs(ang) / 38)
        ex, ey = ox + math.cos(a) * L, oy + math.sin(a) * L * 0.62
        bend = 110 * (1 if ang >= 0 else -1) * (abs(ang) / 38)
        p1 = (ox + (ex - ox) * 0.35, oy + (ey - oy) * 0.05 - bend * 0.2)
        p2 = (ox + (ex - ox) * 0.7, ey - bend * 0.5)
        pts = props.bezier((ox, oy), p1, p2, (ex, ey), 90)
        ends.append((ex, ey, pts))
        trail = props.taper_path(pts, 4, 70, 1.4)
        tl = rasterize(svg_doc(W, H, f'<path d="{trail}" fill="{c.col}"/>'), W, H)
        c.add(blur(tl, 16), 0.8)
        c.add(blur(tl, 3), 0.55)
        core = props.taper_path(pts, 1, 18, 1.4)
        c.add(rasterize(svg_doc(W, H, f'<path d="{core}" fill="#FFE9D6"/>'), W, H), 0.7)
    for i, (ex, ey, pts) in enumerate(ends):
        dx, dy = pts[-1] - pts[-6]
        d = 120 - abs(i - 2) * 6
        ball(c, d, ex, ey, rot=(0.5 + i * 0.7, 0.3 * i, 0.4 * i), glow=0.9, rim_strength=1.0,
             rim_dir=(-dx, dy, -0.3), light=(0.4, 0.7, 0.6))
    ball(c, 120, ox, oy, rot=(0.2, 0.5, 0.1), glow=1.2, glow_col="#FFD0A0", light=(0.4, 0.7, 0.6),
         emissive=0.35)
    c.add(fx.particles(W, H, 50 + 15 * c.lv, c.seed + 3, region=(ox, 60, W, H - 60),
                       color=["#FFFFFF", lighten(c.col, 0.4)], size=(1.5, 4), sparkle_frac=0.3), 1.0)
    finish(c)


@painter
def grand_slam_barrage(c: Card):
    hz = H * 0.70
    rgb = scene.sky(W, H, hz, scene.SUNSET, sun=(W * 0.36, hz - 10, 60, "#FF9A4A"), clouds=1.0, seed=c.seed)
    c.img = opaque(np.clip(rgb, 0, 1))
    c.add(fx.light_rays(W, H, W * 0.36, hz - 10, 24, c.seed, "#FFD9A0", spread=0.8, opacity=(0.03, 0.10)), 1.0)
    rng = c.rng(3)
    travel = 125.0      # moving down-left
    tdx, tdy = math.cos(math.radians(travel)), math.sin(math.radians(travel))
    mets = []
    # distant meteors near the horizon, big ones up front; avoid the outer frame margin
    for i in range(26):
        depth = (i / 25) ** 1.2
        size = 22 + 82 * depth
        for _ in range(40):
            x = rng.uniform(70, W - 40)
            y = rng.uniform(90, hz - 60 - 120 * depth)
            if all(math.hypot(x - m[0], y - m[1]) > (m[2] + size) * 0.75 for m in mets):
                break
        mets.append((x, y, size, depth))
    for (x, y, size, depth) in mets:
        haze = 1 - depth
        tg = fx.fireball_tongues(x, y, size / 2, travel, n=11, length=5.5, seed=int(x * 7 + y), spread=28, origin=0.15)
        fb = rasterize(svg_doc(W, H, fx.flames_svg(tg)), W, H)
        c.add(from_mask(blur(fb[..., 3], 5 + 12 * depth), "#FF6A2A"), 0.5 + 0.4 * depth)
        c.over(fb, 0.5 + 0.5 * depth)
        b = render_ball(size, rot=(x * 0.01, y * 0.02, 0.3), rim="#FFE08A", rim_strength=1.2, base="#FFE9D2",
                        shadow="#B85A3A", rim_dir=(-tdx, tdy, -0.2), light=(-0.5, -0.4, 0.7), bounce="#FF7A3A")
        c.place(from_mask(blur(np.pad(b[..., 3], int(size)), size * 0.2), "#FFB060"), x, y, "add", 0.6)
        c.place(b, x, y, k=0.55 + 0.45 * depth)
        if haze > 0.35:
            c.place(from_mask(b[..., 3], "#FF9A6A"), x, y, "over", haze * 0.45)
    # stadium silhouette, field in front, impact bursts along the stands
    stadium_layer(c, hz + 70, rim="#FFB060", seed=5, towers=3, hs=0.9, glow=0.55, color="#0A0D1A", bottom=hz + 75)
    g = field_floor(c, hz - 40, hz + 72, "grass", cam_h=1.2, light=(0, 6, 5, "#FF7A2A", 0.10), fog_col="#120C16")
    for ix, iy, sz in ((W * 0.18, hz + 38, 0.62), (W * 0.56, hz + 30, 0.85), (W * 0.86, hz + 42, 0.55)):
        c.add(from_mask(np.exp(-(radial(H, W, ix, iy - 20, 200 * sz, 90 * sz) ** 2)), "#FF8A3A"), 0.35)
        c.add(from_mask(np.exp(-(radial(H, W, ix, iy + 80, 300 * sz, 70 * sz) ** 2)) * (g.y > hz + 72), "#FF7A2A"), 0.25)
        bs = rasterize(svg_doc(W, H, fx.comic_burst_svg(ix, iy, 115 * sz, seed=int(ix), points=11, squash=0.72)), W, H)
        c.add(from_mask(blur(bs[..., 3], 14), "#FF7A2A"), 0.7)
        c.over(bs)
        tg = [(ix + rng.uniform(-60, 60) * sz, iy + 30 * sz, rng.uniform(50, 110) * sz, rng.uniform(30, 50) * sz,
               rng.uniform(-30, 30), rng.uniform(-0.6, 0.6)) for _ in range(6)]
        tg.sort(key=lambda t: -t[2])
        c.over(rasterize(svg_doc(W, H, fx.flames_svg(tg)), W, H))
    c.add(fx.particles(W, H, 110, c.seed + 9, region=(30, 30, W - 30, H - 30), color=["#FFD27A", "#FF8A3A", "#FFFFFF"],
                       size=(1.2, 3.5), sparkle_frac=0.25), 1.0)
    finish(c, bloom=0.6, vignette=0.6)


@painter
def grand_relay(c: Card):
    gold = PAL["gold"]
    hz = H * 0.30
    g = scene.Ground(W, H, hz, cam_h=2.2)
    x, y = grid(H, W)
    rgb = gradient_map(np.clip(y / hz, 0, 1), [(0, "#08101E"), (1, "#1E1A2A")])
    grass = g.grass(seed=c.seed, light="#14301F", dark="#0E2216", stripe=2.0)
    pool = g.light_pool(0, 7, 6)
    grass = grass * (0.55 + 0.9 * pool[..., None])
    rgb = rgb * (1 - g.mask[..., None]) + grass * g.mask[..., None]
    fog = g.fog(40)[..., None]
    rgb = rgb * (1 - fog) + hexrgb("#1E1A2A") * fog
    c.img = opaque(np.clip(rgb, 0, 1))
    stadium_layer(c, hz + 2, rim=gold, seed=4, hs=0.5, glow=0.6, bottom=hz + 3)
    add_halftone(c, gold, corners=((1.0, 0.0), (0.0, 0.0)), k=0.12)
    # relay nodes on the ground, zig-zag from far to near
    nodes_w = [(-3.6, 30), (3.4, 20), (-3.0, 13.5), (2.6, 9.4), (-1.6, 6.8), (1.0, 5.0)]
    nodes = [g.project(X, Z) for X, Z in nodes_w]
    body = []
    for (X, Z), (sx, sy) in zip(nodes_w, nodes):
        sc = g.scale_at(Z)
        r = 0.9 * sc
        body.append(fx.ring_svg(sx, sy, r, r * g.cam_h / Z * 0.9 + 1, max(2, 0.12 * sc), gold, 0.95))
        body.append(fx.ring_svg(sx, sy, r * 0.6, r * 0.6 * g.cam_h / Z * 0.9 + 1, max(1.5, 0.06 * sc), "#FFFFFF", 0.8))
    rings = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(rings[..., 3], 10), gold), 1.0)
    c.over(rings)
    # chain of light growing in power
    hgt = 1.0
    pts3 = [(sx, sy - hgt * g.scale_at(Z)) for (X, Z), (sx, sy) in zip(nodes_w, nodes)]
    for i in range(len(pts3) - 1):
        (x0, y0), (x1, y1) = pts3[i], pts3[i + 1]
        w0 = 4 + i * 5
        seg = props.taper_path(np.array([(x0, y0), (x1, y1)]), w0, w0 + 6)
        lay = rasterize(svg_doc(W, H, f'<path d="{seg}" fill="{gold}"/>'), W, H)
        c.add(blur(lay, 6 + i * 3), 1.0)
        c.over(lay, 0.9)
        core = props.taper_path(np.array([(x0, y0), (x1, y1)]), w0 * 0.35, (w0 + 6) * 0.35)
        c.over(rasterize(svg_doc(W, H, f'<path d="{core}" fill="#FFFFFF"/>'), W, H))
        # node flare
        sp = rasterize(svg_doc(W, H, fx.sparkle_svg(x0, y0, 18 + i * 10, "#FFFFFF", 0.95, 0.2)), W, H)
        c.add(blur(sp, 4), 1.0)
        c.over(sp)
        # vertical light pillar from ground node
        sx, sy = nodes[i]
        pil = props.taper_path(np.array([(sx, sy), (x0, y0)]), 2 + i, 1)
        c.add(blur(rasterize(svg_doc(W, H, f'<path d="{pil}" fill="{gold}"/>'), W, H), 3), 0.7)
    bx, by = pts3[-1]
    c.add(fx.light_rays(W, H, bx, by - 20, 26, c.seed, "#FFD45A", spread=0.5, opacity=(0.04, 0.2)), 1.0)
    ball(c, 190, bx, by - 20, rot=(0.9, 0.4, 0.2), base="#FFD45A", shadow="#B0700E", rim="#FFF4C0",
         glow=1.2, glow_col=gold, light=(0.3, 0.7, 0.6), stitch="#C0281E", seam_color="#C99A2E")
    c.add(fx.particles(W, H, 70, c.seed + 5, region=(0, hz - 40, W, H), color=["#FFE7A0", "#FFFFFF", gold],
                       size=(1.5, 4), sparkle_frac=0.4), 1.0)
    finish(c)


@painter
def power_catch(c: Card):
    purple = "#8E44AD"
    hz = H * 0.46
    g = scene.Ground(W, H, hz, cam_h=1.7)
    x, y = grid(H, W)
    rgb = gradient_map(np.clip(y / hz, 0, 1), [(0, "#0A0E1C"), (1, "#2A1838")])
    dirt = g.dirt(seed=c.seed, base=("#1E1218", "#3A2324", "#5A3A30", "#7A5040"))
    rgb = rgb * (1 - g.mask[..., None]) + dirt * g.mask[..., None]
    fog = g.fog(30)[..., None]
    rgb = rgb * (1 - fog) + hexrgb("#2A1838") * fog
    c.img = opaque(np.clip(rgb, 0, 1))
    stadium_layer(c, hz + 2, rim=purple, seed=6, hs=0.5, glow=0.5, bottom=hz + 3)
    add_bokeh(c, "#B45CFF", n=12, region=(0, 0, W, hz))
    ix, iz = 0.0, 5.0
    sx, sy = g.project(ix, iz)
    sc = g.scale_at(iz)
    # shockwave rings on the ground
    body = []
    for r, op, wd in ((2.2, 0.95, 14), (3.4, 0.55, 9), (4.6, 0.3, 6)):
        body.append(fx.ring_svg(sx, sy, r * sc, r * sc * g.cam_h / iz * 1.0, wd, "#D9A6FF", op))
    rings = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(rings[..., 3], 12), "#B45CFF"), 1.3)
    c.over(rings)
    # cracks radiating from the impact
    rng = c.rng(4)
    cracks = []
    for k in range(11):
        a = rng.uniform(0, 2 * math.pi)
        pts = [(ix, iz)]
        X, Z = ix, iz
        for s in range(6):
            a += rng.uniform(-0.5, 0.5)
            step = rng.uniform(0.35, 0.7)
            X, Z = X + math.cos(a) * step, Z + math.sin(a) * step * 0.9
            pts.append((X, max(2.2, Z)))
        scr = [g.project(px, pz) for px, pz in pts]
        widths = np.linspace(12, 1, len(scr))
        cracks.append(props.taper_path(np.array(scr), 30, 3))
    cr = rasterize(svg_doc(W, H, "".join(f'<path d="{d}" fill="#0A0610"/>' for d in cracks)), W, H)
    c.over(cr)
    inner = rasterize(svg_doc(W, H, "".join(f'<path d="{d}" fill="#E0B8FF" transform="translate(0,1)" '
                                            f'fill-opacity="0.9"/>' for d in cracks)), W, H)
    core_m = np.clip(cr[..., 3] - np.roll(cr[..., 3], 3, 0), 0, 1) + blur(cr[..., 3], 1.5) * 0.5
    c.add(from_mask(np.clip(core_m, 0, 1), "#E8C8FF"), 1.0)
    c.add(from_mask(blur(cr[..., 3], 10), "#B45CFF"), 1.4)
    c.add(from_mask(blur(cr[..., 3], 3), "#D9A6FF"), 0.6)
    # debris rocks flying up
    rocks = []
    for k in range(16):
        rx = sx + rng.uniform(-380, 380)
        ry = sy - rng.uniform(40, 330)
        rr = rng.uniform(8, 26)
        pts = [(rx + math.cos(t) * rr * rng.uniform(0.6, 1.1), ry + math.sin(t) * rr * rng.uniform(0.6, 1.1))
               for t in np.linspace(0, 2 * math.pi, 7)[:-1]]
        rocks.append(props.inked(props.poly_d(pts), "#6A4A3C", INK, 3))
        rocks.append(f'<path d="{props.poly_d(pts[:3] + [(rx, ry)])}" fill="#9A7058"/>')
    c.svg("".join(rocks))
    # vertical speed lines above the glove
    c.add(fx.speed_lines(W, H, 90, n=26, seed=c.seed, color="#E8D0FF", length=(0.15, 0.35), width=(2, 6),
                         region=(sx - 300, 0, sx + 300, sy - 250), opacity=(0.2, 0.6)), 0.8)
    # the glove, fingers down, slamming into the ground
    defs, gl = props.glove(trim="#8E44AD")
    sh = blank(H, W)
    sh[..., 3] = np.exp(-(radial(H, W, sx, sy + 8, 230, 50) ** 4)) * 0.85
    c.over(sh)
    gsvg = f'<g transform="translate({sx - 10:.1f},{sy - 250:.1f}) rotate(168) scale(0.92) translate(-232,-250)">{gl}</g>'
    glay = rasterize(svg_doc(W, H, gsvg, defs), W, H)
    c.add(from_mask(blur(glay[..., 3], 22), "#B45CFF"), 0.9)
    rim = rim_mask(glay[..., 3], (0.3, -1), 7)
    c.over(glay)
    c.add(from_mask(blur(rim, 1.5), "#D9A6FF"), 0.9)
    # impact flash
    fl = blank(H, W)
    fl[..., 3] = np.exp(-(radial(H, W, sx, sy - 10, 220, 60) ** 2))
    fl[..., :3] = fl[..., 3:4] * hexrgb("#E8C8FF")
    c.add(fl, 0.9)
    c.add(fx.particles(W, H, 60, c.seed + 6, region=(sx - 420, sy - 300, sx + 420, sy + 120),
                       color=["#E0B8FF", "#FFFFFF", c.col], size=(1.5, 4), sparkle_frac=0.3), 1.0)
    finish(c)


@painter
def thunderbolt(c: Card):
    yel = "#FFE135"
    bx, by = W * 0.52, H * 0.52
    backdrop(c, focus=(bx, by), color="#FFB02E", glow_k=0.3, bokeh=0)
    # storm clouds
    n = fft_noise(H, W, scale=140, beta=1.2, seed=c.seed)
    n2 = fft_noise(H, W, scale=40, beta=1.0, seed=c.seed + 1)
    cl = smoothstep(0.35, 0.7, n * 0.8 + n2 * 0.2) * (1 - 0.8 * np.exp(-(radial(H, W, bx, by, 330) ** 2)))
    c.over(from_mask(cl, "#0C0A18", 0.9))
    rimc = np.clip(cl - np.roll(np.roll(cl, 8, 0), -6, 1), 0, 1)
    c.add(from_mask(rimc * 0.8, "#6A5A30"), 0.8)
    # bolts radiating from the ball
    rng = c.rng(8)
    glow_b, core_b = [], []
    for i in range(7):
        a = (i + rng.uniform(-0.3, 0.3)) / 7 * 2 * math.pi
        L = rng.uniform(420, 720)
        p0 = (bx + math.cos(a) * 80, by + math.sin(a) * 80)
        p1 = (bx + math.cos(a) * L, by + math.sin(a) * L)
        gb, cb = fx.lightning_svg(p0, p1, c.seed + i * 13, rng.uniform(5, 10), yel, branches=3, detail=6, rough=0.18)
        glow_b.append(gb)
        core_b.append(cb)
    gl = rasterize(svg_doc(W, H, "".join(glow_b)), W, H)
    c.add(blur(gl, 18), 1.0)
    c.add(blur(gl, 5), 0.6)
    c.over(rasterize(svg_doc(W, H, "".join(core_b)), W, H))
    # electric halo
    halo = "".join(fx.ring_svg(bx, by, r, r, w, yel, op) for r, w, op in ((150, 5, 0.8), (185, 3, 0.4)))
    hl = rasterize(svg_doc(W, H, halo), W, H)
    c.add(blur(hl, 10), 1.0)
    c.over(hl, 0.8)
    ball(c, 230, bx, by, rot=(0.3, 0.9, 0.4), base="#FFE85A", shadow="#C08A10", rim="#FFFFFF", glow=1.3,
         glow_col=yel, stitch="#D02A1E", seam_color="#D8B020", light=(-0.4, 0.7, 0.6), rim_strength=1.0)
    # arcs crackling on the ball surface
    gb, cb = fx.lightning_svg((bx - 90, by - 40), (bx + 80, by + 60), c.seed + 99, 3, "#FFFFFF", branches=1, detail=5)
    c.over(rasterize(svg_doc(W, H, cb), W, H), 0.8)
    c.add(fx.particles(W, H, 70, c.seed + 4, region=(0, 0, W, H), color=[yel, "#FFFFFF"], size=(1.5, 3.5),
                       sparkle_frac=0.5), 1.0)
    finish(c, bloom=1.2)


def inked_glyph(ch, x, y, size, rot=0.0, fill="#FFFFFF", ink=INK, ow=10, family="Bangers"):
    d, e = props.glyph_d(ch, family, size)
    cx, cy = e["x_bearing"] + e["width"] / 2, e["y_bearing"] + e["height"] / 2
    tf = f'transform="translate({x:.1f},{y:.1f}) rotate({rot:.1f}) translate({-cx:.1f},{-cy:.1f})"'
    return (f'<path d="{d}" {tf} fill="{ink}" stroke="{ink}" stroke-width="{ow * 2}" stroke-linejoin="round"/>'
            f'<path d="{d}" {tf} fill="{fill}"/>')


@painter
def knuckleball(c: Card):
    bx, by = W * 0.60, H * 0.50
    backdrop(c, focus=(bx, by))
    # dizzy wobbling spiral trail
    t = np.linspace(0, 1, 400)
    xs = -40 + (bx - 60 + 40) * t
    ys = by + 40 * np.sin(t * 2 * np.pi * 3.0) * (0.4 + 0.6 * t)
    loop = 70 * np.sin(t * 2 * np.pi * 4) * t
    pts = np.stack([xs + loop * 0.6, ys + 60 * np.cos(t * 2 * np.pi * 4) * t * 0.8], 1)
    tr = props.taper_path(pts, 3, 36, 1.2)
    lay = rasterize(svg_doc(W, H, f'<path d="{tr}" fill="{lighten(c.col, 0.2)}"/>'), W, H)
    c.add(blur(lay, 14), 1.0)
    c.over(lay, 0.75)
    c.over(rasterize(svg_doc(W, H, f'<path d="{props.taper_path(pts, 1, 10, 1.2)}" fill="#FFFFFF"/>'), W, H), 0.85)
    # wobble echoes
    for i, (dx, dy, rot, op) in enumerate(((-70, -26, 0.9, 0.18), (-38, 22, 0.5, 0.28))):
        b = render_ball(230, rot=(1.0 + rot, 0.4, 0.8 - rot), rim=lighten(c.col, 0.3), bounce=c.col)
        c.place(b, bx + dx, by + dy, k=op)
    # orbiting dizzy stars + question marks
    body = []
    rng = c.rng(2)
    for i, (qx, qy, sz, rot) in enumerate(((bx - 200, by - 170, 120, -18), (bx + 190, by - 150, 95, 16),
                                         (bx + 230, by + 120, 80, 24), (bx - 270, by + 150, 70, -10))):
        body.append(inked_glyph("?", qx, qy, sz * 1.6, rot, "#FFFFFF" if i % 2 == 0 else lighten(c.col, 0.55), ow=9))
    q = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(q[..., 3], 14), c.col), 1.0)
    c.over(q)
    orbit = fx.ring_svg(bx, by - 140, 160, 40, 4, lighten(c.col, 0.5), 0.7, -8)
    stars = ""
    for k in range(5):
        a = k / 5 * 2 * math.pi + 0.4
        sx, sy = bx + math.cos(a) * 160, by - 140 + math.sin(a) * 40
        pts5 = []
        for j in range(10):
            aa = -math.pi / 2 + j * math.pi / 5
            rr = 22 if j % 2 == 0 else 9
            pts5.append((sx + math.cos(aa) * rr, sy + math.sin(aa) * rr))
        stars += props.inked(props.poly_d(pts5), PAL["gold"], INK, 4)
    c.svg(orbit)
    ball(c, 230, bx, by, rot=(1.0, 0.4, 0.8), glow=0.5, light=(0.4, 0.75, 0.5))
    st = rasterize(svg_doc(W, H, stars), W, H)
    c.add(from_mask(blur(st[..., 3], 8), PAL["gold"]), 0.8)
    c.over(st)
    finish(c)


@painter
def shadow_change(c: Card):
    purple = PAL["purple"]
    bx, by = W * 0.64, H * 0.48
    backdrop(c, focus=(bx, by), color=purple, glow_k=0.35, bokeh=10)
    # shadow smoke streaming left (backwards)
    x, y = grid(H, W)
    along = np.clip((bx - x) / 700, 0, 1)
    shape = np.exp(-((y - by - (x - bx) * 0.05) / (90 + 260 * along)) ** 2) * (x < bx + 60) * (1 - along * 0.6)
    sm = fx.smoke(H, W, shape.astype(np.float32), c.seed, colors=("#120A22", "#2E1650", "#5A2E99"), scale=90, soft=3)
    c.add(from_mask(blur(shape.astype(np.float32), 30), purple), 0.6)
    c.over(sm)
    # ghostly hands reaching from the smoke and pulling the ball back
    hands = []
    for (hx, hy, rot, sc) in ((bx - 210, by - 40, 72, 1.05), (bx - 170, by + 120, 118, 0.85), (bx - 320, by - 150, 60, 0.75)):
        d = props.ghost_hand_d(0.8)
        hands.append(f'<g transform="translate({hx:.1f},{hy:.1f}) rotate({rot}) scale({sc})"><path d="{d}" fill="url(#gh)" '
                     f'stroke="url(#gh)" stroke-width="10" stroke-linejoin="round"/></g>')
    defs = props.lin_grad("gh", [(0, "#E8D4FF", 1.0), (0.45, "#B07AF0", 0.8), (1, "#5A2E99", 0.0)], 0, 0, 0, 1)
    hl = rasterize(svg_doc(W, H, "".join(hands), defs), W, H)
    c.add(from_mask(blur(hl[..., 3], 22), purple), 1.2)
    c.add(from_mask(blur(hl[..., 3], 6), "#C9A0FF"), 0.6)
    c.over(blur(hl, 1.2), 0.75)
    edge = np.clip(hl[..., 3] - blur(hl[..., 3], 3), 0, 1)
    c.add(from_mask(edge * 2.0, "#F2E6FF"), 0.8)
    # the ball, dark purple, dissolving on its trailing side
    b = render_ball(220, rot=(0.8, 0.3, 0.6), base="#7A4FB5", shadow="#26123F", rim="#D8B8FF", stitch="#E04A6A",
                    seam_color="#4A2A70", rim_dir=(0.8, 0.3, -0.2), light=(0.5, 0.6, 0.6), bounce="#9B5DE5")
    bs = b.shape[0]
    yy, xx = np.mgrid[0:bs, 0:bs].astype(np.float32)
    n = fft_noise(bs, bs, scale=10, seed=c.seed + 5)
    dissolve = smoothstep(0.15, 0.55, (xx / bs) + (n - 0.5) * 0.5)
    b = b * dissolve[..., None]
    c.place(from_mask(blur(np.pad(b[..., 3], 120), 30), purple), bx, by, "add", 1.0)
    c.place(b, bx, by)
    c.add(fx.particles(W, H, 90, c.seed + 3, region=(bx - 420, by - 220, bx + 40, by + 220),
                       color=["#D8B8FF", "#9B5DE5", "#FFFFFF"], size=(1.5, 4.5), sparkle_frac=0.15), 1.0)
    finish(c)


@painter
def changeup(c: Card):
    cx0, cy0 = W * 0.42, H * 0.50
    backdrop(c, focus=(W * 0.6, H * 0.5))
    # giant faint clock face
    body = [fx.ring_svg(cx0, cy0, 330, 330, 10, lighten(c.col, 0.3), 0.35)]
    for i in range(12):
        a = math.radians(i * 30)
        r0, r1 = 300, 270 if i % 3 else 245
        body.append(f'<line x1="{cx0 + math.sin(a) * r0:.1f}" y1="{cy0 - math.cos(a) * r0:.1f}" x2="{cx0 + math.sin(a) * r1:.1f}" '
                    f'y2="{cy0 - math.cos(a) * r1:.1f}" stroke="{lighten(c.col, 0.3)}" stroke-opacity="0.4" stroke-width="{10 if i % 3 == 0 else 5}" stroke-linecap="round"/>')
    c.svg("".join(body))
    # clock-hand sweep trail: wedge sectors fading toward the past
    bx, by = cx0 + math.cos(math.radians(-10)) * 250, cy0 + math.sin(math.radians(-10)) * 250
    sweep = []
    for k in range(10):
        a0 = math.radians(-10 - 12 * (k + 1))
        a1 = math.radians(-10 - 12 * k)
        op = 0.35 * (1 - k / 10)
        sweep.append(f'<path d="M{cx0},{cy0} L{cx0 + math.cos(a0) * 250:.1f},{cy0 + math.sin(a0) * 250:.1f} '
                     f'A250,250 0 0 1 {cx0 + math.cos(a1) * 250:.1f},{cy0 + math.sin(a1) * 250:.1f}Z" fill="{c.col}" fill-opacity="{op:.2f}"/>')
    sw = rasterize(svg_doc(W, H, "".join(sweep)), W, H)
    c.add(sw, 1.0)
    hands = (f'<line x1="{cx0}" y1="{cy0}" x2="{bx:.1f}" y2="{by:.1f}" stroke="{INK}" stroke-width="26" stroke-linecap="round"/>'
             f'<line x1="{cx0}" y1="{cy0}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#F4F1EA" stroke-width="14" stroke-linecap="round"/>'
             f'<line x1="{cx0}" y1="{cy0}" x2="{cx0 - 60:.1f}" y2="{cy0 - 150:.1f}" stroke="{INK}" stroke-width="30" stroke-linecap="round"/>'
             f'<line x1="{cx0}" y1="{cy0}" x2="{cx0 - 60:.1f}" y2="{cy0 - 150:.1f}" stroke="#F4F1EA" stroke-width="18" stroke-linecap="round"/>'
             f'<circle cx="{cx0}" cy="{cy0}" r="22" fill="{INK}"/><circle cx="{cx0}" cy="{cy0}" r="13" fill="{PAL["gold"]}"/>')
    c.svg(hands)
    # slow-motion echoes along the arc + ripples
    for k, op in ((3, 0.12), (2, 0.2), (1, 0.32)):
        a = math.radians(-10 - 16 * k)
        b = render_ball(170, rot=(0.6 + k * 0.15, 0.5, 0.3), rim=lighten(c.col, 0.3), bounce=c.col)
        c.place(b, cx0 + math.cos(a) * 250 + 40 * k * 0, cy0 + math.sin(a) * 250, k=op)
    rip = "".join(fx.ring_svg(bx + 20, by, r, r * 0.95, 4, "#FFFFFF", op) for r, op in ((130, 0.5), (175, 0.3), (225, 0.16)))
    rl = rasterize(svg_doc(W, H, rip), W, H)
    c.add(from_mask(blur(rl[..., 3], 6), c.col), 1.0)
    c.over(rl)
    ball(c, 180, bx + 20, by, rot=(0.6, 0.5, 0.3), glow=0.6, light=(0.4, 0.7, 0.6))
    finish(c)


@painter
def pickoff(c: Card):
    teal = "#1ABC9C"
    hz = H * 0.36
    x, y = grid(H, W)
    c.img = opaque(gradient_map(np.clip(y / hz, 0, 1), [(0, "#0A1220"), (1, "#22213A")]))
    stadium_layer(c, hz + 2, rim=c.col, seed=7, hs=0.55, glow=0.5, bottom=hz + 3)
    g = field_floor(c, hz, hz, "dirt", cam_h=1.1, light=(0.2, 3.2, 2.2, "#B8A8FF", 0.15), fog_col="#22213A", fog_far=30)
    add_bokeh(c, n=10, region=(0, 0, W, hz))
    # base bag
    c.svg(props.base_bag_svg(g, 0.75, 2.6, size=0.42, height=0.09))
    # dust cloud from the slide
    sm_shape = np.exp(-(radial(H, W, W * 0.33, H * 0.72, 300, 110) ** 2)).astype(np.float32)
    c.over(fx.smoke(H, W, sm_shape, c.seed, colors=("#3A2A2A", "#6A5048", "#9A7A66"), scale=40), 0.8)
    # motion lines behind the sliding boot
    c.add(fx.speed_lines(W, H, 0, n=30, seed=c.seed, color="#FFFFFF", length=(0.15, 0.35), width=(2, 6),
                         region=(-100, H * 0.55, W * 0.45, H * 0.8), opacity=(0.2, 0.6)), 0.8)
    # sliding runner's leg + cleat (Wreckers gunmetal / hazard orange)
    leg = (f'<path d="M-40,{H * 0.66:.1f} L{W * 0.40:.1f},{H * 0.60:.1f} L{W * 0.42:.1f},{H * 0.73:.1f} L-40,{H * 0.80:.1f}Z" '
           f'fill="{INK}" stroke="{INK}" stroke-width="14" stroke-linejoin="round"/>'
           f'<path d="M-40,{H * 0.66:.1f} L{W * 0.40:.1f},{H * 0.60:.1f} L{W * 0.42:.1f},{H * 0.73:.1f} L-40,{H * 0.80:.1f}Z" fill="#2B2F36"/>'
           f'<path d="M-40,{H * 0.69:.1f} L{W * 0.40:.1f},{H * 0.625:.1f}" stroke="#FF7A1A" stroke-width="10"/>')
    cl = props.cleat(W * 0.36, H * 0.74, 250)
    c.svg(leg + cl)
    # impact burst at the tag point
    tx, ty = W * 0.58, H * 0.60
    c.add(fx.light_rays(W, H, tx, ty, 16, c.seed + 2, lighten(teal, 0.5), spread=0.4, opacity=(0.02, 0.09)), 1.0)
    burst = rasterize(svg_doc(W, H, fx.comic_burst_svg(tx, ty, 120, seed=3, points=10, squash=0.85,
                                                        colors=(teal, lighten(teal, 0.4), "#FFFFFF"))), W, H)
    c.add(from_mask(blur(burst[..., 3], 12), teal), 0.8)
    c.over(burst, 0.9)
    # teal glove slapping the tag down onto the boot, ball held in the pocket
    bx_, by_ = tx + 6, ty - 14
    defs, gl = props.glove(leather="#1E9E88", dark="#0B5A4C", light="#6FE8D2", lace="#062E28", trim="#0F7A68")
    gx, gy = bx_ - 17 + 40, by_ + 37 - 70
    gsvg = f'<g transform="translate({gx:.1f},{gy:.1f}) rotate(-150) scale(0.62) translate(-232,-250)">{gl}</g>'
    glay = rasterize(svg_doc(W, H, gsvg, defs), W, H)
    c.add(from_mask(blur(glay[..., 3], 18), teal), 0.8)
    c.over(glay)
    ball(c, 92, bx_, by_, rot=(0.4, 0.3, 0.2), rim="#B8FFF0", light=(0.3, 0.7, 0.6))
    # tag motion arcs
    arcs = "".join(f'<path d="M{gx + 150 + k * 30:.1f},{gy - 170 + k * 10:.1f} Q{gx + 200 + k * 30:.1f},{gy - 20:.1f} {gx + 110 + k * 20:.1f},{gy + 110:.1f}" '
                   f'fill="none" stroke="#FFFFFF" stroke-opacity="{0.6 - k * 0.15:.2f}" stroke-width="{7 - k * 2}" stroke-linecap="round"/>'
                   for k in range(3))
    c.svg(arcs)
    finish(c)


@painter
def time_out(c: Card):
    hz = H * 0.80
    rgb = scene.sky(W, H, hz, scene.TWILIGHT, clouds=0.6, seed=c.seed)
    c.img = opaque(np.clip(rgb, 0, 1))
    stadium_layer(c, hz + 40, rim="#9FD8FF", seed=8, towers=3, hs=1.0, glow=0.7)
    cx0, cy0, r = W * 0.50, H * 0.46, 210
    c.add(fx.light_rays(W, H, cx0, cy0, 30, c.seed, "#CFE8FF", spread=0.7, opacity=(0.04, 0.16)), 1.0)
    halo = np.exp(-(radial(H, W, cx0, cy0, 380) ** 2))
    c.add(from_mask(halo, c.col), 0.6)
    defs, sw = props.stopwatch(cx0, cy0, r, accent=PAL["scarlet"], hand_angle=-50)
    swl = rasterize(svg_doc(W, H, sw, defs), W, H)
    c.over(swl)
    # frost overlay on the watch: cyan tint + streaks
    m = swl[..., 3]
    n = fft_noise(H, W, scale=18, seed=c.seed + 3, stretch=4, angle=0.8)
    frost = smoothstep(0.55, 0.9, n) * m
    c.add(from_mask(frost * 0.7, "#DFF4FF"), 0.7)
    c.over(from_mask(m * 0.18, "#8FD3FF"))
    # ice crystals growing over the watch: clusters at the base and the sides
    rng = c.rng(5)
    shards = []
    clusters = [(cx0 - 60, cy0 + r * 0.95, 1.5, 7), (cx0 + 120, cy0 + r * 0.85, 1.25, 6), (cx0 - r * 0.95, cy0 + 40, 1.0, 5),
                (cx0 + r * 0.98, cy0 - 30, 0.95, 5), (cx0 - r * 0.6, cy0 - r * 0.8, 0.75, 4), (cx0 + r * 0.7, cy0 - r * 0.78, 0.7, 3)]
    for (qx, qy, sc, n) in clusters:
        base_ang = math.degrees(math.atan2(qy - cy0, qx - cx0)) + 90
        for k in range(n):
            ang = base_ang + rng.uniform(-38, 38)
            L = rng.uniform(70, 170) * sc
            shards.append((qx + rng.uniform(-30, 30) * sc, qy + rng.uniform(-14, 14) * sc, L, L * rng.uniform(0.28, 0.42), ang))
    shards.sort(key=lambda q: -q[2])
    body = []
    for sx, sy, L, wdt, ang in shards:
        pts = [(-wdt / 2, 0), (-wdt * 0.42, -L * 0.72), (0, -L), (wdt * 0.42, -L * 0.70), (wdt / 2, 0)]
        d = props.poly_d(pts)
        half = props.poly_d([(0, 0), (0, -L), (wdt * 0.42, -L * 0.70), (wdt / 2, 0)])
        tf = f'transform="translate({sx:.1f},{sy:.1f}) rotate({ang:.1f})"'
        body.append(f'<path d="{d}" {tf} fill="#0B2A44" stroke="#0B2A44" stroke-width="8" stroke-linejoin="round"/>'
                    f'<path d="{d}" {tf} fill="#7FC8F0" fill-opacity="0.9"/>'
                    f'<path d="{half}" {tf} fill="#DDF4FF" fill-opacity="0.85"/>'
                    f'<path d="M{-wdt * 0.2:.1f},{-L * 0.15:.1f} L{-wdt * 0.1:.1f},{-L * 0.75:.1f}" {tf} stroke="#FFFFFF" stroke-width="3" stroke-opacity="0.9" stroke-linecap="round"/>')
    ice = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(ice[..., 3], 16), "#7FD0FF"), 0.8)
    c.over(ice)
    # whistle (lower left) and T sign (right)
    wdefs, wh = props.whistle(W * 0.17, H * 0.80, 70)
    cord = f'<path d="M{W * 0.17 + 17:.1f},{H * 0.80 - 66:.1f} C{W * 0.22:.1f},{H * 0.55:.1f} {W * 0.05:.1f},{H * 0.5:.1f} {W * 0.02:.1f},{H * 0.62:.1f}" fill="none" stroke="{PAL["scarlet"]}" stroke-width="8"/>'
    c.svg(cord + wh, wdefs)
    hx, hy = W * 0.86, H * 0.36
    tsign = (f'<g transform="translate({hx - 10:.1f},{hy + 196:.1f}) rotate(-90) scale(0.68)">{props.flat_hand_svg()}</g>'
             f'<g transform="translate({hx - 88:.1f},{hy:.1f}) scale(0.68)">{props.flat_hand_svg()}</g>')
    tl = rasterize(svg_doc(W, H, tsign), W, H)
    c.add(from_mask(blur(tl[..., 3], 14), c.col), 0.8)
    c.over(tl)
    c.add(fx.particles(W, H, 120, c.seed + 9, region=(30, 30, W - 30, H - 30), color=["#FFFFFF", "#CFE8FF", PAL["gold"]],
                       size=(1.2, 3.5), sparkle_frac=0.5), 1.0)
    finish(c)


def night_field(c: Card, hz, kind="dirt", cam_h=1.3, rim=None, light=None, towers=2, sky=("#08101E", "#1A2238"),
                fog_col="#1A2238", fog_far=34, seed=0, stadium=True):
    x, y = grid(H, W)
    c.img = opaque(gradient_map(np.clip(y / hz, 0, 1), [(0, sky[0]), (1, sky[1])]))
    if stadium:
        stadium_layer(c, hz + 2, rim=rim or c.col, seed=seed, hs=0.55, glow=0.55, bottom=hz + 3, towers=towers)
    add_bokeh(c, n=10, region=(0, 0, W, hz))
    return field_floor(c, hz, hz, kind, cam_h=cam_h, light=light, fog_col=fog_col, fog_far=fog_far, seed=seed)


def plate_svg(g, X=0.0, Z=3.2, size=0.55, thick=0.05):
    top = props.home_plate_poly(g, X, Z, size)
    sc = g.scale_at(Z)
    hp = thick * sc
    up = [(px, py - hp) for px, py in top]
    side = [top[0], top[1], up[1], up[0]]
    return (f'<path d="{props.poly_d(up)}{props.poly_d(side)}" fill="{INK}" stroke="{INK}" stroke-width="10" stroke-linejoin="round"/>'
            f'<path d="{props.poly_d(side)}" fill="#9AA3B2"/><path d="{props.poly_d(up)}" fill="#F4F1EA"/>'
            f'<path d="{props.poly_d(up)}" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-opacity="0.7" '
            f'transform="translate(0,-2)"/>')


@painter
def lockdown(c: Card):
    blue = "#4FA3FF"
    hz = H * 0.36
    g = night_field(c, hz, "dirt", cam_h=1.4, rim=blue, light=(0, 3.4, 2.6, blue, 0.25), seed=1)
    add_halftone(c, blue, corners=((1.0, 0.0), (0.0, 0.0)), k=0.12)
    # catcher's mitt behind the plate
    defs, mitt = props.glove(catcher=True, leather="#7A3A1A", dark="#3E1A08", light="#B86A3A", trim="#2A1206",
                             lace_hi="#D9A070")
    mx, my = W * 0.5, H * 0.31
    ml = rasterize(svg_doc(W, H, f'<g transform="translate({mx:.1f},{my:.1f}) rotate(-8) scale(0.62) translate(-215,-240)">{mitt}</g>', defs), W, H)
    c.add(from_mask(blur(ml[..., 3], 20), blue), 0.6)
    c.over(ml)
    c.add(from_mask(rim_mask(ml[..., 3], (1, -0.4), 6), "#9FD0FF"), 0.8)
    # home plate
    c.svg(plate_svg(g, 0, 3.5, 0.62))
    # energy chains: a ring around the plate + two crossing chains
    ring = [g.project(math.cos(t) * 1.0, 3.5 + math.sin(t) * 0.8) for t in np.linspace(0, 2 * math.pi, 120)]
    ring = [(px, py - 0.25 * g.scale_at(3.5)) for px, py in ring]
    back = [p for p, t in zip(ring, np.linspace(0, 2 * math.pi, 120)) if math.sin(t) > 0]
    front = [p for p, t in zip(ring, np.linspace(0, 2 * math.pi, 120)) if math.sin(t) <= 0]
    x1 = [g.project(-1.6, 2.5), g.project(1.4, 4.4)]
    x2 = [g.project(1.6, 2.5), g.project(-1.4, 4.4)]
    x1 = [(p[0], p[1] - 40) for p in x1]
    x2 = [(p[0], p[1] - 40) for p in x2]
    chains = props.chain_links(np.array(x1), 54, 30, "#7FC0FF") + props.chain_links(np.array(x2), 54, 30, "#7FC0FF")
    chains += props.chain_links(np.array(ring), 46, 26, "#7FC0FF")
    ch = rasterize(svg_doc(W, H, chains), W, H)
    c.add(from_mask(blur(ch[..., 3], 16), blue), 1.6)
    c.add(from_mask(blur(ch[..., 3], 5), "#4F9BFF"), 0.9)
    c.over(ch)
    # padlock where the chains meet
    pdefs, pl = props.padlock(W * 0.5, H * 0.62, 150)
    pll = rasterize(svg_doc(W, H, pl, pdefs), W, H)
    c.add(from_mask(blur(pll[..., 3], 18), blue), 1.0)
    c.over(pll)
    c.add(fx.particles(W, H, 60, c.seed + 2, region=(W * 0.15, H * 0.3, W * 0.85, H * 0.95), color=["#BFE0FF", "#FFFFFF", blue],
                       size=(1.5, 4), sparkle_frac=0.35), 1.0)
    finish(c)


@painter
def frost_field(c: Card):
    ice = "#BFF4FF"
    hz = H * 0.34
    x, y = grid(H, W)
    c.img = opaque(gradient_map(np.clip(y / hz, 0, 1), [(0, "#07121E"), (1, "#16303E")]))
    stadium_layer(c, hz + 2, rim=c.col, seed=2, hs=0.55, glow=0.5, bottom=hz + 3)
    g = scene.Ground(W, H, hz, cam_h=1.5)
    grass = g.grass(seed=c.seed, light="#245A3A", dark="#1A4630", stripe=2.0)
    # spreading ice: radial frost front with fractal edge
    d = np.hypot(g.X * 0.9, g.Z - 5.2)
    n = scene.sample_tex(fft_noise(512, 512, scale=40, seed=c.seed, tileable=True), g.X * 50, g.Z * 50)
    frost = smoothstep(3.8, 2.8, d + (n - 0.5) * 2.4) * g.mask
    icecol = gradient_map(np.clip(n, 0, 1), [(0, "#3E7A8E"), (0.5, "#6FB0C4"), (1, "#BFE6F2")])
    icecol = icecol * (0.6 + 0.6 * np.exp(-((d - 0.5) / 2.0) ** 2))[..., None]
    rgb = grass * (1 - frost[..., None]) + icecol * frost[..., None]
    cracks = scene.sample_tex(fft_noise(512, 512, scale=10, seed=c.seed + 1, tileable=True), g.X * 70, g.Z * 70)
    crack_m = smoothstep(0.03, 0.0, np.abs(cracks - 0.5)) * frost * (1 - g.fog(14))
    rgb = rgb * (1 - crack_m[..., None] * 0.6) + hexrgb("#FFFFFF") * crack_m[..., None] * 0.6
    fog = g.fog(30)[..., None]
    rgb = rgb * (1 - fog) + hexrgb("#16303E") * fog
    c.over(from_mask(g.mask, rgb))
    c.add(from_mask(blur(frost, 30), c.col), 0.35)
    add_halftone(c, ice, corners=((0.0, 0.0), (1.0, 0.0)), k=0.10)
    # jagged ice crystals growing out of the turf
    rng = c.rng(4)
    shards = []
    for k in range(26):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(1.5, 3.4)
        X, Z = math.cos(a) * rr * 1.25, 5.6 + math.sin(a) * rr
        if Z < 3.4:
            continue
        sx, sy = g.project(X, Z)
        sc = g.scale_at(Z)
        L = rng.uniform(0.35, 0.9) * sc
        shards.append((sx, sy, L, L * rng.uniform(0.3, 0.45), rng.uniform(-35, 35) + X * 6, Z))
    shards.sort(key=lambda q: -q[5])
    body = []
    for sx, sy, L, wdt, ang, Z in shards:
        pts = [(-wdt / 2, 0), (-wdt * 0.42, -L * 0.72), (0, -L), (wdt * 0.42, -L * 0.70), (wdt / 2, 0)]
        half = [(0, 0), (0, -L), (wdt * 0.42, -L * 0.70), (wdt / 2, 0)]
        tf = f'transform="translate({sx:.1f},{sy:.1f}) rotate({ang:.1f})"'
        body.append(f'<path d="{props.poly_d(pts)}" {tf} fill="#0B2A3A" stroke="#0B2A3A" stroke-width="6" stroke-linejoin="round"/>'
                    f'<path d="{props.poly_d(pts)}" {tf} fill="#6FC6E0"/><path d="{props.poly_d(half)}" {tf} fill="#D8F6FF"/>'
                    f'<path d="M{-wdt * 0.18:.1f},{-L * 0.12:.1f} L{-wdt * 0.08:.1f},{-L * 0.72:.1f}" {tf} stroke="#FFFFFF" '
                    f'stroke-width="2.5" stroke-linecap="round"/>')
    sh = rasterize(svg_doc(W, H, "".join(body)), W, H)
    c.add(from_mask(blur(sh[..., 3], 14), c.col), 0.8)
    c.over(sh)
    # frosted ball sitting in the ice
    bx, by = g.project(0.15, 3.9)
    b = render_ball(170, rot=(0.6, 0.6, 0.2), base="#EAF8FF", shadow="#6F97B8", rim="#BFF4FF", rim_strength=1.0,
                    stitch="#C8384A", light=(-0.3, 0.8, 0.5), bounce=c.col)
    bs = b.shape[0]
    fr = fft_noise(bs, bs, scale=8, seed=c.seed + 7)
    frost_ball = smoothstep(0.55, 0.8, fr) * b[..., 3]
    b[..., :3] = b[..., :3] * (1 - frost_ball[..., None] * 0.7) + frost_ball[..., None] * 0.7
    c.place(from_mask(blur(np.pad(b[..., 3], 80), 24), ice), bx, by - 55, "add", 0.5)
    sh = blank(H, W)
    sh[..., 3] = np.exp(-(radial(H, W, bx, by + 20, 120, 26) ** 2)) * 0.6
    c.over(sh)
    c.place(b, bx, by - 55)
    # ice creeping up the ball's base
    cap = [(bx - 70, by + 15), (bx - 50, by - 25), (bx - 20, by - 5), (bx + 5, by - 40), (bx + 30, by - 10), (bx + 60, by - 30), (bx + 80, by + 15)]
    c.svg(props.inked(props.poly_d(cap), "#BFE6F2", "#0B2A3A", 4) + f'<path d="M{bx - 40:.1f},{by + 2:.1f} L{bx + 50:.1f},{by - 4:.1f}" stroke="#FFFFFF" stroke-width="3"/>')
    c.add(fx.particles(W, H, 90 + 15 * c.lv, c.seed + 6, region=(20, 20, W - 20, H - 20), color=["#FFFFFF", ice],
                       size=(1.2, 3.5), sparkle_frac=0.45), 1.0)
    finish(c)


@painter
def wall_of_dirt(c: Card):
    hz = H * 0.36
    g = night_field(c, hz, "dirt", cam_h=1.2, light=(0, 6, 4, c.col, 0.15), seed=3)
    # chalk baseline running into the distance
    chalk = g.line(-0.2, 1.0, -2.6, 60, 0.12)
    c.over(from_mask(chalk, "#F2F0EA", 0.95))
    # the wall: a jagged mound of packed dirt bursting up across the line
    rng = c.rng(2)
    Zw = 5.4
    sc = g.scale_at(Zw)
    xl, yb = g.project(-3.0, Zw)
    xr, _ = g.project(2.0, Zw)
    n = 22
    top = []
    for i in range(n + 1):
        t = i / n
        env = math.sin(t * math.pi) ** 0.55
        hgt = (0.35 + 1.25 * env) * sc * (0.8 + 0.4 * rng.random())
        if i % 2:
            hgt *= 0.82
        top.append((xl + (xr - xl) * t + rng.uniform(-8, 8), yb - hgt))
    front = [(xl - 30, yb + 10)] + top + [(xr + 30, yb + 10)]
    slab = props.poly_d(front)
    # back glow first so the teal light sits behind the wall
    m = rasterize(svg_doc(W, H, f'<path d="{slab}" fill="#fff"/>'), W, H)[..., 3]
    c.add(from_mask(blur(m, 40), c.col), 0.55)
    nn = fft_noise(H, W, scale=26, seed=c.seed + 4)
    n2 = fft_noise(H, W, scale=7, seed=c.seed + 5)
    tone = gradient_map(np.clip(nn * 0.75 + n2 * 0.25, 0, 1), [(0, "#3E2214"), (0.35, "#5E3520"), (0.7, "#7E4C2E"), (1, "#A06A40")])
    yy = (grid(H, W)[1] - (yb - 1.6 * sc)) / (1.7 * sc)
    tone *= (1.25 - 0.6 * np.clip(yy, 0, 1))[..., None]
    c.over(from_mask(dilate_soft(m, 6), INK))
    c.over(from_mask(m, np.clip(tone, 0, 1)))
    # lit top crust
    crust = []
    for i in range(n):
        a, b = top[i], top[i + 1]
        crust.append(f'<path d="M{a[0]:.1f},{a[1]:.1f} L{b[0]:.1f},{b[1]:.1f} L{b[0]:.1f},{b[1] + 16:.1f} L{a[0]:.1f},{a[1] + 22:.1f}Z" fill="#B88456"/>')
    lines = []
    for k in range(12):
        x0 = rng.uniform(xl + 40, xr - 40)
        i0 = min(n, max(0, int((x0 - xl) / (xr - xl) * n)))
        pts = [(x0, top[i0][1] + 20)]
        for j in range(3):
            pts.append((pts[-1][0] + rng.uniform(-22, 22), min(yb - 8, pts[-1][1] + rng.uniform(20, 40))))
        lines.append(f'<path d="{props.poly_d(pts, False)}" fill="none" stroke="{INK}" stroke-width="4" stroke-linejoin="round" stroke-opacity="0.8"/>')
    c.svg("".join(crust) + "".join(lines))
    chunks = []
    for k in range(20):
        i = rng.integers(2, n - 1)
        cxk, cyk = top[i][0] + rng.uniform(-20, 20), top[i][1] - rng.uniform(20, 190)
        rr = rng.uniform(12, 34)
        pts = [(cxk + math.cos(t) * rr * rng.uniform(0.6, 1.1), cyk + math.sin(t) * rr * rng.uniform(0.6, 1.1))
               for t in np.linspace(0, 2 * math.pi, 7)[:-1]]
        chunks.append(props.inked(props.poly_d(pts), mix_hex("#5E3520", "#8E5A38", rng.random()), INK, 4)
                      + f'<path d="{props.poly_d(pts[:3] + [(cxk, cyk)])}" fill="#B88456"/>')
    c.svg("".join(chunks))
    c.add(from_mask(rim_mask(m, (0, -1), 6), lighten(c.col, 0.45)), 0.9)
    # flying chunks and dust
    sm_shape = np.exp(-(radial(H, W, W * 0.45, yb - 1.2 * sc, 480, 110) ** 2)).astype(np.float32) * 0.7
    c.over(fx.smoke(H, W, sm_shape, c.seed, colors=("#3A2A22", "#5A4234", "#7A5C48"), scale=70), 0.45)
    rocks = []
    for k in range(18):
        rx, ry = rng.uniform(W * 0.12, W * 0.88), rng.uniform(H * 0.06, yb - 1.4 * sc)
        rr = rng.uniform(6, 20)
        pts = [(rx + math.cos(t) * rr * rng.uniform(0.6, 1.1), ry + math.sin(t) * rr * rng.uniform(0.6, 1.1))
               for t in np.linspace(0, 2 * math.pi, 7)[:-1]]
        rocks.append(props.inked(props.poly_d(pts), "#7A5038", INK, 3))
    c.svg("".join(rocks))
    c.add(fx.speed_lines(W, H, -90, n=24, seed=c.seed, color="#FFFFFF", length=(0.08, 0.2), width=(2, 5),
                         region=(W * 0.1, H * 0.05, W * 0.9, H * 0.45), opacity=(0.15, 0.45)), 0.8)
    finish(c)


def dilate_soft(mask, r):
    return np.clip(blur(mask, r * 0.6) * 3.0, 0, 1)


def hex_dome(c: Card, cx, cy, R, squash=0.55, color="#2EC4B6", hexes=7.0):
    """Translucent hexagon-grid energy dome (front hemisphere) centred on (cx, cy) base."""
    x, y = grid(H, W)
    nx = (x - cx) / R
    ny = (cy - y) / R
    inside = (nx ** 2 + ny ** 2 <= 1) & (ny >= -0.02)
    nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
    lon = np.arctan2(nx, nz)
    lat = np.arcsin(np.clip(ny, -1, 1))
    u = lon * hexes / math.pi * 2
    v = lat * hexes / math.pi * 2 * 1.15
    # hex grid distance (axial)
    q = u * 2 / 3
    r = (-u / 3 + v / math.sqrt(3))
    cq, cr = np.round(q), np.round(r)
    cs = np.round(-q - r)
    dq, dr, ds = np.abs(cq - q), np.abs(cr - r), np.abs(cs - (-q - r))
    fix_q = (dq > dr) & (dq > ds)
    fix_r = ~fix_q & (dr > ds)
    cq = np.where(fix_q, -cr - cs, cq)
    cr = np.where(fix_r, -cq - cs, cr)
    fq, fr_ = q - cq, r - cr
    fs = -fq - fr_
    edge = np.maximum(np.maximum(np.abs(fq), np.abs(fr_)), np.abs(fs))
    lines = smoothstep(0.44, 0.49, edge)
    fres = (1 - nz) ** 1.5
    a = inside * (0.06 + 0.5 * fres + lines * (0.45 + 0.5 * fres))
    a = blur(a.astype(np.float32), 1.0)
    lay = from_mask(np.clip(a, 0, 1), lighten(color, 0.35))
    c.add(from_mask(blur(inside.astype(np.float32) * (0.3 + fres), 18), color), 0.7)
    c.over(lay, 0.85)
    c.add(from_mask(lines * inside * (0.3 + fres), "#FFFFFF"), 0.35)


@painter
def base_shield(c: Card):
    hz = H * 0.38
    g = night_field(c, hz, "dirt", cam_h=1.4, light=(0, 3.4, 3.0, c.col, 0.3), seed=4)
    add_halftone(c, corners=((1.0, 0.0), (0.0, 0.0)), k=0.12)
    c.svg(plate_svg(g, 0, 3.4, 0.62))
    px, py = g.project(0, 3.4)
    # ground ring where the dome meets the dirt
    sc = g.scale_at(3.4)
    rr = 1.25 * sc
    ring = rasterize(svg_doc(W, H, fx.ring_svg(px, py, rr, rr * g.cam_h / 3.4 * 0.95, 8, lighten(c.col, 0.4), 1.0)), W, H)
    c.add(from_mask(blur(ring[..., 3], 10), c.col), 1.2)
    c.over(ring)
    hex_dome(c, px, py, rr, color=c.col, hexes=6.0)
    c.add(fx.light_rays(W, H, px, py - rr * 0.6, 20, c.seed, lighten(c.col, 0.5), spread=0.5, opacity=(0.02, 0.08)), 1.0)
    c.add(fx.particles(W, H, 70, c.seed + 2, region=(px - rr * 1.3, py - rr * 1.2, px + rr * 1.3, py + 60),
                       color=["#FFFFFF", lighten(c.col, 0.5)], size=(1.5, 4), sparkle_frac=0.4), 1.0)
    finish(c)


@painter
def bunt_trap(c: Card):
    hz = H * 0.30
    g = night_field(c, hz, "dirt", cam_h=1.6, light=(-0.1, 3.9, 2.2, c.col, 0.45), seed=5)
    chalk = g.line(-2.2, 1.0, 1.2, 60, 0.12)
    c.over(from_mask(chalk, "#F2F0EA", 0.9))
    cX, cZ = -0.1, 3.9
    rng = c.rng(3)
    def P(X, Z):
        d = math.hypot(X - cX, (Z - cZ) * 1.2)
        sag = 0.16 * math.exp(-(d / 0.7) ** 2)
        sx, sy = g.project(X, Z)
        return sx, sy + sag * g.scale_at(Z)
    # irregular web: wobbly strands radiating from the ball plus rings around it
    strands = []
    for k in range(14):
        a = k / 14 * 2 * math.pi + rng.uniform(-0.12, 0.12)
        Lr = rng.uniform(1.4, 1.9)
        pts = []
        for t in np.linspace(0.15, 1, 24):
            w = 0.06 * math.sin(t * 9 + k)
            X = cX + math.cos(a) * Lr * t * 1.2 + w
            Z = cZ + math.sin(a) * Lr * t
            pts.append(P(X, Z))
        strands.append((pts, 7))
    for ring_r in (0.45, 0.8, 1.15, 1.5):
        pts = []
        for t in np.linspace(0, 2 * math.pi, 90):
            rr = ring_r * (1 + 0.08 * math.sin(t * 5 + ring_r * 7))
            pts.append(P(cX + math.cos(t) * rr * 1.2, cZ + math.sin(t) * rr))
        strands.append((pts, 5))
    body = []
    for pts, wdt in strands:
        d = props.poly_d(pts, False)
        body.append(f'<path d="{d}" fill="none" stroke="#0A3A34" stroke-width="{wdt + 5}" stroke-linecap="round" stroke-linejoin="round"/>')
    for pts, wdt in strands:
        d = props.poly_d(pts, False)
        body.append(f'<path d="{d}" fill="none" stroke="#8FFFEA" stroke-width="{wdt}" stroke-linecap="round" stroke-linejoin="round"/>')
    goo = []
    for k in range(40):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.3, 1.6)
        sx, sy = P(cX + math.cos(a) * rr * 1.2, cZ + math.sin(a) * rr)
        r = rng.uniform(6, 15) * g.scale_at(cZ + math.sin(a) * rr) / g.scale_at(cZ)
        goo.append(f'<ellipse cx="{sx:.1f}" cy="{sy:.1f}" rx="{r:.1f}" ry="{r * 0.62:.1f}" fill="#0A3A34"/>'
                   f'<ellipse cx="{sx:.1f}" cy="{sy - 1:.1f}" rx="{r * 0.8:.1f}" ry="{r * 0.5:.1f}" fill="#5FF0D8"/>'
                   f'<ellipse cx="{sx - r * 0.3:.1f}" cy="{sy - r * 0.25:.1f}" rx="{r * 0.28:.1f}" ry="{r * 0.16:.1f}" fill="#FFFFFF"/>')
    net = rasterize(svg_doc(W, H, "".join(body) + "".join(goo)), W, H)
    c.add(from_mask(blur(net[..., 3], 16), c.col), 1.3)
    c.over(net)
    bx, by = P(cX, cZ)
    ball(c, 150, bx, by - 50, rot=(0.3, 0.9, 0.2), glow=0.4, light=(-0.4, 0.8, 0.5))
    # sticky strings clinging to the ball
    sticky = []
    for (ex, ey, qx, qy) in ((-120, 25, -60, -40), (115, 30, 70, -30), (-60, 60, -20, 0), (70, 55, 40, 10)):
        sticky.append(f'<path d="M{bx + ex:.1f},{by + ey:.1f} Q{bx + qx:.1f},{by + qy - 30:.1f} {bx + qx * 0.4:.1f},{by - 60:.1f}" '
                      f'fill="none" stroke="#8FFFEA" stroke-width="6" stroke-linecap="round" stroke-opacity="0.95"/>')
    drips = "".join(f'<path d="M{bx + dx:.1f},{by - 30:.1f} q-6,24 0,{L:.1f} q6,-24 0,{-L:.1f}Z" fill="#5FF0D8"/>'
                    for dx, L in ((-35, 30), (10, 44), (45, 26)))
    ol = rasterize(svg_doc(W, H, "".join(sticky) + drips), W, H)
    c.add(from_mask(blur(ol[..., 3], 8), c.col), 1.0)
    c.over(ol)
    c.add(fx.particles(W, H, 40, c.seed + 2, region=(W * 0.15, H * 0.35, W * 0.85, H * 0.95), color=["#9FFFF0", "#FFFFFF"],
                       size=(1.5, 3.5), sparkle_frac=0.3), 1.0)
    finish(c)


@painter
def diving_catch(c: Card):
    pink = "#FF6FA8"
    hz = H * 0.62
    x, y = grid(H, W)
    c.img = opaque(gradient_map(np.clip(y / hz, 0, 1), [(0, "#08101E"), (1, "#1A2A40")]))
    stadium_layer(c, hz + 2, rim=c.col, seed=6, hs=0.8, glow=0.7, bottom=hz + 3, towers=3)
    field_floor(c, hz, hz, "grass", cam_h=1.0, light=(0.5, 4, 3, c.col, 0.15), fog_col="#1A2A40")
    add_bokeh(c, n=14, region=(0, 0, W, hz))
    # speed lines along the dive direction
    c.add(fx.speed_lines(W, H, -28, n=40, seed=c.seed, color="#FFFFFF", length=(0.15, 0.4), width=(2, 6),
                         region=(-100, H * 0.3, W * 0.7, H * 1.0), opacity=(0.15, 0.5)), 0.9)
    # arm: navy sleeve, pink undershirt cuff, from lower-left to the glove
    gx, gy = W * 0.66, H * 0.34
    hx_, hy_ = gx - 92, gy + 83                      # heel of the rotated glove
    ax0, ay0 = -60, H * 1.08
    ux, uy = hx_ - ax0, hy_ - ay0
    ul = math.hypot(ux, uy)
    ux, uy = ux / ul, uy / ul
    ax1, ay1 = hx_ - ux * 40, hy_ - uy * 40
    arm = props.capsule_d(ax0, ay0, ax1, ay1, 66, 44)
    cuff = props.capsule_d(ax1 - ux * 22, ay1 - uy * 22, ax1 + ux * 10, ay1 + uy * 10, 46, 46)
    armsvg = (f'<path d="{arm}" fill="{INK}" stroke="{INK}" stroke-width="14" stroke-linejoin="round"/>'
              f'<path d="{arm}" fill="#1C2E4A"/>'
              f'<path d="M{ax0 + 40:.1f},{ay0 - 52:.1f} L{ax1 - ux * 40 - uy * 30:.1f},{ay1 - uy * 40 + ux * 30:.1f}" stroke="#D7262E" stroke-width="10" stroke-linecap="round"/>'
              f'<path d="M{ax0 + 10:.1f},{ay0 - 80:.1f} L{ax1 - ux * 40 + uy * 20:.1f},{ay1 - uy * 40 - ux * 20:.1f}" stroke="#2C4466" stroke-width="14" stroke-linecap="round"/>'
              f'<path d="{cuff}" fill="{INK}" stroke="{INK}" stroke-width="12" stroke-linejoin="round"/><path d="{cuff}" fill="{pink}"/>')
    c.svg(armsvg)
    defs, gl = props.glove(trim=pink, lace="#7A1E48", lace_hi="#FFB0D0")
    gsvg = f'<g transform="translate({gx:.1f},{gy:.1f}) rotate(48) scale(0.62) translate(-232,-250)">{gl}</g>'
    glay = rasterize(svg_doc(W, H, gsvg, defs), W, H)
    c.add(from_mask(blur(glay[..., 3], 20), c.col), 0.8)
    c.over(glay)
    c.add(from_mask(rim_mask(glay[..., 3], (0.6, -1), 6), "#B8FFF5"), 0.8)
    # ball snagged in the web
    bx, by = gx + 40, gy - 120
    c.add(fx.light_rays(W, H, bx, by, 18, c.seed, "#FFFFFF", spread=0.4, opacity=(0.02, 0.10)), 1.0)
    ball(c, 120, bx, by, rot=(0.9, 0.2, 0.6), glow=0.7, glow_col="#FFFFFF", light=(0.3, 0.8, 0.5))
    # grass blades and sparkles flying
    rng = c.rng(9)
    blades = []
    for k in range(30):
        bx0, by0 = rng.uniform(W * 0.2, W * 0.95), rng.uniform(H * 0.55, H * 0.95)
        L = rng.uniform(14, 34)
        a = rng.uniform(-1.2, 1.2)
        blades.append(f'<path d="M{bx0:.1f},{by0:.1f} q{math.cos(a) * L * 0.5:.1f},{-L * 0.6:.1f} {math.cos(a) * L:.1f},{-L * math.sin(abs(a) + 0.3):.1f}" '
                      f'fill="none" stroke="#5FCB7A" stroke-width="4" stroke-linecap="round"/>')
    c.svg("".join(blades))
    c.add(fx.particles(W, H, 50, c.seed + 4, region=(W * 0.3, 40, W - 40, H * 0.7), color=["#FFFFFF", pink, lighten(c.col, 0.5)],
                       size=(1.5, 4), sparkle_frac=0.4), 1.0)
    finish(c)


def diamond_map_svg(cx, cy, s, color, op=0.35, width=4):
    """Top-down tactical diamond: base paths, bases, mound, X/O marks and play arrows."""
    b = []
    d = [(cx, cy + s), (cx + s, cy), (cx, cy - s), (cx - s, cy)]
    b.append(f'<path d="{props.poly_d(d)}" fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="{width}"/>')
    b.append(f'<path d="M{cx},{cy + s} L{cx + s * 2.2:.1f},{cy - s * 1.2:.1f} M{cx},{cy + s} L{cx - s * 2.2:.1f},{cy - s * 1.2:.1f}" '
             f'stroke="{color}" stroke-opacity="{op * 0.7:.2f}" stroke-width="{width * 0.8:.1f}"/>')
    b.append(f'<path d="M{cx - s * 2.0:.1f},{cy - s * 1.0:.1f} Q{cx:.1f},{cy - s * 2.6:.1f} {cx + s * 2.0:.1f},{cy - s * 1.0:.1f}" '
             f'fill="none" stroke="{color}" stroke-opacity="{op * 0.6:.2f}" stroke-width="{width * 0.8:.1f}" stroke-dasharray="14 10"/>')
    for (x, y) in d:
        b.append(f'<rect x="{x - s * 0.06:.1f}" y="{y - s * 0.06:.1f}" width="{s * 0.12:.1f}" height="{s * 0.12:.1f}" '
                 f'transform="rotate(45 {x:.1f} {y:.1f})" fill="{color}" fill-opacity="{op * 1.6:.2f}"/>')
    b.append(f'<circle cx="{cx}" cy="{cy}" r="{s * 0.1:.1f}" fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="{width}"/>')
    return "".join(b)


@painter
def twin_play(c: Card):
    green = "#2ECC71"
    cx0, cy0 = W * 0.50, H * 0.48
    backdrop(c, focus=(cx0, cy0), glow_k=0.25)
    c.svg(diamond_map_svg(cx0, cy0 + 60, 250, lighten(c.col, 0.2), 0.16, 5))
    # double-play arrow: bold curved arrow sweeping under the orbit
    pts = props.bezier((W * 0.12, H * 0.70), (W * 0.30, H * 0.98), (W * 0.70, H * 0.98), (W * 0.86, H * 0.66), 80)
    shaft = props.taper_path(pts[:-6], 46, 46)
    tip = pts[-1]
    dvec = pts[-1] - pts[-8]
    dvec /= np.linalg.norm(dvec)
    nv = np.array([-dvec[1], dvec[0]])
    head = [tuple(tip + dvec * 40), tuple(tip - dvec * 50 + nv * 62), tuple(tip - dvec * 50 - nv * 62)]
    arrow = props.inked(shaft + props.poly_d(head), c.col, INK, 9)
    arrow += f'<path d="{props.taper_path(pts[5:-10], 10, 10)}" fill="#FFF2B0" fill-opacity="0.7"/>'
    al = rasterize(svg_doc(W, H, arrow), W, H)
    c.add(from_mask(blur(al[..., 3], 16), c.col), 0.7)
    c.over(al)
    # orbit trails
    rx, ry, tilt = 270, 120, -14
    def orb(t):
        x, y = math.cos(t) * rx, math.sin(t) * ry
        a = math.radians(tilt)
        return cx0 + x * math.cos(a) - y * math.sin(a), cy0 + x * math.sin(a) + y * math.cos(a)
    for t0 in (0.35, 0.35 + math.pi):
        tp = np.array([orb(t0 - k * 0.022) for k in range(110)])[::-1]
        tr = props.taper_path(tp, 2, 70, 1.5)
        lay = rasterize(svg_doc(W, H, f'<path d="{tr}" fill="{green}"/>'), W, H)
        c.add(blur(lay, 16), 1.0)
        c.over(lay, 0.65)
        c.over(rasterize(svg_doc(W, H, f'<path d="{props.taper_path(tp, 1, 18, 1.5)}" fill="#D8FFE6"/>'), W, H), 0.9)
    for t0, rot in ((0.35, (0.4, 0.6, 0.2)), (0.35 + math.pi, (1.6, 0.2, 0.9))):
        bx, by = orb(t0)
        ball(c, 150, bx, by, rot=rot, glow=0.6, glow_col=green, rim="#B8FFD0", light=(0.3, 0.7, 0.6), bounce=green)
    c.add(fx.particles(W, H, 50, c.seed + 2, region=(60, 60, W - 60, H - 60), color=["#D8FFE6", "#FFFFFF", c.col],
                       size=(1.5, 4), sparkle_frac=0.4), 1.0)
    finish(c)


@painter
def field_vision(c: Card):
    cx0, cy0 = W * 0.5, H * 0.50
    backdrop(c, focus=(cx0, cy0), glow_k=0.25, bokeh=8)
    # tactical map
    gl = []
    for k in range(0, W, 64):
        gl.append(f'<line x1="{k}" y1="0" x2="{k}" y2="{H}" stroke="{c.col}" stroke-opacity="0.06" stroke-width="2"/>')
    for k in range(0, H, 64):
        gl.append(f'<line x1="0" y1="{k}" x2="{W}" y2="{k}" stroke="{c.col}" stroke-opacity="0.06" stroke-width="2"/>')
    c.svg("".join(gl))
    c.svg(diamond_map_svg(cx0, cy0 + 130, 230, "#7FD3FF", 0.28, 5))
    marks = []
    rng = c.rng(4)
    for k in range(7):
        mx, my = rng.uniform(W * 0.1, W * 0.9), rng.uniform(H * 0.15, H * 0.9)
        if math.hypot(mx - cx0, (my - cy0) * 1.6) < 300:
            continue
        if k % 2:
            marks.append(f'<path d="M{mx - 16},{my - 16} L{mx + 16},{my + 16} M{mx + 16},{my - 16} L{mx - 16},{my + 16}" stroke="#FF7A5A" stroke-opacity="0.7" stroke-width="6" stroke-linecap="round"/>')
        else:
            marks.append(f'<circle cx="{mx:.1f}" cy="{my:.1f}" r="16" fill="none" stroke="#7FD3FF" stroke-opacity="0.7" stroke-width="6"/>')
    marks.append(f'<path d="M{W * 0.18:.1f},{H * 0.80:.1f} Q{W * 0.25:.1f},{H * 0.55:.1f} {W * 0.33:.1f},{H * 0.72:.1f}" fill="none" stroke="{c.col}" stroke-opacity="0.6" stroke-width="5" stroke-dasharray="12 8"/>')
    c.svg("".join(marks))
    # eye
    ew, eh = 330, 150
    eye_d = (f"M{cx0 - ew:.1f},{cy0:.1f} C{cx0 - ew * 0.5:.1f},{cy0 - eh * 1.35:.1f} {cx0 + ew * 0.5:.1f},{cy0 - eh * 1.35:.1f} {cx0 + ew:.1f},{cy0:.1f} "
             f"C{cx0 + ew * 0.5:.1f},{cy0 + eh * 1.35:.1f} {cx0 - ew * 0.5:.1f},{cy0 + eh * 1.35:.1f} {cx0 - ew:.1f},{cy0:.1f}Z")
    eye_l = rasterize(svg_doc(W, H, f'<path d="{eye_d}" fill="#fff"/>'), W, H)
    c.add(fx.light_rays(W, H, cx0, cy0, 28, c.seed, lighten(c.col, 0.3), spread=0.5, opacity=(0.03, 0.14)), 1.0)
    c.add(from_mask(blur(eye_l[..., 3], 30), c.col), 1.0)
    defs = props.rad_grad("sc", [(0, "#FFFFFF"), (0.7, "#F4F1EA"), (1, "#B9C2D0")], 0.5, 0.5, 0.6)
    c.svg(f'<path d="{eye_d}" fill="{INK}" stroke="{INK}" stroke-width="22" stroke-linejoin="round"/><path d="{eye_d}" fill="url(#sc)"/>', defs)
    iris = (f'<circle cx="{cx0}" cy="{cy0}" r="146" fill="{INK}"/><circle cx="{cx0}" cy="{cy0}" r="139" fill="url(#ir)"/>')
    idefs = props.rad_grad("ir", [(0.80, "#FFE27A"), (0.92, PAL["gold"]), (1, "#B07010")], 0.5, 0.5, 0.5)
    irl = rasterize(svg_doc(W, H, iris, idefs), W, H)
    irl *= eye_l[..., 3:4]
    c.over(irl)
    b = render_ball(250, rot=(0.0, 0.25, 0.0), rim=c.col, rim_strength=0.5, light=(-0.3, 0.6, 0.8), bounce=c.col, spec=0.0)
    bs = b.shape[0]
    clip = rasterize(svg_doc(bs, bs, f'<path d="{eye_d}" transform="translate({bs / 2 - cx0:.1f},{bs / 2 - cy0:.1f})" fill="#fff"/>'), bs, bs)[..., 3]
    b = b * clip[..., None]
    c.place(b, cx0, cy0)
    lidsh = np.clip((grid(H, W)[1] - (cy0 - eh * 1.05)) / (eh * 0.9), 0, 1)
    c.over(from_mask(eye_l[..., 3] * (1 - lidsh) * 0.45, "#6A5A30"))
    hl = (f'<circle cx="{cx0 - 50:.1f}" cy="{cy0 - 52:.1f}" r="24" fill="#FFFFFF" fill-opacity="0.95"/>'
          f'<circle cx="{cx0 + 34:.1f}" cy="{cy0 + 40:.1f}" r="10" fill="#FFFFFF" fill-opacity="0.8"/>')
    # upper lid crease + lashes
    lid = f'<path d="M{cx0 - ew * 0.95:.1f},{cy0 - 20:.1f} C{cx0 - ew * 0.45:.1f},{cy0 - eh * 1.6:.1f} {cx0 + ew * 0.45:.1f},{cy0 - eh * 1.6:.1f} {cx0 + ew * 0.95:.1f},{cy0 - 20:.1f}" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round"/>'
    lashes = ""
    for k in range(7):
        t = (k + 1) / 8
        p0 = props.bezier((cx0 - ew, cy0), (cx0 - ew * 0.5, cy0 - eh * 1.35), (cx0 + ew * 0.5, cy0 - eh * 1.35), (cx0 + ew, cy0), 9)[k + 1]
        ang = math.radians(-90 + (t - 0.5) * 110)
        lashes += f'<path d="M{p0[0]:.1f},{p0[1]:.1f} L{p0[0] + math.cos(ang) * 46:.1f},{p0[1] + math.sin(ang) * 46:.1f}" stroke="{INK}" stroke-width="12" stroke-linecap="round"/>'
    c.svg(hl + lid + lashes)
    c.add(fx.particles(W, H, 40, c.seed + 2, region=(60, 60, W - 60, H - 60), color=["#FFFFFF", c.col], size=(1.5, 3.5),
                       sparkle_frac=0.4), 1.0)
    finish(c)


def gem_svg(cx, cy, s, light="#FFFFFF", mid="#9FD8FF", dark="#2F6FD8", ink=INK):
    """Brilliant-cut gem in side view: table, crown facets, pavilion facets."""
    tw, cw, ch, ph = s * 0.55, s, s * 0.32, s * 0.85
    T = cy - ch
    girdle = cy
    pts_outline = [(cx - tw / 2, T), (cx + tw / 2, T), (cx + cw / 2, girdle), (cx, girdle + ph), (cx - cw / 2, girdle)]
    p = [f'<path d="{props.poly_d(pts_outline)}" fill="{ink}" stroke="{ink}" stroke-width="{s * 0.05:.1f}" stroke-linejoin="round"/>']
    # crown facets
    crown = [((cx - tw / 2, T), (cx - cw / 2, girdle), (cx - cw * 0.25, girdle), light),
             ((cx - tw / 2, T), (cx - cw * 0.25, girdle), (cx, T), mid),
             ((cx, T), (cx - cw * 0.25, girdle), (cx + cw * 0.25, girdle), light),
             ((cx, T), (cx + cw * 0.25, girdle), (cx + tw / 2, T), mid),
             ((cx + tw / 2, T), (cx + cw * 0.25, girdle), (cx + cw / 2, girdle), dark)]
    for a, b_, c_, col in crown:
        p.append(f'<path d="{props.poly_d([a, b_, c_])}" fill="{col}"/>')
    pav = [((cx - cw / 2, girdle), (cx - cw * 0.25, girdle), (cx, girdle + ph), mid),
           ((cx - cw * 0.25, girdle), (cx, girdle), (cx, girdle + ph), light),
           ((cx, girdle), (cx + cw * 0.25, girdle), (cx, girdle + ph), mid),
           ((cx + cw * 0.25, girdle), (cx + cw / 2, girdle), (cx, girdle + ph), dark)]
    for a, b_, c_, col in pav:
        p.append(f'<path d="{props.poly_d([a, b_, c_])}" fill="{col}"/>')
    p.append(f'<path d="M{cx - tw / 2:.1f},{T:.1f} L{cx + tw / 2:.1f},{T:.1f}" stroke="#FFFFFF" stroke-width="{s * 0.03:.1f}"/>')
    p.append(f'<path d="M{cx - cw / 2:.1f},{girdle:.1f} L{cx + cw / 2:.1f},{girdle:.1f}" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="{s * 0.02:.1f}"/>')
    for a, b_ in (((cx - cw * 0.25, girdle), (cx, girdle + ph)), ((cx + cw * 0.25, girdle), (cx, girdle + ph)),
                  ((cx - tw / 2, T), (cx - cw * 0.25, girdle)), ((cx + tw / 2, T), (cx + cw * 0.25, girdle))):
        p.append(f'<path d="M{a[0]:.1f},{a[1]:.1f} L{b_[0]:.1f},{b_[1]:.1f}" stroke="{ink}" stroke-opacity="0.35" stroke-width="{s * 0.012:.1f}"/>')
    return "".join(p)


@painter
def diamond_aura(c: Card):
    blue = "#7FC8FF"
    hz = H * 0.42
    x, y = grid(H, W)
    c.img = opaque(gradient_map(np.clip(y / hz, 0, 1), [(0, "#070E1C"), (1, "#18264A")]))
    stadium_layer(c, hz + 2, rim=blue, seed=9, hs=0.6, glow=0.5, bottom=hz + 3)
    g = scene.Ground(W, H, hz, cam_h=3.0)
    grass = g.grass(seed=c.seed, light="#1F4A2C", dark="#173C24", stripe=2.0)
    # infield dirt diamond + bases
    Zc = 9.0
    dX, dZ = g.X, g.Z - Zc
    dia = np.abs(dX) + np.abs(dZ) * 1.0
    dirt = g.dirt(seed=c.seed, base=("#2E1A12", "#4A2C1C", "#653C26", "#7E5034"))
    infield = smoothstep(4.3, 4.1, dia)
    inner = smoothstep(2.9, 3.1, dia)
    m_dirt = infield * np.maximum(inner, 0)
    rgb = grass * (1 - m_dirt[..., None]) + dirt * m_dirt[..., None]
    pool = g.light_pool(0, Zc, 5)
    rgb = rgb * (0.45 + 0.9 * pool[..., None]) + hexrgb(blue) * (pool * 0.25)[..., None]
    fog = g.fog(40)[..., None]
    rgb = rgb * (1 - fog) + hexrgb("#18264A") * fog
    c.over(from_mask(g.mask, rgb))
    lines = "".join(f'<path d="{props.poly_d([g.project(*p) for p in seg], False)}" fill="none" stroke="#F2F0EA" stroke-width="5" stroke-opacity="0.8"/>'
                    for seg in ([(0, Zc - 3.6), (3.6, Zc)], [(0, Zc - 3.6), (-3.6, Zc)], [(3.6, Zc), (0, Zc + 3.6)], [(-3.6, Zc), (0, Zc + 3.6)]))
    c.svg(lines)
    c.svg("".join(props.base_bag_svg(g, X, Z, 0.5, 0.1) for X, Z in ((3.6, Zc), (0, Zc + 3.6), (-3.6, Zc))))
    c.svg(plate_svg(g, 0, Zc - 3.6, 0.55))
    # gem + beams
    gx, gy = W * 0.5, H * 0.34
    c.add(fx.light_rays(W, H, gx, gy, 34, c.seed, "#DDF0FF", spread=0.7, opacity=(0.04, 0.18)), 1.0)
    beams = []
    for X, Z in ((0, Zc - 3.6), (3.6, Zc), (-3.6, Zc), (0, Zc + 3.6)):
        px, py = g.project(X, Z)
        beams.append(f'<path d="M{gx - 8:.1f},{gy + 60:.1f} L{px - 26:.1f},{py:.1f} L{px + 26:.1f},{py:.1f} L{gx + 8:.1f},{gy + 60:.1f}Z" fill="#CFEAFF" fill-opacity="0.35"/>')
    bl = rasterize(svg_doc(W, H, "".join(beams)), W, H)
    c.add(blur(bl, 8), 1.0)
    halo = np.exp(-(radial(H, W, gx, gy, 260) ** 2))
    c.add(from_mask(halo, blue), 0.7)
    gm = rasterize(svg_doc(W, H, gem_svg(gx, gy, 260)), W, H)
    c.add(from_mask(blur(gm[..., 3], 24), blue), 1.0)
    c.over(gm)
    c.svg(fx.sparkle_svg(gx - 70, gy - 70, 46, "#FFFFFF", 1.0, 0.0, 0.12) + fx.sparkle_svg(gx + 90, gy + 30, 30, "#FFFFFF", 0.9, 0.3, 0.12))
    c.add(fx.particles(W, H, 90, c.seed + 2, region=(40, 40, W - 40, H - 40), color=["#FFFFFF", blue, c.col],
                       size=(1.5, 4), sparkle_frac=0.5), 1.0)
    finish(c)


@painter
def rally_cry(c: Card):
    gold = PAL["gold"]
    backdrop(c, focus=(W * 0.62, H * 0.45), glow_k=0.35)
    # golden shockwave arcs
    mx, my = W * 0.30, H * 0.42
    arcs = []
    for k, (r, wdt, op) in enumerate(((180, 26, 0.95), (290, 20, 0.75), (400, 15, 0.5), (510, 10, 0.3))):
        a0, a1 = math.radians(-50), math.radians(50)
        arcs.append(f'<path d="M{mx + math.cos(a0) * r:.1f},{my + math.sin(a0) * r:.1f} A{r},{r} 0 0 1 {mx + math.cos(a1) * r:.1f},{my + math.sin(a1) * r:.1f}" '
                    f'fill="none" stroke="{lighten(gold, 0.2)}" stroke-width="{wdt}" stroke-opacity="{op}" stroke-linecap="round"/>')
    al = rasterize(svg_doc(W, H, "".join(arcs)), W, H)
    c.add(from_mask(blur(al[..., 3], 18), gold), 1.2)
    c.over(al)
    c.add(fx.speed_lines(W, H, 0, n=30, seed=c.seed, color="#FFF2B0", length=(0.15, 0.35), width=(2, 6),
                         region=(mx + 100, my - 220, W, my + 220), opacity=(0.2, 0.6)), 0.8)
    # crowd silhouettes at the bottom, rim-lit gold
    crowd = scene.crowd_svg(W, H * 0.80, rows=3, seed=c.seed, color="#0A0F1A", arms=0.8, scale=1.5)
    cl = rasterize(svg_doc(W, H, crowd), W, H)
    c.add(from_mask(blur(cl[..., 3], 20), gold), 0.5)
    c.over(cl)
    c.add(from_mask(rim_mask(cl[..., 3], (0, -1), 4), gold), 0.9)
    # megaphone
    mp = []
    cone = f"M{mx - 230:.1f},{my - 40:.1f} L{mx - 10:.1f},{my - 120:.1f} L{mx - 10:.1f},{my + 120:.1f} L{mx - 230:.1f},{my + 40:.1f}Z"
    mp.append(props.inked(cone, "url(#mpg)", INK, 9))
    mp.append(f'<path d="M{mx - 150:.1f},{my - 69:.1f} L{mx - 110:.1f},{my - 84:.1f} L{mx - 110:.1f},{my + 84:.1f} L{mx - 150:.1f},{my + 69:.1f}Z" fill="#F4F1EA"/>')
    mp.append(f'<ellipse cx="{mx - 10:.1f}" cy="{my:.1f}" rx="34" ry="120" fill="{INK}" stroke="{INK}" stroke-width="18"/>')
    mp.append(f'<ellipse cx="{mx - 10:.1f}" cy="{my:.1f}" rx="26" ry="108" fill="#FFF2B0"/>')
    mp.append(f'<rect x="{mx - 270:.1f}" y="{my - 46:.1f}" width="50" height="92" rx="14" fill="{INK}" stroke="{INK}" stroke-width="18"/>'
              f'<rect x="{mx - 270:.1f}" y="{my - 46:.1f}" width="50" height="92" rx="14" fill="#2B2F36"/>')
    mp.append(f'<path d="M{mx - 180:.1f},{my + 40:.1f} L{mx - 190:.1f},{my + 130:.1f} L{mx - 150:.1f},{my + 130:.1f} L{mx - 140:.1f},{my + 40:.1f}" '
              f'fill="{INK}" stroke="{INK}" stroke-width="14" stroke-linejoin="round"/>')
    mp.append(f'<path d="M{mx - 210:.1f},{my - 30:.1f} L{mx - 30:.1f},{my - 98:.1f}" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="8" stroke-linecap="round"/>')
    defs = props.lin_grad("mpg", [(0, "#FF5A5F"), (0.5, PAL["scarlet"]), (1, PAL["scarlet_deep"])], 0, 0, 0, 1)
    c.add(from_mask(np.exp(-(radial(H, W, mx, my, 160) ** 2)), gold), 0.8)
    c.svg("".join(mp), defs)
    c.add(fx.particles(W, H, 70, c.seed + 2, region=(mx, 40, W - 40, H * 0.8), color=["#FFF2B0", "#FFFFFF", gold],
                       size=(1.5, 4.5), sparkle_frac=0.45), 1.0)
    finish(c)


@painter
def magnet_glove(c: Card):
    cx0, cy0 = W * 0.5, H * 0.52
    backdrop(c, focus=(cx0, cy0), glow_k=0.3)
    # dipole field lines
    fl = []
    for k in range(1, 6):
        r = 70 + k * 62
        for side in (-1, 1):
            fl.append(f'<ellipse cx="{cx0 + side * r * 0.95:.1f}" cy="{cy0:.1f}" rx="{r:.1f}" ry="{r * 0.62:.1f}" fill="none" '
                      f'stroke="{lighten(c.col, 0.35)}" stroke-width="{6 - k * 0.7:.1f}" stroke-opacity="{0.75 - k * 0.11:.2f}" stroke-dasharray="{30 + k * 6} 14"/>')
    fll = rasterize(svg_doc(W, H, "".join(fl)), W, H)
    c.add(from_mask(blur(fll[..., 3], 10), c.col), 1.0)
    c.over(fll)
    # baseballs pulled in from all sides
    rng = c.rng(3)
    for k, (bx, by, d) in enumerate(((W * 0.12, H * 0.25, 90), (W * 0.88, H * 0.22, 80), (W * 0.10, H * 0.78, 84),
                                     (W * 0.90, H * 0.74, 96), (W * 0.30, H * 0.10, 60), (W * 0.72, H * 0.92, 64))):
        motion_trail(c, bx + (bx - cx0) * 0.6, by + (by - cy0) * 0.6, bx, by, d * 0.9, c.col, 0.55, blur_s=3)
        ball(c, d, bx, by, rot=(k * 0.8, 0.4, k * 0.3), glow=0.4, rim_dir=(bx - cx0, cy0 - by, -0.2))
    # glove + crackling arcs
    defs, gl = props.glove()
    glay = rasterize(svg_doc(W, H, f'<g transform="translate({cx0:.1f},{cy0:.1f}) rotate(-8) scale(0.78) translate(-232,-250)">{gl}</g>', defs), W, H)
    c.add(from_mask(blur(glay[..., 3], 26), c.col), 1.1)
    c.over(glay)
    c.add(from_mask(rim_mask(glay[..., 3], (1, -0.6), 6), lighten(c.col, 0.5)), 1.0)
    gb, cb = [], []
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        p0 = (cx0 + math.cos(a) * 150, cy0 + math.sin(a) * 160)
        p1 = (cx0 + math.cos(a) * 300, cy0 + math.sin(a) * 260)
        g1, c1 = fx.lightning_svg(p0, p1, c.seed + k, 4, lighten(c.col, 0.2), branches=1, detail=5, rough=0.25)
        gb.append(g1)
        cb.append(c1)
    c.add(blur(rasterize(svg_doc(W, H, "".join(gb)), W, H), 8), 0.9)
    c.over(rasterize(svg_doc(W, H, "".join(cb)), W, H))
    c.add(fx.particles(W, H, 50, c.seed + 2, region=(60, 60, W - 60, H - 60), color=["#FFFFFF", c.col], size=(1.5, 4),
                       sparkle_frac=0.4), 1.0)
    finish(c)


@painter
def sky_hook(c: Card):
    cyan = "#29B6F6"
    hz = H * 0.84
    rgb = scene.sky(W, H, hz, scene.TWILIGHT, clouds=0.5, seed=c.seed)
    c.img = opaque(np.clip(rgb, 0, 1))
    c.add(fx.particles(W, H, 120, c.seed + 1, region=(0, 0, W, H * 0.55), color=["#FFFFFF", "#CFE8FF"], size=(0.8, 2.2),
                       sparkle_frac=0.15, opacity=(0.3, 0.9)), 1.0)
    stadium_layer(c, hz + 30, rim=cyan, seed=10, towers=3, hs=0.9, glow=0.6)
    # the hook: launch lower-left, apex high, curls down to the right
    p0, p1, p2, p3 = (W * 0.06, H * 0.86), (W * 0.20, H * -0.30), (W * 0.92, H * -0.18), (W * 0.74, H * 0.56)
    pts = props.bezier(p0, p1, p2, p3, 200)
    outer = props.taper_path(pts, 2, 120, 1.6)
    lay = rasterize(svg_doc(W, H, f'<path d="{outer}" fill="{cyan}"/>'), W, H)
    c.add(blur(lay, 26), 1.1)
    c.add(blur(lay, 6), 0.6)
    c.over(rasterize(svg_doc(W, H, f'<path d="{props.taper_path(pts, 1, 40, 1.6)}" fill="#E6F8FF"/>'), W, H), 0.95)
    # sparkle dust along the arc
    body = []
    rng = c.rng(5)
    for t in np.linspace(0.1, 0.95, 40):
        j = int(t * (len(pts) - 1))
        px, py = pts[j]
        off = rng.normal(0, 30 * t)
        body.append(fx.sparkle_svg(px + off, py + rng.normal(0, 20 * t), rng.uniform(4, 12) * (0.4 + t), "#FFFFFF", rng.uniform(0.5, 1), rng.uniform(0, 1)))
    c.add(rasterize(svg_doc(W, H, "".join(body)), W, H), 1.0)
    bx, by = pts[-1]
    dx, dy = pts[-1] - pts[-10]
    ball(c, 170, bx, by, rot=(0.9, 0.5, 0.2), glow=0.9, glow_col=cyan, rim="#B8ECFF", rim_dir=(-dx, dy, -0.2),
         light=(0.4, 0.7, 0.6), bounce=cyan)
    finish(c)


@painter
def seventh_inning_stretch(c: Card):
    gold = PAL["gold"]
    hz = H * 0.62
    rgb = scene.sky(W, H, hz, [(0.0, "#0B1430"), (0.45, "#2A2A6A"), (0.75, "#8A3A7A"), (1.0, "#F08A5A")], clouds=0.5, seed=c.seed)
    c.img = opaque(np.clip(rgb, 0, 1))
    lamps = stadium_layer(c, hz + 30, rim="#FFC07A", seed=11, towers=3, hs=1.2, glow=1.0)
    c.add(fx.light_rays(W, H, W * 0.5, -40, 20, c.seed, "#FFE7B0", spread=0.6, opacity=(0.02, 0.08)), 1.0)
    # pennant strings across the top
    pen = []
    for row, (y0, sag) in enumerate(((H * 0.10, 60), (H * 0.20, 40))):
        pts = props.bezier((-20, y0), (W * 0.3, y0 + sag), (W * 0.7, y0 + sag), (W + 20, y0), 60)
        pen.append(f'<path d="{props.poly_d(pts, False)}" fill="none" stroke="#F4F1EA" stroke-width="4"/>')
        cols = [PAL["scarlet"], "#F4F1EA", "#1C2E4A", gold]
        for k in range(1, 15):
            t = k / 15
            j = int(t * 59)
            px, py = pts[j]
            col = cols[(k + row) % 4]
            tri = [(px - 22, py), (px + 22, py), (px + 2, py + 58)]
            pen.append(props.inked(props.poly_d(tri), col, INK, 3))
    c.svg("".join(pen))
    # crowd with arms raised, rows getting closer, rim-lit by the stadium lights
    c.add(from_mask(np.exp(-(radial(H, W, W * 0.5, H * 0.72, 700, 160) ** 2)), "#FFB060"), 0.35)
    for row, (yb, sc, col, rimk) in enumerate(((H * 0.74, 2.2, "#1A2036", 0.5), (H * 0.86, 3.2, "#10152A", 0.8),
                                             (H * 1.02, 4.4, "#080C18", 1.0))):
        cr = scene.crowd_svg(W, yb, rows=1, seed=c.seed + row * 7, color=col, arms=1.0, scale=sc, x0=-30 * sc)
        cl = rasterize(svg_doc(W, H, cr), W, H)
        c.over(cl)
        c.add(from_mask(rim_mask(cl[..., 3], (0.2, -1), 3 + row * 2), "#FFC07A"), rimk)
    # popcorn flying
    rng = c.rng(6)
    pc = []
    for k in range(26):
        px, py = rng.uniform(60, W - 60), rng.uniform(H * 0.30, H * 0.70)
        r = rng.uniform(6, 11)
        blob = "".join(f'<circle cx="{px + math.cos(a) * r * 0.6:.1f}" cy="{py + math.sin(a) * r * 0.6:.1f}" r="{r * 0.62:.1f}"/>'
                       for a in np.linspace(0, 2 * math.pi, 5)[:-1])
        pc.append(f'<g fill="{INK}" stroke="{INK}" stroke-width="5">{blob}</g>')
        pc.append(f'<g fill="#FFF0C0">{blob}</g><circle cx="{px - r * 0.2:.1f}" cy="{py - r * 0.2:.1f}" r="{r * 0.25:.1f}" fill="#FFFFFF"/>'
                  f'<circle cx="{px + r * 0.3:.1f}" cy="{py + r * 0.3:.1f}" r="{r * 0.22:.1f}" fill="#F5B82E"/>')
    c.svg("".join(pc))
    # popcorn box in the corner
    bx0, by0 = W * 0.84, H * 0.80
    box = [(bx0 - 70, by0 - 110), (bx0 + 70, by0 - 110), (bx0 + 52, by0 + 120), (bx0 - 52, by0 + 120)]
    stripes = "".join(f'<path d="{props.poly_d([(bx0 - 70 + 35 * k, by0 - 110), (bx0 - 52 + 26 * k, by0 + 120), (bx0 - 52 + 26 * k + 13, by0 + 120), (bx0 - 70 + 35 * k + 17.5, by0 - 110)])}" fill="#F4F1EA"/>' for k in range(4))
    kernels = "".join(f'<circle cx="{bx0 + rng.uniform(-60, 60):.1f}" cy="{by0 - 112 - rng.uniform(0, 34):.1f}" r="{rng.uniform(12, 18):.1f}" fill="#FFF4D0" stroke="{INK}" stroke-width="3"/>' for _ in range(14))
    c.svg(kernels + props.inked(props.poly_d(box), PAL["scarlet"], INK, 7) + stripes)
    finish(c)


def rounded_rect_sdf(h, w, x0, y0, x1, y1, r):
    """Signed distance (px) to a rounded rectangle (negative inside)."""
    x, y = grid(h, w)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(x + 0.5 - cx) - hx, np.abs(y + 0.5 - cy) - hy
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - r


def build_frame_glow(path):
    """300x400 soft white rounded-rect glow ring around a 256x352 card (tint at runtime)."""
    S = 4
    Wg, Hg = 300 * S, 400 * S
    d = rounded_rect_sdf(Hg, Wg, 22 * S, 24 * S, 278 * S, 376 * S, 16 * S) / S
    outer = np.exp(-np.maximum(d, 0) / 7.0) * smoothstep(21.5, 14, d)
    inner = np.exp(-np.maximum(-d, 0) / 3.0)
    a = np.where(d >= 0, outer, inner).astype(np.float32)
    lay = from_mask(np.clip(a, 0, 1), "#FFFFFF")
    save(lay, path, size=(300, 400))


def build_back(path):
    """256x352 card back: navy, diamond emblem with ball, logo mark."""
    from PIL import Image
    S = 4
    Wb, Hb = 256 * S, 352 * S
    x, y = grid(Hb, Wb)
    d = radial(Hb, Wb, Wb / 2, Hb * 0.45, Wb * 0.75, Hb * 0.6)
    rgb = gradient_map(np.clip(d, 0, 1), [(0, "#22385C"), (0.6, PAL["navy"]), (1, PAL["navy_dark"])])
    lay = opaque(rgb)
    # diagonal stitch lattice texture
    pat = []
    for k in range(-Hb, Wb + Hb, 64):
        pat.append(f'<path d="M{k},0 L{k + Hb},{Hb}" stroke="#FFFFFF" stroke-opacity="0.035" stroke-width="6"/>')
        pat.append(f'<path d="M{k},0 L{k - Hb},{Hb}" stroke="#FFFFFF" stroke-opacity="0.035" stroke-width="6"/>')
    lay = over(lay, rasterize(svg_doc(Wb, Hb, "".join(pat)), Wb, Hb))
    # halftone corners in scarlet
    field = np.maximum(smoothstep(0.5, 0.0, radial(Hb, Wb, 0, 0, Wb, Hb)), smoothstep(0.5, 0.0, radial(Hb, Wb, Wb, Hb, Wb, Hb)))
    lay = add(lay, from_mask(fx.halftone_mask(Wb, Hb, field * 0.8, spacing=26, angle_deg=45), PAL["scarlet"]), 0.35)
    # borders
    border = (f'<rect x="{14 * S}" y="{14 * S}" width="{Wb - 28 * S}" height="{Hb - 28 * S}" rx="{10 * S}" fill="none" stroke="{PAL["gold"]}" stroke-width="{2.2 * S}"/>'
              f'<rect x="{20 * S}" y="{20 * S}" width="{Wb - 40 * S}" height="{Hb - 40 * S}" rx="{7 * S}" fill="none" stroke="{PAL["scarlet"]}" stroke-width="{1.2 * S}" stroke-opacity="0.9"/>')
    for (cx, cy) in ((30, 30), (226, 30), (30, 322), (226, 322)):
        X, Y = cx * S, cy * S
        r = 6 * S
        border += f'<path d="M{X},{Y - r} L{X + r},{Y} L{X},{Y + r} L{X - r},{Y}Z" fill="{PAL["gold"]}"/>'
    lay = over(lay, rasterize(svg_doc(Wb, Hb, border), Wb, Hb))
    # emblem: brush swoosh + diamond + ball
    cx, cy = Wb / 2, Hb * 0.43
    lay = add(lay, from_mask(np.exp(-(radial(Hb, Wb, cx, cy, 95 * S) ** 2)), PAL["scarlet"]), 0.35)
    lay = add(lay, fx.light_rays(Wb, Hb, cx, cy, 24, 3, "#9FC4FF", spread=0.4, opacity=(0.01, 0.04)), 1.0)
    s_ = 82 * S
    dia = [(cx, cy - s_), (cx + s_, cy), (cx, cy + s_), (cx - s_, cy)]
    emb = (f'<path d="{props.poly_d(dia)}" fill="{PAL["navy_dark"]}" fill-opacity="0.85" stroke="{INK}" stroke-width="{16 * S}" stroke-linejoin="round"/>'
           f'<path d="{props.poly_d(dia)}" fill="none" stroke="#F4F1EA" stroke-width="{5 * S}" stroke-linejoin="round"/>')
    for (bx, by) in dia:
        r = 9 * S
        emb += f'<path d="M{bx},{by - r} L{bx + r},{by} L{bx},{by + r} L{bx - r},{by}Z" fill="#F4F1EA" stroke="{INK}" stroke-width="{2.5 * S}"/>'
    lay = over(lay, rasterize(svg_doc(Wb, Hb, emb), Wb, Hb))
    b = render_ball(92 * S, rot=(0.5, 0.6, 0.3), rim="#FF8A5A", rim_strength=0.8, bounce=PAL["scarlet"], light=(-0.4, 0.7, 0.6))
    gl = blank(int(150 * S), int(150 * S))
    gl = place(gl, b, gl.shape[1] / 2, gl.shape[0] / 2)
    lay = place(lay, from_mask(blur(gl[..., 3], 12 * S), "#FF8A5A"), cx, cy, "add", 0.8)
    lay = place(lay, b, cx, cy)
    # logo mark
    lp = TEX_DIR / "logo" / "logo.png"
    if lp.exists():
        L = Image.open(lp).convert("RGBA")
        lw = int(196 * S)
        L = L.resize((lw, int(L.height * lw / L.width)), Image.LANCZOS)
        arr = np.asarray(L).astype(np.float32) / 255.0
        arr[..., :3] *= arr[..., 3:4]
        lay = place(lay, arr, cx, Hb * 0.80)
    # rounded card corners
    sd = rounded_rect_sdf(Hb, Wb, 0, 0, Wb, Hb, 14 * S)
    lay = lay * np.clip(0.5 - sd, 0, 1)[..., None]
    save(lay, path, size=(256, 352))


# ---------------------------------------------------------------------------
def build(only=None, out_dir=OUT):
    cards = load_cards()
    done = []
    for info in cards:
        if only and info["id"] not in only:
            continue
        fn = PAINTERS.get(info["id"])
        if fn is None:
            print(f"  ! no painter for {info['id']}")
            continue
        c = Card(info)
        fn(c)
        p = save(c.img, out_dir / f"{info['id']}.png", size=(512, 384), opaque_out=True)
        done.append(p)
        print(f"  card {info['id']}")
    if not only:
        build_back(out_dir / "card_back.png")
        build_frame_glow(out_dir / "card_frame_glow.png")
        done += [out_dir / "card_back.png", out_dir / "card_frame_glow.png"]
        print("  card back + frame glow")
    return done


if __name__ == "__main__":
    build(set(sys.argv[1:]) or None)
