"""Text-bearing placeholder textures (needs Pillow; run with the system python3).

    python3 text_textures.py <out_dir>

Writes:
  screen.png  1152x512  scoreboard LED placeholder (9:4, matches the Screen quad)
  banner.png   512x1344 vertical stadium banner placeholder (matches Banner mesh)
The game replaces both at runtime; these only make the props look finished.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'assets', 'fonts'))


def font(name, size):
    for cand in (os.path.join(FONTS, name), name):
        try:
            return ImageFont.truetype(cand, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def text_center(d, xy, s, f, fill):
    bb = d.textbbox((0, 0), s, font=f)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    d.text((xy[0] - w / 2 - bb[0], xy[1] - h / 2 - bb[1]), s, font=f, fill=fill)


def screen(path):
    W, H = 1152, 512
    img = Image.new('RGB', (W, H), (6, 8, 12))
    d = ImageDraw.Draw(img)
    amber = (255, 176, 46)
    white = (240, 236, 226)
    scarlet = (230, 38, 47)
    blue = (47, 125, 225)
    title = font('RussoOne-Regular.ttf', 66)
    big = font('BarlowCondensed-Bold.ttf', 58)
    mid = font('BarlowCondensed-Bold.ttf', 44)
    # header band
    d.rectangle((0, 0, W, 92), fill=(20, 35, 58))
    d.rectangle((0, 92, W, 98), fill=scarlet)
    text_center(d, (W / 2, 48), 'STEEL YARD', title, white)
    # line score grid
    x0, y0 = 40, 128
    cw = 66
    cols = [str(i) for i in range(1, 10)] + ['R', 'H', 'E']
    for i, c in enumerate(cols):
        cx = x0 + 230 + i * cw + cw / 2
        text_center(d, (cx, y0 + 26), c, mid, amber if c in 'RHE' else white)
    rows = [('AWAY', scarlet, [0, 1, 0, 0, 2, 0, 0, 1, None], [4, 7, 1]),
            ('HOME', blue, [1, 0, 0, 3, 0, 0, 1, 0, None], [5, 9, 0])]
    for r, (name, col, inn, rhe) in enumerate(rows):
        y = y0 + 70 + r * 84
        d.rectangle((x0, y, x0 + 210, y + 70), fill=col)
        text_center(d, (x0 + 105, y + 35), name, big, white)
        for i, v in enumerate(inn + rhe):
            cx = x0 + 230 + i * cw + cw / 2
            d.rectangle((cx - cw / 2 + 4, y + 4, cx + cw / 2 - 4, y + 66), outline=(40, 46, 58), width=2)
            if v is not None:
                text_center(d, (cx, y + 35), str(v), big, amber)
    # count / outs
    yb = 420
    for i, (lab, n, on, c) in enumerate((('BALL', 4, 2, (61, 220, 132)), ('STRIKE', 3, 1, amber), ('OUT', 3, 2, scarlet))):
        bx = 70 + i * 360
        text_center(d, (bx + 60, yb + 30), lab, mid, white)
        for k in range(n - 1 if lab != 'BALL' else 3):
            cx = bx + 150 + k * 52
            d.ellipse((cx - 18, yb + 12, cx + 18, yb + 48), fill=c if k < on else (40, 44, 52))
    # LED dot matrix
    a = np.asarray(img).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    cell = 4
    fx = (xx % cell) - (cell - 1) / 2
    fy = (yy % cell) - (cell - 1) / 2
    dot = np.clip(1.6 - np.sqrt(fx * fx + fy * fy), 0.25, 1.0)
    a = a * dot[..., None]
    a = np.clip(a * 1.1 + 0.015, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(path)


def banner(path):
    W, H = 512, 1344
    img = Image.new('RGB', (W, H), (196, 31, 41))
    d = ImageDraw.Draw(img)
    navy = (20, 35, 58)
    gold = (245, 184, 46)
    white = (244, 241, 234)
    # vertical gradient for depth
    a = np.asarray(img).astype(np.float32)
    g = np.linspace(1.0, 0.72, H)[:, None, None]
    img = Image.fromarray(np.clip(a * g, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 150), fill=navy)
    d.rectangle((0, H - 170, W, H), fill=navy)
    d.rectangle((0, 150, W, 160), fill=gold)
    d.rectangle((0, H - 180, W, H - 170), fill=gold)
    d.rectangle((24, 160, 34, H - 180), fill=white)
    d.rectangle((W - 34, 160, W - 24, H - 180), fill=white)
    # baseball emblem
    cx, cy, r = W / 2, 330, 120
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=white, outline=navy, width=8)
    for side in (-1, 1):
        pts = []
        for k in range(40):
            t = -1.1 + 2.2 * k / 39
            x = cx + side * (r * 0.62 - r * 0.28 * math.cos(t * 1.4))
            y = cy + r * 0.82 * math.sin(t)
            pts.append((x, y))
        d.line(pts, fill=(200, 35, 44), width=6)
        for k in range(2, 38, 4):
            x, y = pts[k]
            d.line((x - 12, y - 5, x + 12, y + 5) if side < 0 else (x - 12, y + 5, x + 12, y - 5),
                   fill=(200, 35, 44), width=4)
    text_center(d, (W / 2, 80), 'STEEL', font('RussoOne-Regular.ttf', 92), white)
    text_center(d, (W / 2, H - 90), 'YARD', font('RussoOne-Regular.ttf', 104), white)
    # rotated team name
    size = 190
    while size > 40:
        f = font('BarlowCondensed-Bold.ttf', size)
        bb = d.textbbox((0, 0), 'DEFENDERS', font=f)
        if bb[2] - bb[0] <= 640:
            break
        size -= 4
    tw = Image.new('RGBA', (700, 240), (0, 0, 0, 0))
    td = ImageDraw.Draw(tw)
    text_center(td, (350, 120), 'DEFENDERS', f, white)
    tw = tw.rotate(90, expand=True, resample=Image.BICUBIC)
    img.paste(tw, (int(W / 2 - tw.width / 2), 480), tw)
    # subtle fabric weave + wear
    a = np.asarray(img).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    weave = 0.96 + 0.04 * np.sin(xx * 1.3) * np.sin(yy * 1.3)
    rng = np.random.default_rng(3)
    nse = Image.fromarray((rng.random((H // 16, W // 16)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    nse = np.asarray(nse.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0
    a = a * weave[..., None] * (0.9 + 0.12 * nse[..., None])
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    screen(os.path.join(out, 'screen.png'))
    banner(os.path.join(out, 'banner.png'))
    print('text textures written to', out)


if __name__ == '__main__':
    main()
