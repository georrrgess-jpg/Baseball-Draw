"""Card-pack faces: assets/textures/packs/<type>.png and <type>_back.png (512x788).

Each pack type has its own identity, getting more premium with the tier:
  rookie    - fresh sky blue, big sunburst behind a baseball, clean single border.
  pro       - electric violet, neon double border, crossed lightning behind a bat + ball.
  champion  - black and gold luxury: ornate filigree corners, trophy with crown and laurels.
  signature - jersey pinstripes in red, stitched seam border and a large gold-ringed
              medallion window at (256, 370) r=82, filled dark: the game draws the new
              defender's portrait into it at runtime.
The front carries the game logo, the pack name and the card-count tag. Everything
important stays inside a 24 px margin. Painted at 2x and downsampled.
"""
from __future__ import annotations

import json
import math

import numpy as np
from PIL import Image

from artlib.baseball import render_ball
from artlib.core import (ROOT, TEX_DIR, add, blank, blur, cmds_to_d, darken, from_mask, gradient_map, grid,
                         hexrgb, lighten, opaque, over, place, rasterize, save, smoothstep, svg_doc, text_outline)
from artlib import fx, props

S = 2
W, H = 512 * S, 788 * S
OUT = TEX_DIR / "packs"
INK = "#08070F"
MED = (256 * S, 370 * S, 82 * S)     # signature medallion (cx, cy, r) in 2x pixels


def lay(body, defs=""):
    return rasterize(svg_doc(W, H, body, defs), W, H)


def load_packs():
    return {p["id"]: p for p in json.loads((ROOT / "data" / "packs.json").read_text())["packs"]}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def text_d(text, family, size, cx, base_y, max_w=None, tracking=0.0, skew=0.0):
    """SVG path for centred text; shrinks to max_w. Returns (d, (x0, y0, x1, y1))."""
    def measure(sz):
        parts, x = [], 0.0
        for ch in text:
            cmds, e = text_outline(ch, family, sz)
            parts.append((cmds, x))
            x += e["x_advance"] + tracking * sz
        return parts, x - tracking * sz
    parts, wdt = measure(size)
    if max_w and wdt > max_w:
        size *= max_w / wdt
        parts, wdt = measure(size)
    x0 = cx - wdt / 2
    d = "".join(cmds_to_d(cmds, lambda x, y, ox=ox: (x0 + ox + x - y * skew, base_y + y)) for cmds, ox in parts)
    return d, (x0, base_y - size * 0.75, x0 + wdt, base_y), size


def title(name, family, size, cx, base_y, fill_defs, fill, ink=INK, ow=14, shadow="#000000", max_w=430 * S,
          tracking=0.02, skew=0.0, glow=None):
    d, box, sz = text_d(name, family, size, cx, base_y, max_w, tracking, skew)
    body = (f'<path d="{d}" fill="{shadow}" fill-opacity="0.55" stroke="{shadow}" stroke-opacity="0.55" '
            f'stroke-width="{ow * 2}" stroke-linejoin="round" transform="translate(0,{ow * 0.9:.0f})"/>'
            f'<path d="{d}" fill="{ink}" stroke="{ink}" stroke-width="{ow * 2}" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="{fill}"/>')
    return lay(body, fill_defs), box


