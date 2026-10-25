"""Card illustrations v2 (512x384): one bold subject per card, poster style.

Rendering language (shared by every card):
  * background  - category-tinted radial gradient + a crisp comic sunburst centred
                  on the subject; nothing else (no stadium scenes).
  * objects     - thick, uniform ink outline (silhouette dilation), flat fills with
                  one cel shade, key light from the upper left, a bright rim light
                  in the category colour on the lower-right edge and a back glow.
  * energy      - trails, shockwaves, lightning and auras are pure light: no outline,
                  additive glow + white-hot core.
  * rarity      - scales the energy: more rays, brighter bloom, rarity-coloured
                  accents (epic violet, legendary gold) and sparkles.

Painted at 2x (1024x768) and downsampled. The important content stays inside the
central band y = 70..700 (2x) so the art also survives a 1.6:1 cover-crop.
The previous, detailed generator (cards.py) still builds the card back and the
frame glow.
"""
from __future__ import annotations

import json
import math
import sys
import zlib

import numpy as np

from artlib.baseball import render_ball
from artlib.core import (CATEGORY, RARITY, ROOT, STITCH_RED, TEX_DIR, add, blank, blur, darken, from_mask,
                         gradient_map, grid, hexrgb, lighten, mix_hex, opaque, over, place, rasterize, save,
                         smoothstep, svg_doc)
from artlib import fx, props

W, H = 1024, 768
OUT = TEX_DIR / "cards"
LEVEL = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}
INK = "#070D17"
OW = 15            # object outline (px at 2x)
GOLD = "#FFC43D"
VIOLET = "#B45CFF"


def load_cards():
    return json.loads((ROOT / "data" / "cards.json").read_text())["cards"]


def lay(body, defs=""):
    return rasterize(svg_doc(W, H, body, defs), W, H)


def dilate(mask, r):
    """Octagonal max-dilation of a coverage mask by r pixels (keeps antialiasing)."""
    out = mask.copy()
    for i in range(int(r)):
        m = out.copy()
        np.maximum(m[1:], out[:-1], out=m[1:])
        np.maximum(m[:-1], out[1:], out=m[:-1])
        np.maximum(m[:, 1:], out[:, :-1], out=m[:, 1:])
        np.maximum(m[:, :-1], out[:, 1:], out=m[:, :-1])
        if i % 2 == 1:
            np.maximum(m[1:, 1:], out[:-1, :-1], out=m[1:, 1:])
            np.maximum(m[:-1, :-1], out[1:, 1:], out=m[:-1, :-1])
            np.maximum(m[1:, :-1], out[:-1, 1:], out=m[1:, :-1])
            np.maximum(m[:-1, 1:], out[1:, :-1], out=m[:-1, 1:])
        out = m
    return out


def edge_band(mask, direction, width):
    """Inner band of `mask` on the side facing `direction`."""
    dx, dy = direction
    n = math.hypot(dx, dy)
    sx, sy = int(round(dx / n * width)), int(round(dy / n * width))
    sh = np.zeros_like(mask)
    ys = slice(max(0, -sy), H - max(0, sy))
    yd = slice(max(0, sy), H - max(0, -sy))
    xs = slice(max(0, -sx), W - max(0, sx))
    xd = slice(max(0, sx), W - max(0, -sx))
    sh[ys, xs] = mask[yd, xd]
    return np.clip(mask - sh, 0, 1)


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
        self.img = opaque(np.zeros((H, W, 3), np.float32))
        # accent: epic -> violet, legendary -> gold, else the category colour
        self.acc = {3: VIOLET, 4: GOLD}.get(self.lv, self.col)

    def over(self, layer, k=1.0):
        self.img = over(self.img, layer, k)

    def add(self, layer, k=1.0):
        self.img = add(self.img, layer, k)

    def rng(self, salt=0):
        return np.random.default_rng(self.seed + salt)


# ---------------------------------------------------------------------------
# Shared building blocks
# ---------------------------------------------------------------------------
def backdrop(c: Card, focus=(W * 0.5, H * 0.5), col=None, rays=None, ray_k=1.0, spin=0.0, bright=1.0, stops=None):
    col = col or c.col
    fx_, fy = focus
    x, y = grid(H, W)
    d = np.sqrt(((x - fx_) / (W * 0.62)) ** 2 + ((y - fy) / (W * 0.62)) ** 2)
    stops = stops or [(0.0, lighten(col, 0.10)), (0.22, darken(col, 0.18)), (0.55, darken(col, 0.62)),
                      (1.0, darken(col, 0.86))]
    rgb = gradient_map(np.clip(d / bright, 0, 1), stops)
    # comic sunburst: alternating wedges, strongest mid-range
    n = rays or (14 + 2 * c.lv)
    ang = np.arctan2(y - fy, x - fx_) + spin
    s = np.sin(ang * n)
    wedge = smoothstep(-0.06, 0.06, s)
    fade = smoothstep(0.05, 0.35, d) * smoothstep(1.25, 0.45, d)
    rgb = rgb + hexrgb(lighten(col, 0.45)) * (wedge * fade * (0.07 + 0.012 * c.lv) * ray_k)[..., None]
    if c.lv >= 3:   # second, finer burst in the rarity accent
        s2 = np.sin(ang * n * 2 + 0.7)
        w2 = smoothstep(0.75, 0.9, s2) * smoothstep(0.12, 0.5, d) * smoothstep(1.2, 0.5, d)
        rgb = rgb + hexrgb(c.acc) * (w2 * 0.10 * (c.lv - 2))[..., None]
    # floor shadow at the very bottom so the in-game gradient band blends
    rgb = rgb * (1 - smoothstep(0.75, 1.0, y / H) * 0.25)[..., None]
    c.img = opaque(np.clip(rgb, 0, 1))


def subject(c: Card, layer, ow=OW, glow=1.0, glow_col=None, rim=True, rim_col=None, rim_dir=(1.0, 0.65),
            rim_w=11, rim_k=0.9, outline=True):
    """Composite a solid object: back glow, uniform ink outline, the art, rim light."""
    a = layer[..., 3]
    sil = dilate(a, ow) if outline else a
    gc = glow_col or c.col
    if glow:
        c.add(from_mask(blur(sil, 70), gc), 0.55 * glow * (1 + 0.15 * c.lv))
        c.add(from_mask(blur(sil, 22), lighten(gc, 0.25)), 0.55 * glow)
    if outline:
        c.over(from_mask(sil, INK))
    c.over(layer)
    if rim:
        band = blur(edge_band(a, rim_dir, rim_w), 1.2) * a
        c.add(from_mask(band, rim_col or lighten(c.col, 0.6)), rim_k)
    return sil


