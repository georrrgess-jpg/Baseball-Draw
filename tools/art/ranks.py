"""Division rank emblems (256x256) and rarity gems (64x64).

Emblems escalate in ornateness: rookie (stitched leather badge) -> bronze -> silver
(+star) -> gold (+wings, 3 stars) -> platinum (+laurels) -> diamond (+crystal gem,
ice aura) -> champion (crimson+gold, crown, crossed bats, banner) -> legend
(purple+gold, crown, big wings, prismatic rays).
"""
from __future__ import annotations

import math

import numpy as np

from artlib.baseball import render_ball
from artlib.core import (PAL, RARITY, TEX_DIR, add, blank, blur, from_mask, lighten, darken, over, place, rasterize,
                         save, svg_doc, radial, smoothstep)
from artlib import fx, props

OUT = TEX_DIR / "ui"
INK = "#070D17"
S = 1024
CX, CY = 512, 540

DIVISIONS = ["rookie", "bronze", "silver", "gold", "platinum", "diamond", "champion", "legend"]

# (highlight, light, mid, dark, deep)
METALS = {
    "leather":  ("#F2C890", "#C8955A", "#A06A35", "#6E4320", "#3E2410"),
    "bronze":   ("#FFD2A8", "#E89A5A", "#C0702F", "#8A4A1E", "#4A2410"),
    "silver":   ("#FFFFFF", "#E2E8F0", "#AEB8C6", "#6E7888", "#3A4250"),
    "gold":     ("#FFF6C8", "#FFD45A", "#F0A82A", "#B06E12", "#5E3806"),
    "platinum": ("#FFFFFF", "#DDF6F6", "#A6CED6", "#5F8E9C", "#2A4A56"),
    "ice":      ("#FFFFFF", "#BFEFFF", "#6CC6FF", "#2F7DE1", "#123A8A"),
    "crimson":  ("#FFB0A8", "#F04A50", "#D7262E", "#8E0E16", "#46060A"),
    "royal":    ("#F2DEFF", "#C890FF", "#9B5DE5", "#5A2E99", "#22103E"),
    "navy":     ("#4A6A9A", "#2A4470", "#1C2E4A", "#14233A", "#0A1220"),
}

TIER = {
    #            body metal, trim metal,  shape,    stars, wings, laurel, crown, bats, banner, gem, aura
    "rookie":   ("leather", "leather",  "badge",   0, 0, 0, 0, 0, None, 0, None),
    "bronze":   ("bronze",  "bronze",   "heater",  0, 0, 0, 0, 0, None, 0, None),
    "silver":   ("silver",  "silver",   "heater",  1, 0, 0, 0, 0, None, 0, None),
    "gold":     ("gold",    "gold",     "heater",  3, 1, 0, 0, 0, None, 0, "#FFD45A"),
    "platinum": ("platinum", "platinum", "heater", 3, 1, 1, 0, 0, None, 0, "#BFF4F4"),
    "diamond":  ("ice",     "silver",   "heater",  3, 2, 1, 0, 0, None, 1, "#6CC6FF"),
    "champion": ("crimson", "gold",     "heater",  0, 2, 1, 1, 1, "crimson", 1, "#FFB23A"),
    "legend":   ("royal",   "gold",     "heater",  0, 3, 1, 1, 1, "royal", 1, "prism"),
}

SHIELDS = {
    "badge": ("M512,250 C660,250 770,300 770,460 C770,660 650,790 512,858 C374,790 254,660 254,460 "
              "C254,300 364,250 512,250Z"),
    "heater": ("M262,262 C362,272 452,258 512,226 C572,258 662,272 762,262 V488 C762,656 650,790 512,870 "
               "C374,790 262,656 262,488Z"),
}


def metal_grad(gid, m, x1=0.15, y1=0.0, x2=0.85, y2=1.0):
    hi, li, mid, dk, dp = METALS[m]
    return props.lin_grad(gid, [(0, li), (0.30, mid), (0.46, hi), (0.56, li), (0.78, mid), (1.0, dk)], x1, y1, x2, y2)


