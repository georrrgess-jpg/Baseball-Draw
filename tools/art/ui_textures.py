"""UI textures: tileable grain/halftone/diamond pattern, vignette, loading and dugout backdrops."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from artlib.core import (PAL, TEX_DIR, add, blur, fft_noise, from_mask, gradient_map, grid, hexrgb, opaque, over,
                         place, radial, rasterize, save, smoothstep, solid, svg_doc)
from artlib import fx, props, scene

OUT = TEX_DIR / "ui"
INK = "#070D17"


# ---------------------------------------------------------------------------
# Tileable textures
# ---------------------------------------------------------------------------
def noise_grain(path):
    rng = np.random.default_rng(7)
    g = rng.standard_normal((256, 256)).astype(np.float32)
    g = blur(g, 0.55, wrap=True)
    g = g / g.std()
    g2 = fft_noise(256, 256, scale=24, beta=1.0, seed=8, tileable=True) - 0.5
    v = 128 + g * 16 + g2 * 10
    Image.fromarray(np.clip(v + 0.5, 0, 255).astype(np.uint8), "L").save(path, optimize=True)
    return path


def halftone(path):
    S = 4
    N = 256 * S
    p = 16 * S                       # period divides 256 -> tileable
    x, y = grid(N, N)
    a = np.zeros((N, N), np.float32)
    r = 0.22 * p
    for ox, oy in ((0, 0), (p / 2, p / 2)):
        fx_ = np.mod(x + 0.5 - ox + p / 2, p) - p / 2
        fy_ = np.mod(y + 0.5 - oy + p / 2, p) - p / 2
        d = np.sqrt(fx_ ** 2 + fy_ ** 2)
        a = np.maximum(a, np.clip(r - d + 0.5 * S, 0, S) / S)
    lay = from_mask(a, "#FFFFFF")
    save(lay, path, size=(256, 256))
    return path


def diamond_pattern(path):
    S = 2
    N = 512 * S
    P = 128 * S                        # lattice period (4 cells per tile)
    body = []
    rng = np.random.default_rng(3)
    for k in range(-4, 9):
        o = k * P
        body.append(f'<path d="M{o},{-P} L{o + N + 2 * P},{N + P}" stroke="#FFFFFF" stroke-opacity="0.07" stroke-width="{2 * S}"/>')
        body.append(f'<path d="M{o},{N + P} L{o + N + 2 * P},{-P}" stroke="#FFFFFF" stroke-opacity="0.07" stroke-width="{2 * S}"/>')
    # baseball-seam stitching (paired V stitches) along every other lattice line
    step = P / 8
    dvec = (0.7071, 0.7071)
    nvec = (0.7071, -0.7071)
    for k in range(-4, 9):
        if k % 2:
            continue
        o = k * P
        for i in range(-20, 140):
            t = i * step
            cx, cy = o + t, t
            if not (-P < cx < N + P and -P < cy < N + P):
                continue
            for sd in (-1, 1):
                ax, ay = cx + nvec[0] * sd * 2.5 * S, cy + nvec[1] * sd * 2.5 * S
                bx, by = cx + nvec[0] * sd * 8 * S + dvec[0] * 4 * S, cy + nvec[1] * sd * 8 * S + dvec[1] * 4 * S
                body.append(f'<path d="M{ax:.1f},{ay:.1f} L{bx:.1f},{by:.1f}" stroke="#FFFFFF" stroke-opacity="0.13" '
                            f'stroke-width="{1.8 * S}" stroke-linecap="round"/>')
    # small diamonds at the lattice intersections
    for i in range(-1, 6):
        for j in range(-1, 6):
            for ox, oy in ((0, 0), (P / 2, P / 2)):
                cx, cy = i * P + ox, j * P + oy
                r = 6 * S if (ox == 0) else 3.5 * S
                body.append(f'<path d="M{cx},{cy - r} L{cx + r},{cy} L{cx},{cy + r} L{cx - r},{cy}Z" fill="#FFFFFF" fill-opacity="0.10"/>')
    lay = rasterize(svg_doc(N, N, "".join(body)), N, N)
    save(lay, path, size=(512, 512))
    return path


def vignette(path):
    N = 1024
    d = radial(N, N, N / 2, N / 2, N / 2)
    a = smoothstep(0.35, 1.42, d) ** 1.3 * 0.92
    lay = from_mask(a.astype(np.float32), "#000000")
    save(lay, path)
    return path


# ---------------------------------------------------------------------------
# Loading background: sunset stadium silhouette
# ---------------------------------------------------------------------------
def loading_bg(path, W=1920, H=1080):
    hz = H * 0.70
    rgb = scene.sky(W, H, hz, scene.SUNSET, sun=(W * 0.5, hz + 10, 64, "#FF9A4A"), clouds=1.0, seed=21)
    img = opaque(np.clip(rgb, 0, 1))
    img = add(img, fx.light_rays(W, H, W * 0.5, hz, 40, 4, "#FFD9A0", spread=0.7, opacity=(0.02, 0.09)), 1.0)
    img = add(img, fx.particles(W, H, 90, 3, region=(0, 0, W, H * 0.35), color=["#FFFFFF", "#FFE2C0"], size=(0.6, 1.6),
                                sparkle_frac=0.1, opacity=(0.2, 0.6)), 1.0)
    # stadium bowl: high at the sides, low behind centre field
    navy = "#0A0F1E"
    pts = []
    for i in range(65):
        t = i / 64
        x = t * W
        side = abs(t - 0.5) * 2
        y = hz - 30 - 260 * side ** 2.2 - 40 * side
        pts.append((x, y))
    bowl = props.poly_d([(0, H)] + pts + [(W, H)])
    body = [f'<path d="{bowl}" fill="{navy}"/>']
    rim = props.poly_d(pts, False)
    body.append(f'<path d="{rim}" fill="none" stroke="#FFB070" stroke-width="3" stroke-opacity="0.6"/>')
    # upper-deck roof overhangs on both sides
    for side in (-1, 1):
        x0 = 0 if side < 0 else W
        roof = [(x0, H * 0.20), (x0 - side * W * 0.30, H * 0.36), (x0 - side * W * 0.30, H * 0.38), (x0, H * 0.27)]
        body.append(f'<path d="{props.poly_d(roof)}" fill="{navy}"/>')
        body.append(f'<path d="M{x0},{H * 0.20:.1f} L{x0 - side * W * 0.30:.1f},{H * 0.36:.1f}" stroke="#FFB070" stroke-width="2" stroke-opacity="0.5"/>')
        # supports
        for k in range(4):
            xs = x0 - side * W * (0.04 + 0.075 * k)
            ytop = H * 0.20 + (H * 0.16) * (abs(xs - x0) / (W * 0.30))
            body.append(f'<rect x="{xs - 3:.1f}" y="{ytop:.1f}" width="6" height="{H:.1f}" fill="{navy}"/>')
    # scoreboard off-centre right
    sbx, sby = W * 0.70, hz - 150
    body.append(f'<rect x="{sbx - 110}" y="{sby - 60}" width="220" height="120" fill="{navy}"/>'
                f'<rect x="{sbx - 12}" y="{sby + 60}" width="24" height="120" fill="{navy}"/>')
    for r in range(3):
        for c in range(8):
            body.append(f'<rect x="{sbx - 96 + c * 24}" y="{sby - 46 + r * 34}" width="16" height="24" fill="#FFB060" fill-opacity="{0.15 + 0.25 * ((r * 3 + c) % 4 == 0)}"/>')
    # light towers
    lamps = []
    for tx, th in ((W * 0.08, 0.50), (W * 0.24, 0.40), (W * 0.76, 0.40), (W * 0.92, 0.50)):
        top = H * (0.62 - th)
        body.append(f'<path d="M{tx - 9:.1f},{H} L{tx - 5:.1f},{top:.1f} L{tx + 5:.1f},{top:.1f} L{tx + 9:.1f},{H}Z" fill="{navy}"/>')
        for k in range(8):
            yk = top + 30 + k * (H - top) / 9
            body.append(f'<path d="M{tx - 7:.1f},{yk:.1f} L{tx + 7:.1f},{yk + 24:.1f} M{tx + 7:.1f},{yk:.1f} L{tx - 7:.1f},{yk + 24:.1f}" stroke="{navy}" stroke-width="3"/>')
        bw, bh = 120, 70
        body.append(f'<rect x="{tx - bw / 2:.1f}" y="{top - bh:.1f}" width="{bw}" height="{bh}" rx="6" fill="{navy}"/>')
        for r in range(3):
            for c in range(6):
                body.append(f'<circle cx="{tx - bw / 2 + 12 + c * 19:.1f}" cy="{top - bh + 13 + r * 22:.1f}" r="7" fill="#FFF4D6"/>')
        lamps.append((tx, top - bh / 2, bw))
    # crowd speckle on the bowl
    rng = np.random.default_rng(5)
    for k in range(2200):
        t = rng.random()
        i = int(t * 64)
        yt = pts[i][1]
        y = rng.uniform(yt + 6, H * 0.86)
        side = abs(t - 0.5) * 2
        body.append(f'<circle cx="{t * W:.1f}" cy="{y:.1f}" r="{rng.uniform(0.8, 1.8):.1f}" fill="#FFB070" '
                    f'fill-opacity="{rng.uniform(0.04, 0.16) * (0.4 + side):.2f}"/>')
    img = over(img, rasterize(svg_doc(W, H, "".join(body)), W, H))
    img = add(img, scene.lamp_glow(W, H, lamps, "#FFE9B0", 1.0), 0.9)
    # field in the foreground (deep shadow, rim of warm light)
    g = scene.Ground(W, H, hz - 40, cam_h=1.5)
    grass = g.grass(seed=4, light="#173A26", dark="#10301E", stripe=3.0)
    dirt_m = smoothstep(0.2, 0.0, np.abs(np.hypot(g.X * 0.6, g.Z - 2) - 8.5) - 1.2)
    dirt = g.dirt(seed=5, base=("#2A170F", "#3E2416", "#553220", "#6E4228"))
    fld = grass * (1 - dirt_m[..., None]) + dirt * dirt_m[..., None]
    fld *= (0.55 + 0.6 * np.exp(-((g.x - W / 2) / (W * 0.35)) ** 2) * smoothstep(H, hz, g.y))[..., None]
    fog = g.fog(60)[..., None]
    fld = fld * (1 - fog) + hexrgb("#3A2030") * fog
    m = np.clip(g.y - (H * 0.86) + 0.5, 0, 1)
    img = over(img, from_mask(m, fld))
    img = add(img, from_mask(np.exp(-(radial(H, W, W / 2, H * 0.86, W * 0.45, 40) ** 2)), "#FF9A5A"), 0.35)
    # gentle vignette + grain
    v = fx.vignette_alpha(H, W, 0.55, 0.45, 1.3)
    rgbf = img[..., :3] * (1 - v[..., None])
    rgbf += fx.grain(H, W, 9, 0.012)[..., None]
    save(opaque(np.clip(rgbf, 0, 1)), path, opaque_out=True)
    return path


# ---------------------------------------------------------------------------
# Dugout interior
# ---------------------------------------------------------------------------
def _quad_map(q, u, v):
    """Bilinear map from unit square (u,v) to quad q = [tl, tr, br, bl]."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = q
    top = (x0 + (x1 - x0) * u, y0 + (y1 - y0) * u)
    bot = (x3 + (x2 - x3) * u, y3 + (y2 - y3) * u)
    return top[0] + (bot[0] - top[0]) * v, top[1] + (bot[1] - top[1]) * v