def energy(c: Card, layer, col=None, core=0.9, glow=1.0, wide=1.0):
    """Composite light: wide glow + tight glow + the layer itself, all additive."""
    col = col or c.col
    a = layer[..., 3]
    c.add(from_mask(blur(a, 34 * wide), col), 0.7 * glow)
    c.add(from_mask(blur(a, 9 * wide), lighten(col, 0.3)), 0.6 * glow)
    c.add(layer, core)


def taper(pts, w0, w1, power=1.0):
    return props.taper_path(np.asarray(pts, float), w0, w1, power)


def arc_pts(cx, cy, rx, ry, a0, a1, n=80):
    t = np.radians(np.linspace(a0, a1, n))
    return np.stack([cx + np.cos(t) * rx, cy + np.sin(t) * ry], 1)


def trail(c: Card, pts, w0, w1, col=None, core="#FFFFFF", glow=1.0, power=1.0, core_k=0.85):
    """Comet trail of light along pts (tail first) widening from w0 to w1."""
    col = col or lighten(c.col, 0.2)
    outer = lay(f'<path d="{taper(pts, w0, w1, power)}" fill="{col}"/>')
    pts = np.asarray(pts, float)
    k0 = len(pts) // 4
    inner = lay(f'<path d="{taper(pts[k0:], w0 * 0.3, w1 * 0.42, power)}" fill="{core}"/>')
    c.add(from_mask(blur(outer[..., 3], 30), col), 0.65 * glow)
    c.add(blur(outer, 2.5), 0.75 * glow)
    c.add(blur(inner, 2.0), core_k)


def ball_layer(diam, x, y, rot=(0.6, 0.5, 0.3), rim="#FFFFFF", bounce=None, **kw):
    b = render_ball(diam, rot=rot, rim=rim, bounce=bounce, outline=0.025, **kw)
    return place(blank(H, W), b, x, y)


def speed(c: Card, angle, n=26, col="#FFFFFF", k=0.55, region=None, width=(3, 9), length=(0.15, 0.45), seed=0):
    sl = fx.speed_lines(W, H, angle, n=n, seed=c.seed + seed, color=col, length=length, width=width,
                        region=region, opacity=(0.35, 0.9))
    c.add(sl, k)


def sparkles(c: Card, n, region=(60, 60, W - 60, H - 60), col=None, size=(2.5, 6.0), k=1.0, seed=0):
    col = col or ["#FFFFFF", lighten(c.acc, 0.4)]
    c.add(fx.particles(W, H, n, c.seed + 900 + seed, region=region, color=col, size=size, sparkle_frac=0.55,
                       opacity=(0.5, 1.0)), k)


def ring(cx, cy, rx, ry, w, col, op=1.0, rot=0.0):
    return fx.ring_svg(cx, cy, rx, ry, w, col, op, rot)


def glove_svg(x, y, scale, rot, **kw):
    defs, body = props.glove(**kw)
    return defs, (f'<g transform="translate({x:.1f},{y:.1f}) rotate({rot:.1f}) scale({scale:.3f}) '
                  f'translate(-210,-230)">{body}</g>')


def finish(c: Card, bloom=1.0, vignette=0.6):
    rgb = c.img[..., :3]
    lum = rgb.max(-1)
    bright = rgb * smoothstep(0.55, 1.0, lum)[..., None]
    e = 1 + 0.18 * c.lv
    rgb = rgb + (blur(bright, 9) * 0.22 + blur(bright, 36) * 0.22) * bloom * e
    x, y = grid(H, W)
    d = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    v = smoothstep(0.55, 1.45, d) * vignette
    rgb = rgb * (1 - v[..., None]) + hexrgb(darken(c.col, 0.9)) * v[..., None] * 0.5
    rgb = np.maximum(rgb, 0)
    rgb = np.where(rgb < 0.82, rgb, 0.82 + 0.18 * (1 - np.exp(-(rgb - 0.82) / 0.18)))
    rgb = rgb + fx.grain(H, W, c.seed, 0.008)[..., None]
    c.img = opaque(np.clip(rgb, 0, 1))


def final_sparkles(c: Card):
    if c.lv >= 3:
        sparkles(c, 14 + 14 * (c.lv - 3), k=0.9)


# ---------------------------------------------------------------------------
# Painters
# ---------------------------------------------------------------------------
PAINTERS = {}


def painter(fn):
    PAINTERS[fn.__name__] = fn
    return fn


def flame_ball(c: Card, x, y, d, direction, length=3.4, n=18, rot=(0.5, 0.7, 0.2), spread=42, glow=1.0):
    tg = fx.fireball_tongues(x, y, d / 2, direction, n=n, length=length, seed=c.seed + int(x), spread=spread)
    fl = lay(fx.flames_svg(tg))
    c.add(from_mask(blur(fl[..., 3], 34), "#FF4A1A"), 0.8 * glow)
    c.over(fl)
    b = ball_layer(d, x, y, rot=rot, rim="#FFC56A", bounce="#FF6A2A", rim_strength=1.1,
                   rim_dir=(-math.cos(math.radians(direction)), math.sin(math.radians(direction)), -0.2))
    subject(c, b, glow=0.6, glow_col="#FF7A2A", rim=False, ow=10)


@painter
def heat_wave(c: Card):
    bx, by = 730, 370
    backdrop(c, (bx - 60, by))
    # heat ripples behind the fireball
    rp = "".join(f'<path d="M{60 + i * 18},{by + o} C{260},{by + o - 60} {420},{by + o + 60} {600},{by + o}" fill="none" '
                 f'stroke="#FFD27A" stroke-width="{7 - abs(i) * 1.2:.1f}" stroke-linecap="round"/>'
                 for i, o in ((0, -170), (1, 175), (2, -235), (3, 235)))
    energy(c, lay(rp), "#FF8A3A", core=0.5, glow=0.7)
    flame_ball(c, bx, by, 230, 0, length=5.0, n=28, spread=30, glow=1.2)
    speed(c, 0, n=16, col="#FFE2A8", k=0.35, region=(0, 120, 520, 640))
    finish(c)


@painter
def power_throw(c: Card):
    bx, by = 650, 384
    backdrop(c, (bx, by))
    trail(c, [(40, 470), (bx, by)], 0, 300, col="#FFB08A")
    speed(c, -8, n=22, k=0.55, region=(0, 160, 560, 620))
    # sonic-boom ring around the ball
    rg = lay(ring(bx - 70, by, 70, 230, 16, "#FFFFFF", 1.0) + ring(bx - 190, by, 45, 165, 9, "#FFFFFF", 0.7))
    energy(c, rg, "#FFB08A", core=0.9)
    subject(c, ball_layer(320, bx, by, rot=(0.3, 0.9, 0.2), bounce=c.col), glow=1.0)
    finish(c)