def scaled(d, k, cx=CX, cy=CY):
    return f'transform="translate({cx} {cy}) scale({k}) translate({-cx} {-cy})"'


def feather_wing(side, metal, n, size=1.0):
    """Fan of feathers on one side (side=+1 right, -1 left). Returns svg string."""
    hi, li, mid, dk, dp = METALS[metal]
    gid = props.uid("fw")
    defs = props.lin_grad(gid, [(0, li), (0.5, mid), (1, dk)], 0, 0, 1, 0)
    out = []
    count = 5 + 2 * n
    for i in range(count):
        t = i / (count - 1)
        ang = -70 + t * 95        # degrees from up, toward outside
        L = (190 + 140 * math.sin(t * math.pi * 0.9 + 0.2)) * size * (0.85 + 0.15 * n)
        w = 52 * size
        ax, ay = 512 + side * 215, 470 + t * 120
        d = (f"M0,0 C{-w * 0.7:.1f},{-L * 0.3:.1f} {-w * 0.5:.1f},{-L * 0.85:.1f} 0,{-L:.1f} "
             f"C{w * 0.5:.1f},{-L * 0.85:.1f} {w * 0.7:.1f},{-L * 0.3:.1f} 0,0Z")
        tf = f'transform="translate({ax:.1f},{ay:.1f}) rotate({side * (ang + 35):.1f})"'
        out.append((f'<path d="{d}" {tf} fill="{INK}" stroke="{INK}" stroke-width="16" stroke-linejoin="round"/>',
                    f'<path d="{d}" {tf} fill="url(#{gid})"/>'
                    f'<path d="M0,-8 L0,{-L * 0.8:.1f}" {tf} stroke="{dp}" stroke-width="5" stroke-opacity="0.6"/>'))
    body = "".join(o[0] for o in out[::-1]) + "".join(o[1] for o in out[::-1])
    return defs, body


def laurel(metal):
    hi, li, mid, dk, dp = METALS[metal]
    out = []
    for side in (-1, 1):
        for i in range(9):
            t = i / 8
            a = math.radians(200 - t * 115) if side < 0 else math.radians(-20 + t * 115)
            r = 330
            x = CX + math.cos(a) * r * (1 if side > 0 else 1)
            y = 600 + math.sin(a) * r * 0.95
            x = CX + side * abs(x - CX)
            ang = math.degrees(a) + (90 if side > 0 else -90)
            leaf = "M0,-34 C18,-22 18,22 0,34 C-18,22 -18,-22 0,-34Z"
            tf = f'transform="translate({x:.1f},{y:.1f}) rotate({ang + side * 35:.1f})"'
            out.append((f'<path d="{leaf}" {tf} fill="{INK}" stroke="{INK}" stroke-width="12"/>',
                        f'<path d="{leaf}" {tf} fill="{mid}"/><path d="M0,-30 C10,-18 10,10 0,30Z" {tf} fill="{li}"/>'))
    return "".join(o[0] for o in out) + "".join(o[1] for o in out)


def crown_svg(metal, y=226, gem="#E0262F"):
    hi, li, mid, dk, dp = METALS[metal]
    gid = props.uid("cr")
    defs = props.lin_grad(gid, [(0, hi), (0.4, li), (1, dk)], 0, 0, 0, 1)
    d = (f"M372,{y} L392,{y - 110} L448,{y - 50} L512,{y - 150} L576,{y - 50} L632,{y - 110} L652,{y} Z")
    p = [f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="22" stroke-linejoin="round"/>',
         f'<path d="{d}" fill="url(#{gid})"/>',
         f'<rect x="372" y="{y - 30}" width="280" height="34" fill="{dk}"/>']
    for x, yy, r in ((392, y - 110, 15), (512, y - 150, 19), (632, y - 110, 15)):
        p.append(f'<circle cx="{x}" cy="{yy}" r="{r + 7}" fill="{INK}"/><circle cx="{x}" cy="{yy}" r="{r}" fill="{li}"/>')
    for x in (430, 512, 594):
        p.append(f'<path d="M{x},{y - 30} l14,17 l-14,17 l-14,-17Z" fill="{gem}" stroke="{INK}" stroke-width="5"/>')
    return defs, "".join(p)


