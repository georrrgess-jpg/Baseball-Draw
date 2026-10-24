"""App icon: icon.svg (repo root, 256 viewBox) + rasterised icon_256.png and multi-size icon.ico.

The SVG uses only paths, circles and linear/radial gradients so Godot's ThorVG
importer renders it identically to librsvg.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from artlib.core import ROOT, TEX_DIR, rasterize, to_image
from artlib.props import bezier

LOGO_DIR = TEX_DIR / "logo"


def _f(v):
    return f"{v:.1f}"


def icon_svg() -> str:
    cx, cy, r = 152, 100, 70
    parts = []
    defs = (
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#22385C"/><stop offset="1" stop-color="#0E1A2B"/></linearGradient>'
        '<linearGradient id="slash" x1="0" y1="1" x2="0.7" y2="0.2">'
        '<stop offset="0" stop-color="#A3141C"/><stop offset="0.5" stop-color="#E0262F"/><stop offset="1" stop-color="#FF4D55"/></linearGradient>'
        '<radialGradient id="ball" cx="0.38" cy="0.32" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F1EDE4"/><stop offset="1" stop-color="#A9B0C2"/></radialGradient>'
    )
    parts.append('<rect x="8" y="8" width="240" height="240" rx="52" fill="url(#bg)"/>')
    parts.append('<rect x="8" y="8" width="240" height="240" rx="52" fill="none" stroke="#F5B82E" stroke-width="5"/>')
    # scarlet dry-brush trail: wide under the ball, fraying into bristle streaks toward the lower left
    hx, hy = cx - 6, cy + 8
    tx, ty = 34, 214
    L = math.hypot(tx - hx, ty - hy)
    ux, uy = (tx - hx) / L, (ty - hy) / L
    nx, ny = -uy, ux
    W0 = 96
    streaks = [(-0.42, 1.00, 0.20), (-0.17, 0.86, 0.22), (0.08, 0.96, 0.20), (0.32, 0.78, 0.18), (0.50, 0.62, 0.12)]
    body = []
    for off, ln, wd in streaks:
        pts_l, pts_r = [], []
        for k in range(21):
            t = k / 20 * ln
            w = W0 * wd * (1 - (t / ln) ** 2.2) + 1.0
            o = off * W0 * (1 - 0.35 * t)
            x, y = hx + ux * t * L + nx * o, hy + uy * t * L + ny * o
            pts_l.append((x + nx * w / 2, y + ny * w / 2))
            pts_r.append((x - nx * w / 2, y - ny * w / 2))
        body.append("M" + " L".join(f"{_f(x)},{_f(y)}" for x, y in pts_l + pts_r[::-1]) + "Z")
    head = (f"M{_f(hx + nx * W0 * 0.55)},{_f(hy + ny * W0 * 0.55)} "
            f"L{_f(hx + ux * L * 0.45 + nx * W0 * 0.42)},{_f(hy + uy * L * 0.45 + ny * W0 * 0.42)} "
            f"L{_f(hx + ux * L * 0.45 - nx * W0 * 0.52)},{_f(hy + uy * L * 0.45 - ny * W0 * 0.52)} "
            f"L{_f(hx - nx * W0 * 0.62)},{_f(hy - ny * W0 * 0.62)}Z")
    slash = head + "".join(body)
    parts.append(f'<path d="{slash}" fill="#070D17" transform="translate(4,6)" fill-opacity="0.45"/>')
    parts.append(f'<path d="{slash}" fill="url(#slash)"/>')
    parts.append(f'<path d="M{_f(hx + ux * 20 + nx * 30)},{_f(hy + uy * 20 + ny * 30)} L{_f(hx + ux * L * 0.62 + nx * 20)},{_f(hy + uy * L * 0.62 + ny * 20)}" '
                 f'stroke="#FF8A8F" stroke-width="5" stroke-linecap="round" stroke-opacity="0.7"/>')
    # speed streaks
    for (x0, y0, x1, y1, w) in ((150, 214, 196, 186, 6), (178, 226, 214, 204, 4)):
        parts.append(f'<path d="M{x0},{y0} L{x1},{y1}" stroke="#FFFFFF" stroke-width="{w}" stroke-linecap="round" stroke-opacity="0.8"/>')
    # ball with ink outline
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r + 7}" fill="#070D17"/>')
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#ball)"/>')
    for side in (-1, 1):
        p0 = (cx + side * r * 0.66, cy - r * 0.75)
        p1 = (cx + side * r * 0.20, cy - r * 0.30)
        p2 = (cx + side * r * 0.20, cy + r * 0.30)
        p3 = (cx + side * r * 0.66, cy + r * 0.75)
        pts = bezier(p0, p1, p2, p3, 40)
        d = "M" + " L".join(f"{_f(x)},{_f(y)}" for x, y in pts)
        parts.append(f'<path d="{d}" fill="none" stroke="#B9B2A6" stroke-width="3"/>')
        tg = np.gradient(pts, axis=0)
        tg /= np.linalg.norm(tg, axis=1, keepdims=True)
        for i in range(3, 38, 4):
            x, y = pts[i]
            tx, ty = tg[i]
            nx, ny = -ty, tx
            for s in (-1, 1):
                ax, ay = x + nx * s * 3, y + ny * s * 3
                bx, by = x + nx * s * 11 + tx * 5, y + ny * s * 11 + ty * 5
                parts.append(f'<path d="M{_f(ax)},{_f(ay)} L{_f(bx)},{_f(by)}" stroke="#D3232C" stroke-width="4.2" stroke-linecap="round"/>')
    parts.append(f'<path d="M{cx - 50},{cy - 40} C{cx - 36},{cy - 60} {cx - 14},{cy - 66} {cx + 4},{cy - 64}" fill="none" '
                 f'stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" stroke-opacity="0.8"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
            f'<defs>{defs}</defs>{"".join(parts)}</svg>\n')


def build():
    svg = icon_svg()
    (ROOT / "icon.svg").write_text(svg)
    LOGO_DIR.mkdir(parents=True, exist_ok=True)
    big = to_image(rasterize(svg.replace('width="256" height="256"', 'width="1024" height="1024"'), 1024, 1024), dither=False)
    img256 = big.resize((256, 256), Image.LANCZOS)
    img256.save(LOGO_DIR / "icon_256.png", optimize=True)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [big.resize((s, s), Image.LANCZOS) for s in sizes]
    frames[-1].save(LOGO_DIR / "icon.ico", format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
    print("  icon.svg, icon_256.png, icon.ico")
    return [ROOT / "icon.svg", LOGO_DIR / "icon_256.png", LOGO_DIR / "icon.ico"]


if __name__ == "__main__":
    build()