@painter
def splitter(c: Card):
    sx, sy = 240, 400
    backdrop(c, (sx + 80, sy))
    ends = [(735, 180), (820, 410), (720, 625)]
    for (ex, ey) in ends:
        pts = props.bezier((sx, sy), (sx + 200, sy), (ex - 220, ey), (ex, ey), 60)
        trail(c, pts, 30, 150, col="#FFB08A", glow=0.8)
    burst = lay(fx.comic_burst_svg(sx + 40, sy, 150, seed=4, points=10,
                                   colors=("#FF5A36", "#FF9A4A", "#FFE08A", "#FFFFFF"), squash=1.0))
    energy(c, burst, "#FF8A4A", core=1.0, glow=0.8)
    balls = blank(H, W)
    for i, (ex, ey) in enumerate(ends):
        balls = over(balls, ball_layer(175, ex, ey, rot=(0.4 + i, 0.6, 0.3 * i), bounce=c.col))
    balls = over(balls, ball_layer(200, sx, sy, rot=(0.9, 0.3, 0.6), bounce=c.col))
    subject(c, balls)
    finish(c)


@painter
def grand_slam_barrage(c: Card):
    backdrop(c, (560, 330), stops=[(0, "#FFE08A"), (0.18, "#FF9A3A"), (0.45, "#C2322E"), (0.75, "#4A1236"),
                                   (1.0, "#1A0818")], ray_k=1.4)
    # gold light rays from the top right
    c.add(fx.light_rays(W, H, 900, -60, 18, c.seed, GOLD, spread=0.7, opacity=(0.04, 0.12)), 1.0)
    # stadium silhouette as one bold shape
    st = lay(f'<path d="M-20,{H + 20} L-20,640 Q{W / 2},540 {W + 20},640 L{W + 20},{H + 20}Z" fill="#14060F"/>'
             + "".join(f'<rect x="{x - 9}" y="{y}" width="18" height="{650 - y}" fill="#14060F"/>'
                       f'<rect x="{x - 34}" y="{y - 22}" width="68" height="30" rx="4" fill="#14060F"/>'
                       f'<rect x="{x - 28}" y="{y - 16}" width="56" height="16" rx="3" fill="#FFE9B0"/>'
                       for x, y in ((120, 470), (905, 470))))
    c.over(st)
    c.add(from_mask(blur(edge_band(st[..., 3], (0, -1), 6), 2), "#FFB347"), 1.0)
    for (x, y, d) in ((800, 210, 120), (230, 150, 95), (360, 430, 250)):
        flame_ball(c, x, y, d, 135, length=3.0, n=18, spread=34)
    # impact flashes on the stadium rim
    imp = lay(fx.comic_burst_svg(170, 610, 80, seed=2, points=9, colors=("#FF5A1F", "#FFC93C", "#FFFFFF"), squash=0.55)
              + fx.comic_burst_svg(640, 575, 70, seed=5, points=9, colors=("#FF5A1F", "#FFC93C", "#FFFFFF"), squash=0.55))
    energy(c, imp, "#FF8A2A", core=1.0)
    finish(c, bloom=1.2)
    final_sparkles(c)


@painter
def grand_relay(c: Card):
    nodes = [(120, 600), (360, 220), (590, 560), (835, 300)]
    backdrop(c, (835, 300))
    pts = []
    for (a, b) in zip(nodes[:-1], nodes[1:]):
        for t in np.linspace(0, 1, 30, endpoint=False):
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    pts.append(nodes[-1])
    pts = np.array(pts)
    gold = lay(f'<path d="{taper(pts, 18, 130)}" fill="{GOLD}"/>')
    energy(c, gold, GOLD, core=0.0, glow=1.2)
    c.add(blur(gold, 2), 0.9)
    core = lay(f'<path d="{taper(pts, 5, 46)}" fill="#FFFFFF"/>')
    c.add(blur(core, 1.5), 0.9)
    rings = "".join(ring(x, y, 46 + 14 * i, 46 + 14 * i, 12, "#FFF2B8", 1.0) for i, (x, y) in enumerate(nodes[:-1]))
    energy(c, lay(rings), GOLD, core=1.0)
    subject(c, ball_layer(220, *nodes[-1], rot=(0.4, 0.7, 0.3), base="#FFE9A8", shadow="#C58A1A",
                          rim="#FFF6D0", bounce=GOLD), glow=1.3, glow_col=GOLD, rim_col="#FFF6D0")
    finish(c, bloom=1.2)
    final_sparkles(c)


@painter
def power_catch(c: Card):
    gx, gy = 512, 330
    backdrop(c, (gx, 600))
    # shockwave on the ground
    sw = lay(ring(gx, 620, 330, 70, 18, "#FFFFFF") + ring(gx, 625, 455, 100, 9, "#FFFFFF", 0.6))
    energy(c, sw, "#E07BFF", core=0.9)
    # cracks
    rng = c.rng(3)
    cr = []
    for k in range(9):
        a = math.radians(-180 + k * 22.5 + rng.uniform(-6, 6))
        p = [(gx, 615)]
        for s in range(4):
            r = 70 + s * 80
            p.append((gx + math.cos(a) * r * 1.4 + rng.uniform(-15, 15), 615 - math.sin(a) * r * 0.3 + rng.uniform(-8, 8)))
        cr.append(f'<path d="{taper(p, 16, 2)}" fill="#FFE6C0"/>')
    energy(c, lay("".join(cr)), "#FF8A4A", core=0.9, glow=0.8)
    imp = lay(fx.comic_burst_svg(gx, 600, 260, seed=3, points=12, colors=("#FF5A36", "#FFB36A", "#FFFFFF"), squash=0.32))
    energy(c, imp, "#FF8A4A", core=0.9, glow=0.8)
    speed(c, 90, n=18, col="#FFFFFF", k=0.5, region=(200, 0, 820, 260), width=(4, 10))
    defs, g = glove_svg(gx, gy, 0.98, 180, leather="#C46A2C", dark="#6E3714", light="#F0A866")
    subject(c, lay(g, defs), glow=1.1)
    finish(c)


@painter
def thunderbolt(c: Card):
    bx, by = 512, 384
    backdrop(c, (bx, by), col="#FF7A2A")
    glow_b, core_b = [], []
    for i, ang in enumerate((-160, -100, -35, 20, 85, 150)):
        a = math.radians(ang)
        p0 = (bx + math.cos(a) * 110, by + math.sin(a) * 110)
        p1 = (bx + math.cos(a) * 560, by + math.sin(a) * 470)
        gb, cb = fx.lightning_svg(p0, p1, c.seed + i * 11, 11, "#FFE14A", branches=2, detail=5, rough=0.2)
        glow_b.append(gb)
        core_b.append(cb)
    c.add(from_mask(blur(lay("".join(glow_b))[..., 3], 18), "#FFC21A"), 0.9)
    c.over(lay("".join(core_b)))
    halo = lay(ring(bx, by, 170, 170, 14, "#FFF6B0"))
    energy(c, halo, "#FFD21A", core=0.8)
    subject(c, ball_layer(270, bx, by, rot=(0.5, 0.6, 0.4), base="#FFF07A", shadow="#E0A21A", stitch="#C2261C",
                          rim="#FFFFFF", bounce="#FFB21A"), glow=1.4, glow_col="#FFD21A", rim_col="#FFFFFF")
    finish(c, bloom=1.2)
    final_sparkles(c)