def bats_svg():
    p = []
    for side in (-1, 1):
        tf = f'transform="rotate({side * 38} 512 560)"'
        bat = "M500,120 C500,100 524,100 524,120 L534,640 C536,700 528,780 522,860 L530,890 L494,890 L502,860 C496,780 488,700 490,640Z"
        p.append(f'<path d="{bat}" {tf} fill="{INK}" stroke="{INK}" stroke-width="18" stroke-linejoin="round"/>')
        p.append(f'<path d="{bat}" {tf} fill="url(#batg)"/>')
        p.append(f'<path d="M506,140 L512,640" {tf} stroke="#FFF0D0" stroke-width="6" stroke-opacity="0.5"/>')
        p.append(f'<rect x="496" y="800" width="32" height="56" {tf} fill="#1C2E4A"/>')
    defs = props.lin_grad("batg", [(0, "#E8C48A"), (0.5, "#C08A4A"), (1, "#7A4A20")], 0, 0, 1, 0)
    return defs, "".join(p)


def banner_svg(metal):
    hi, li, mid, dk, dp = METALS[metal]
    y = 800
    main = f"M300,{y} C400,{y + 40} 624,{y + 40} 724,{y} L742,{y + 80} C624,{y + 120} 400,{y + 120} 282,{y + 80}Z"
    tails = (f"M300,{y + 6} L220,{y + 30} L250,{y + 66} L214,{y + 104} L290,{y + 88}Z"
             f"M724,{y + 6} L804,{y + 30} L774,{y + 66} L810,{y + 104} L734,{y + 88}Z")
    return (f'<path d="{tails}{main}" fill="{INK}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>'
            f'<path d="{tails}" fill="{dk}"/><path d="{main}" fill="{mid}"/>'
            f'<path d="M310,{y + 14} C410,{y + 52} 614,{y + 52} 714,{y + 14}" fill="none" stroke="{li}" stroke-width="8" stroke-opacity="0.8"/>'
            + "".join(props.inked(props.poly_d(fx_star(x, y + 62, 18, 8)), PAL["gold"], INK, 4) for x in (452, 512, 572)))


def fx_star(cx, cy, ro, ri):
    out = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = ro if i % 2 == 0 else ri
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