def tag(text, cx, cy, fill, txt="#FFFFFF", ink=INK, family="Russo One", h=46 * S, shape="pill", defs=""):
    d, box, sz = text_d(text, family, h * 0.52, cx, cy + h * 0.19, None, 0.06)
    w = (box[2] - box[0]) + h * 1.1
    x0, y0 = cx - w / 2, cy - h / 2
    if shape == "pill":
        sh = f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h / 2:.1f}"/>'
    elif shape == "hex":
        k = h * 0.35
        sh = f'<path d="{props.poly_d([(x0, cy), (x0 + k, y0), (x0 + w - k, y0), (x0 + w, cy), (x0 + w - k, y0 + h), (x0 + k, y0 + h)])}"/>'
    else:  # ribbon
        k = h * 0.4
        sh = (f'<path d="{props.poly_d([(x0 - k * 1.6, y0 + h * 0.18), (x0 + 4, y0 + h * 0.18), (x0 + 4, y0 + h * 1.02), (x0 - k * 1.6, y0 + h * 1.02), (x0 - k * 0.8, y0 + h * 0.6)])}"/>'
              f'<path d="{props.poly_d([(x0 + w + k * 1.6, y0 + h * 0.18), (x0 + w - 4, y0 + h * 0.18), (x0 + w - 4, y0 + h * 1.02), (x0 + w + k * 1.6, y0 + h * 1.02), (x0 + w + k * 0.8, y0 + h * 0.6)])}"/>'
              f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{w:.1f}" height="{h:.1f}" rx="6"/>')
    body = (f'<g fill="{ink}" stroke="{ink}" stroke-width="{7 * S}" stroke-linejoin="round">{sh}</g>'
            f'<g fill="{fill}">{sh}</g>'
            f'<path d="{d}" fill="{ink}" stroke="{ink}" stroke-width="{5 * S}" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="{txt}"/>')
    return lay(body, defs)


def logo_layer(width, cx, cy, glow_col="#FFFFFF", glow=0.5):
    L = Image.open(TEX_DIR / "logo" / "logo_small.png").convert("RGBA")
    L = L.resize((int(width), int(L.height * width / L.width)), Image.LANCZOS)
    arr = np.asarray(L).astype(np.float32) / 255.0
    arr[..., :3] *= arr[..., 3:4]
    base = place(blank(H, W), arr, cx, cy)
    out = from_mask(blur(base[..., 3], 10 * S), "#000000", 0.7)
    out = add(out, from_mask(blur(base[..., 3], 24 * S), glow_col), glow)
    return over(out, base)


def sunburst(cx, cy, n, col, k, spin=0.0, r0=0.0, r1=1.0):
    x, y = grid(H, W)
    ang = np.arctan2(y - cy, x - cx) + spin
    d = np.hypot(x - cx, y - cy) / H
    w = smoothstep(-0.05, 0.05, np.sin(ang * n)) * smoothstep(r0, r0 + 0.15, d) * smoothstep(r1, r1 * 0.4, d)
    return from_mask(w * k, col)


def vgrad(stops):
    x, y = grid(H, W)
    return opaque(gradient_map(y / H, stops))


def rgrad(cx, cy, r, stops):
    d = np.hypot(*(a - b for a, b in zip(grid(H, W), (cx, cy)))) / r
    return opaque(gradient_map(np.clip(d, 0, 1), stops))


def sheen(img, k=0.10):
    x, y = grid(H, W)
    t = (x * 0.8 + y * 0.45) / W
    band = np.exp(-((t - 0.55) / 0.10) ** 2) + 0.5 * np.exp(-((t - 0.78) / 0.04) ** 2)
    return add(img, from_mask(band.astype(np.float32), "#FFFFFF"), k)


def rounded_border(m, r, col, wdt, op=1.0):
    return (f'<rect x="{m}" y="{m}" width="{W - 2 * m}" height="{H - 2 * m}" rx="{r}" fill="none" stroke="{col}" '
            f'stroke-width="{wdt}" stroke-opacity="{op}"/>')


def outlined(img, layer, ow=7 * S, glow_col=None, glow=0.8):
    a = layer[..., 3]
    sil = smoothstep(0.02, 0.25, blur(a, ow * 0.5))
    if glow_col:
        img = add(img, from_mask(blur(sil, 30 * S), glow_col), glow)
    img = over(img, from_mask(sil, INK))
    return over(img, layer)


def ball_at(diam, cx, cy, **kw):
    b = render_ball(diam, outline=0.03, **kw)
    return place(blank(H, W), b, cx, cy)


def finish(img, vign=0.45, col="#000000"):
    x, y = grid(H, W)
    d = np.hypot((x - W / 2) / (W / 2), (y - H / 2) / (H / 2))
    v = smoothstep(0.7, 1.5, d) * vign
    rgb = img[..., :3] * (1 - v[..., None]) + hexrgb(col) * v[..., None]
    lum = rgb.max(-1)
    rgb = rgb + blur(rgb * smoothstep(0.6, 1.0, lum)[..., None], 16 * S) * 0.25
    rgb = np.where(rgb < 0.85, rgb, 0.85 + 0.15 * (1 - np.exp(-(rgb - 0.85) / 0.15)))
    return opaque(np.clip(rgb, 0, 1))


def name_block(img, p, name, family, fill, defs, glow_col, tag_fill, tag_shape="pill", tag_txt="#FFFFFF",
               skew=0.0, name_size=118 * S, pack_col="#FFFFFF", ink=INK, tag_defs=""):
    tl, box = title(name, family, name_size, W / 2, 648 * S, defs, fill, ink=ink, skew=skew)
    img = add(img, from_mask(blur(tl[..., 3], 22 * S), glow_col), 0.7)
    img = over(img, tl)
    pk, _ = title("PACK", "Russo One", 30 * S, W / 2, 686 * S, "", pack_col, ink=ink, ow=6 * S, tracking=0.5)
    img = over(img, pk)
    n = p["cards"]
    img = over(img, tag(f"{n} CARD" + ("S" if n != 1 else ""), W / 2, 728 * S, tag_fill, tag_txt, ink=ink,
                        shape=tag_shape, defs=tag_defs))
    return img


# ---------------------------------------------------------------------------
# Rookie
# ---------------------------------------------------------------------------
def rookie_front(p):
    cx, cy = W / 2, 400 * S
    img = rgrad(cx, cy, 560 * S, [(0, "#BFE6FF"), (0.25, "#4FA3F0"), (0.6, "#2F7BE0"), (1, "#0E2A5C")])
    img = add(img, sunburst(cx, cy, 18, "#FFFFFF", 0.16, r1=0.9))
    img = add(img, from_mask(fx.halftone_mask(W, H, smoothstep(0.55, 1.0, grid(H, W)[1] / H) * 0.8, spacing=26,
                                              angle_deg=45), "#9FD3FF"), 0.25)
    rings = lay(fx.ring_svg(cx, cy, 190 * S, 190 * S, 14 * S, "#FFFFFF") +
                fx.ring_svg(cx, cy, 222 * S, 222 * S, 5 * S, "#FFFFFF", 0.7))
    img = add(img, from_mask(blur(rings[..., 3], 12 * S), "#9FD3FF"), 0.8)
    img = add(img, rings, 0.9)
    sw = lay(f'<path d="{props.taper_path(props.bezier((40 * S, 520 * S), (140 * S, 470 * S), (250 * S, 440 * S), (330 * S, 420 * S), 50), 0, 70 * S)}" fill="#FFFFFF"/>')
    img = add(img, from_mask(blur(sw[..., 3], 10 * S), "#9FD3FF"), 0.8)
    img = add(img, sw, 0.8)
    img = outlined(img, ball_at(290 * S, cx, cy, rot=(0.5, 0.6, 0.3), rim="#BFE6FF", bounce="#2F7BE0"),
                   glow_col="#FFFFFF", glow=0.5)
    border = lay(rounded_border(16 * S, 22 * S, "#FFFFFF", 6 * S) + rounded_border(28 * S, 14 * S, "#9FD3FF", 2.5 * S, 0.8))
    img = over(img, border)
    img = over(img, logo_layer(300 * S, cx, 126 * S, "#BFE6FF", 0.4))
    defs = props.lin_grad("rk", [(0, "#FFFFFF"), (0.55, "#E6F4FF"), (1, "#9FD3FF")], 0, 0, 0, 1)
    img = name_block(img, p, "ROOKIE", "Bangers", "url(#rk)", defs, "#4FA3F0", "#2F7BE0", "pill", ink="#06183A")
    return finish(sheen(img, 0.10), 0.35, "#06183A")


# ---------------------------------------------------------------------------
# Pro
# ---------------------------------------------------------------------------
def bat_svg(x0, y0, x1, y1, defs_id="bat"):
    d = props.capsule_d(x0, y0, x1, y1, 13 * S, 34 * S)
    ang = math.atan2(y1 - y0, x1 - x0)
    kx, ky = x0 - math.cos(ang) * 10 * S, y0 - math.sin(ang) * 10 * S
    return (f'<ellipse cx="{kx:.1f}" cy="{ky:.1f}" rx="{22 * S}" ry="{14 * S}" fill="#6E3A12" '
            f'transform="rotate({math.degrees(ang) + 90:.1f} {kx:.1f} {ky:.1f})"/>'
            f'<path d="{d}" fill="url(#{defs_id})"/>'
            f'<path d="{props.capsule_d(x0, y0, x0 + (x1 - x0) * 0.28, y0 + (y1 - y0) * 0.28, 15 * S, 17 * S)}" fill="#1B1F27"/>')


def pro_front(p):
    cx, cy = W / 2, 395 * S
    img = vgrad([(0, "#1A0638"), (0.45, "#3A1080"), (1, "#12042A")])
    # diagonal neon slashes
    x, y = grid(H, W)
    t = (x - y * 0.55) / W
    stripes = smoothstep(0.0, 0.02, np.sin(t * 9 * math.pi)) * 0.12
    img = add(img, from_mask(stripes.astype(np.float32), "#8A3BE0"), 1.0)
    img = add(img, from_mask(np.exp(-((np.hypot(x - cx, y - cy)) / (300 * S)) ** 2).astype(np.float32), "#B45CFF"), 0.75)
    img = add(img, sunburst(cx, cy, 12, "#E2B8FF", 0.10, spin=0.2))
    # lightning
    gl, cr = [], []
    for i, ang in enumerate((-150, -95, -35, 30, 150, 205)):
        a = math.radians(ang)
        p0 = (cx + math.cos(a) * 120 * S, cy + math.sin(a) * 120 * S)
        p1 = (cx + math.cos(a) * 330 * S, cy + math.sin(a) * 300 * S)
        g, c = fx.lightning_svg(p0, p1, 40 + i * 7, 9 * S, "#C88CFF", branches=2, detail=5, rough=0.22)
        gl.append(g)
        cr.append(c)
    img = add(img, from_mask(blur(lay("".join(gl))[..., 3], 12 * S), "#B45CFF"), 1.0)
    img = over(img, lay("".join(cr)))
    # bat + ball
    bat = lay(bat_svg(130 * S, 560 * S, 400 * S, 230 * S),
              props.lin_grad("bat", [(0, "#F6D7A8"), (0.5, "#D9A066"), (1, "#8A5226")], 0, 0, 1, 1))
    img = outlined(img, bat, glow_col="#B45CFF", glow=0.8)
    img = outlined(img, ball_at(190 * S, 300 * S, 410 * S, rot=(0.4, 0.7, 0.3), rim="#E2B8FF", bounce="#8A3BE0"),
                   glow_col="#E2B8FF", glow=0.6)
    # neon double border with chevron notches
    m = 16 * S
    notch = (f'<path d="M{W / 2 - 60 * S},{m} L{W / 2},{m + 22 * S} L{W / 2 + 60 * S},{m}" fill="none" stroke="#E2B8FF" stroke-width="{5 * S}"/>'
             f'<path d="M{W / 2 - 60 * S},{H - m} L{W / 2},{H - m - 22 * S} L{W / 2 + 60 * S},{H - m}" fill="none" stroke="#E2B8FF" stroke-width="{5 * S}"/>')
    neon = lay(rounded_border(m, 10 * S, "#E2B8FF", 5 * S) + rounded_border(28 * S, 6 * S, "#B45CFF", 3 * S) + notch)
    img = add(img, from_mask(blur(neon[..., 3], 10 * S), "#B45CFF"), 1.0)
    img = over(img, neon)
    img = over(img, logo_layer(300 * S, W / 2, 126 * S, "#B45CFF", 0.6))
    defs = props.lin_grad("pr", [(0, "#FFFFFF"), (0.5, "#F0DCFF"), (1, "#C88CFF")], 0, 0, 0, 1)
    img = name_block(img, p, "PRO", "Russo One", "url(#pr)", defs, "#B45CFF", "#8A3BE0", "hex", skew=0.18,
                     name_size=140 * S, ink="#12042A")
    sp = fx.particles(W, H, 40, 9, region=(40 * S, 220 * S, W - 40 * S, 580 * S), color=["#FFFFFF", "#E2B8FF"],
                      size=(2, 5), sparkle_frac=0.5)
    img = add(img, sp, 0.8)
    return finish(sheen(img, 0.12), 0.4, "#0A0118")


# ---------------------------------------------------------------------------
# Champion
# ---------------------------------------------------------------------------
GOLD_STOPS = [(0, "#FFF6C8"), (0.35, "#FFD45A"), (0.6, "#E8A317"), (0.85, "#9A5A08"), (1, "#FFE08A")]


def curl_d(x, y, r, a0, turns, sx=1, sy=1):
    pts = []
    for t in np.linspace(0, turns * 2 * math.pi, 60):
        rr = r * math.exp(-0.28 * t)
        pts.append((x + sx * math.cos(a0 + t) * rr, y + sy * math.sin(a0 + t) * rr))
    return "M" + " L".join(f"{px:.1f},{py:.1f}" for px, py in pts)


def filigree(cx, cy, sx, sy):
    """Corner flourish: two scrolls and a leaf, mirrored by (sx, sy)."""
    s = S
    p = []
    p.append(f'M{cx},{cy + sy * 120 * s} Q{cx},{cy} {cx + sx * 120 * s},{cy}')
    p.append(curl_d(cx + sx * 150 * s, cy + sy * 22 * s, 30 * s, math.pi if sx > 0 else 0, 1.6, sx, sy))
    p.append(curl_d(cx + sx * 22 * s, cy + sy * 150 * s, 30 * s, -math.pi / 2, 1.6, sx, sy))
    p.append(f'M{cx + sx * 40 * s},{cy + sy * 40 * s} Q{cx + sx * 80 * s},{cy + sy * 50 * s} {cx + sx * 110 * s},{cy + sy * 90 * s}')
    return "".join(f'<path d="{d}" fill="none" stroke="url(#gd)" stroke-width="{5 * s}" stroke-linecap="round"/>' for d in p) + \
        f'<circle cx="{cx + sx * 48 * s}" cy="{cy + sy * 48 * s}" r="{11 * s}" fill="url(#gd)"/>'


def trophy_svg(cx, top):
    s = S
    b = []
    # handles
    b.append(f'<path d="M{cx - 92 * s},{top + 40 * s} C{cx - 175 * s},{top + 30 * s} {cx - 170 * s},{top + 150 * s} {cx - 70 * s},{top + 165 * s}" '
             f'fill="none" stroke="url(#gd)" stroke-width="{22 * s}" stroke-linecap="round"/>')
    b.append(f'<path d="M{cx + 92 * s},{top + 40 * s} C{cx + 175 * s},{top + 30 * s} {cx + 170 * s},{top + 150 * s} {cx + 70 * s},{top + 165 * s}" '
             f'fill="none" stroke="url(#gd)" stroke-width="{22 * s}" stroke-linecap="round"/>')
    # bowl
    b.append(f'<path d="M{cx - 110 * s},{top} L{cx + 110 * s},{top} C{cx + 110 * s},{top + 150 * s} {cx + 60 * s},{top + 200 * s} {cx},{top + 205 * s} '
             f'C{cx - 60 * s},{top + 200 * s} {cx - 110 * s},{top + 150 * s} {cx - 110 * s},{top}Z" fill="url(#gd)"/>')
    b.append(f'<ellipse cx="{cx}" cy="{top}" rx="{110 * s}" ry="{16 * s}" fill="#7A4404"/>')
    b.append(f'<path d="M{cx - 70 * s},{top + 30 * s} C{cx - 70 * s},{top + 120 * s} {cx - 40 * s},{top + 160 * s} {cx - 20 * s},{top + 175 * s}" '
             f'fill="none" stroke="#FFFBE6" stroke-width="{12 * s}" stroke-linecap="round" stroke-opacity="0.85"/>')
    # stem + base
    b.append(f'<path d="M{cx - 22 * s},{top + 200 * s} L{cx + 22 * s},{top + 200 * s} L{cx + 34 * s},{top + 255 * s} L{cx - 34 * s},{top + 255 * s}Z" fill="url(#gd)"/>')
    b.append(f'<rect x="{cx - 80 * s}" y="{top + 255 * s}" width="{160 * s}" height="{30 * s}" rx="{6 * s}" fill="url(#gd)"/>')
    b.append(f'<rect x="{cx - 100 * s}" y="{top + 283 * s}" width="{200 * s}" height="{34 * s}" rx="{6 * s}" fill="#1B1206"/>')
    b.append(f'<rect x="{cx - 50 * s}" y="{top + 292 * s}" width="{100 * s}" height="{16 * s}" rx="{3 * s}" fill="url(#gd)"/>')
    # star on the bowl
    st = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = (34 if i % 2 == 0 else 14) * s
        st.append((cx + math.cos(a) * r, top + 85 * s + math.sin(a) * r))
    b.append(f'<path d="{props.poly_d(st)}" fill="#FFFBE6" stroke="#7A4404" stroke-width="{3 * s}"/>')
    return "".join(b)


def crown_svg(cx, base):
    s = S
    pts = [(cx - 90 * s, base), (cx - 100 * s, base - 85 * s), (cx - 50 * s, base - 40 * s), (cx, base - 110 * s),
           (cx + 50 * s, base - 40 * s), (cx + 100 * s, base - 85 * s), (cx + 90 * s, base)]
    b = f'<path d="{props.poly_d(pts)}" fill="url(#gd)"/>'
    b += f'<rect x="{cx - 92 * s}" y="{base - 6 * s}" width="{184 * s}" height="{24 * s}" rx="{5 * s}" fill="url(#gd)"/>'
    for (x, y, r, col) in ((cx - 100 * s, base - 88 * s, 11, "#FFFBE6"), (cx, base - 114 * s, 13, "#FFFBE6"),
                           (cx + 100 * s, base - 88 * s, 11, "#FFFBE6"), (cx, base + 6 * s, 10, "#D7262E"),
                           (cx - 50 * s, base + 6 * s, 7, "#2F7BE0"), (cx + 50 * s, base + 6 * s, 7, "#2F7BE0")):
        b += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * s}" fill="{col}"/>'
    return b