def _wood(H, W, seed, base=("#3A2416", "#5A3A22", "#7A5232"), plank=None, horizontal=True, scale=1.0):
    n = fft_noise(H, W, scale=10 * scale, beta=1.0, seed=seed, stretch=18, angle=0 if horizontal else math.pi / 2)
    n2 = fft_noise(H, W, scale=60 * scale, beta=1.0, seed=seed + 1)
    rgb = gradient_map(np.clip(n * 0.6 + n2 * 0.4, 0, 1), [(0, base[0]), (0.5, base[1]), (1, base[2])])
    return rgb


def dugout_bg(path, W=1920, H=1080):
    VPx, VPy = W / 2, H * 0.47
    oL, oR, oT, oB = 330, W - 330, 200, 770        # far opening (front edge of the dugout)
    railY = 640
    img = solid(H, W, "#0B0F18")
    x, y = grid(H, W)

    # -- view of the field through the opening (rendered then softly defocused) --
    fw, fh = oR - oL, railY - oT
    sub_h = fh
    sk = scene.sky(fw, sub_h, sub_h * 0.62, scene.SUNSET, sun=(fw * 0.62, sub_h * 0.60, 40, "#FF9A4A"), clouds=0.9, seed=31)
    view = opaque(np.clip(sk, 0, 1))
    body, lamps = scene.stadium_svg(fw, sub_h, sub_h * 0.66, seed=4, color="#141A2E", rim="#FFB070", towers=3,
                                    height_scale=0.7, bottom=sub_h * 0.67)
    view = over(view, rasterize(svg_doc(fw, sub_h, body), fw, sub_h))
    view = add(view, scene.lamp_glow(fw, sub_h, lamps, "#FFE9B0", 0.8), 0.8)
    g = scene.Ground(fw, sub_h, sub_h * 0.60, cam_h=1.2)
    grass = g.grass(seed=6, light="#3E8A4E", dark="#2E7040", stripe=2.5)
    dz = np.abs(np.hypot(g.X * 0.8, g.Z - 3.0) - 7.0)
    dirt_m = smoothstep(0.6, 0.3, dz) + smoothstep(2.2, 1.9, np.hypot(g.X, g.Z - 3.0))
    dirt = g.dirt(seed=7, base=("#8A5A3A", "#A06A44", "#B87A4E", "#CC8E5E"))
    fld = grass * (1 - np.clip(dirt_m, 0, 1)[..., None]) + dirt * np.clip(dirt_m, 0, 1)[..., None]
    fld *= 0.75
    fld += hexrgb("#FF9A5A") * 0.12
    fog = g.fog(50)[..., None]
    fld = fld * (1 - fog) + hexrgb("#E08A6A") * fog
    view = over(view, from_mask(np.clip(g.y - sub_h * 0.67 + 0.5, 0, 1), fld))
    view = blur(view, 2.2)
    lum = view[..., :3].mean(-1, keepdims=True)
    view[..., :3] = (view[..., :3] * 0.8 + lum * 0.2) * 0.84 + hexrgb("#FFB070") * 0.04   # calmer centre for UI panels
    view[..., 3] = 1
    img = place(img, view, oL + fw / 2, oT + fh / 2)

    shapes = []
    # -- ceiling (wood planks converging to the vanishing point) --
    ceil = [(0, 0), (W, 0), (oR, oT), (oL, oT)]
    shapes.append(("ceiling", ceil))
    leftw = [(0, 0), (oL, oT), (oL, oB), (0, H)]
    rightw = [(W, 0), (W, H), (oR, oB), (oR, oT)]
    floor = [(0, H), (oL, oB), (oR, oB), (W, H)]
    m_ceil = rasterize(svg_doc(W, H, f'<path d="{props.poly_d(ceil)}" fill="#fff"/>'), W, H)[..., 3]
    wood = _wood(H, W, 11, base=("#1E140E", "#2E1E14", "#3E2A1C"))
    # plank seams radiating to VP
    seams = []
    for k in range(-14, 15):
        xt = W / 2 + k * 90
        xb = oL + (oR - oL) * (k + 14) / 28
        seams.append(f'<path d="M{xt:.1f},0 L{xb:.1f},{oT}" stroke="#0A0705" stroke-width="3"/>')
    for t in (0.18, 0.42, 0.7):
        yb = oT * t
        xl = oL * t
        seams.append(f'<path d="M{xl:.1f},{yb:.1f} L{W - xl:.1f},{yb:.1f}" stroke="#0A0705" stroke-width="{10 * (1 - t) + 4:.1f}"/>')
    img = over(img, from_mask(m_ceil, wood))
    img = over(img, rasterize(svg_doc(W, H, "".join(seams)), W, H))
    # -- side walls (painted concrete block) --
    for q, seed in ((leftw, 12), (rightw, 13)):
        m = rasterize(svg_doc(W, H, f'<path d="{props.poly_d(q)}" fill="#fff"/>'), W, H)[..., 3]
        n = fft_noise(H, W, scale=30, seed=seed)
        wall = gradient_map(n, [(0, "#18233A"), (1, "#22304C")])
        img = over(img, from_mask(m, wall))
        lines = []
        for k in range(1, 12):
            v = k / 12
            a = _quad_map(q, 0, v) if q is leftw else _quad_map(q, 0, v)
            p0 = _quad_map(q, 0.0, v)
            p1 = _quad_map(q, 1.0, v)
            if q is leftw:
                p0, p1 = (0, v * H), (oL, oT + (oB - oT) * v)
            else:
                p0, p1 = (W, v * H), (oR, oT + (oB - oT) * v)
            lines.append(f'<path d="M{p0[0]:.1f},{p0[1]:.1f} L{p1[0]:.1f},{p1[1]:.1f}" stroke="#0E1626" stroke-width="2.5"/>')
        img = over(img, rasterize(svg_doc(W, H, "".join(lines)), W, H))
    # -- floor --
    m_floor = rasterize(svg_doc(W, H, f'<path d="{props.poly_d(floor)}" fill="#fff"/>'), W, H)[..., 3]
    fl = gradient_map(fft_noise(H, W, scale=40, seed=14), [(0, "#101219"), (1, "#191C24")])
    img = over(img, from_mask(m_floor, fl))
    mats = []
    for k in range(-12, 13):
        xb = W / 2 + k * 160
        xt = oL + (oR - oL) * (k + 12) / 24
        mats.append(f'<path d="M{xt:.1f},{oB} L{xb:.1f},{H}" stroke="#0A0C10" stroke-width="3"/>')
    img = over(img, rasterize(svg_doc(W, H, "".join(mats)), W, H))
    # sunlight spilling onto the floor through the opening
    spill = np.exp(-(radial(H, W, W / 2, oB + 20, (oR - oL) * 0.5, 50) ** 2))
    img = add(img, from_mask(spill * m_floor, "#FF9A5A"), 0.18)
    # -- front wall + padded rail --
    fwall = [(oL, railY), (oR, railY), (oR, oB), (oL, oB)]
    body = [f'<path d="{props.poly_d(fwall)}" fill="#1B2438"/>']
    body.append(f'<rect x="{oL - 10}" y="{railY - 26}" width="{oR - oL + 20}" height="34" rx="10" fill="{INK}"/>'
                f'<rect x="{oL - 6}" y="{railY - 22}" width="{oR - oL + 12}" height="26" rx="8" fill="#1C2E4A"/>'
                f'<rect x="{oL - 6}" y="{railY - 4}" width="{oR - oL + 12}" height="6" fill="{PAL["scarlet"]}"/>'
                f'<rect x="{oL}" y="{railY - 20}" width="{oR - oL}" height="4" fill="#FFB070" fill-opacity="0.6"/>')
    # steel posts (opening corners + two supports, centre left clear)
    for px_, w_ in ((oL, 26), (oR, 26), (oL + (oR - oL) * 0.18, 16), (oR - (oR - oL) * 0.18, 16)):
        body.append(f'<rect x="{px_ - w_ / 2:.1f}" y="{oT - 4}" width="{w_}" height="{railY - oT + 10}" fill="url(#steel)"/>'
                    f'<rect x="{px_ - w_ / 2:.1f}" y="{oT - 4}" width="{w_}" height="{railY - oT + 10}" fill="none" stroke="{INK}" stroke-width="3"/>')
    # roof lip beam across the top of the opening
    body.append(f'<rect x="{oL - 20}" y="{oT - 26}" width="{oR - oL + 40}" height="32" fill="url(#steel)" stroke="{INK}" stroke-width="3"/>')
    defs = props.lin_grad("steel", [(0, "#3A4458"), (0.35, "#8A96AA"), (0.5, "#C8D0DC"), (0.7, "#6A7488"), (1, "#2A3244")], 0, 0, 1, 0)
    img = over(img, rasterize(svg_doc(W, H, "".join(body), defs), W, H))
    # warm rim light along the rail top from the sunset
    img = add(img, from_mask(np.exp(-((y - (railY - 22)) / 5) ** 2) * (x > oL) * (x < oR), "#FFB070"), 0.5)

    # -- chalkboard on the left wall --
    board = [(40, 250), (270, 300), (270, 600), (40, 680)]
    frame = [(22, 232), (288, 286), (288, 616), (22, 700)]
    cb = [f'<path d="{props.poly_d(frame)}" fill="#5A3A22" stroke="{INK}" stroke-width="5"/>',
          f'<path d="{props.poly_d(board)}" fill="#1E2A24"/>']
    def B(u, v):
        return _quad_map(board, u, v)
    chalk = 'fill="none" stroke="#E8E6DE" stroke-opacity="0.85" stroke-width="3.5" stroke-linecap="round"'
    dia = [B(0.5, 0.25), B(0.8, 0.5), B(0.5, 0.78), B(0.2, 0.5)]
    cb.append(f'<path d="{props.poly_d(dia)}" {chalk}/>')
    for (u, v, kind) in ((0.5, 0.18, "o"), (0.86, 0.45, "o"), (0.14, 0.45, "o"), (0.5, 0.52, "o"), (0.35, 0.88, "x"), (0.7, 0.85, "x"), (0.62, 0.35, "x")):
        cx, cy = B(u, v)
        if kind == "o":
            cb.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="10" ry="12" {chalk}/>')
        else:
            cb.append(f'<path d="M{cx - 9:.1f},{cy - 9:.1f} L{cx + 9:.1f},{cy + 9:.1f} M{cx + 9:.1f},{cy - 9:.1f} L{cx - 9:.1f},{cy + 9:.1f}" {chalk}/>')
    a0, a1 = B(0.35, 0.86), B(0.5, 0.56)
    cb.append(f'<path d="M{a0[0]:.1f},{a0[1]:.1f} Q{a0[0] - 30:.1f},{(a0[1] + a1[1]) / 2:.1f} {a1[0]:.1f},{a1[1]:.1f}" {chalk} stroke-dasharray="10 8"/>')
    a2 = B(0.78, 0.48)
    cb.append(f'<path d="M{a1[0]:.1f},{a1[1]:.1f} L{a2[0]:.1f},{a2[1]:.1f}" {chalk}/>'
              f'<path d="M{a2[0] - 14:.1f},{a2[1] - 2:.1f} L{a2[0]:.1f},{a2[1]:.1f} L{a2[0] - 8:.1f},{a2[1] + 12:.1f}" {chalk}/>')
    t1, t2 = B(0.12, 0.08), B(0.55, 0.08)
    cb.append(f'<path d="M{t1[0]:.1f},{t1[1]:.1f} L{t2[0]:.1f},{t2[1] + 5:.1f}" {chalk.replace("3.5", "5")}/>')
    # chalk tray
    cb.append(f'<path d="M22,700 L288,616 L292,628 L26,714Z" fill="#4A2E1A" stroke="{INK}" stroke-width="4"/>')
    img = over(img, rasterize(svg_doc(W, H, "".join(cb)), W, H))
    smudge = fft_noise(H, W, scale=40, seed=15)
    mb = rasterize(svg_doc(W, H, f'<path d="{props.poly_d(board)}" fill="#fff"/>'), W, H)[..., 3]
    img = add(img, from_mask(mb * smoothstep(0.55, 0.9, smudge), "#C8C8C0"), 0.08)

    # -- helmet cubbies + bat rack on the right wall --
    rk = []
    shelf = [(W - 290, 300), (W - 40, 240), (W - 40, 262), (W - 290, 318)]
    rk.append(f'<path d="{props.poly_d(shelf)}" fill="#5A3A22" stroke="{INK}" stroke-width="4"/>')
    for i, hx in enumerate((W - 250, W - 170, W - 92)):
        hy = 300 - (hx - (W - 290)) * 0.24
        s = 0.9 + i * 0.12
        helmet = (f"M{hx - 34 * s:.1f},{hy:.1f} C{hx - 34 * s:.1f},{hy - 52 * s:.1f} {hx + 30 * s:.1f},{hy - 52 * s:.1f} "
                  f"{hx + 34 * s:.1f},{hy - 8 * s:.1f} L{hx + 52 * s:.1f},{hy - 2 * s:.1f} L{hx + 50 * s:.1f},{hy + 4 * s:.1f} Z")
        rk.append(props.inked(helmet, "url(#helm)", INK, 4))
        rk.append(f'<path d="M{hx - 26 * s:.1f},{hy - 30 * s:.1f} C{hx - 10 * s:.1f},{hy - 42 * s:.1f} {hx + 10 * s:.1f},{hy - 42 * s:.1f} {hx + 22 * s:.1f},{hy - 30 * s:.1f}" '
                  f'fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="4" stroke-linecap="round"/>')
        rk.append(f'<circle cx="{hx - 4 * s:.1f}" cy="{hy - 14 * s:.1f}" r="{9 * s:.1f}" fill="{PAL["scarlet"]}" stroke="{INK}" stroke-width="2"/>')
    # bat rack
    rack_top = [(W - 300, 520), (W - 40, 470)]
    rk.append(f'<path d="M{W - 300},{520} L{W - 40},{470} L{W - 40},{492} L{W - 300},{540}Z" fill="#5A3A22" stroke="{INK}" stroke-width="4"/>')
    rng = np.random.default_rng(16)
    for i in range(9):
        t = (i + 0.5) / 9
        bx = W - 300 + 260 * t
        by_top = 520 - 50 * t - rng.uniform(160, 230)
        by_bot = 760 + 120 * t
        lean = rng.uniform(-14, 6)
        col = ["#C9955A", "#D8A86A", "#3A2A20", "#B07840"][i % 4]
        bat = props.capsule_d(bx + lean, by_top, bx, by_bot, 8, 4.5)
        rk.append(props.inked(bat, col, INK, 3))
        rk.append(f'<rect x="{bx - 6:.1f}" y="{by_bot - 70:.1f}" width="12" height="40" fill="#1C2E4A"/>')
    rk.append(f'<path d="M{W - 300},{700} L{W - 40},{720} L{W - 40},{744} L{W - 300},{724}Z" fill="#5A3A22" stroke="{INK}" stroke-width="4"/>')
    hdefs = props.lin_grad("helm", [(0, "#4A6A9A"), (0.4, "#1C2E4A"), (1, "#0E1A2B")], 0, 0, 0.6, 1)
    img = over(img, rasterize(svg_doc(W, H, "".join(rk), hdefs), W, H))

    # cooler on the floor by the right wall
    cx0, cy0 = 1500, 830
    cooler = (f'<path d="M{cx0 - 60},{cy0 - 90} L{cx0 + 60},{cy0 - 90} L{cx0 + 54},{cy0 + 60} L{cx0 - 54},{cy0 + 60}Z" fill="#E86A1A" stroke="{INK}" stroke-width="5"/>'
              f'<rect x="{cx0 - 66}" y="{cy0 - 112}" width="132" height="26" rx="8" fill="#F4F1EA" stroke="{INK}" stroke-width="5"/>'
              f'<rect x="{cx0 - 40}" y="{cy0 - 50}" width="80" height="40" rx="6" fill="#F4F1EA" fill-opacity="0.9"/>'
              f'<rect x="{cx0 - 12}" y="{cy0 + 20}" width="24" height="14" fill="{INK}"/>')
    img = over(img, rasterize(svg_doc(W, H, cooler), W, H))

    # -- bench in the foreground --
    bn = []
    seat = [(120, 905), (W - 120, 905), (W - 70, 948), (70, 948)]
    front = [(70, 948), (W - 70, 948), (W - 70, 985), (70, 985)]
    for lx in (220, 700, 1220, 1700):
        bn.append(f'<rect x="{lx - 12}" y="985" width="24" height="120" fill="url(#steel)" stroke="{INK}" stroke-width="3"/>')
    bn.append(f'<path d="{props.poly_d(front)}" fill="#3A2416" stroke="{INK}" stroke-width="4"/>')
    bn.append(f'<path d="{props.poly_d(seat)}" fill="#7A5232" stroke="{INK}" stroke-width="4"/>')
    for k in (1, 2):
        yk = 905 + 43 * k / 3
        bn.append(f'<path d="M{120 - 50 * k / 3:.1f},{yk:.1f} L{W - 120 + 50 * k / 3:.1f},{yk:.1f}" stroke="#4A3020" stroke-width="3"/>')
    img = over(img, rasterize(svg_doc(W, H, "".join(bn), defs), W, H))
    m_seat = rasterize(svg_doc(W, H, f'<path d="{props.poly_d(seat)}" fill="#fff"/>'), W, H)[..., 3]
    grain_w = fft_noise(H, W, scale=6, seed=17, stretch=30, angle=0)
    img = add(img, from_mask(m_seat * smoothstep(0.6, 0.9, grain_w), "#C08A5A"), 0.25)
    img = add(img, from_mask(np.exp(-((y - 907) / 3) ** 2) * (x > 120) * (x < W - 120), "#FFB070"), 0.5)
    # props on the bench: glove (left), helmet + towel (right)
    gdefs, gl = props.glove()
    glov = rasterize(svg_doc(W, H, f'<g transform="translate(330,880) rotate(-70) scale(0.34) translate(-232,-250)">{gl}</g>', gdefs), W, H)
    img = over(img, glov)
    hx, hy, s = W - 600, 908, 1.5
    helmet = (f"M{hx - 34 * s:.1f},{hy:.1f} C{hx - 34 * s:.1f},{hy - 52 * s:.1f} {hx + 30 * s:.1f},{hy - 52 * s:.1f} "
              f"{hx + 34 * s:.1f},{hy - 8 * s:.1f} L{hx + 52 * s:.1f},{hy - 2 * s:.1f} L{hx + 50 * s:.1f},{hy + 4 * s:.1f} Z")
    towel = f"M{W - 330},{908} C{W - 320},{880} {W - 250},{876} {W - 220},{890} L{W - 214},{960} L{W - 236},{1000} L{W - 300},{990} L{W - 312},{948}Z"
    pr = (props.inked(helmet, "url(#helm)", INK, 4)
          + f'<circle cx="{hx - 4 * s:.1f}" cy="{hy - 14 * s:.1f}" r="{9 * s:.1f}" fill="{PAL["scarlet"]}" stroke="{INK}" stroke-width="2"/>'
          + f'<path d="M{hx - 26 * s:.1f},{hy - 30 * s:.1f} C{hx - 10 * s:.1f},{hy - 42 * s:.1f} {hx + 10 * s:.1f},{hy - 42 * s:.1f} {hx + 22 * s:.1f},{hy - 30 * s:.1f}" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="4" stroke-linecap="round"/>')
    img = over(img, rasterize(svg_doc(W, H, pr, hdefs), W, H))
    # -- warm caged lamps in the ceiling --
    lamps_svg = []
    for lx, ly in ((620, 70), (1300, 70)):
        lamps_svg.append(f'<path d="M{lx},{0} L{lx},{ly - 26}" stroke="#2A2A2A" stroke-width="4"/>'
                         f'<path d="M{lx - 26},{ly - 26} L{lx + 26},{ly - 26} L{lx + 20},{ly + 20} L{lx - 20},{ly + 20}Z" fill="#3A3A3A" stroke="{INK}" stroke-width="3"/>'
                         f'<ellipse cx="{lx}" cy="{ly + 24}" rx="18" ry="14" fill="#FFE6A0"/>'
                         + "".join(f'<path d="M{lx + k * 7},{ly + 14} L{lx + k * 9},{ly + 40}" stroke="#2A2A2A" stroke-width="2.5"/>' for k in (-2, -1, 0, 1, 2)))
    img = over(img, rasterize(svg_doc(W, H, "".join(lamps_svg)), W, H))
    for lx, ly in ((620, 94), (1300, 94)):
        img = add(img, from_mask(np.exp(-(radial(H, W, lx, ly, 70) ** 2)), "#FFE6A0"), 0.9)
        img = add(img, from_mask(np.exp(-(radial(H, W, lx, ly + 200, 650, 520) ** 2)), "#FF9A4A"), 0.22)

    # -- grading: warm interior, darker edges, calm centre --
    rgb = img[..., :3]
    v = fx.vignette_alpha(H, W, 0.6, 0.4, 1.25)
    rgb = rgb * (1 - v[..., None])
    rgb += fx.grain(H, W, 18, 0.012)[..., None]
    save(opaque(np.clip(rgb, 0, 1)), path, opaque_out=True)
    return path


def build(out_dir=OUT):
    out_dir.mkdir(parents=True, exist_ok=True)
    out = [noise_grain(out_dir / "noise_grain.png"), halftone(out_dir / "halftone.png"),
           diamond_pattern(out_dir / "diamond_pattern.png"), vignette(out_dir / "vignette.png")]
    print("  tileable textures + vignette")
    out.append(loading_bg(out_dir / "loading_bg.png"))
    print("  loading_bg")
    out.append(dugout_bg(out_dir / "dugout_bg.png"))
    print("  dugout_bg")
    return out


if __name__ == "__main__":
    build()