@painter
def curveball(c: Card):
    bx, by = 720, 470
    backdrop(c, (bx, by))
    pts = props.bezier((70, 150), (520, 30), (760, 220), (bx, by), 90)
    trail(c, pts, 0, 250, col="#B8AEFF")
    spin = lay(ring(bx, by, 190, 190, 12, "#FFFFFF", 0.0) +
               f'<path d="{taper(arc_pts(bx, by, 185, 185, 200, 330), 2, 18)}" fill="#FFFFFF"/>'
               f'<path d="{taper(arc_pts(bx, by, 185, 185, 20, 150), 2, 18)}" fill="#FFFFFF"/>')
    energy(c, spin, "#B8AEFF", core=0.9, glow=0.8)
    subject(c, ball_layer(270, bx, by, rot=(0.9, 0.2, 0.9), bounce=c.col))
    finish(c)


@painter
def knuckleball(c: Card):
    bx, by = 650, 400
    backdrop(c, (bx, by))
    xs = np.linspace(40, bx, 120)
    pts = np.stack([xs, by + np.sin((xs - 40) / 70) * 60 * (1 - (xs - 40) / (bx - 40)) ** 0.5], 1)
    trail(c, pts, 0, 170, col="#B8AEFF")
    # wobble marks around the ball
    wb = "".join(f'<path d="{taper(arc_pts(bx, by, 175, 175, a, a + 50), 2, 16)}" fill="#FFFFFF"/>' for a in (-130, 60, 160))
    energy(c, lay(wb), "#C8BEFF", core=0.9, glow=0.7)
    q = ""
    for (x, y, s, r) in ((300, 230, 230, -14), (870, 610, 190, 16)):
        d, e = props.glyph_d("?", "Bangers", s)
        q += (f'<g transform="translate({x},{y}) rotate({r}) translate({-e["width"] / 2 - e["x_bearing"]:.1f},'
              f'{-e["height"] / 2 - e["y_bearing"]:.1f})"><path d="{d}" fill="#FFE14A"/></g>')
    subject(c, lay(q), glow=0.6, glow_col="#FFE14A", rim_col="#FFFFFF")
    subject(c, ball_layer(260, bx, by, rot=(0.2, 1.1, 0.7), bounce=c.col))
    finish(c)


@painter
def shadow_change(c: Card):
    bx, by = 660, 380
    backdrop(c, (bx, by), col="#8A5CFF")
    # shadow wisps streaming back to the left
    rng = c.rng(5)
    ws = []
    for i in range(7):
        oy = (i - 3) * 55
        p = props.bezier((bx, by + oy * 0.4), (bx - 250, by + oy * 0.8 + rng.uniform(-40, 40)),
                         (bx - 450, by + oy * 1.6 + rng.uniform(-60, 60)), (30, by + oy * 2.2), 60)
        ws.append(f'<path d="{taper(p, 120 - abs(i - 3) * 22, 0, 0.8)}" fill="#1A0B33"/>')
    smoke = lay("".join(ws))
    c.add(from_mask(blur(smoke[..., 3], 30), "#B07AF0"), 0.6)
    c.over(blur(smoke, 3), 0.95)
    c.add(from_mask(blur(edge_band(smoke[..., 3], (0, -1), 5), 2), "#C9A0FF"), 0.8)
    # one ghost hand pulling the ball back
    d = props.ghost_hand_d(0.9)
    hand = lay(f'<g transform="translate(250,560) rotate(68) scale(1.25)"><path d="{d}" fill="url(#gh)" '
               f'stroke="url(#gh)" stroke-width="12" stroke-linejoin="round"/></g>',
               props.lin_grad("gh", [(0, "#F4E8FF"), (0.55, "#B98AF5"), (1, "#5A2E99")], 0, 0, 0, 1))
    subject(c, hand, glow=1.0, glow_col="#B07AF0", rim_col="#FFFFFF")
    b = ball_layer(270, bx, by, rot=(0.8, 0.3, 0.6), base="#8E62D0", shadow="#2A1450", rim="#E2CCFF",
                   stitch="#FF4A7A", seam_color="#4A2A70", bounce="#9B5DE5")
    subject(c, b, glow=1.2, glow_col="#9B5DE5", rim_col="#F0E0FF")
    finish(c)
    final_sparkles(c)


@painter
def time_out(c: Card):
    cx, cy = 512, 410
    backdrop(c, (cx, cy), ray_k=1.4, bright=0.7)
    c.add(fx.light_rays(W, H, cx, cy, 22, c.seed, GOLD, spread=0.8, opacity=(0.04, 0.10)), 1.0)
    # ice shards around the dial
    rng = c.rng(8)
    sh = []
    for i, ang in enumerate(np.linspace(150, 390, 9)):
        a = math.radians(ang)
        L = rng.uniform(150, 230)
        w = rng.uniform(46, 70)
        x0, y0 = cx + math.cos(a) * 210, cy + math.sin(a) * 190
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        tip = (x0 + ux * L, y0 + uy * L)
        p1 = (x0 + nx * w / 2, y0 + ny * w / 2)
        p2 = (x0 - nx * w / 2, y0 - ny * w / 2)
        m1 = (x0 + ux * L * 0.62 + nx * w / 2, y0 + uy * L * 0.62 + ny * w / 2)
        m2 = (x0 + ux * L * 0.62 - nx * w / 2, y0 + uy * L * 0.62 - ny * w / 2)
        mid = (x0 + ux * L * 0.55, y0 + uy * L * 0.55)
        sh.append(f'<path d="{props.poly_d([p1, m1, tip, mid])}" fill="#D8F6FF"/>'
                  f'<path d="{props.poly_d([p2, m2, tip, mid])}" fill="#3E9AD6"/>'
                  f'<path d="{props.poly_d([p1, mid, p2])}" fill="#8CD6F5"/>')
    subject(c, lay("".join(sh)), glow=0.6, glow_col="#6FD0FF", rim_col="#FFFFFF", ow=11)
    defs, sw = props.stopwatch(cx, cy, 200, hand_angle=-30, accent="#E0262F", rim="#FFD86A")
    subject(c, lay(sw, defs), glow=0.7, glow_col=GOLD, rim_col="#FFF2B8")
    # frost glaze over the dial
    fz = lay(f'<circle cx="{cx}" cy="{cy}" r="200" fill="url(#fz)"/>',
             props.rad_grad("fz", [(0, "#BFF0FF", 0.0), (0.7, "#BFF0FF", 0.15), (1, "#E8FBFF", 0.55)], 0.5, 0.5, 0.5))
    c.over(fz)
    finish(c, bloom=1.2)
    final_sparkles(c)