def emblem(div: str) -> np.ndarray:
    body_m, trim_m, shape, stars, wings, laurels, crown, bats, banner, gem, aura = TIER[div]
    lay = blank(S, S)
    defs, behind, front = [], [], []
    sh = SHIELDS[shape]
    # back elements (kept inside a circular fade so nothing is clipped by the canvas) ---
    edge_fade = smoothstep(508, 400, radial(S, S, 512, 512, 1.0))[..., None]
    if aura == "prism":
        cols = ["#FF5A5F", "#FFAA1D", "#FFE135", "#5BD75B", "#3A8DFF", "#B45CFF"]
        rays = blank(S, S)
        for i, ccol in enumerate(cols * 3):
            a0 = i / 18 * 2 * math.pi
            body = (f'<path d="M512,520 L{512 + math.cos(a0 - 0.07) * 700:.1f},{520 + math.sin(a0 - 0.07) * 700:.1f} '
                    f'L{512 + math.cos(a0 + 0.07) * 700:.1f},{520 + math.sin(a0 + 0.07) * 700:.1f}Z" fill="{ccol}"/>')
            rays = over(rays, rasterize(svg_doc(S, S, body), S, S))
        fade = np.exp(-(radial(S, S, 512, 520, 520) ** 2))
        rays *= fade[..., None]
        lay = add(lay, blur(rays, 6) * edge_fade, 1.2)
        lay = add(lay, from_mask(np.exp(-(radial(S, S, 512, 520, 280) ** 2)), "#E8C8FF") * edge_fade, 0.8)
    elif aura:
        lay = add(lay, from_mask(np.exp(-(radial(S, S, 512, 520, 300) ** 2)), aura) * edge_fade, 0.55 + 0.1 * wings)
        if div in ("diamond", "champion"):
            lay = add(lay, fx.light_rays(S, S, 512, 520, 22, 5, aura, spread=0.5, opacity=(0.08, 0.25)) * edge_fade, 0.9)
    if bats:
        d, b = bats_svg()
        defs.append(d)
        behind.append(b)
    if wings:
        for side in (-1, 1):
            d, b = feather_wing(side, trim_m if div != "diamond" else "silver", wings)
            defs.append(d)
            behind.append(b)
    if laurels:
        behind.append(laurel(trim_m))
    # shield ----------------------------------------------------------------
    gb, gt = props.uid("mb"), props.uid("mt")
    defs.append(metal_grad(gb, body_m))
    defs.append(metal_grad(gt, trim_m, 0.9, 0, 0.1, 1))
    front.append(f'<path d="{sh}" fill="{INK}" stroke="{INK}" stroke-width="40" stroke-linejoin="round"/>')
    front.append(f'<path d="{sh}" fill="url(#{gt})"/>')
    front.append(f'<path d="{sh}" {scaled(sh, 0.86)} fill="{INK}" fill-opacity="0.55"/>')
    front.append(f'<path d="{sh}" {scaled(sh, 0.84)} fill="url(#{gb})"/>')
    if div == "rookie":
        front.append(f'<path d="{sh}" {scaled(sh, 0.92)} fill="none" stroke="#F2DDB0" stroke-width="7" stroke-dasharray="22 14"/>')
    # specular sweep on the face
    front.append(f'<path d="M330,330 C420,300 520,300 600,320 L560,380 C480,360 400,370 340,400Z" fill="#FFFFFF" fill-opacity="0.18"/>')
    # central diamond plate
    s_ = 150 if div != "rookie" else 140
    dia = [(512, 540 - s_), (512 + s_, 540), (512, 540 + s_), (512 - s_, 540)]
    plate_col = METALS["navy"][2]
    front.append(f'<path d="{props.poly_d(dia)}" fill="{INK}" stroke="{INK}" stroke-width="30" stroke-linejoin="round"/>')
    front.append(f'<path d="{props.poly_d(dia)}" fill="{plate_col}"/>')
    inner = [(512, 540 - s_ * 0.8), (512 + s_ * 0.8, 540), (512, 540 + s_ * 0.8), (512 - s_ * 0.8, 540)]
    front.append(f'<path d="{props.poly_d(inner)}" fill="none" stroke="#F4F1EA" stroke-width="7"/>')
    for x, y in inner:
        r = 16
        front.append(f'<path d="M{x},{y - r} L{x + r},{y} L{x},{y + r} L{x - r},{y}Z" fill="#F4F1EA" stroke="{INK}" stroke-width="5"/>')
    # stars on top
    if stars and not crown:
        xs = [512] if stars == 1 else [420, 512, 604]
        for i, x in enumerate(xs):
            y = 180 if (stars == 1 or i == 1) else 205
            r = 46 if (stars == 1 or i == 1) else 36
            front.append(props.inked(props.poly_d(fx_star(x, y, r, r * 0.45)), METALS[trim_m][1], INK, 9))
    svg = svg_doc(S, S, "".join(behind) + "".join(front), "".join(defs))
    lay = over(lay, rasterize(svg, S, S))
    # ball in the centre
    rim = {"legend": "#E8C8FF", "champion": "#FFD45A", "diamond": "#BFEFFF"}.get(div, "#FFFFFF")
    b = render_ball(170, rot=(0.5, 0.6, 0.3), rim=rim, rim_strength=0.7, light=(-0.4, 0.7, 0.6), outline=0.06)
    if gem:
        lay = place(lay, from_mask(blur(np.pad(b[..., 3], 60), 22), rim), 512, 540, "add", 0.8)
    lay = place(lay, b, 512, 540)
    # overlays: crown, banner, diamond gem
    top = []
    tdefs = []
    if crown:
        d, cr = crown_svg("gold", 236, "#E0262F" if div == "champion" else "#9B5DE5")
        tdefs.append(d)
        top.append(cr)
    if banner:
        top.append(banner_svg(banner))
    if div == "diamond":
        g = props.uid("gm")
        top.append(f'<g transform="translate(512,200) scale(0.42) translate(-512,-200)">'
                   f'{gem_side_svg(512, 200, 260)}</g>')
    if top:
        lay = over(lay, rasterize(svg_doc(S, S, "".join(top), "".join(tdefs)), S, S))
    # sparkles for the top tiers
    if div in ("diamond", "champion", "legend"):
        sp = "".join(fx.sparkle_svg(x, y, r, "#FFFFFF", 0.95, 0.3, 0.12)
                     for x, y, r in ((330, 330, 34), (700, 700, 26), (720, 300, 22), (300, 760, 18)))
        lay = add(lay, rasterize(svg_doc(S, S, sp), S, S), 1.0)
    return lay


