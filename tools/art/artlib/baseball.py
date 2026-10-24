"""Stylised 3D baseball renderer (cel shading, rim light, projected seams and stitches)."""
from __future__ import annotations

import math

import numpy as np

from .core import (STITCH_RED, hexrgb, rasterize, smoothstep, svg_doc, value_noise)

SEAM_B = 0.28  # tennis-ball curve shape parameter (a + b = 1)


def rot_matrix(yaw: float, pitch: float, roll: float) -> np.ndarray:
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    Rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    return Rz @ Rx @ Ry


def seam(t: np.ndarray, b: float = SEAM_B):
    a = 1 - b
    k = 2 * math.sqrt(a * b)
    p = np.stack([a * np.cos(t) + b * np.cos(3 * t), a * np.sin(t) - b * np.sin(3 * t), k * np.sin(2 * t)], -1)
    d = np.stack([-a * np.sin(t) - 3 * b * np.sin(3 * t), a * np.cos(t) - 3 * b * np.cos(3 * t), 2 * k * np.cos(2 * t)], -1)
    return p, d / np.linalg.norm(d, axis=-1, keepdims=True)


def _norm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def render_ball(diam: float, rot=(0.6, 0.5, 0.3), light=(-0.55, 0.65, 0.55),
                base="#F7F3EA", shadow="#8E97AE", stitch=STITCH_RED, rim="#FFFFFF",
                rim_strength: float = 0.8, rim_dir=(0.7, -0.3, -0.2), ink="#0A1220",
                outline: float = 0.045, stitches: int = 34, spec: float = 1.0,
                bounce=None, pad: float = 0.08, texture: bool = True, emissive: float = 0.0,
                seam_color=None) -> np.ndarray:
    """Return a premultiplied RGBA layer containing the ball (square, ball diameter `diam`)."""
    R = diam / 2.0
    S = int(math.ceil(diam * (1 + 2 * pad)))
    c = S / 2.0
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    dx = (x + 0.5 - c) / R
    dy = -(y + 0.5 - c) / R
    r2 = dx * dx + dy * dy
    dist = np.sqrt(r2) * R
    alpha = np.clip(R - dist + 0.5, 0, 1)
    nz = np.sqrt(np.clip(1 - r2, 0, 1))
    n = np.stack([dx, dy, nz], -1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    L = np.array(light, np.float32)
    L /= np.linalg.norm(L)
    ndl = (n @ L)

    base_c, sh_c = hexrgb(base), hexrgb(shadow)
    lit = smoothstep(-0.06, 0.10, ndl)
    soft = np.clip(0.80 + 0.22 * ndl, 0, 1.05)
    col = sh_c[None, None] * (1 - lit[..., None]) + (base_c * soft[..., None]) * lit[..., None]
    # bounce light from below on the shadow side
    if bounce:
        b = np.clip(-n[..., 1] * 0.8 + 0.2, 0, 1) ** 2 * (1 - lit)
        col += hexrgb(bounce) * b[..., None] * 0.35
    # rim light
    rd = np.array(rim_dir, np.float32)
    rd /= np.linalg.norm(rd)
    fres = np.clip(1 - nz, 0, 1) ** 2.2
    rimm = fres * np.clip(n @ rd * 1.4 + 0.25, 0, 1) * rim_strength
    rimm = smoothstep(0.08, 0.35, rimm) * 0.9 + rimm * 0.3
    col = col * (1 - rimm[..., None] * 0.6) + hexrgb(rim) * rimm[..., None]
    # leather texture
    if texture:
        tex = value_noise(S, S, max(2.0, diam / 60), seed=7, octaves=3)
        col *= (0.975 + 0.035 * tex)[..., None]
    # specular
    H = L + np.array([0, 0, 1], np.float32)
    H /= np.linalg.norm(H)
    sp = smoothstep(0.955, 0.975, n @ H) * spec
    col = col * (1 - sp[..., None]) + sp[..., None] * 1.0
    if emissive:
        col = col * (1 - emissive) + base_c * emissive

    # ---- seams and stitches (vector, projected) ----
    M = rot_matrix(*rot)
    body = []
    sw = max(0.6, diam * 0.012)
    t = np.linspace(0, 2 * np.pi, 360, endpoint=False)
    P, T = seam(t)
    B = _norm(np.cross(P, T))
    seam_c = seam_color or "#B9B2A6"
    for side in (-1, 1):
        q = _norm(P + side * B * 0.045) @ M.T
        for i in range(len(q)):
            a_, b_ = q[i], q[(i + 1) % len(q)]
            zm = (a_[2] + b_[2]) / 2
            if zm <= 0.02:
                continue
            op = min(1.0, zm / 0.25)
            body.append(f'<line x1="{c + a_[0] * R:.2f}" y1="{c - a_[1] * R:.2f}" x2="{c + b_[0] * R:.2f}" '
                        f'y2="{c - b_[1] * R:.2f}" stroke="{seam_c}" stroke-width="{sw * (0.5 + 0.5 * zm):.2f}" '
                        f'stroke-opacity="{op * 0.9:.2f}" stroke-linecap="round"/>')
    ts = np.linspace(0, 2 * np.pi, stitches * 2, endpoint=False) + 0.03
    P, T = seam(ts)
    B = _norm(np.cross(P, T))
    sc = stitch
    dk = "#7A0E14"
    for side in (-1, 1):
        inner = _norm(P + side * B * 0.05) @ M.T
        outer = _norm(P + side * B * 0.135 + T * 0.055) @ M.T
        for a_, b_ in zip(inner, outer):
            zm = (a_[2] + b_[2]) / 2
            if zm <= 0.03:
                continue
            op = min(1.0, (zm - 0.03) / 0.2)
            w = diam * 0.030 * (0.45 + 0.55 * zm)
            x1, y1, x2, y2 = c + a_[0] * R, c - a_[1] * R, c + b_[0] * R, c - b_[1] * R
            body.append(f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{dk}" '
                        f'stroke-width="{w * 1.45:.2f}" stroke-opacity="{op * 0.55:.2f}" stroke-linecap="round"/>')
            body.append(f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{sc}" '
                        f'stroke-width="{w:.2f}" stroke-opacity="{op:.2f}" stroke-linecap="round"/>')
    st = rasterize(svg_doc(S, S, "".join(body)), S, S)
    shade = np.clip(0.42 + 0.58 * lit * soft, 0, 1.05)
    st[..., :3] *= shade[..., None]
    # composite stitches over leather
    out = np.empty((S, S, 4), np.float32)
    out[..., :3] = col * (1 - st[..., 3:4]) + st[..., :3]
    # ink outline
    ow = outline * R
    ring = np.clip(dist - (R - ow) + 0.5, 0, 1)
    out[..., :3] = out[..., :3] * (1 - ring[..., None]) + hexrgb(ink) * ring[..., None]
    out[..., :3] *= alpha[..., None]
    out[..., 3] = alpha
    return out