@painter
def changeup(c: Card):
    bx, by = 690, 384
    backdrop(c, (bx, by))
    rp = "".join(ring(bx, by, r, r, 10 - i * 2, "#FFFFFF", 0.9 - i * 0.2) for i, r in enumerate((205, 265, 330)))
    energy(c, lay(rp), "#B8AEFF", core=0.7, glow=0.7)
    # slow-motion after-images
    for i, (x, k) in enumerate(((210, 0.22), (360, 0.36), (515, 0.55))):
        g = ball_layer(250, x, by, rot=(0.6 + i * 0.25, 0.5, 0.3), base="#C8C0FF", shadow="#5A4FC0", bounce=c.col)
        c.add(from_mask(blur(g[..., 3], 10), "#9F95FF"), k * 0.7)
        c.over(g, k)
    subject(c, ball_layer(270, bx, by, rot=(1.35, 0.5, 0.3), bounce=c.col))
    finish(c)


@painter
def pickoff(c: Card):
    px, py = 470, 590
    backdrop(c, (px + 60, py - 120))
    burst = lay(fx.comic_burst_svg(px + 40, py - 40, 210, seed=7, points=11,
                                   colors=("#7B6CFF", "#B8AEFF", "#FFFFFF"), squash=0.6))
    energy(c, burst, "#B8AEFF", core=0.9, glow=0.9)
    speed(c, 130, n=18, k=0.5, region=(450, 60, 1000, 380))
    bag = lay(f'<path d="M{px - 210},{py} L{px},{py - 70} L{px + 210},{py} L{px},{py + 70}Z" fill="#F4F1EA"/>'
              f'<path d="M{px - 210},{py} L{px},{py + 70} L{px + 210},{py} L{px + 210},{py + 26} L{px},{py + 96} '
              f'L{px - 210},{py + 26}Z" fill="#9AA3B5"/>')
    subject(c, bag, glow=0.5, rim=False)
    defs, g = glove_svg(px + 120, py - 230, 0.82, 215, leather="#22B3A6", dark="#0E5E58", light="#7FF0E2",
                        lace="#06302C")
    gl = over(lay(g, defs), ball_layer(120, px + 60, py - 150, rot=(0.4, 0.5, 0.2)))
    subject(c, gl, glow=1.0)
    finish(c)


@painter
def lockdown(c: Card):
    cx, cy = 512, 400
    backdrop(c, (cx, cy))
    ch = (props.chain_links([(40, 120), (cx, cy), (990, 690)], 92, 46, color="#9FF3EA")
          + props.chain_links([(40, 690), (cx, cy), (990, 120)], 92, 46, color="#9FF3EA"))
    chl = lay(ch)
    c.add(from_mask(blur(chl[..., 3], 22), c.col), 0.9)
    c.over(chl)
    defs, pl = props.padlock(cx, cy + 20, 330, body="#FFC43D", dark="#B07210", light="#FFF0B0")
    subject(c, lay(pl, defs), glow=1.3, rim_col="#E8FFFB")
    finish(c)


def shard(x, y, L, w, ang, light="#E8FBFF", mid="#B6E9FF", dark="#6CC6EE"):
    a = math.radians(ang - 90)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    p1 = (x + nx * w / 2, y + ny * w / 2)
    p2 = (x - nx * w / 2, y - ny * w / 2)
    m1 = (p1[0] + ux * L * 0.65, p1[1] + uy * L * 0.65)
    m2 = (p2[0] + ux * L * 0.65, p2[1] + uy * L * 0.65)
    tip = (x + ux * L, y + uy * L)
    ctr = (x + ux * L * 0.55, y + uy * L * 0.55)
    return (f'<path d="{props.poly_d([p1, m1, tip, ctr])}" fill="{light}"/>'
            f'<path d="{props.poly_d([p2, m2, tip, ctr])}" fill="{dark}"/>'
            f'<path d="{props.poly_d([p1, ctr, p2])}" fill="{mid}"/>')


@painter
def frost_field(c: Card):
    cx, cy = 512, 470
    backdrop(c, (cx, cy - 40))
    fl = lay(f'<ellipse cx="{cx}" cy="{cy + 150}" rx="430" ry="95" fill="url(#ff)"/>',
             props.rad_grad("ff", [(0, "#FFFFFF", 0.9), (0.6, "#9FF3EA", 0.55), (1, "#2EC4B6", 0.0)], 0.5, 0.5, 0.5))
    energy(c, fl, "#9FF3EA", core=0.8, glow=0.8)
    back = "".join(shard(x, cy + 150, L, w, a) for x, L, w, a in
                   ((300, 300, 92, -24), (420, 380, 110, -8), (600, 360, 104, 10), (730, 290, 92, 26)))
    subject(c, lay(back), glow=1.0, glow_col="#9FF3EA", rim_col="#FFFFFF")
    b = ball_layer(240, cx, cy + 40, rot=(0.6, 0.8, 0.2), base="#EAFBFF", shadow="#7FB8D8", stitch="#D3232C",
                   rim="#FFFFFF", bounce="#9FF3EA")
    front = over(b, lay("".join(shard(x, cy + 175, L, w, a) for x, L, w, a in
                                ((215, 190, 74, -40), (360, 150, 66, -18), (680, 170, 70, 20), (820, 200, 74, 38)))))
    subject(c, front, glow=0.8, glow_col="#9FF3EA", rim_col="#FFFFFF")
    sparkles(c, 22, region=(150, 120, 880, 640), col=["#FFFFFF", "#BFF6FF"])
    finish(c)


