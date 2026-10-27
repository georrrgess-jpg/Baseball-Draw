"""Portraits for runner types that reuse another runner's model in new colours.

  python3 tools/art/portrait_variants.py

The Base Stealer wears the Runner model with magenta trim (data/enemies.json "colors"), so
its portrait is the Runner portrait with the orange trim turned magenta and the dark
uniform tinted plum. No Blender render needed.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PORTRAITS = ROOT / "assets" / "textures" / "portraits"

# id: (source portrait, hue shift in degrees for saturated trim, tint for the dark uniform)
VARIANTS = {
    "base_stealer": ("runner", -62.0, (0.16, 0.08, 0.19)),
}


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    out = np.zeros(hsv.shape)
    for k, (a, b, c) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        sel = i == k
        out[..., 0][sel] = a[sel]
        out[..., 1][sel] = b[sel]
        out[..., 2][sel] = c[sel]
    return out


def build(cid):
    src, shift, tint = VARIANTS[cid]
    im = np.asarray(Image.open(PORTRAITS / f"{src}.png").convert("RGBA"), np.float64) / 255.0
    rgb, a = im[..., :3], im[..., 3:]
    hsv = rgb_to_hsv(rgb)
    orange = (hsv[..., 0] < 0.16) | (hsv[..., 0] > 0.95)
    trim = np.clip((hsv[..., 1] - 0.08) / 0.2, 0, 1) * orange    # the orange trim, incl. its soft edges
    shifted = hsv.copy()
    shifted[..., 0] = (hsv[..., 0] + shift / 360.0) % 1.0
    out = rgb * (1 - trim[..., None]) + hsv_to_rgb(shifted) * trim[..., None]
    # Tint the dark, unsaturated uniform toward plum (strongest in the shadows).
    dark = (1 - trim) * np.clip(1.0 - hsv[..., 2] * 1.6, 0, 1)
    out = out + np.array(tint)[None, None, :] * dark[..., None] * 0.6
    res = np.concatenate([np.clip(out, 0, 1), a], -1)
    path = PORTRAITS / f"{cid}.png"
    Image.fromarray((res * 255 + 0.5).astype(np.uint8), "RGBA").save(path)
    print("  portrait", path.relative_to(ROOT))


if __name__ == "__main__":
    for cid in VARIANTS:
        build(cid)