def gem_side_svg(cx, cy, s):
    tw, cw, ch, ph = s * 0.55, s, s * 0.32, s * 0.85
    T = cy - ch
    light, mid, dark = "#FFFFFF", "#9FE0FF", "#2F7DE1"
    outline = [(cx - tw / 2, T), (cx + tw / 2, T), (cx + cw / 2, cy), (cx, cy + ph), (cx - cw / 2, cy)]
    p = [f'<path d="{props.poly_d(outline)}" fill="{INK}" stroke="{INK}" stroke-width="30" stroke-linejoin="round"/>']
    facets = [((cx - tw / 2, T), (cx - cw / 2, cy), (cx - cw * 0.25, cy), light),
              ((cx - tw / 2, T), (cx - cw * 0.25, cy), (cx, T), mid),
              ((cx, T), (cx - cw * 0.25, cy), (cx + cw * 0.25, cy), light),
              ((cx, T), (cx + cw * 0.25, cy), (cx + tw / 2, T), mid),
              ((cx + tw / 2, T), (cx + cw * 0.25, cy), (cx + cw / 2, cy), dark),
              ((cx - cw / 2, cy), (cx - cw * 0.25, cy), (cx, cy + ph), mid),
              ((cx - cw * 0.25, cy), (cx, cy), (cx, cy + ph), light),
              ((cx, cy), (cx + cw * 0.25, cy), (cx, cy + ph), mid),
              ((cx + cw * 0.25, cy), (cx + cw / 2, cy), (cx, cy + ph), dark)]
    for a, b, c, col in facets:
        p.append(f'<path d="{props.poly_d([a, b, c])}" fill="{col}"/>')
    return "".join(p)


# ---------------------------------------------------------------------------
# Rarity gems
# ---------------------------------------------------------------------------
GEM_CUT = {"common": (0, 1), "uncommon": (4, 2), "rare": (6, 2), "epic": (8, 3), "legendary": (10, 4)}


