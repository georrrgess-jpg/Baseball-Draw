"""Baseball Draw logo, small logo, tagline lock-up, standalone brush stroke."""
from __future__ import annotations

import math

import numpy as np

from artlib.baseball import render_ball
from artlib.core import (PAL, TEX_DIR, blur, cmds_to_polys, from_mask, hexrgb, over, place, polys_to_d, rasterize,
                         roughen_poly, save, smoothstep, fft_noise, svg_doc, text_outline, add, blank)
from artlib.fx import (brush_stroke_rect, bend_columns, rotate_layer, paint_layer, speed_lines,
                       particles, sparkle_svg)

INK = "#081120"
LOGO_DIR = TEX_DIR / "logo"
TAGLINE = "DRAW YOUR HAND. DEFEND THE DIAMOND."


def _glyph_polys(text, family, size, tracking=0.0, flat_tol=0.25, weight=0):
    """Per-glyph flattened polygons laid out left to right; returns list of (char, polys, advance)."""
    out = []
    x = 0.0
    for ch in text:
        cmds, e = text_outline(ch, family, size, weight=weight, flat=True, tolerance=flat_tol)
        polys = [p + np.array([x, 0.0]) for p in cmds_to_polys(cmds)]
        out.append((ch, polys, x, e))
        x += e["x_advance"] + tracking
    return out, x


def _xf(polys, *, skew=0.0, rot=0.0, scale=(1.0, 1.0), pivot=(0.0, 0.0), offset=(0.0, 0.0)):
    """Skew (x += -y*tan), scale, rotate (degrees, CCW visually) about pivot, then offset."""
    t = math.tan(math.radians(skew))
    c, s = math.cos(math.radians(-rot)), math.sin(math.radians(-rot))
    res = []
    for p in polys:
        q = p - np.array(pivot)
        q = np.stack([q[:, 0] * scale[0] - q[:, 1] * scale[1] * t, q[:, 1] * scale[1]], 1)
        q = np.stack([q[:, 0] * c - q[:, 1] * s, q[:, 0] * s + q[:, 1] * c], 1)
        res.append(q + np.array(pivot) + np.array(offset))
    return res


def _mask(W, H, d, fill_rule="nonzero"):
    return rasterize(svg_doc(W, H, f'<path d="{d}" fill="#fff" fill-rule="{fill_rule}"/>'), W, H)[..., 3]


def _stroke_mask(W, H, d, width, shifts=((0, 0),)):
    body = "".join(f'<path d="{d}" transform="translate({dx:.1f},{dy:.1f})" fill="#fff" stroke="#fff" '
                   f'stroke-width="{width:.1f}" stroke-linejoin="round"/>' for dx, dy in shifts)
    return rasterize(svg_doc(W, H, body), W, H)[..., 3]


