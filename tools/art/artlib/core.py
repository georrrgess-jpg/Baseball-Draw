"""Core helpers: palette, SVG rasterisation (librsvg via ctypes), font outlines
(cairo via ctypes), premultiplied-RGBA float compositing, blur and noise.

Only the Python standard library, numpy and Pillow are required. librsvg-2 and
cairo are loaded from the system with ctypes (they ship with most Linux
desktops; on this build machine they are installed system-wide).

Image convention: layers are float32 arrays of shape (H, W, 4) holding
*premultiplied* RGBA in the 0..1 range (sRGB-encoded colour).
"""
from __future__ import annotations

import ctypes
import math
import os
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
FONT_DIR = ROOT / "assets" / "fonts"
TEX_DIR = ROOT / "assets" / "textures"

# ---------------------------------------------------------------------------
# fontconfig: make the repo fonts visible to librsvg / cairo toy text API.
# Must happen before the libraries are loaded.
# ---------------------------------------------------------------------------
_TMP = Path(os.environ.get("ART_TMP", Path(tempfile.gettempdir()) / "baseball_draw_art"))
_TMP.mkdir(parents=True, exist_ok=True)
_FC_CONF = _TMP / "fonts.conf"
_FC_CONF.write_text(
    '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
    f"<fontconfig><dir>{FONT_DIR}</dir><cachedir>{_TMP / 'fccache'}</cachedir></fontconfig>\n"
)
os.environ["FONTCONFIG_FILE"] = str(_FC_CONF)

# ---------------------------------------------------------------------------
# Palette (docs/ASSET_SPEC.md section 2)
# ---------------------------------------------------------------------------
PAL = {
    "navy_dark": "#0E1A2B",
    "navy": "#14233A",
    "charcoal": "#1B1F27",
    "scarlet": "#E0262F",
    "scarlet_deep": "#A3141C",
    "blue": "#2F7DE1",
    "gold": "#F5B82E",
    "green": "#3DDC84",
    "purple": "#9B5DE5",
    "offwhite": "#F4F1EA",
    "jersey": "#1C2E4A",
    "ink": "#070D17",
}
CATEGORY = {"offense": "#FF5A36", "control": "#7B6CFF", "defense": "#2EC4B6", "utility": "#FFD23F"}
RARITY = {"common": "#B8C0CC", "uncommon": "#5BD75B", "rare": "#3A8DFF", "epic": "#B45CFF", "legendary": "#FFAA1D"}
STITCH_RED = "#D3232C"


def hexrgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def mix_hex(a: str, b: str, t: float) -> str:
    c = hexrgb(a) * (1 - t) + hexrgb(b) * t
    return "#%02X%02X%02X" % tuple(int(round(v * 255)) for v in np.clip(c, 0, 1))


def lighten(h: str, t: float) -> str:
    return mix_hex(h, "#FFFFFF", t)


def darken(h: str, t: float) -> str:
    return mix_hex(h, "#000000", t)


# ---------------------------------------------------------------------------
# librsvg / cairo through ctypes
# ---------------------------------------------------------------------------
_rsvg = ctypes.CDLL("librsvg-2.so.2")
_cairo = ctypes.CDLL("libcairo.so.2")
_gobj = ctypes.CDLL("libgobject-2.0.so.0")


class _RsvgRect(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double),
                ("width", ctypes.c_double), ("height", ctypes.c_double)]


class _CairoTextExtents(ctypes.Structure):
    _fields_ = [(n, ctypes.c_double) for n in
                ("x_bearing", "y_bearing", "width", "height", "x_advance", "y_advance")]


class _CairoPath(ctypes.Structure):
    _fields_ = [("status", ctypes.c_int), ("data", ctypes.c_void_p), ("num_data", ctypes.c_int)]