def laurel_svg(cx, cy, r, side):
    s = S
    b = []
    for i in range(9):
        a = math.radians(110 + i * 17) if side < 0 else math.radians(70 - i * 17)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * 1.05
        rot = math.degrees(a) + (90 if side < 0 else -90) + side * 35
        b.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{13 * s}" ry="{30 * s}" fill="url(#gd)" '
                 f'transform="rotate({rot:.1f} {x:.1f} {y:.1f})"/>')
    a0, a1 = (math.radians(105), math.radians(255)) if side < 0 else (math.radians(75), math.radians(-75))
    b.insert(0, f'<path d="M{cx + math.cos(a0) * r:.1f},{cy + math.sin(a0) * r * 1.05:.1f} A{r:.1f},{r * 1.05:.1f} 0 0 {1 if side < 0 else 0} '
                f'{cx + math.cos(a1) * r:.1f},{cy + math.sin(a1) * r * 1.05:.1f}" fill="none" stroke="#B87A10" stroke-width="{6 * s}"/>')
    return "".join(b)


def champion_front(p):
    cx, cy = W / 2, 400 * S
    img = rgrad(cx, cy, 620 * S, [(0, "#3A2408"), (0.4, "#1C1206"), (1, "#050403")])
    # gold diamond lattice
    x, y = grid(H, W)
    u = (x + y) / (60 * S)
    v = (x - y) / (60 * S)
    lat = np.maximum(smoothstep(0.42, 0.48, np.abs(u - np.round(u))), smoothstep(0.42, 0.48, np.abs(v - np.round(v))))
    img = add(img, from_mask(lat.astype(np.float32) * 0.10, "#E8A317"), 1.0)
    img = add(img, fx.light_rays(W, H, cx, cy - 40 * S, 26, 3, "#FFD45A", spread=0.7, opacity=(0.02, 0.06)), 1.0)
    img = add(img, from_mask(np.exp(-(np.hypot(x - cx, y - cy) / (200 * S)) ** 2).astype(np.float32), "#E8A317"), 0.18)
    gd = props.lin_grad("gd", GOLD_STOPS, 0, 0, 0.35, 1)
    g0 = f'<g transform="translate({cx},{430 * S}) scale(0.72) translate({-cx},{-430 * S})">'
    laurel = lay(g0 + laurel_svg(cx, cy + 20 * S, 190 * S, -1) + laurel_svg(cx, cy + 20 * S, 190 * S, 1) + "</g>", gd)
    img = outlined(img, laurel, ow=5 * S, glow_col="#E8A317", glow=0.2)
    trophy = lay(g0 + trophy_svg(cx, cy - 95 * S) + "</g>", gd)
    img = outlined(img, trophy, ow=6 * S, glow_col="#FFD45A", glow=0.35)
    crown = lay(g0 + crown_svg(cx, cy - 102 * S) + "</g>", gd)
    img = outlined(img, crown, ow=6 * S, glow_col="#FFD45A", glow=0.3)
    # ornate frame
    m = 16 * S
    fr = (rounded_border(m, 6 * S, "url(#gd)", 7 * S) + rounded_border(30 * S, 4 * S, "url(#gd)", 2.5 * S)
          + filigree(m + 18 * S, m + 18 * S, 1, 1) + filigree(W - m - 18 * S, m + 18 * S, -1, 1)
          + filigree(m + 18 * S, H - m - 18 * S, 1, -1) + filigree(W - m - 18 * S, H - m - 18 * S, -1, -1))
    for yy in (232 * S, 560 * S):
        fr += (f'<path d="M{70 * S},{yy} L{W / 2 - 30 * S},{yy}" stroke="url(#gd)" stroke-width="{3 * S}"/>'
               f'<path d="M{W / 2 + 30 * S},{yy} L{W - 70 * S},{yy}" stroke="url(#gd)" stroke-width="{3 * S}"/>'
               f'<path d="M{W / 2},{yy - 14 * S} L{W / 2 + 14 * S},{yy} L{W / 2},{yy + 14 * S} L{W / 2 - 14 * S},{yy}Z" fill="url(#gd)"/>')
    frame = lay(fr, props.lin_grad("gd", GOLD_STOPS, 0, 0, 1, 1))
    img = add(img, from_mask(blur(frame[..., 3], 6 * S), "#E8A317"), 0.5)
    img = over(img, frame)
    img = over(img, logo_layer(290 * S, W / 2, 126 * S, "#FFD45A", 0.5))
    defs = props.lin_grad("ch", [(0, "#FFF6C8"), (0.45, "#FFD45A"), (0.55, "#E8A317"), (1, "#8A4E06")], 0, 0, 0, 1)
    tdefs = props.lin_grad("tg", [(0, "#FFE08A"), (1, "#B87A10")], 0, 0, 0, 1)
    img = name_block(img, p, "CHAMPION", "Bangers", "url(#ch)", defs, "#E8A317", "url(#tg)", "ribbon",
                     tag_txt="#1C1206", name_size=112 * S, pack_col="#FFE08A", ink="#120B02", tag_defs=tdefs)
    sp = fx.particles(W, H, 50, 21, region=(40 * S, 60 * S, W - 40 * S, H - 60 * S), color=["#FFFFFF", "#FFE08A"],
                      size=(1.5, 4.5), sparkle_frac=0.6)
    img = add(img, sp, 0.8)
    return finish(sheen(img, 0.10), 0.55, "#000000")