def build_logo_layer(S: float = 1.0, seed: int = 3):
    """Render the full logo at working scale. Returns premultiplied RGBA (H, W, 4)."""
    OX = 160 * S                                   # left margin so the frayed tail never touches the edge
    W, H = int(4400 * S + OX), int(2500 * S)
    canvas = blank(H, W)
    theta = 6.0                                   # swoosh / trail angle (degrees, rising to the right)
    th = math.radians(theta)

    # ------------------------------------------------------------ swoosh (ball trail)
    L, BH = int(3300 * S), int(820 * S)
    m, st = brush_stroke_rect(L, BH, seed=seed + 11, thickness=0.82, taper=0.40, dry=0.75, raggedness=0.05)
    m, st = m[:, ::-1].copy(), st[:, ::-1].copy()   # head on the right (ball), frayed tail on the left
    bend = (np.linspace(-1, 1, L) ** 2) * 60 * S
    m = bend_columns(m, bend)
    st = bend_columns(st, bend)
    swoosh = paint_layer(m, st, PAL["scarlet"], PAL["scarlet_deep"], "#FF6B6B")
    yy = np.linspace(0, 1, BH, dtype=np.float32)[:, None, None]
    swoosh[..., :3] *= (1.05 - 0.25 * smoothstep(0.45, 0.95, yy))
    swoosh = rotate_layer(swoosh, theta)
    sw_cx, sw_cy = 1980 * S + OX, 860 * S
    canvas = place(canvas, swoosh, sw_cx, sw_cy)
    # head of the swoosh = ball position
    bx = sw_cx + (L / 2 - 120 * S) * math.cos(th)
    by = sw_cy - (L / 2 - 120 * S) * math.sin(th) + 30 * S

    # ------------------------------------------------------------ DRAW
    size = 1250 * S
    glyphs, adv = _glyph_polys("DRAW", "Bangers", size, tracking=-14 * S)
    draw_polys = []
    jit = [(-1.5, 1.07, 0), (1.0, 1.0, -6), (-0.8, 1.0, -14), (1.5, 1.04, -26)]
    for (ch, polys, x0, e), (r, sc, dy) in zip(glyphs, jit):
        cx = x0 + e["x_advance"] / 2
        pp = _xf(polys, rot=r, scale=(1.18 * sc, sc), pivot=(cx, -size * 0.35), offset=(cx * 0.18, dy * S))
        draw_polys += pp
    draw_polys = _xf(draw_polys, rot=4.0, offset=(840 * S + OX, 2190 * S))
    draw_polys = [roughen_poly(p, 4.5 * S, seed + i, step=3.0 * S) for i, p in enumerate(draw_polys)]
    d_draw = polys_to_d(draw_polys)

    ext_n, ext_dx, ext_dy = 18, 2.3 * S, 3.6 * S
    shifts = [(k * ext_dx, k * ext_dy) for k in range(0, ext_n + 1, 3)]
    r_white, r_dark = 30 * S, 24 * S
    dark = _stroke_mask(W, H, d_draw, 2 * (r_white + r_dark), shifts)
    white = _stroke_mask(W, H, d_draw, 2 * r_white, shifts)
    body = []
    for k in range(ext_n, 0, -1):
        t = k / ext_n
        col = "#%02X%02X%02X" % tuple(int(v * 255) for v in (hexrgb("#5A0710") * t + hexrgb("#A3141C") * (1 - t)))
        body.append(f'<path d="{d_draw}" transform="translate({k * ext_dx:.1f},{k * ext_dy:.1f})" fill="{col}"/>')
    ext = rasterize(svg_doc(W, H, "".join(body)), W, H)
    face_m = _mask(W, H, d_draw)

    # face colour: vertical gradient + broad brush streaks + bevel highlight
    ys = np.arange(H, dtype=np.float32)[:, None]
    top, bot = 1350 * S, 2250 * S
    g = np.clip((ys - top) / (bot - top), 0, 1)[..., None]
    face_rgb = hexrgb("#F0313A")[None, None] * (1 - g) + hexrgb("#B8111C")[None, None] * g
    face_rgb = np.broadcast_to(face_rgb, (H, W, 3)).copy()
    streak = fft_noise(H, W, scale=90 * S, beta=1.0, seed=seed + 5, stretch=8, angle=math.radians(80))
    face_rgb *= (0.95 + 0.08 * streak)[..., None]
    dk = smoothstep(0.12, 0.03, streak)[..., None] * 0.28
    face_rgb = face_rgb * (1 - dk) + hexrgb("#7A0A12") * dk
    sh = np.roll(np.roll(face_m, int(12 * S), 0), int(8 * S), 1)
    bevel_hi = np.clip(face_m - sh, 0, 1)[..., None] * 0.8
    face_rgb = face_rgb * (1 - bevel_hi) + hexrgb("#FF9A9A") * bevel_hi
    sh2 = np.roll(np.roll(face_m, -int(10 * S), 0), -int(6 * S), 1)
    bevel_lo = np.clip(face_m - sh2, 0, 1)[..., None] * 0.5
    face_rgb = face_rgb * (1 - bevel_lo) + hexrgb("#6E0A12") * bevel_lo
    # glossy top highlight band
    gl = smoothstep(0.30, 0.0, np.clip((ys - top) / (bot - top), 0, 1)) * 0.08
    face_rgb = face_rgb + gl[..., None] * (1 - face_rgb)
    face = from_mask(face_m, face_rgb)

    draw_layer = from_mask(dark, INK)
    draw_layer = over(draw_layer, from_mask(white, "#FFFFFF"))
    draw_layer = over(draw_layer, ext)
    draw_layer = over(draw_layer, face)

    # ------------------------------------------------------------ BASEBALL
    bsize = 520 * S
    bg, badv = _glyph_polys("BASEBALL", "Permanent Marker", bsize, tracking=4 * S)
    bpolys = []
    for i, (ch, polys, x0, e) in enumerate(bg):
        cx = x0 + e["x_advance"] / 2
        dy = (-1) ** i * 7 * S
        bpolys += _xf(polys, rot=(-1) ** (i + 1) * 1.8, pivot=(cx, -bsize * 0.3), offset=(0, dy))
    bpolys = _xf(bpolys, skew=10, rot=theta, pivot=(badv / 2, -bsize * 0.28),
                 offset=(sw_cx - badv / 2 - 290 * S, sw_cy + bsize * 0.28 + 8 * S))
    bpolys = [roughen_poly(p, 3.2 * S, seed + 50 + i, step=2.5 * S) for i, p in enumerate(bpolys)]
    d_base = polys_to_d(bpolys)
    b_dark = _stroke_mask(W, H, d_base, 2 * 16 * S, [(0, 0), (4 * S, 7 * S), (8 * S, 14 * S), (12 * S, 20 * S)])
    b_face = _mask(W, H, d_base)
    ys2 = np.clip((ys - (sw_cy - 330 * S)) / (560 * S), 0, 1)[..., None]
    b_rgb = np.broadcast_to(hexrgb("#FFFFFF") * (1 - ys2) + hexrgb("#D5DBE6") * ys2, (H, W, 3))
    bstreak = fft_noise(H, W, scale=12 * S, beta=1.0, seed=seed + 8, stretch=26, angle=math.radians(-theta))
    holes = smoothstep(0.11, 0.04, bstreak) * smoothstep(0.35, 0.75, fft_noise(H, W, scale=200 * S, seed=seed + 9))
    base_layer = from_mask(b_dark, INK)
    base_layer = over(base_layer, from_mask(b_face * (1 - holes * 0.95), b_rgb))

    # ------------------------------------------------------------ ball + energy trail
    ball_d = 660 * S
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx, dy = xx - bx, yy - by
    back = (-math.cos(th), math.sin(th))            # unit vector pointing behind the ball
    along = dx * back[0] + dy * back[1]
    across = dx * back[1] - dy * back[0]
    cone_w = ball_d * 0.52 * np.clip(1 - along / (ball_d * 3.6), 0, 1) ** 0.9
    comet = np.where((along > -ball_d * 0.25) & (cone_w > 0.5), np.clip(1 - np.abs(across) / np.maximum(cone_w, 1), 0, 1), 0)
    comet = blur(comet.astype(np.float32), 34 * S)
    core = np.where((along > 0) & (cone_w > 2.0), np.clip(1 - np.abs(across) / np.maximum(cone_w * 0.38, 1), 0, 1), 0)
    core = blur(core.astype(np.float32), 10 * S)
    del xx, yy, dx, dy, along, across, cone_w
    lines = speed_lines(W, H, -theta, n=60, seed=seed + 21, color="#FFFFFF", length=(0.08, 0.30),
                        width=(4 * S, 15 * S), region=(1100 * S + OX, by - 420 * S, bx - 300 * S, by + 380 * S),
                        opacity=(0.35, 0.95))
    ball = render_ball(ball_d, rot=(0.35, 0.65, 0.5), light=(-0.45, 0.7, 0.55), rim="#FF8A5A",
                       rim_strength=0.9, rim_dir=(-0.9, -0.2, -0.2), outline=0.05, ink=INK, stitches=30)
    hs = int(ball_d * 1.3)
    halo = rasterize(svg_doc(hs, hs, f'<circle cx="{hs / 2}" cy="{hs / 2}" r="{ball_d / 2 + 24 * S}" fill="{INK}"/>'), hs, hs)
    rng = np.random.default_rng(seed + 31)
    flare_body = []
    for i in range(16):
        ang = rng.uniform(-math.pi, math.pi)
        if math.cos(ang) < -0.6:      # keep rays off the trail side
            continue
        flare_body.append(sparkle_svg(bx, by, rng.uniform(0.62, 1.05) * ball_d, "#FFFFFF",
                                      rng.uniform(0.18, 0.45), ang, 0.025))
    flare = rasterize(svg_doc(W, H, "".join(flare_body)), W, H)
    # long tapered light slashes leaving the ball (the 'energy trail')
    slash_body = []
    for off, ln, wd, op in ((-0.36, 2.9, 30, 0.95), (0.30, 2.3, 22, 0.85), (-0.05, 3.4, 14, 0.75), (0.47, 1.6, 12, 0.7)):
        ox, oy = bx + back[1] * off * ball_d * -1, by + back[0] * off * ball_d
        ox, oy = bx - math.sin(th) * off * ball_d, by - math.cos(th) * off * ball_d
        ex, ey = ox + back[0] * ln * ball_d, oy + back[1] * ln * ball_d
        nx, ny = -back[1] * wd * S / 2, back[0] * wd * S / 2
        slash_body.append(f'<path d="M{ox + nx:.1f},{oy + ny:.1f} L{ex:.1f},{ey:.1f} L{ox - nx:.1f},{oy - ny:.1f}Z" '
                          f'fill="#FFFFFF" fill-opacity="{op}"/>')
    slashes = rasterize(svg_doc(W, H, "".join(slash_body)), W, H)
    sparks = particles(W, H, 80, seed + 41, region=(900 * S + OX, by - 520 * S, bx, by + 520 * S),
                       color=["#FFFFFF", "#FFD27A", "#FF8A5A"], size=(3 * S, 9 * S), sparkle_frac=0.35)

    # ------------------------------------------------------------ assemble
    canvas = add(canvas, from_mask(comet, "#FF6A2A"), 0.85)
    canvas = add(canvas, from_mask(core, "#FFE2A8"), 0.95)
    canvas = over(canvas, lines * 0.75)
    canvas = over(canvas, base_layer)
    canvas = over(canvas, draw_layer)
    canvas = add(canvas, from_mask(blur(slashes[..., 3], 14 * S), "#FFB36B"), 0.9)
    canvas = over(canvas, slashes)
    canvas = add(canvas, sparks, 1.0)
    canvas = add(canvas, blur(flare, 2.5 * S), 1.0)
    canvas = place(canvas, halo, bx, by)
    canvas = place(canvas, ball, bx, by)

    # global drop shadow + dark contour so it reads on bright skies
    al = canvas[..., 3]
    shadow = blur(al, 20 * S)
    shadow = np.roll(np.roll(shadow, int(28 * S), 0), int(18 * S), 1)
    contour = smoothstep(0.0, 0.3, blur(al, 7 * S))
    under = from_mask(np.maximum(shadow * 0.7, contour * 0.5), INK)
    return over(under, canvas)


