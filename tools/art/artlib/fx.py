"""Reusable effects: brush strokes, speed lines, halftone, sparkles, lightning,
comic fire, smoke, shockwaves, light rays, vignette, grain."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from .core import (fimg, blur, fft_noise, from_mask, grid, hexrgb, radial, rasterize, smoothstep, svg_doc)


# ---------------------------------------------------------------------------
# Brush strokes
# ---------------------------------------------------------------------------
def _noise1d(n: int, cell: float, seed: int, octaves: int = 3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(1.0, cell / 2 ** o)
        k = int(n / c) + 4
        pts = rng.random(k)
        out += amp * np.interp(np.arange(n) / c, np.arange(k), pts)
        tot += amp
        amp *= 0.5
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def brush_stroke_rect(L: int, H: int, seed: int = 1, thickness: float = 0.78, start_round: float = 0.6,
                      taper: float = 0.30, dry: float = 0.55, raggedness: float = 0.05,
                      head_taper: float = 0.0):
    """A horizontal dry-brush stroke in rectified space.

    Returns (mask, streak) arrays of shape (H, L): coverage 0..1 and a streak field
    (0..1) useful for paint colour variation.  The stroke runs left->right; the right
    end frays into bristle streaks.
    """
    rng = np.random.default_rng(seed)
    u, v = grid(H, L)
    un = u / L
    hw0 = H * thickness / 2
    # width profile
    prof = np.ones(L)
    x = np.arange(L) / L
    prof *= 0.92 + 0.08 * _noise1d(L, L / 6, seed + 1)
    prof *= np.clip(1 - ((x - (1 - taper)) / taper).clip(0, 1) ** 1.6 * 0.55, 0, 1)  # gentle end narrowing
    if head_taper > 0:
        prof *= np.clip(0.35 + 0.65 * (x / head_taper).clip(0, 1) ** 0.6, 0, 1)
    hw = hw0 * prof
    top_noise = (_noise1d(L, 40, seed + 2, 5) - 0.5) * 2
    bot_noise = (_noise1d(L, 40, seed + 3, 5) - 0.5) * 2
    centre = H / 2 + (_noise1d(L, L / 3, seed + 4, 2) - 0.5) * hw0 * 0.15
    top = centre - hw * (1 + raggedness * top_noise)
    bot = centre + hw * (1 + raggedness * bot_noise)
    vt = (v - top[None, :]) / np.maximum(1, bot - top)[None, :]  # 0..1 across stroke
    edge = np.clip(np.minimum(v - top[None, :], bot[None, :] - v) + 0.5, 0, 1)
    mask = edge.copy()
    # rounded, slightly slanted head where the brush first touches down
    head = L * 0.045
    across = vt * 2 - 1
    start = head * (start_round * (1 - np.sqrt(np.clip(1 - across ** 2, 0, 1))) + 0.35 * (across + 1) / 2
                    + 0.15 * (_noise1d(H, 6, seed + 9, 3)[:, None] - 0.5))
    mask *= np.clip(u - start + 0.5, 0, 1)
    # bristle rows: each row runs out of paint at a different length
    rows = 110
    rpos = np.clip(vt * rows, 0, rows - 1)
    row_len = 1 - taper * (0.1 + 0.9 * _noise1d(rows, 2.2, seed + 5, 2) ** 1.3)
    row_len = np.minimum(row_len, 1 - taper * 0.08 * rng.random(rows))
    # edges dry out earlier
    edge_dry = 1 - np.abs(np.linspace(-1, 1, rows)) ** 3 * taper * 0.5
    row_len *= edge_dry
    end = np.interp(rpos, np.arange(rows), row_len)
    mask *= smoothstep(end, end - 0.02, un)
    # interior dry-brush streaks (long thin holes along the stroke)
    streak = fft_noise(H, L, scale=H / 10, beta=1.1, seed=seed + 6, stretch=30.0, angle=0)
    dryness = dry * (0.22 + 0.78 * smoothstep(0.30, 1.0, un) ** 1.3) + dry * 0.25 * smoothstep(0.10, 0.0, un)
    holes = smoothstep(dryness - 0.04, dryness + 0.04, streak + 0.12)
    mask *= holes
    # soft speckle at the very end
    return np.clip(mask, 0, 1).astype(np.float32), streak.astype(np.float32)


def bend_columns(a: np.ndarray, offsets: np.ndarray) -> np.ndarray:
    """Shift each column vertically by offsets[x] pixels (linear interpolation)."""
    H = a.shape[0]
    out = np.empty_like(a)
    ys = np.arange(H, dtype=np.float32)
    for x in range(a.shape[1]):
        src = ys - offsets[x]
        if a.ndim == 2:
            out[:, x] = np.interp(src, ys, a[:, x], left=0, right=0)
        else:
            for c in range(a.shape[2]):
                out[:, x, c] = np.interp(src, ys, a[:, x, c], left=0, right=0)
    return out


def rotate_layer(a: np.ndarray, deg: float) -> np.ndarray:
    """Rotate a float layer (2D or premultiplied RGBA) counter-clockwise, expanding the canvas."""
    if a.ndim == 2:
        return np.asarray(fimg(a).rotate(deg, Image.BICUBIC, expand=True))
    return np.stack([rotate_layer(a[..., c], deg) for c in range(a.shape[2])], -1)


def paint_layer(mask: np.ndarray, streak: np.ndarray, base: str, dark: str, light: str,
                seed: int = 0) -> np.ndarray:
    """Colour a brush mask with paint streak variation (premultiplied RGBA)."""
    s = streak
    c = (hexrgb(base)[None, None] * (1 - smoothstep(0.25, 0.05, s)[..., None])
         + hexrgb(dark)[None, None] * smoothstep(0.25, 0.05, s)[..., None])
    hl = smoothstep(0.80, 0.95, s)[..., None] * 0.55
    c = c * (1 - hl) + hexrgb(light)[None, None] * hl
    return from_mask(mask, c)


# ---------------------------------------------------------------------------
# Lines / bursts / halftone
# ---------------------------------------------------------------------------
def speed_lines(w: int, h: int, angle_deg: float, n: int = 40, seed: int = 0, color="#FFFFFF",
                length=(0.2, 0.6), width=(1.0, 4.0), region=None, opacity=(0.3, 1.0)) -> np.ndarray:
    """Parallel tapered streaks travelling along angle (degrees, 0 = to the right)."""
    rng = np.random.default_rng(seed)
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    body = []
    x0, y0, x1, y1 = region or (0, 0, w, h)
    for _ in range(n):
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        ln = rng.uniform(*length) * max(w, h)
        wd = rng.uniform(*width)
        op = rng.uniform(*opacity)
        hx, hy = cx + dx * ln / 2, cy + dy * ln / 2
        tx, ty = cx - dx * ln / 2, cy - dy * ln / 2
        nx, ny = -dy * wd / 2, dx * wd / 2
        body.append(f'<path d="M{tx:.1f},{ty:.1f} L{hx + nx:.1f},{hy + ny:.1f} L{hx - nx:.1f},{hy - ny:.1f}Z" '
                    f'fill="{color}" fill-opacity="{op:.2f}"/>')
    return rasterize(svg_doc(w, h, "".join(body)), w, h)


def radial_burst(w: int, h: int, cx: float, cy: float, n: int = 36, seed: int = 0, color="#FFFFFF",
                 r0: float = 0.0, r1: float | None = None, spread: float = 0.5, opacity=(0.15, 0.6),
                 jitter: float = 1.0) -> np.ndarray:
    """Comic radial 'action burst' wedges from a focus point."""
    rng = np.random.default_rng(seed)
    r1 = r1 or math.hypot(w, h)
    body = []
    for i in range(n):
        a = (i + rng.uniform(-0.4, 0.4) * jitter) / n * 2 * math.pi
        da = spread * math.pi / n * rng.uniform(0.3, 1.0)
        rr0 = r0 * rng.uniform(0.8, 1.4)
        rr1 = r1 * rng.uniform(0.6, 1.0)
        p0 = (cx + math.cos(a) * rr0, cy + math.sin(a) * rr0)
        p1 = (cx + math.cos(a - da) * rr1, cy + math.sin(a - da) * rr1)
        p2 = (cx + math.cos(a + da) * rr1, cy + math.sin(a + da) * rr1)
        op = rng.uniform(*opacity)
        body.append(f'<path d="M{p0[0]:.1f},{p0[1]:.1f} L{p1[0]:.1f},{p1[1]:.1f} L{p2[0]:.1f},{p2[1]:.1f}Z" '
                    f'fill="{color}" fill-opacity="{op:.2f}"/>')
    return rasterize(svg_doc(w, h, "".join(body)), w, h)


def halftone_mask(w: int, h: int, field: np.ndarray, spacing: float = 10.0, angle_deg: float = 45.0,
                  max_r: float = 0.62) -> np.ndarray:
    """Antialiased halftone dot coverage driven by `field` (0..1 = dot size)."""
    x, y = grid(h, w)
    a = math.radians(angle_deg)
    u = (x * math.cos(a) + y * math.sin(a)) / spacing
    v = (-x * math.sin(a) + y * math.cos(a)) / spacing
    fu = u - np.round(u)
    fv = v - np.round(v)
    d = np.sqrt(fu * fu + fv * fv) * spacing
    r = np.sqrt(np.clip(field, 0, 1)) * max_r * spacing
    return np.clip(r - d + 0.5, 0, 1) * (r > 0.3)


def sparkle_svg(x, y, r, color="#FFFFFF", op=1.0, rot=0.0, thin=0.18) -> str:
    """Four-point star."""
    pts = []
    for i in range(8):
        a = rot + i * math.pi / 4
        rr = r if i % 2 == 0 else r * thin
        pts.append(f"{x + math.cos(a) * rr:.1f},{y + math.sin(a) * rr:.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{color}" fill-opacity="{op:.2f}"/>'


def particles(w: int, h: int, n: int, seed: int, region=None, color="#FFFFFF", size=(1.0, 4.0),
              sparkle_frac: float = 0.25, opacity=(0.4, 1.0), weight_fn=None) -> np.ndarray:
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = region or (0, 0, w, h)
    body = []
    k = 0
    while k < n:
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if weight_fn is not None and rng.random() > weight_fn(x, y):
            continue
        k += 1
        s = rng.uniform(*size)
        op = rng.uniform(*opacity)
        col = color if isinstance(color, str) else color[rng.integers(len(color))]
        if rng.random() < sparkle_frac:
            body.append(sparkle_svg(x, y, s * 2.6, col, op, rng.uniform(0, 0.8)))
        else:
            body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{s:.2f}" fill="{col}" fill-opacity="{op:.2f}"/>')
    return rasterize(svg_doc(w, h, "".join(body)), w, h)


# ---------------------------------------------------------------------------
# Lightning
# ---------------------------------------------------------------------------
def bolt_points(p0, p1, seed: int, detail: int = 6, rough: float = 0.22):
    rng = np.random.default_rng(seed)
    pts = [np.array(p0, float), np.array(p1, float)]
    disp = rough * math.dist(p0, p1)
    for _ in range(detail):
        new = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            m = (a + b) / 2
            d = b - a
            nrm = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-9)
            m = m + nrm * rng.uniform(-disp, disp)
            new += [m, b]
        pts = new
        disp *= 0.55
    return pts


def lightning_svg(p0, p1, seed: int, width: float, color: str, core="#FFFFFF", branches: int = 3,
                  detail: int = 6, rough: float = 0.22) -> tuple[str, str]:
    """Return (glow_body, core_body) SVG strings for a forked bolt."""
    rng = np.random.default_rng(seed + 99)
    paths = [(bolt_points(p0, p1, seed, detail, rough), width)]
    main = paths[0][0]
    for b in range(branches):
        i = rng.integers(len(main) // 5, len(main) * 4 // 5)
        s = main[i]
        d = np.array(p1) - np.array(p0)
        ang = math.atan2(d[1], d[0]) + rng.uniform(-0.9, 0.9)
        ln = math.hypot(*d) * rng.uniform(0.15, 0.4)
        e = (s[0] + math.cos(ang) * ln, s[1] + math.sin(ang) * ln)
        paths.append((bolt_points(tuple(s), e, seed + 7 * b + 1, detail - 1, rough * 1.1), width * 0.55))
    glow, cores = [], []
    for pts, wd in paths:
        d = "M" + " L".join(f"{p[0]:.1f},{p[1]:.1f}" for p in pts)
        glow.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{wd * 3.2:.1f}" '
                    f'stroke-linejoin="round" stroke-linecap="round"/>')
        cores.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{wd * 1.6:.1f}" '
                     f'stroke-linejoin="round" stroke-linecap="round"/>'
                     f'<path d="{d}" fill="none" stroke="{core}" stroke-width="{wd * 0.75:.1f}" '
                     f'stroke-linejoin="round" stroke-linecap="round"/>')
    return "".join(glow), "".join(cores)


# ---------------------------------------------------------------------------
# Comic fire / smoke
# ---------------------------------------------------------------------------
FIRE_STOPS = [(0.0, "#7A0A12"), (0.25, "#C81E1E"), (0.45, "#FF5A1F"), (0.65, "#FF9A1F"),
              (0.82, "#FFD54A"), (1.0, "#FFF8D8")]


def fire_field(h: int, w: int, shape: np.ndarray, flow_angle: float, seed: int = 0, scale: float = 40.0,
               turbulence: float = 0.55) -> np.ndarray:
    """Heat field (0..1) = shape (0..1 falloff) perturbed by stretched noise along the flow."""
    n1 = fft_noise(h, w, scale=scale, beta=1.1, seed=seed, stretch=2.8, angle=flow_angle)
    n2 = fft_noise(h, w, scale=scale * 0.4, beta=1.0, seed=seed + 1, stretch=2.5, angle=flow_angle)
    n = n1 * 0.65 + n2 * 0.35
    return np.clip(shape - turbulence * (1 - n) * (1 - shape * 0.5), 0, 1)


def cel_fire(heat: np.ndarray, levels=(0.08, 0.28, 0.48, 0.68, 0.86), aa: float = 0.012,
             colors=("#8E0E14", "#E0262F", "#FF6A1F", "#FFB52E", "#FFF2B0")) -> np.ndarray:
    """Banded (cel-shaded) fire from a heat field -> premultiplied RGBA."""
    h, w = heat.shape
    out = np.zeros((h, w, 4), np.float32)
    for lv, col in zip(levels, colors):
        m = smoothstep(lv - aa, lv + aa, heat)
        layer = from_mask(m, col)
        out = layer + out * (1 - layer[..., 3:4])
    return out


def smoke(h: int, w: int, shape: np.ndarray, seed: int, colors=("#120A1E", "#3A1F5C", "#7B4BC0"),
          scale: float = 50.0, soft: float = 2.5) -> np.ndarray:
    """Soft billowing smoke with banded tones (premultiplied RGBA)."""
    n = fft_noise(h, w, scale=scale, beta=1.3, seed=seed)
    n2 = fft_noise(h, w, scale=scale * 0.45, beta=1.2, seed=seed + 3)
    f = np.clip(shape * (0.45 + 0.75 * n) - 0.18 * n2, 0, 1)
    out = np.zeros((h, w, 4), np.float32)
    lv = (0.12, 0.32, 0.55)
    for l, c in zip(lv, colors):
        m = smoothstep(l - 0.06, l + 0.10, f)
        layer = from_mask(m, c, 0.9)
        out = layer + out * (1 - layer[..., 3:4])
    return blur(out, soft)


# ---------------------------------------------------------------------------
# Rings, rays, vignette, grain
# ---------------------------------------------------------------------------
def ring_svg(cx, cy, rx, ry, width, color, op=1.0, rot=0.0) -> str:
    return (f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="none" stroke="{color}" '
            f'stroke-width="{width:.1f}" stroke-opacity="{op:.2f}" transform="rotate({rot:.1f} {cx:.1f} {cy:.1f})"/>')


def light_rays(w: int, h: int, cx: float, cy: float, n: int, seed: int, color="#FFFFFF",
               spread: float = 0.6, opacity=(0.05, 0.25), angle_range=None) -> np.ndarray:
    rng = np.random.default_rng(seed)
    R = math.hypot(w, h) * 1.2
    body = []
    for i in range(n):
        if angle_range:
            a = rng.uniform(*angle_range)
        else:
            a = (i + rng.uniform(-0.3, 0.3)) / n * 2 * math.pi
        da = spread * rng.uniform(0.2, 1.0) * math.pi / max(n, 8)
        p1 = (cx + math.cos(a - da) * R, cy + math.sin(a - da) * R)
        p2 = (cx + math.cos(a + da) * R, cy + math.sin(a + da) * R)
        body.append(f'<path d="M{cx:.1f},{cy:.1f} L{p1[0]:.1f},{p1[1]:.1f} L{p2[0]:.1f},{p2[1]:.1f}Z" '
                    f'fill="{color}" fill-opacity="{rng.uniform(*opacity):.3f}"/>')
    lay = rasterize(svg_doc(w, h, "".join(body)), w, h)
    return blur(lay, max(1.0, w / 300))


def vignette_alpha(h: int, w: int, strength: float = 0.75, inner: float = 0.45, outer: float = 1.15,
                   cx=None, cy=None) -> np.ndarray:
    cx = w / 2 if cx is None else cx
    cy = h / 2 if cy is None else cy
    d = radial(h, w, cx, cy, w / 2, h / 2)
    return smoothstep(inner, outer, d) * strength


def grain(h: int, w: int, seed: int = 0, amount: float = 0.035) -> np.ndarray:
    rng = np.random.default_rng(seed)
    g = rng.standard_normal((h, w)).astype(np.float32)
    g = blur(g, 0.6)
    return g / (g.std() + 1e-6) * amount


# ---------------------------------------------------------------------------
# Vector comic flames
# ---------------------------------------------------------------------------
FLAME_COLORS = ("#B3121C", "#F0401F", "#FF8A1F", "#FFC93C", "#FFF6D0")
FLAME_SCALES = (1.0, 0.80, 0.60, 0.42, 0.22)


def _tongue_d(L, w, wig):
    """Teardrop flame tongue with its base at the origin, pointing to -y."""
    tipx = wig * w * 0.45
    return (f"M{-w / 2:.1f},0 C{-w * 0.72:.1f},{-L * 0.32:.1f} {-w * 0.10 + wig * w * 0.35:.1f},{-L * 0.70:.1f} "
            f"{tipx:.1f},{-L:.1f} C{w * 0.30 + wig * w * 0.25:.1f},{-L * 0.62:.1f} {w * 0.74:.1f},{-L * 0.30:.1f} "
            f"{w / 2:.1f},0 Q0,{w * 0.55:.1f} {-w / 2:.1f},0Z")


def flames_svg(tongues, colors=FLAME_COLORS, scales=FLAME_SCALES) -> str:
    """tongues: iterable of (x, y, length, width, angle_deg, wiggle). Angle 0 = flame points up.

    All tongues' outer layers are drawn first, then the next layer, so neighbouring
    tongues merge into one banded fire mass.
    """
    tongues = list(tongues)
    out = []
    for col, k in zip(colors, scales):
        for (x, y, L, w, ang, wig) in tongues:
            d = _tongue_d(L * (k ** 0.75), w * k, wig)
            out.append(f'<path d="{d}" fill="{col}" transform="translate({x:.1f},{y:.1f}) rotate({ang:.1f}) '
                       f'translate(0,{w * (1 - k) * 0.25:.1f})"/>')
    return "".join(out)


def fireball_tongues(cx, cy, r, direction_deg, n=14, length=3.0, seed=0, spread=70.0, origin=0.55):
    """Tongues streaming from a ball of radius r away from direction (the way it travels)."""
    rng = np.random.default_rng(seed)
    back = direction_deg + 180.0
    tg = []
    for i in range(n):
        a = back + rng.uniform(-spread, spread) * (0.4 + 0.6 * (i / n))
        ar = math.radians(a)
        ox, oy = cx + math.cos(ar) * r * origin, cy + math.sin(ar) * r * origin
        cen = 1 - abs(a - back) / (spread + 1e-6)
        L = r * length * (0.30 + 0.80 * cen ** 1.5) * rng.uniform(0.7, 1.1)
        w = r * rng.uniform(0.5, 0.8)
        # svg angle: 0 = up (-y). direction a (screen degrees, 0 = +x) -> rotate = a + 90
        tg.append((ox, oy, L, w, a + 90, rng.uniform(-0.5, 0.5)))
    tg.sort(key=lambda t: -t[2])
    return tg


def comic_burst_svg(cx, cy, r, seed=0, points=12, colors=("#B3121C", "#FF6A1F", "#FFC93C", "#FFF6D0"),
                    squash=0.6, ink=None):
    """Spiky comic explosion (nested star polygons)."""
    rng = np.random.default_rng(seed)
    radii = [rng.uniform(0.75, 1.15) for _ in range(points)]
    out = []
    for k, col in enumerate(colors):
        sc = 1.0 - k * 0.22
        pts = []
        for i in range(points * 2):
            a = i / (points * 2) * 2 * math.pi + seed * 0.1
            rr = r * sc * (radii[i // 2] if i % 2 == 0 else 0.55)
            pts.append(f"{cx + math.cos(a) * rr:.1f},{cy + math.sin(a) * rr * squash:.1f}")
        stroke = f' stroke="{ink}" stroke-width="{r * 0.04:.1f}" stroke-linejoin="round"' if (ink and k == 0) else ""
        out.append(f'<polygon points="{" ".join(pts)}" fill="{col}"{stroke}/>')
    return "".join(out)