# ---------------------------------------------------------------------------
# Signature
# ---------------------------------------------------------------------------
def stitches(m, r, n_side=(16, 26)):
    """Baseball-seam stitches around a rounded rect inset by m."""
    out = []
    x0, y0, x1, y1 = m, m, W - m, H - m
    pts = []
    for i in range(n_side[0]):
        t = (i + 0.5) / n_side[0]
        pts += [(x0 + r + (x1 - x0 - 2 * r) * t, y0, 0), (x0 + r + (x1 - x0 - 2 * r) * t, y1, 0)]
    for i in range(n_side[1]):
        t = (i + 0.5) / n_side[1]
        pts += [(x0, y0 + r + (y1 - y0 - 2 * r) * t, 1), (x1, y0 + r + (y1 - y0 - 2 * r) * t, 1)]
    L = 9 * S
    for (x, y, v) in pts:
        if v == 0:
            out.append(f'<path d="M{x - L},{y - L * 0.7} L{x + L * 0.2},{y + L * 0.1} M{x + L},{y - L * 0.7} L{x - L * 0.2},{y + L * 0.1}" '
                       f'transform="translate(0,{0})"/>')
        else:
            out.append(f'<path d="M{x - L * 0.7},{y - L} L{x + L * 0.1},{y + L * 0.2} M{x - L * 0.7},{y + L} L{x + L * 0.1},{y - L * 0.2}"/>')
    return out