def crop_alpha(a: np.ndarray, pad: int) -> np.ndarray:
    al = a[..., 3]
    ys, xs = np.where(al > 0.002)
    y0, y1 = max(0, ys.min() - pad), min(a.shape[0], ys.max() + pad)
    x0, x1 = max(0, xs.min() - pad), min(a.shape[1], xs.max() + pad)
    return a[y0:y1, x0:x1]


def tagline_layer(width: float) -> np.ndarray:
    """Tagline lock-up strip (premultiplied RGBA) fitted to `width` pixels."""
    parts = [("DRAW YOUR HAND.", "#FFFFFF"), ("DEFEND THE DIAMOND.", PAL["gold"])]
    size = 300.0
    gap = size * 0.75
    track = size * 0.06
    pieces, x, seps = [], 0.0, []
    for i, (text, col) in enumerate(parts):
        glyphs, adv = _glyph_polys(text, "Barlow Condensed", size, tracking=track, weight=1)
        polys = [p + np.array([x, 0]) for _, ps, _, _ in glyphs for p in ps]
        pieces.append((polys, col))
        x += adv - track
        if i < len(parts) - 1:
            seps.append(x + gap / 2)
            x += gap
    total = x
    k = width / total
    cap = size * 0.70
    H = int((cap + 150) * k) + 40
    W = int(width + 160 * k) + 40
    ox, oy = (W - width) / 2, H / 2 + cap * k / 2
    fills, dark = [], []
    for polys, col in pieces:
        d = polys_to_d(_xf(polys, skew=10, scale=(k, k), offset=(ox, oy)))
        dark.append(f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{46 * k:.1f}" stroke-linejoin="round"/>')
        fills.append(f'<path d="{d}" fill="{col}"/>')
    for sx in seps:
        cx, cy, r = ox + sx * k, oy - cap * k / 2, cap * k * 0.30
        dpath = f"M{cx:.1f},{cy - r:.1f} L{cx + r * 0.8:.1f},{cy:.1f} L{cx:.1f},{cy + r:.1f} L{cx - r * 0.8:.1f},{cy:.1f}Z"
        dark.append(f'<path d="{dpath}" fill="{INK}" stroke="{INK}" stroke-width="{40 * k:.1f}" stroke-linejoin="round"/>')
        fills.append(f'<path d="{dpath}" fill="{PAL["scarlet"]}"/>')
    dark_l = rasterize(svg_doc(W, H, "".join(dark)), W, H)
    sh = np.roll(np.roll(blur(dark_l[..., 3], 10 * k), int(16 * k), 0), int(10 * k), 1)
    lay = over(from_mask(sh, INK, 0.6), dark_l)
    return over(lay, rasterize(svg_doc(W, H, "".join(fills)), W, H))


def build(out_dir=LOGO_DIR):
    hi = crop_alpha(build_logo_layer(1.0), 40)
    h, w = hi.shape[:2]
    save(hi, out_dir / "logo.png", size=(2048, int(round(h * 2048 / w))))
    save(hi, out_dir / "logo_small.png", size=(768, int(round(h * 768 / w))))

    # tagline lock-up: logo above, tagline strip below
    tag = tagline_layer(w * 0.80)
    th, tw = tag.shape[:2]
    gap = int(h * 0.01)
    H = h + gap + th
    full = blank(H, max(w, tw))
    full = place(full, hi, full.shape[1] / 2, h / 2)
    full = place(full, tag, full.shape[1] / 2 + w * 0.03, h + gap + th / 2)
    full = crop_alpha(full, 30)
    fh, fw = full.shape[:2]
    save(full, out_dir / "logo_tagline.png", size=(2048, int(round(fh * 2048 / fw))))

    brush = brush_stroke_layer()
    save(brush, out_dir / "brush_stroke.png", size=(1024, 160))
    return hi


def brush_stroke_layer(seed: int = 21) -> np.ndarray:
    """Standalone scarlet horizontal dry-brush stroke, 2x of 1024x160."""
    W, H = 2048, 320
    m, st = brush_stroke_rect(1960, 300, seed=seed, thickness=0.80, taper=0.34, dry=0.8, raggedness=0.06)
    lay = paint_layer(m, st, PAL["scarlet"], PAL["scarlet_deep"], "#FF6B6B")
    yy = np.linspace(0, 1, lay.shape[0], dtype=np.float32)[:, None, None]
    lay[..., :3] *= (1.04 - 0.18 * smoothstep(0.5, 0.95, yy))
    out = blank(H, W)
    return place(out, lay, W / 2 - 10, H / 2)


if __name__ == "__main__":
    build()
