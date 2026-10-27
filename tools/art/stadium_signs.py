#!/usr/bin/env python3
"""Outfield-wall advertising boards for the stadium (fictional brands).

Writes assets/textures/stadium/ad_boards.png: an atlas of 8 boards (each 512x128, 2 columns x 4 rows).
The stadium builder picks boards by index (row-major) and maps them onto panels on the outfield wall.

Usage (from the repo root):  python3 tools/art/stadium_signs.py
Requires Pillow.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "assets" / "fonts"
OUT = ROOT / "assets" / "textures" / "stadium" / "ad_boards.png"
W, H = 512, 128

# (headline, tagline, background, headline colour, accent, font, motif)
BOARDS = [
    ("SLUGGER SODA", "CRACK OPEN A COLD ONE", "#c81d25", "#fff6e0", "#ffd23f", "Bangers-Regular.ttf", "bubbles"),
    ("DIAMOND DOGS", "FOOT-LONG FRANKS", "#ffd23f", "#7a1010", "#c81d25", "RussoOne-Regular.ttf", "stripes"),
    ("FASTBALL FUEL", "ENERGY FOR EXTRA INNINGS", "#0b2545", "#5ce1ff", "#ff7a1a", "RussoOne-Regular.ttf", "speed"),
    ("GRAND SLAM BANK", "WE COVER ALL THE BASES", "#13315c", "#ffffff", "#ffc83d", "Oswald-Variable.ttf", "diamond"),
    ("BULLPEN BURGERS", "RELIEF IS ON THE WAY", "#2b9348", "#ffffff", "#ffd23f", "Bangers-Regular.ttf", "dots"),
    ("CURVEBALL COFFEE", "A BREAK YOU CAN TASTE", "#3e2723", "#ffe8c2", "#ff9f43", "Teko-Variable.ttf", "swirl"),
    ("HOMER HARDWARE", "BUILT TO GO DEEP", "#f77f00", "#1b1b1b", "#ffffff", "RussoOne-Regular.ttf", "stripes"),
    ("DRAW YOUR HAND", "BASEBALL DRAW", "#1c2e4a", "#ffffff", "#e0262f", "Bangers-Regular.ttf", "ball"),
]


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONTS / name), size)
    if name.startswith(("Oswald", "Teko")):
        try:
            f.set_variation_by_name("Bold")
        except Exception:
            pass
    return f


def fit_font(name: str, text: str, max_w: int, size: int) -> ImageFont.FreeTypeFont:
    while size > 12:
        f = font(name, size)
        if f.getbbox(text)[2] <= max_w:
            return f
        size -= 2
    return font(name, size)


def motif(d: ImageDraw.ImageDraw, kind: str, accent: str, bg: str) -> None:
    if kind == "stripes":
        for x in range(-H, W, 40):
            d.polygon([(x, H), (x + 18, H), (x + 18 + H, 0), (x + H, 0)], fill=_mix(bg, accent, 0.12))
    elif kind == "speed":
        for i, y in enumerate(range(18, H, 22)):
            d.rectangle([W - 140 + i * 10, y, W - 20, y + 5], fill=_mix(bg, accent, 0.5))
    elif kind == "diamond":
        c = (W - 64, H // 2)
        d.polygon([(c[0], c[1] - 40), (c[0] + 40, c[1]), (c[0], c[1] + 40), (c[0] - 40, c[1])], outline=accent, width=5)
    elif kind == "dots":
        for x in range(10, W, 26):
            for y in range(10, H, 26):
                d.ellipse([x, y, x + 6, y + 6], fill=_mix(bg, "#ffffff", 0.15))
    elif kind == "bubbles":
        for i in range(14):
            x = W - 140 + (i * 37) % 120
            y = 15 + (i * 53) % 100
            r = 4 + (i * 7) % 9
            d.ellipse([x - r, y - r, x + r, y + r], outline=_mix(bg, "#ffffff", 0.6), width=2)
    elif kind == "swirl":
        pts = [(W - 120 + 40 * math.cos(t / 6) * (t / 40), H / 2 + 40 * math.sin(t / 6) * (t / 40)) for t in range(0, 40)]
        d.line(pts, fill=accent, width=4)
    elif kind == "ball":
        c = (W - 66, H // 2)
        d.ellipse([c[0] - 42, c[1] - 42, c[0] + 42, c[1] + 42], fill="#f7f4ec")
        d.arc([c[0] - 92, c[1] - 40, c[0] - 12, c[1] + 40], -50, 50, fill=accent, width=3)
        d.arc([c[0] + 12, c[1] - 40, c[0] + 92, c[1] + 40], 130, 230, fill=accent, width=3)


def _mix(a: str, b: str, t: float) -> tuple:
    ca = tuple(int(a[i:i + 2], 16) for i in (1, 3, 5))
    cb = tuple(int(b[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(int(ca[i] + (cb[i] - ca[i]) * t) for i in range(3))


def board(headline, tagline, bg, fg, accent, fname, kind) -> Image.Image:
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    motif(d, kind, accent, bg)
    # Accent bars top and bottom.
    d.rectangle([0, 0, W, 7], fill=accent)
    d.rectangle([0, H - 8, W, H], fill=accent)
    text_w = W - (170 if kind in ("speed", "diamond", "bubbles", "swirl", "ball") else 40)
    hf = fit_font(fname, headline, text_w, 72)
    sf = fit_font("BarlowCondensed-Bold.ttf", tagline, text_w, 26)
    hb = hf.getbbox(headline)
    x = 22
    y = 14
    # Drop shadow then the headline.
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).text((x + 3, y + 4), headline, font=hf, fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2))
    img.paste(Image.new("RGB", (W, H), "#000000"), (0, 0), shadow)
    d = ImageDraw.Draw(img)
    d.text((x, y), headline, font=hf, fill=fg)
    d.text((x + 2, y + hb[3] + 6), tagline, font=sf, fill=accent if accent != bg else fg)
    return img


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGB", (W * 2, H * 4), "#000000")
    for i, b in enumerate(BOARDS):
        atlas.paste(board(*b), ((i % 2) * W, (i // 2) * H))
    atlas.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} ({atlas.width}x{atlas.height})")


if __name__ == "__main__":
    main()