def medallion_ring(cx, cy, r):
    s = S
    b = [f'<circle cx="{cx}" cy="{cy}" r="{r + 40 * s}" fill="url(#gd)"/>',
         f'<circle cx="{cx}" cy="{cy}" r="{r + 30 * s}" fill="#7A0A10"/>',
         f'<circle cx="{cx}" cy="{cy}" r="{r + 22 * s}" fill="url(#gd)"/>']
    for i in range(24):
        a = i / 24 * 2 * math.pi
        x, y = cx + math.cos(a) * (r + 35 * s), cy + math.sin(a) * (r + 35 * s)
        b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{3.2 * s}" fill="#FFF0C0"/>')
    return "".join(b)


def signature_front(p):
    mx, my, mr = MED
    img = rgrad(mx, my, 640 * S, [(0, "#FF4A4A"), (0.35, "#D7262E"), (0.75, "#7A0A10"), (1, "#3A0508")])
    x, y = grid(H, W)
    pin = smoothstep(0.85, 0.95, np.cos(x / (34 * S) * 2 * math.pi)) * 0.16
    img = add(img, from_mask(pin.astype(np.float32), "#FFC9C9"), 1.0)
    img = add(img, sunburst(mx, my, 24, "#FFC9C9", 0.10, r0=0.02))
    img = add(img, fx.light_rays(W, H, mx, my, 20, 5, "#FFE0B0", spread=0.6, opacity=(0.03, 0.09)), 1.0)
    # five stars arc above the medallion
    st = ""
    for i, a in enumerate(np.linspace(-150, -30, 5)):
        ar = math.radians(a)
        sx, sy = mx + math.cos(ar) * (mr + 92 * S), my + math.sin(ar) * (mr + 82 * S)
        rr = (16 if i in (0, 4) else 20 if i in (1, 3) else 26) * S
        pts = [(sx + math.cos(-math.pi / 2 + k * math.pi / 5) * (rr if k % 2 == 0 else rr * 0.42),
                sy + math.sin(-math.pi / 2 + k * math.pi / 5) * (rr if k % 2 == 0 else rr * 0.42)) for k in range(10)]
        st += f'<path d="{props.poly_d(pts)}" fill="url(#gd)"/>'
    gd = props.lin_grad("gd", GOLD_STOPS, 0, 0, 0.35, 1)
    # laurel sprigs left/right of the medallion
    lau = laurel_svg(mx, my + 10 * S, mr + 75 * S, -1) + laurel_svg(mx, my + 10 * S, mr + 75 * S, 1)
    deco = lay(st + lau, gd)
    img = outlined(img, deco, ow=5 * S, glow_col="#FFD45A", glow=0.5)
    ring = lay(medallion_ring(mx, my, mr), gd)
    img = outlined(img, ring, ow=6 * S, glow_col="#FFD45A", glow=1.0)
    # the dark portrait window (game draws the defender portrait on top)
    win = lay(f'<circle cx="{mx}" cy="{my}" r="{mr + 2 * S}" fill="url(#mw)"/>'
              f'<circle cx="{mx}" cy="{my}" r="{mr}" fill="none" stroke="#000000" stroke-opacity="0.6" stroke-width="{4 * S}"/>',
              props.rad_grad("mw", [(0, "#2A0A10"), (0.8, "#14050A"), (1, "#06020A")], 0.5, 0.4, 0.6))
    img = over(img, win)
    # stitched seam border
    bd = lay(rounded_border(16 * S, 22 * S, "#F4F1EA", 7 * S) + rounded_border(30 * S, 12 * S, "#FFC9C9", 2 * S, 0.7))
    img = over(img, bd)
    stl = lay(f'<g fill="none" stroke="#D3232C" stroke-width="{3.5 * S}" stroke-linecap="round">{"".join(stitches(16 * S, 30 * S))}</g>')
    img = over(img, stl)
    img = over(img, logo_layer(290 * S, W / 2, 120 * S, "#FFC9C9", 0.4))
    defs = props.lin_grad("sg", [(0, "#FFFFFF"), (0.6, "#FFE9E9"), (1, "#FFC9C9")], 0, 0, 0, 1)
    tdefs = props.lin_grad("tg", [(0, "#FFE08A"), (1, "#C88A1A")], 0, 0, 0, 1)
    img = name_block(img, p, "SIGNATURE", "Permanent Marker", "url(#sg)", defs, "#FF6A6A", "url(#tg)", "pill",
                     tag_txt="#3A0508", name_size=96 * S, pack_col="#FFE08A", ink="#2A0306", tag_defs=tdefs)
    return finish(sheen(img, 0.12), 0.45, "#1A0204")