def gem_icon(rarity: str) -> np.ndarray:
    G = 512
    col = RARITY[rarity]
    n, lvl = GEM_CUT[rarity]
    cx, cy = G / 2, G / 2
    lay = blank(G, G)
    fade = smoothstep(250, 170, radial(G, G, cx, cy, 1.0))[..., None]
    if lvl >= 3:
        lay = add(lay, from_mask(np.exp(-(radial(G, G, cx, cy, 170) ** 2)), col) * fade, 0.55 if lvl == 3 else 0.8)
    if lvl >= 4:
        lay = add(lay, fx.light_rays(G, G, cx, cy, 16, 2, lighten(col, 0.4), spread=0.5, opacity=(0.15, 0.35)) * fade, 0.9)
    body = []
    L = lambda t: lighten(col, t)
    D = lambda t: darken(col, t)
    if n == 0:
        # common: round cabochon
        R = 150
        gid = props.uid("cb")
        defs = props.rad_grad(gid, [(0, L(0.6)), (0.5, col), (1, D(0.45))], 0.4, 0.35, 0.7)
        body.append(f'<circle cx="{cx}" cy="{cy}" r="{R + 22}" fill="{INK}"/>')
        body.append(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="url(#{gid})"/>')
        body.append(f'<ellipse cx="{cx - 45}" cy="{cy - 55}" rx="50" ry="30" fill="#FFFFFF" fill-opacity="0.75" transform="rotate(-30 {cx - 45} {cy - 55})"/>')
        svg = svg_doc(G, G, "".join(body), defs)
    else:
        R = 190 if n != 4 else 200
        r_t = R * 0.52
        rot = -math.pi / 2 if n != 4 else -math.pi / 2
        sy = 1.0 if n != 4 else 1.25
        outer = [(cx + math.cos(rot + i * 2 * math.pi / n) * R / (sy if n == 4 else 1), cy + math.sin(rot + i * 2 * math.pi / n) * R * (1 if n != 4 else 1.0)) for i in range(n)]
        if n == 4:
            outer = [(cx, cy - R), (cx + R * 0.72, cy), (cx, cy + R), (cx - R * 0.72, cy)]
        inner = [(cx + (x - cx) * 0.52, cy + (y - cy) * 0.52) for x, y in outer]
        body.append(f'<path d="{props.poly_d(outer)}" fill="{INK}" stroke="{INK}" stroke-width="44" stroke-linejoin="round"/>')
        light_dir = math.radians(-135)
        for i in range(n):
            a, b = outer[i], outer[(i + 1) % n]
            ia, ib = inner[i], inner[(i + 1) % n]
            mx, my = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy
            ang = math.atan2(my, mx)
            k = 0.5 + 0.5 * math.cos(ang - light_dir)
            c1 = L(0.55 * k) if k > 0.5 else D(0.5 * (1 - k))
            c2 = L(0.35 * k) if k > 0.45 else D(0.6 * (1 - k))
            body.append(f'<path d="{props.poly_d([a, b, ib, ia])}" fill="{c1}"/>')
            body.append(f'<path d="{props.poly_d([ia, b, ib])}" fill="{c2}"/>')
        gid = props.uid("tb")
        defs = props.lin_grad(gid, [(0, L(0.6)), (0.6, col), (1, D(0.2))], 0.2, 0, 0.8, 1)
        body.append(f'<path d="{props.poly_d(inner)}" fill="url(#{gid})"/>')
        body.append(f'<path d="{props.poly_d(inner[:2] + [(cx, cy)])}" fill="#FFFFFF" fill-opacity="0.35"/>')
        for i in range(n):
            a, ia = outer[i], inner[i]
            body.append(f'<path d="M{a[0]:.1f},{a[1]:.1f} L{ia[0]:.1f},{ia[1]:.1f}" stroke="{INK}" stroke-opacity="0.35" stroke-width="5"/>')
        body.append(f'<path d="{props.poly_d(outer)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="6"/>')
        svg = svg_doc(G, G, "".join(body), defs)
    gem = rasterize(svg, G, G)
    lay = add(lay, from_mask(blur(gem[..., 3], 18), col) * fade, 0.4 + 0.15 * lvl)
    lay = over(lay, gem)
    if lvl >= 2:
        sp = fx.sparkle_svg(cx - 70, cy - 85, 46 + 10 * lvl, "#FFFFFF", 1.0, 0.0, 0.14)
        if lvl >= 3:
            sp += fx.sparkle_svg(cx + 95, cy + 80, 30, "#FFFFFF", 0.9, 0.4, 0.14)
        lay = add(lay, rasterize(svg_doc(G, G, sp), G, G), 1.0)
    return lay


def build(out_dir=OUT):
    out = []
    for div in DIVISIONS:
        p = save(emblem(div), out_dir / f"rank_{div}.png", size=(256, 256))
        out.append(p)
    print(f"  {len(DIVISIONS)} rank emblems")
    for r in RARITY:
        out.append(save(gem_icon(r), out_dir / f"gem_{r}.png", size=(64, 64)))
    print(f"  {len(RARITY)} rarity gems")
    return out


if __name__ == "__main__":
    build()