_vp = ctypes.c_void_p
_rsvg.rsvg_handle_new_from_data.restype = _vp
_rsvg.rsvg_handle_new_from_data.argtypes = [ctypes.c_char_p, ctypes.c_size_t, _vp]
_rsvg.rsvg_handle_render_document.argtypes = [_vp, _vp, ctypes.POINTER(_RsvgRect), _vp]
_rsvg.rsvg_handle_render_document.restype = ctypes.c_int
_cairo.cairo_image_surface_create.restype = _vp
_cairo.cairo_image_surface_create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
_cairo.cairo_create.restype = _vp
_cairo.cairo_create.argtypes = [_vp]
_cairo.cairo_image_surface_get_data.restype = ctypes.POINTER(ctypes.c_ubyte)
_cairo.cairo_image_surface_get_data.argtypes = [_vp]
_cairo.cairo_image_surface_get_stride.argtypes = [_vp]
_cairo.cairo_surface_flush.argtypes = [_vp]
_cairo.cairo_destroy.argtypes = [_vp]
_cairo.cairo_surface_destroy.argtypes = [_vp]
_cairo.cairo_select_font_face.argtypes = [_vp, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
_cairo.cairo_set_font_size.argtypes = [_vp, ctypes.c_double]
_cairo.cairo_move_to.argtypes = [_vp, ctypes.c_double, ctypes.c_double]
_cairo.cairo_text_path.argtypes = [_vp, ctypes.c_char_p]
_cairo.cairo_text_extents.argtypes = [_vp, ctypes.c_char_p, ctypes.POINTER(_CairoTextExtents)]
_cairo.cairo_copy_path.restype = ctypes.POINTER(_CairoPath)
_cairo.cairo_copy_path.argtypes = [_vp]
_cairo.cairo_copy_path_flat.restype = ctypes.POINTER(_CairoPath)
_cairo.cairo_copy_path_flat.argtypes = [_vp]
_cairo.cairo_path_destroy.argtypes = [ctypes.POINTER(_CairoPath)]
_cairo.cairo_new_path.argtypes = [_vp]
_cairo.cairo_set_tolerance.argtypes = [_vp, ctypes.c_double]
_gobj.g_object_unref.argtypes = [_vp]


def fimg(a: np.ndarray) -> Image.Image:
    """Float32 'F' mode PIL image from any 2D array (PIL needs contiguous float32)."""
    return Image.fromarray(np.ascontiguousarray(a, dtype=np.float32), "F")


def svg_doc(w: float, h: float, body: str, defs: str = "", vb: str | None = None) -> str:
    vb = vb or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{w}" height="{h}" viewBox="{vb}"><defs>{defs}</defs>{body}</svg>')


def rasterize(svg: str, w: int, h: int) -> np.ndarray:
    """Render an SVG document to a premultiplied float RGBA array (h, w, 4)."""
    data = svg.encode("utf-8")
    hnd = _rsvg.rsvg_handle_new_from_data(data, len(data), None)
    if not hnd:
        raise ValueError("librsvg failed to parse SVG:\n" + svg[:400])
    surf = _cairo.cairo_image_surface_create(0, int(w), int(h))
    cr = _cairo.cairo_create(surf)
    vp = _RsvgRect(0, 0, w, h)
    _rsvg.rsvg_handle_render_document(hnd, cr, ctypes.byref(vp), None)
    _cairo.cairo_surface_flush(surf)
    stride = _cairo.cairo_image_surface_get_stride(surf)
    ptr = _cairo.cairo_image_surface_get_data(surf)
    buf = np.ctypeslib.as_array(ptr, shape=(int(h), stride)).copy()
    _cairo.cairo_destroy(cr)
    _cairo.cairo_surface_destroy(surf)
    _gobj.g_object_unref(hnd)
    bgra = buf[:, :int(w) * 4].reshape(int(h), int(w), 4)
    out = np.empty((int(h), int(w), 4), np.float32)
    k = np.float32(1.0 / 255.0)
    for dst, src in ((0, 2), (1, 1), (2, 0), (3, 3)):
        np.multiply(bgra[..., src], k, out=out[..., dst], casting="unsafe")
    return out


def rasterize_alpha(svg: str, w: int, h: int) -> np.ndarray:
    """Render an SVG and return only its coverage (alpha) channel as float32 (h, w)."""
    return rasterize(svg, w, h)[..., 3].copy()


def svg_layer(w: int, h: int, body: str, defs: str = "") -> np.ndarray:
    return rasterize(svg_doc(w, h, body, defs), w, h)


# ---------------------------------------------------------------------------
# Font outlines via cairo toy text API
# ---------------------------------------------------------------------------
_TXT_SURF = _cairo.cairo_image_surface_create(0, 8, 8)


def _read_path(p) -> list:
    """Convert a cairo_path_t into a list of commands: (op, [(x,y)...])."""
    path = p.contents
    n = path.num_data
    if n <= 0:
        return []
    dbl = (ctypes.c_double * (n * 2)).from_address(path.data)
    ints = (ctypes.c_int32 * (n * 4)).from_address(path.data)
    out, i = [], 0
    while i < n:
        typ, length = ints[i * 4], ints[i * 4 + 1]
        pts = [(dbl[(i + k) * 2], dbl[(i + k) * 2 + 1]) for k in range(1, length)]
        out.append((typ, pts))
        i += length
    return out


def text_outline(text: str, family: str, size: float, weight: int = 0, flat: bool = False,
                 tolerance: float = 0.1):
    """Return (commands, extents) of the text outline with its origin on the baseline at 0,0.

    commands: list of (op, points) with op 0=move 1=line 2=curve 3=close.
    """
    cr = _cairo.cairo_create(_TXT_SURF)
    _cairo.cairo_set_tolerance(cr, tolerance)
    _cairo.cairo_select_font_face(cr, family.encode(), 0, weight)
    _cairo.cairo_set_font_size(cr, size)
    ext = _CairoTextExtents()
    _cairo.cairo_text_extents(cr, text.encode(), ctypes.byref(ext))
    _cairo.cairo_new_path(cr)
    _cairo.cairo_move_to(cr, 0, 0)
    _cairo.cairo_text_path(cr, text.encode())
    p = _cairo.cairo_copy_path_flat(cr) if flat else _cairo.cairo_copy_path(cr)
    cmds = _read_path(p)
    _cairo.cairo_path_destroy(p)
    _cairo.cairo_destroy(cr)
    e = {k: getattr(ext, k) for k in ("x_bearing", "y_bearing", "width", "height", "x_advance")}
    return cmds, e


def cmds_to_d(cmds, tf=None, prec=2) -> str:
    """Path commands to an SVG d string, optionally transforming points with tf(x, y)."""
    parts = []
    f = f"%.{prec}f"
    for op, pts in cmds:
        if tf:
            pts = [tf(x, y) for x, y in pts]
        if op == 0:
            parts.append("M" + " ".join(f % v for p in pts for v in p))
        elif op == 1:
            parts.append("L" + " ".join(f % v for p in pts for v in p))
        elif op == 2:
            parts.append("C" + " ".join(f % v for p in pts for v in p))
        else:
            parts.append("Z")
    return "".join(parts)


def cmds_to_polys(cmds) -> list:
    """Flattened commands to a list of closed polygons (numpy (n,2))."""
    polys, cur = [], []
    for op, pts in cmds:
        if op == 0:
            if len(cur) > 2:
                polys.append(np.array(cur))
            cur = list(pts)
        elif op in (1, 2):
            cur.extend(pts)
        else:
            if len(cur) > 2:
                polys.append(np.array(cur))
            cur = []
    if len(cur) > 2:
        polys.append(np.array(cur))
    return polys


def polys_to_d(polys, prec=1) -> str:
    f = f"%.{prec}f"
    out = []
    for p in polys:
        out.append("M" + " L".join(f"{f % x},{f % y}" for x, y in p) + "Z")
    return "".join(out)


def resample_poly(p: np.ndarray, step: float) -> np.ndarray:
    q = np.vstack([p, p[:1]])
    seg = np.linalg.norm(np.diff(q, axis=0), axis=1)
    L = np.concatenate([[0], np.cumsum(seg)])
    n = max(8, int(L[-1] / step))
    s = np.linspace(0, L[-1], n, endpoint=False)
    return np.stack([np.interp(s, L, q[:, 0]), np.interp(s, L, q[:, 1])], axis=1)


def roughen_poly(p: np.ndarray, amp: float, seed: int, step: float = 2.0, freqs=(3, 9, 27, 61)) -> np.ndarray:
    """Displace a closed polygon along its normals with smooth periodic noise."""
    q = resample_poly(p, step)
    n = len(q)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / n * 2 * np.pi
    perim = n * step
    disp = np.zeros(n)
    for f in freqs:
        k = max(1, int(round(f * perim / 600.0)))
        disp += rng.normal() * np.sin(k * t + rng.uniform(0, 6.3)) / (1 + 0.15 * f)
        disp += rng.normal() * np.sin((k + 1) * t + rng.uniform(0, 6.3)) / (1 + 0.15 * f)
    # sparse spiky nicks (bristle gaps)
    spikes = np.zeros(n)
    for _ in range(max(1, n // 90)):
        c = rng.integers(0, n)
        wdt = rng.uniform(1.5, 5)
        d = np.minimum(np.abs(np.arange(n) - c), n - np.abs(np.arange(n) - c))
        spikes += -rng.uniform(0.6, 1.6) * np.exp(-(d / wdt) ** 2)
    disp = disp / (np.abs(disp).max() + 1e-6) + spikes
    tang = np.roll(q, -1, axis=0) - np.roll(q, 1, axis=0)
    nrm = np.stack([tang[:, 1], -tang[:, 0]], axis=1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
    return q + nrm * (disp * amp)[:, None]


# ---------------------------------------------------------------------------
# Array helpers
# ---------------------------------------------------------------------------
def blank(h: int, w: int) -> np.ndarray:
    return np.zeros((h, w, 4), np.float32)


def solid(h: int, w: int, color, alpha: float = 1.0) -> np.ndarray:
    c = hexrgb(color) if isinstance(color, str) else np.asarray(color, np.float32)
    out = np.empty((h, w, 4), np.float32)
    out[..., :3] = c * alpha
    out[..., 3] = alpha
    return out


def from_mask(mask: np.ndarray, color, alpha: float = 1.0) -> np.ndarray:
    """Colour layer from a (h,w) coverage mask. colour may be hex, rgb, or (h,w,3)."""
    if isinstance(color, str):
        color = hexrgb(color)
    color = np.asarray(color, np.float32)
    a = np.clip(mask, 0, 1).astype(np.float32)
    if alpha != 1.0:
        a *= np.float32(alpha)
    out = np.empty(mask.shape + (4,), np.float32)
    if color.ndim == 1:
        for c in range(3):
            np.multiply(a, color[c], out=out[..., c])
    else:
        np.multiply(color, a[..., None], out=out[..., :3])
    out[..., 3] = a
    return out


def over(dst: np.ndarray, src: np.ndarray, opacity: float = 1.0) -> np.ndarray:
    if opacity != 1.0:
        src = src * opacity
    return src + dst * (1.0 - src[..., 3:4])


def add(dst: np.ndarray, src: np.ndarray, k: float = 1.0) -> np.ndarray:
    """Additive light: adds premultiplied colour, alpha grows like 'over'."""
    out = dst.copy()
    out[..., :3] += src[..., :3] * k
    out[..., 3] = np.clip(dst[..., 3] + src[..., 3] * k * (1 - dst[..., 3]), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], np.maximum(out[..., 3:4], 1.0) * 1.0)
    return out


def screen(dst: np.ndarray, src: np.ndarray, k: float = 1.0) -> np.ndarray:
    s = src * k
    out = dst + s - dst * s
    return out


def multiply_rgb(dst: np.ndarray, factor) -> np.ndarray:
    out = dst.copy()
    f = np.asarray(factor, np.float32)
    if f.ndim == 2:
        f = f[..., None]
    out[..., :3] *= f
    return out


def place(dst: np.ndarray, src: np.ndarray, cx: float, cy: float, mode: str = "over", k: float = 1.0) -> np.ndarray:
    """Composite src centred at (cx, cy) on dst (in place copy returned)."""
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0 = int(round(cx - w / 2))
    y0 = int(round(cy - h / 2))
    xa, ya = max(0, x0), max(0, y0)
    xb, yb = min(W, x0 + w), min(H, y0 + h)
    if xa >= xb or ya >= yb:
        return dst
    out = dst.copy()
    s = src[ya - y0:yb - y0, xa - x0:xb - x0]
    d = out[ya:yb, xa:xb]
    if mode == "over":
        out[ya:yb, xa:xb] = over(d, s, k)
    elif mode == "add":
        out[ya:yb, xa:xb] = add(d, s, k)
    elif mode == "screen":
        out[ya:yb, xa:xb] = screen(d, s, k)
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def grid(h: int, w: int):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x, y


def radial(h, w, cx, cy, rx, ry=None):
    x, y = grid(h, w)
    ry = ry or rx
    return np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)


def gradient_map(t: np.ndarray, stops) -> np.ndarray:
    """Map scalar field t (0..1) through colour stops [(pos, hex), ...] -> (h,w,3)."""
    pos = np.array([s[0] for s in stops], np.float32)
    cols = np.array([hexrgb(s[1]) for s in stops], np.float32)
    t = np.clip(t, 0, 1)
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def opaque(rgb: np.ndarray) -> np.ndarray:
    out = np.empty(rgb.shape[:2] + (4,), np.float32)
    out[..., :3] = rgb
    out[..., 3] = 1
    return out


# ---------------------------------------------------------------------------
# Blur
# ---------------------------------------------------------------------------
def _box1d(a: np.ndarray, r: int, axis: int, wrap: bool) -> np.ndarray:
    if r < 1:
        return a
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="wrap" if wrap else "constant")
    c = np.cumsum(p, axis=axis, dtype=np.float32)
    sl_hi = [slice(None)] * a.ndim
    sl_lo = [slice(None)] * a.ndim
    sl_hi[axis] = slice(2 * r + 1, 2 * r + 1 + n)
    sl_lo[axis] = slice(0, n)
    out = c[tuple(sl_hi)] - c[tuple(sl_lo)]
    out *= np.float32(1.0 / (2 * r + 1))
    return out


def _resize_f(a: np.ndarray, w: int, h: int) -> np.ndarray:
    if a.ndim == 2:
        return np.asarray(fimg(a).resize((w, h), Image.BILINEAR))
    return np.stack([_resize_f(a[..., c], w, h) for c in range(a.shape[2])], axis=-1)


def blur(a: np.ndarray, sigma: float, wrap: bool = False) -> np.ndarray:
    """Approximate gaussian blur (3 box passes) for 2D or 3D float arrays."""
    if sigma <= 0.3:
        return a
    a = a.astype(np.float32)
    if sigma > 5 and not wrap:
        f = max(2, int(sigma / 2.5))
        H, W = a.shape[:2]
        h2, w2 = -(-H // f), -(-W // f)
        pad = [(0, h2 * f - H), (0, w2 * f - W)] + [(0, 0)] * (a.ndim - 2)
        p = np.pad(a, pad)
        small = p.reshape(h2, f, w2, f, *a.shape[2:]).mean(axis=(1, 3))
        small = blur(small, sigma / f)
        big = _resize_f(small, w2 * f, h2 * f)
        return big[:H, :W]
    w_ideal = math.sqrt(12 * sigma * sigma / 3 + 1)
    r = max(1, int(round((w_ideal - 1) / 2)))
    for _ in range(3):
        a = _box1d(a, r, 0, wrap)
        a = _box1d(a, r, 1, wrap)
    return a


def glow_of(layer: np.ndarray, sigma: float, color=None, strength: float = 1.0) -> np.ndarray:
    """Blurred copy of a layer (optionally recoloured) for additive glow."""
    if color is not None:
        a = layer[..., 3]
        layer = from_mask(a, color)
    return blur(layer, sigma) * strength


def dilate(mask: np.ndarray, r: float) -> np.ndarray:
    """Soft dilation of a coverage mask by radius r (pixels)."""
    if r <= 0:
        return mask
    b = blur(mask, r * 0.5)
    return smoothstep(0.02, 0.18, b)


# ---------------------------------------------------------------------------
# Noise
# ---------------------------------------------------------------------------
def fft_noise(h: int, w: int, scale: float = 32.0, beta: float = 1.0, seed: int = 0,
              stretch: float = 1.0, angle: float = 0.0, tileable: bool = False) -> np.ndarray:
    """Band-limited fractal noise normalised to 0..1 (tileable when tileable=True).

    scale: approx feature size in px; beta: spectral falloff (higher = smoother);
    stretch>1 elongates features along `angle` (radians).
    """
    f = int(scale / 8)
    if not tileable and f >= 2:
        hs, ws = -(-h // f) + 2, -(-w // f) + 2
        small = fft_noise(hs, ws, scale / f, beta, seed, stretch, angle, tileable=True)
        big = np.asarray(fimg(small).resize((ws * f, hs * f), Image.BICUBIC))
        return np.clip(big[f:f + h, f:f + w], 0, 1)
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((h, w)).astype(np.float32)
    F = np.fft.rfft2(white)
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.rfftfreq(w)[None, :]
    c, s = math.cos(angle), math.sin(angle)
    u = (kx * c + ky * s) * stretch
    v = (-kx * s + ky * c)
    k = np.sqrt(u * u + v * v)
    k0 = 1.0 / scale
    amp = np.where(k > 0, (np.maximum(k, k0 * 0.25) / k0) ** (-beta) * np.exp(-(k / (k0 * 4)) ** 2), 0)
    out = np.fft.irfft2(F * amp.astype(np.float32), s=(h, w)).astype(np.float32)
    lo, hi = np.percentile(out, [0.5, 99.5])
    return np.clip((out - lo) / (hi - lo + 1e-9), 0, 1).astype(np.float32)


def value_noise(h: int, w: int, cell: float, seed: int = 0, octaves: int = 4, gain: float = 0.5) -> np.ndarray:
    rng = np.random.default_rng(seed)
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = max(1.0, cell / (2 ** o))
        gh, gw = int(h / c) + 3, int(w / c) + 3
        g = rng.random((gh, gw)).astype(np.float32)
        img = fimg(g).resize((int(gw * c), int(gh * c)), Image.BICUBIC)
        arr = np.asarray(img)[:h, :w]
        total += arr * amp
        norm += amp
        amp *= gain
    total /= norm
    lo, hi = np.percentile(total, [1, 99])
    return np.clip((total - lo) / (hi - lo + 1e-9), 0, 1).astype(np.float32)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def unpremultiply(a: np.ndarray) -> np.ndarray:
    alpha = a[..., 3:4]
    rgb = np.where(alpha > 1e-5, a[..., :3] / np.maximum(alpha, 1e-5), 0)
    return np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)], axis=-1)


def to_image(a: np.ndarray, dither: bool = True) -> Image.Image:
    u = unpremultiply(a)
    if dither:
        rng = np.random.default_rng(1234)
        u = u + (rng.random(u.shape, dtype=np.float32) - 0.5) / 255.0
    return Image.fromarray((np.clip(u, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def downsample(a: np.ndarray, w: int, h: int) -> np.ndarray:
    """High quality downscale of a premultiplied float layer (Lanczos per channel)."""
    chans = [np.asarray(fimg(a[..., c]).resize((w, h), Image.LANCZOS)) for c in range(4)]
    out = np.stack(chans, axis=-1)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[..., :3] = np.clip(out[..., :3], 0, out[..., 3:4] + 1e-6)
    return out


def save(a: np.ndarray, path: Path, size=None, opaque_out: bool = False) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if size and (a.shape[1], a.shape[0]) != tuple(size):
        a = downsample(a, size[0], size[1])
    img = to_image(a)
    if opaque_out:
        img = img.convert("RGB")
    img.save(path, optimize=True)
    return path


def rel(p: Path) -> str:
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)