# ---------------------------------------------------------------------------
# Backs
# ---------------------------------------------------------------------------
def back(p):
    pid = p["id"]
    c1, c2, acc = p["color"], p["color2"], p["accent"]
    cx, cy = W / 2, H / 2
    img = rgrad(cx, cy, 700 * S, [(0, lighten(c1, 0.1)), (0.5, c1), (1, c2)])
    x, y = grid(H, W)
    if pid == "rookie":
        f = fx.halftone_mask(W, H, (0.35 + 0.35 * np.cos(y / H * math.pi * 3)).astype(np.float32), spacing=30, angle_deg=45)
        img = add(img, from_mask(f, acc), 0.18)
    elif pid == "pro":
        t = (x - y * 0.55) / W
        img = add(img, from_mask((smoothstep(0.0, 0.02, np.sin(t * 12 * math.pi)) * 0.14).astype(np.float32), acc), 1.0)
    elif pid == "champion":
        img = rgrad(cx, cy, 700 * S, [(0, "#2A1A06"), (0.6, "#120C04"), (1, "#050403")])
        u, v = (x + y) / (60 * S), (x - y) / (60 * S)
        lat = np.maximum(smoothstep(0.42, 0.48, np.abs(u - np.round(u))), smoothstep(0.42, 0.48, np.abs(v - np.round(v))))
        img = add(img, from_mask(lat.astype(np.float32) * 0.12, "#E8A317"), 1.0)
    else:
        pin = smoothstep(0.85, 0.95, np.cos(x / (34 * S) * 2 * math.pi)) * 0.16
        img = add(img, from_mask(pin.astype(np.float32), acc), 1.0)
    img = add(img, sunburst(cx, cy, 16, acc, 0.06))
    gold = pid in ("champion", "signature")
    bc = "url(#gd)" if gold else acc
    gd = props.lin_grad("gd", GOLD_STOPS, 0, 0, 1, 1)
    em = (f'<path d="M{cx},{cy - 150 * S} L{cx + 150 * S},{cy} L{cx},{cy + 150 * S} L{cx - 150 * S},{cy}Z" fill="{darken(c2, 0.3)}" '
          f'fill-opacity="0.85" stroke="{bc}" stroke-width="{8 * S}" stroke-linejoin="round"/>')
    frame = lay(rounded_border(16 * S, 22 * S, bc, 6 * S) + rounded_border(30 * S, 12 * S, bc, 2 * S, 0.6) + em, gd)
    img = add(img, from_mask(blur(frame[..., 3], 8 * S), acc), 0.5)
    img = over(img, frame)
    img = outlined(img, ball_at(150 * S, cx, cy, rot=(0.5, 0.6, 0.3), rim=acc, bounce=c1), glow_col=acc, glow=0.5)
    img = over(img, logo_layer(260 * S, cx, H - 150 * S, acc, 0.3))
    return finish(sheen(img, 0.08), 0.4, "#000000")