@painter
def wall_of_dirt(c: Card):
    backdrop(c, (512, 300))
    burst = lay(fx.comic_burst_svg(512, 420, 430, seed=9, points=13, colors=("#2EC4B6", "#9FF3EA"), squash=0.75))
    energy(c, burst, "#2EC4B6", core=0.35, glow=0.6)
    rng = c.rng(2)
    slabs = []
    # (base x, base half-width, height, lean deg) - back row first
    for bx, hw, h_, lean in ((300, 95, 330, -14), (720, 95, 340, 13), (420, 110, 430, -6), (610, 110, 420, 6),
                             (515, 120, 470, 0), (180, 80, 230, -24), (850, 80, 240, 24)):
        a = math.radians(lean)
        ux, uy = math.sin(a), -math.cos(a)
        tx, ty = bx + ux * h_, 600 + uy * h_
        tip = (tx + rng.uniform(-20, 20), ty - rng.uniform(10, 40))
        l0, r0 = (bx - hw, 600), (bx + hw, 600)
        l1, r1 = (tx - hw * 0.75, ty + 20), (tx + hw * 0.75, ty + 30)
        mid = (bx + ux * h_ * 0.5 + hw * 0.15, 600 + uy * h_ * 0.5)
        slabs.append(f'<path d="{props.poly_d([l0, l1, tip, (tip[0] + 5, tip[1] + 40), mid, (bx + 10, 600)])}" fill="#D99A5E"/>'
                     f'<path d="{props.poly_d([(bx + 10, 600), mid, (tip[0] + 5, tip[1] + 40), tip, r1, r0])}" fill="#8A4E26"/>'
                     f'<path d="M{l0[0] + 20},{560 - h_ * 0.25} L{r0[0] - 10},{570 - h_ * 0.2}" stroke="#5E3418" '
                     f'stroke-width="12" stroke-linecap="round"/>')
    for i in range(8):
        x, y = rng.uniform(150, 880), rng.uniform(70, 200)
        r = rng.uniform(16, 34)
        pts = [(x + math.cos(t) * r * rng.uniform(0.7, 1.1), y + math.sin(t) * r * rng.uniform(0.7, 1.1))
               for t in np.linspace(0, 2 * math.pi, 6, endpoint=False)]
        slabs.append(f'<path d="{props.poly_d(pts)}" fill="#B87440"/>')
    slabs.append('<path d="M60,640 Q512,560 964,640 L964,610 Q512,540 60,610Z" fill="#5E3418"/>')
    subject(c, lay("".join(slabs)), glow=1.0, rim_col="#E8FFFB")
    chalk = lay('<path d="M-20,712 L1044,672 L1044,700 L-20,744Z" fill="#FFFFFF"/>')
    subject(c, chalk, glow=0.3, rim=False, ow=8)
    speed(c, -90, n=14, col="#FFE6C0", k=0.4, region=(120, 40, 900, 230), width=(3, 7))
    finish(c)


@painter
def base_shield(c: Card):
    cx, cy, R = 512, 610, 400
    backdrop(c, (cx, 380))
    x, y = grid(H, W)
    # dome: upper half-ellipse, fresnel-bright edge, big hexagon grid
    rx, ry = R, R * 1.05
    dn = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    dome = np.clip((1 - dn) * 120, 0, 1) * np.clip((cy - y) * 0.5 + 0.5, 0, 1)
    fres = smoothstep(0.55, 1.0, dn) * dome
    s = 62.0
    q = (x - cx) / s
    r = (y - cy) / s
    # hex grid via axial coordinates
    qa = (math.sqrt(3) / 3 * q - 1 / 3 * r)
    ra = (2 / 3 * r)
    xa, za = qa, ra
    ya = -xa - za
    rxa, rya, rza = np.round(xa), np.round(ya), np.round(za)
    dx, dy, dz = np.abs(rxa - xa), np.abs(rya - ya), np.abs(rza - za)
    edge = np.maximum(np.maximum(dx, dy), dz)
    hexl = smoothstep(0.36, 0.46, edge) * dome * (0.35 + 0.65 * smoothstep(0.2, 1.0, dn))
    col = hexrgb("#7FF5E8")
    shell = from_mask(np.clip(fres * 0.55 + dome * 0.10, 0, 1), col)
    c.add(from_mask(blur(dome, 40), c.col), 0.5)
    c.add(shell, 1.0)
    c.add(from_mask(blur(hexl, 6), "#2EC4B6"), 1.0)
    c.add(from_mask(hexl, "#C8FFF8"), 0.9)
    rimc = lay(f'<path d="M{cx - rx},{cy} A{rx},{ry} 0 0 1 {cx + rx},{cy}" fill="none" stroke="#FFFFFF" stroke-width="12"/>')
    energy(c, rimc, "#7FF5E8", core=1.0)
    # home plate
    plate = lay(f'<path d="M{cx - 170},{cy - 30} L{cx + 170},{cy - 30} L{cx + 170},{cy + 5} L{cx},{cy + 60} '
                f'L{cx - 170},{cy + 5}Z" fill="#F4F1EA"/>'
                f'<path d="M{cx - 170},{cy + 5} L{cx},{cy + 60} L{cx + 170},{cy + 5} L{cx + 170},{cy + 30} L{cx},{cy + 85} '
                f'L{cx - 170},{cy + 30}Z" fill="#9AA3B5"/>')
    subject(c, plate, glow=0.6, rim_col="#E8FFFB")
    ground = lay(ring(cx, cy + 10, R + 30, 90, 10, "#FFFFFF", 0.8))
    energy(c, ground, "#7FF5E8", core=0.6, glow=0.6)
    finish(c)


@painter
def bunt_trap(c: Card):
    cx, cy = 512, 520
    backdrop(c, (cx, cy - 40))
    web = []
    for k in range(12):
        a = k / 12 * 2 * math.pi
        web.append(f'<path d="M{cx},{cy} L{cx + math.cos(a) * 440:.1f},{cy + math.sin(a) * 140:.1f}" stroke="#C8FFF8" '
                   f'stroke-width="8" stroke-linecap="round"/>')
    for i, r in enumerate((110, 210, 310, 410)):
        web.append(ring(cx, cy, r, r * 0.32, 9 - i, "#C8FFF8", 1.0))
    energy(c, lay("".join(web)), "#2EC4B6", core=0.9, glow=1.0)
    goo = lay(f'<ellipse cx="{cx}" cy="{cy + 10}" rx="150" ry="48" fill="#7FF5E8" fill-opacity="0.85"/>')
    energy(c, goo, "#7FF5E8", core=0.7, glow=0.7)
    b = ball_layer(240, cx, cy - 80, rot=(0.6, 0.4, 0.5), bounce=c.col)
    goo_top = lay(f'<path d="M{cx - 120},{cy - 20} Q{cx - 60},{cy - 70} {cx - 40},{cy - 20} Q{cx},{cy - 50} {cx + 30},{cy - 15} '
                  f'Q{cx + 80},{cy - 60} {cx + 120},{cy - 20} L{cx + 120},{cy + 10} L{cx - 120},{cy + 10}Z" fill="#9FF3EA"/>')
    subject(c, over(b, goo_top), glow=1.0)
    finish(c)


@painter
def diving_catch(c: Card):
    backdrop(c, (640, 300))
    speed(c, -38, n=22, k=0.55, region=(0, 200, 700, 768), width=(4, 10))
    # arm: sleeve + pink wristband stretching from the lower left
    arm = lay(f'<path d="{props.capsule_d(110, 760, 470, 450, 80, 60)}" fill="url(#sl)"/>'
              f'<path d="M150,735 L440,488" stroke="#1C3A5E" stroke-width="20" stroke-linecap="round"/>'
              f'<path d="{props.capsule_d(430, 485, 505, 420, 66, 62)}" fill="#FF6FB5"/>',
              props.lin_grad("sl", [(0, "#FFFFFF"), (1, "#AEB8C8")], 0, 0, 1, 1))
    defs, g = glove_svg(640, 300, 0.9, 50, leather="#C46A2C", dark="#6E3714", light="#F0A866", trim="#FF6FB5")
    gl = over(arm, lay(g, defs))
    gl = over(gl, ball_layer(150, 700, 230, rot=(0.6, 0.5, 0.3), bounce=c.col))
    subject(c, gl, glow=1.1)
    finish(c)


@painter
def twin_play(c: Card):
    cx, cy = 512, 384
    backdrop(c, (cx, cy))
    rot = math.radians(-16)
    R = np.array([[math.cos(rot), -math.sin(rot)], [math.sin(rot), math.cos(rot)]])
    a1 = (arc_pts(0, 0, 330, 150, 200, 365) @ R.T) + (cx, cy)
    a2 = (arc_pts(0, 0, 330, 150, 20, 185) @ R.T) + (cx, cy)
    for a in (a1, a2):
        trail(c, a, 0, 80, col="#5BFF7A", glow=0.9)
    p1 = a1[-1]
    p2 = a2[-1]
    balls = over(ball_layer(210, *p1, rot=(0.4, 0.6, 0.3), bounce="#5BD75B"),
                 ball_layer(210, *p2, rot=(1.1, 0.4, 0.8), bounce="#5BD75B"))
    subject(c, balls, glow=1.0, glow_col="#9BFF7A")
    finish(c)


@painter
def field_vision(c: Card):
    cx, cy = 512, 384
    backdrop(c, (cx, cy))
    c.add(fx.light_rays(W, H, cx, cy, 16, c.seed, "#FFF2B0", spread=0.6, opacity=(0.04, 0.1)), 1.0)
    ew, eh = 420, 330
    eye = (f'M{cx - ew},{cy} Q{cx},{cy - eh * 1.25} {cx + ew},{cy} Q{cx},{cy + eh * 1.25} {cx - ew},{cy}Z')
    sclera = lay(f'<path d="{eye}" fill="url(#sc)"/>',
                 props.rad_grad("sc", [(0, "#FFFFFF"), (0.7, "#F4F1EA"), (1, "#C9C2B0")], 0.5, 0.45, 0.6))
    iris = lay(f'<circle cx="{cx}" cy="{cy}" r="170" fill="#FFB21A"/><circle cx="{cx}" cy="{cy}" r="170" fill="none" '
               f'stroke="#7A4A00" stroke-width="14"/>')
    b = ball_layer(270, cx, cy, rot=(0.25, 0.25, 0.1), rim="#FFF2B0", bounce=c.col)
    inner = over(iris, b)
    inner = inner * sclera[..., 3:4]
    lid = lay(f'<path d="M{cx - ew - 10},{cy} Q{cx},{cy - eh * 1.25 - 30} {cx + ew + 10},{cy}" fill="none" '
              f'stroke="{INK}" stroke-width="30" stroke-linecap="round"/>'
              + "".join(f'<path d="M{cx + dx},{cy - 0.5 * eh * (1 - (dx / ew) ** 2) * 1.25 - 10} '
                        f'l{dx * 0.12},{-70}" stroke="{INK}" stroke-width="20" stroke-linecap="round"/>'
                        for dx in (-280, -140, 0, 140, 280)))
    subject(c, over(over(sclera, inner), lid), glow=1.1)
    finish(c)


@painter
def diamond_aura(c: Card):
    from cards import gem_svg
    cx, cy = 512, 330
    backdrop(c, (cx, cy + 40), col="#FFC93C", bright=0.65)
    c.add(fx.light_rays(W, H, cx, cy + 40, 24, c.seed, "#CFE9FF", spread=0.9, opacity=(0.04, 0.11)), 1.0)
    aura = lay(ring(cx, cy + 40, 300, 300, 14, "#FFFFFF") + ring(cx, cy + 40, 360, 360, 6, "#CFE9FF", 0.7))
    energy(c, aura, "#7FC8FF", core=0.8, glow=0.7)
    gem = lay(gem_svg(cx, cy, 440, light="#F4FBFF", mid="#7CC4FF", dark="#2457C8"))
    subject(c, gem, glow=0.9, glow_col="#6FB8FF", rim_col="#FFFFFF", ow=12)
    finish(c, bloom=1.2)
    final_sparkles(c)


@painter
def rally_cry(c: Card):
    mx, my = 300, 400
    backdrop(c, (mx + 300, my))
    waves = "".join(f'<path d="{taper(arc_pts(mx + 160, my, r, r * 1.05, -42, 42), 18, 18)}" fill="#FFFFFF" '
                    f'fill-opacity="{1.0 - i * 0.2:.2f}"/>' for i, r in enumerate((300, 420, 540)))
    energy(c, lay(waves), "#FFC21A", core=0.9, glow=1.1)
    speed(c, 0, n=16, col="#FFF2B0", k=0.4, region=(500, 150, 1024, 650))
    meg = lay(f'<path d="M{mx - 170},{my - 55} L{mx + 120},{my - 200} L{mx + 120},{my + 200} L{mx - 170},{my + 55}Z" fill="url(#mg)"/>'
              f'<path d="M{mx - 40},{my - 120} L{mx + 30},{my - 155} L{mx + 30},{my + 155} L{mx - 40},{my + 120}Z" fill="#F4F1EA"/>'
              f'<ellipse cx="{mx + 120}" cy="{my}" rx="48" ry="205" fill="#7A1015"/>'
              f'<ellipse cx="{mx + 120}" cy="{my}" rx="30" ry="170" fill="#2A0508"/>'
              f'<rect x="{mx - 230}" y="{my - 70}" width="75" height="140" rx="18" fill="#3A4352"/>'
              f'<path d="M{mx - 90},{my + 50} L{mx - 80},{my + 175} L{mx - 30},{my + 175} L{mx - 25},{my + 40}Z" fill="#3A4352"/>',
              props.lin_grad("mg", [(0, "#FF6A5A"), (0.5, "#E0262F"), (1, "#8A0E16")], 0, 0, 0, 1))
    subject(c, meg, glow=1.0, rim_col="#FFF2B0")
    finish(c)