FRONTS = {"rookie": rookie_front, "pro": pro_front, "champion": champion_front, "signature": signature_front}


def _one(args):
    pid, p = args
    f = save(FRONTS[pid](p), OUT / f"{pid}.png", size=(512, 788), opaque_out=True)
    b = save(back(p), OUT / f"{pid}_back.png", size=(512, 788), opaque_out=True)
    print(f"  pack {pid}", flush=True)
    return f, b


def sheet(paths):
    from report import IMG_DIR, _font, _save_jpg
    from PIL import ImageDraw
    tw, th = 256, 394
    pad = 16
    sh = Image.new("RGB", (pad + 8 * (tw + pad), th + 2 * pad + 60), "#0E1A2B")
    dr = ImageDraw.Draw(sh)
    dr.text((pad, 14), "BASEBALL DRAW  -  CARD PACKS (front / back, 512x788)", fill="#F4F1EA",
            font=_font("Teko-Variable.ttf", 36))
    i = 0
    for f, b in paths:
        for q in (f, b):
            im = Image.open(q).convert("RGB").resize((tw, th), Image.LANCZOS)
            sh.paste(im, (pad + i * (tw + pad), 60 + pad))
            i += 1
    return _save_jpg(sh, IMG_DIR / "packs_sheet.jpg")


def build(only=None, jobs=2):
    packs = load_packs()
    todo = [(k, v) for k, v in packs.items() if k in FRONTS and (not only or k in only)]
    if jobs > 1:
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            done = pool.map(_one, todo)
    else:
        done = [_one(t) for t in todo]
    if not only:
        print("  sheet", sheet(done))
    return [p for pair in done for p in pair]


if __name__ == "__main__":
    import sys
    build(set(sys.argv[1:]) or None)