@painter
def magnet_glove(c: Card):
    gx, gy = 512, 400
    backdrop(c, (gx, gy))
    fl = "".join(f'<path d="{taper(arc_pts(gx, gy, r, r * 0.75, a, a + 70), 4, 16)}" fill="#FFFFFF" fill-opacity="0.9"/>'
                 for r in (290, 380) for a in (-160, -60, 30, 120))
    energy(c, lay(fl), "#FFC21A", core=0.8, glow=0.9)
    balls = blank(H, W)
    for i, (x, y) in enumerate(((140, 200), (130, 600), (890, 560))):
        trail(c, [(x + (x - gx) * 0.3, y + (y - gy) * 0.3), (x, y)], 0, 90, col="#FFE07A", glow=0.7)
        balls = over(balls, ball_layer(130, x, y, rot=(0.3 + i, 0.6, 0.2), bounce=c.col))
    subject(c, balls, glow=0.8)
    bolts = []
    for i, ang in enumerate((-120, -60, 200, 20)):
        a = math.radians(ang)
        p0 = (gx + math.cos(a) * 170, gy + math.sin(a) * 180)
        p1 = (gx + math.cos(a) * 270, gy + math.sin(a) * 270)
        _, cb = fx.lightning_svg(p0, p1, c.seed + i, 6, "#FFE14A", branches=1, detail=4, rough=0.3)
        bolts.append(cb)
    energy(c, lay("".join(bolts)), "#FFD21A", core=1.0, glow=0.8)
    defs, g = glove_svg(gx, gy, 0.8, -8, leather="#C46A2C", dark="#6E3714", light="#F0A866")
    subject(c, lay(g, defs), glow=1.2)
    finish(c)


@painter
def sky_hook(c: Card):
    bx, by = 800, 520
    backdrop(c, (560, 300), stops=[(0, "#FFE7A0"), (0.2, "#FF9E5A"), (0.45, "#6A3A8A"), (0.75, "#1E1A4A"),
                                   (1.0, "#0A0C22")], ray_k=0.8)
    hz = lay(f'<path d="M-20,{H + 20} L-20,690 Q512,630 1044,690 L1044,{H + 20}Z" fill="#0B0A1E"/>')
    c.over(hz)
    c.add(from_mask(blur(edge_band(hz[..., 3], (0, -1), 5), 2), "#FFB06A"), 1.0)
    pts = props.bezier((120, 700), (220, -40), (760, 20), (bx, by), 120)
    trail(c, pts, 0, 200, col="#6AF0FF", glow=1.1)
    subject(c, ball_layer(220, bx, by, rot=(0.6, 0.9, 0.3), rim="#BFFAFF", bounce="#6AF0FF"),
            glow=1.0, glow_col="#6AF0FF", rim_col="#E8FFFF")
    sparkles(c, 26, region=(40, 40, 1000, 380), col=["#FFFFFF", "#FFE7A0"], size=(1.5, 3.5))
    finish(c)


def fan(x, y, s, rot, arms=1.0):
    """Silhouette of a fan with both arms raised (local origin at the chest)."""
    return (f'<g transform="translate({x},{y}) rotate({rot}) scale({s})">'
            f'<circle cx="0" cy="-95" r="52"/>'
            f'<path d="M-95,40 Q-90,-40 -40,-50 L40,-50 Q90,-40 95,40 L95,260 L-95,260Z"/>'
            f'<path d="M-70,-30 Q-120,-130 -{90 + 30 * arms:.0f},-250" fill="none" stroke-width="42" stroke-linecap="round"/>'
            f'<path d="M70,-30 Q120,-130 {90 + 30 * arms:.0f},-250" fill="none" stroke-width="42" stroke-linecap="round"/>'
            f'<circle cx="-{90 + 30 * arms:.0f}" cy="-262" r="30"/><circle cx="{90 + 30 * arms:.0f}" cy="-262" r="30"/>'
            f'</g>')


@painter
def seventh_inning_stretch(c: Card):
    backdrop(c, (512, 300), ray_k=1.3)
    c.add(fx.light_rays(W, H, 512, 300, 20, c.seed, "#FFF2B0", spread=0.8, opacity=(0.04, 0.12)), 1.0)
    # pennant
    pen = lay('<rect x="268" y="80" width="18" height="260" rx="8" fill="#7A4A1A"/>'
              '<path d="M286,90 L760,165 L286,250Z" fill="url(#pn)"/>'
              '<path d="M286,140 L620,165 L286,195Z" fill="#FFFFFF"/>',
              props.lin_grad("pn", [(0, "#FF4A3A"), (1, "#B8121C")], 0, 0, 1, 0))
    subject(c, pen, glow=0.9, rim_col="#FFF2B0")
    # popcorn bursting upward
    rng = c.rng(5)
    pc = []
    for i in range(16):
        x, y = rng.uniform(140, 900), rng.uniform(290, 470)
        r = rng.uniform(16, 26)
        pc.append("".join(f'<circle cx="{x + math.cos(t) * r * 0.55:.1f}" cy="{y + math.sin(t) * r * 0.55:.1f}" r="{r * 0.6:.1f}"/>'
                          for t in (0, 2.1, 4.2)))
    pop = lay(f'<g fill="#FFF4D0">{"".join(pc)}</g>')
    subject(c, pop, glow=0.5, ow=7, rim_col="#FFFFFF", rim_w=6)
    crowd = lay(f'<g fill="#0B0D1C" stroke="#0B0D1C">'
                + fan(150, 690, 0.95, -8, 0.6) + fan(870, 690, 0.95, 8, 0.6)
                + fan(330, 640, 1.1, -4, 1.0) + fan(690, 640, 1.1, 5, 1.0) + fan(512, 600, 1.25, 0, 1.2)
                + '</g>')
    subject(c, crowd, glow=1.2, glow_col="#FFD23F", rim_col="#FFE7A0", rim_dir=(0, -1), rim_w=9, outline=False)
    c.add(from_mask(blur(edge_band(crowd[..., 3], (1, -0.3), 8), 1.5), "#FFF2B0"), 0.9)
    finish(c, bloom=1.1)
    final_sparkles(c)


# ---------------------------------------------------------------------------
def render(info, out_dir=OUT):
    fn = PAINTERS.get(info["id"])
    if fn is None:
        print(f"  ! no painter for {info['id']}")
        return None
    c = Card(info)
    fn(c)
    p = save(c.img, out_dir / f"{info['id']}.png", size=(512, 384), opaque_out=True)
    print(f"  card {info['id']}", flush=True)
    return p


def build(only=None, out_dir=OUT, jobs=2, extras=True):
    cards = [c for c in load_cards() if not only or c["id"] in only]
    if jobs > 1 and len(cards) > 1:
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            done = [p for p in pool.starmap(render, [(c, out_dir) for c in cards]) if p]
    else:
        done = [p for p in (render(c, out_dir) for c in cards) if p]
    if extras and not only:
        import cards as cards_v1    # card back + frame glow are still drawn by the v1 module
        cards_v1.build_back(out_dir / "card_back.png")
        cards_v1.build_frame_glow(out_dir / "card_frame_glow.png")
        done += [out_dir / "card_back.png", out_dir / "card_frame_glow.png"]
        print("  card back + frame glow")
    return done


if __name__ == "__main__":
    build(set(sys.argv[1:]) or None)
