"""Environment pieces for illustrations: skies, perspective ground planes, stadium
silhouettes with light towers, crowds."""
from __future__ import annotations

import math

import numpy as np

from .core import (fft_noise, from_mask, gradient_map, grid, hexrgb, smoothstep)

SUNSET = [(0.0, "#0E1A2B"), (0.28, "#2B2357"), (0.52, "#7A2E6B"), (0.70, "#D2475B"),
          (0.84, "#FF8C42"), (0.95, "#FFC46B"), (1.0, "#FFE3A0")]
TWILIGHT = [(0.0, "#070F1E"), (0.40, "#14264A"), (0.68, "#3B3A7A"), (0.86, "#B4507A"), (1.0, "#FF9A5A")]
NIGHT = [(0.0, "#060B14"), (0.55, "#0E1A2B"), (0.85, "#1C2A48"), (1.0, "#2E3F66")]


def sky(W: int, H: int, horizon: float, stops=SUNSET, sun=None, clouds: float = 0.0, seed: int = 0) -> np.ndarray:
    """Vertical gradient sky (rgb, h x w x 3) reaching the last stop at `horizon`."""
    x, y = grid(H, W)
    t = np.clip(y / max(1.0, horizon), 0, 1)
    rgb = gradient_map(t, stops)
    if sun is not None:
        sx, sy, sr, scol = sun
        d = np.sqrt((x - sx) ** 2 + ((y - sy) * 1.3) ** 2)
        rgb += hexrgb(scol) * (np.exp(-(d / (sr * 3.5)) ** 2) * 0.55)[..., None]
        rgb += hexrgb("#FFF4D6") * smoothstep(sr + 1.5, sr - 1.5, d)[..., None]
    if clouds > 0:
        n = fft_noise(H, W, scale=W / 9, beta=1.1, seed=seed, stretch=4.0, angle=0.0)
        n2 = fft_noise(H, W, scale=W / 30, beta=1.0, seed=seed + 1, stretch=3.0, angle=0.0)
        band = smoothstep(horizon * 0.15, horizon * 0.55, y) * smoothstep(horizon * 1.0, horizon * 0.7, y)
        c = np.clip((n * 0.75 + n2 * 0.25) - 0.52, 0, 1) * 3.0 * band * clouds
        lit = smoothstep(0, 1, y / horizon)
        ccol = (hexrgb("#3A2050")[None, None] * (1 - lit[..., None]) + hexrgb("#FF9A6A")[None, None] * lit[..., None])
        cm = smoothstep(0.15, 0.5, c)[..., None]
        rgb = rgb * (1 - cm * 0.85) + ccol * cm * 0.85
        # bright lower rims
        rim = np.clip(cm[..., 0] - np.roll(cm[..., 0], -6, 0), 0, 1)[..., None]
        rgb += hexrgb("#FFC07A") * rim * 0.5 * lit[..., None]
    return np.clip(rgb, 0, 1.2)


def sample_tex(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Bilinear, wrapping texture lookup (tex is h x w [x c])."""
    th, tw = tex.shape[:2]
    u = np.mod(u, tw)
    v = np.mod(v, th)
    x0 = np.floor(u).astype(int)
    y0 = np.floor(v).astype(int)
    fx = (u - x0)
    fy = (v - y0)
    x1 = (x0 + 1) % tw
    y1 = (y0 + 1) % th
    x0 %= tw
    y0 %= th
    if tex.ndim == 3:
        fx = fx[..., None]
        fy = fy[..., None]
    a = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    b = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return a * (1 - fy) + b * fy


class Ground:
    """Perspective ground plane below a horizon line.

    World coords: X to the right, Z away from the camera (metres-ish).
    """

    def __init__(self, W, H, horizon, cam_h=1.6, focal=None, cx=None):
        self.W, self.H, self.horizon = W, H, horizon
        self.cam_h = cam_h
        self.focal = focal or W * 0.9
        self.cx = W / 2 if cx is None else cx
        x, y = grid(H, W)
        dy = np.maximum(y - horizon, 0.35)
        self.mask = np.clip(y - horizon + 0.5, 0, 1)
        self.Z = self.focal * cam_h / dy
        self.X = (x - self.cx) * self.Z / self.focal
        self.x, self.y = x, y

    def project(self, X, Z):
        """World point on the ground -> screen (x, y)."""
        return self.cx + X * self.focal / Z, self.horizon + self.focal * self.cam_h / Z

    def scale_at(self, Z):
        return self.focal / Z

    def fog(self, far=40.0):
        return smoothstep(far * 0.25, far, self.Z)

    def dirt(self, seed=0, base=("#3E2418", "#6B4029", "#8E5A39", "#B57A4E"), scale=1.0):
        tex = fft_noise(512, 512, scale=40, beta=1.0, seed=seed, tileable=True)
        tex2 = fft_noise(512, 512, scale=6, beta=0.8, seed=seed + 1, tileable=True)
        k = 60.0 * scale
        n = sample_tex(tex, self.X * k, self.Z * k)
        n2 = sample_tex(tex2, self.X * k, self.Z * k)
        far = smoothstep(4, 18, self.Z)
        v = n * 0.75 + n2 * 0.25 * (1 - far)
        # cel-ish banding
        stops = [(0.0, base[0]), (0.32, base[0]), (0.36, base[1]), (0.62, base[1]), (0.66, base[2]),
                 (0.86, base[2]), (0.9, base[3]), (1.0, base[3])]
        rgb = gradient_map(v * (1 - far) + 0.5 * far, stops)
        # pebbles
        peb = smoothstep(0.82, 0.86, sample_tex(tex2, self.X * k * 2.3, self.Z * k * 2.3)) * (1 - far)
        rgb = rgb * (1 - peb[..., None] * 0.5) + hexrgb(base[3]) * peb[..., None] * 0.5
        return rgb

    def grass(self, seed=0, light="#2E8048", dark="#1E5A33", stripe=2.2, angle=0.0):
        tex = fft_noise(512, 512, scale=20, beta=1.0, seed=seed, tileable=True)
        c, s = math.cos(angle), math.sin(angle)
        U = self.X * c + self.Z * s
        st = smoothstep(-0.08, 0.08, np.sin(U / stripe * math.pi))
        rgb = (hexrgb(dark)[None, None] * (1 - st[..., None]) + hexrgb(light)[None, None] * st[..., None])
        n = sample_tex(tex, self.X * 40, self.Z * 40)
        far = smoothstep(4, 20, self.Z)
        rgb *= (0.88 + 0.22 * (n * (1 - far) + 0.5 * far))[..., None]
        return rgb

    def line(self, X0, Z0, X1, Z1, width=0.12):
        """Coverage of a straight chalk line on the ground between two world points."""
        dX, dZ = X1 - X0, Z1 - Z0
        L = math.hypot(dX, dZ)
        ux, uz = dX / L, dZ / L
        px, pz = self.X - X0, self.Z - Z0
        t = px * ux + pz * uz
        d = np.abs(px * uz - pz * ux)
        px_per_m = self.focal / self.Z
        cov = np.clip((width / 2 - d) * px_per_m + 0.5, 0, 1)
        cov *= (t > 0) * (t < L)
        return cov * self.mask

    def disc(self, X0, Z0, r):
        d = np.hypot(self.X - X0, self.Z - Z0)
        return np.clip((r - d) * self.focal / self.Z + 0.5, 0, 1) * self.mask

    def light_pool(self, X0, Z0, r):
        d = np.hypot(self.X - X0, (self.Z - Z0))
        return np.exp(-(d / r) ** 2) * self.mask


def stadium_svg(W, H, base_y, seed=0, color="#0A1220", rim="#FF8C42", towers=2, lamp="#FFF2C8",
                deck_h=0.16, height_scale=1.0, bottom=None):
    """Stadium silhouette (stands + light towers). Returns (svg_body, lamp_points)."""
    rng = np.random.default_rng(seed)
    hs = height_scale
    pts = []
    n = 40
    for i in range(n + 1):
        x = i / n * W
        t = i / n
        prof = 0.55 + 0.45 * math.sin(t * math.pi) ** 0.6
        y = base_y - H * deck_h * hs * prof
        pts.append((x, y))
    # upper deck stepped roof
    top = [(x, y - H * 0.05 * hs * (0.6 + 0.4 * math.sin(i / n * math.pi))) for i, (x, y) in enumerate(pts)]
    bottom = H if bottom is None else bottom
    d = f"M0,{bottom} L0,{pts[0][1]:.1f} " + " ".join(f"L{x:.1f},{y:.1f}" for x, y in pts) + f" L{W},{bottom} Z"
    roof = f"M0,{pts[0][1] + 2:.1f} " + " ".join(f"L{x:.1f},{y:.1f}" for x, y in top) + \
        " " + " ".join(f"L{x:.1f},{y + 2:.1f}" for x, y in reversed(pts)) + " Z"
    body = [f'<path d="{d}" fill="{color}"/>', f'<path d="{roof}" fill="{color}"/>']
    # rim light along the top edge
    rimline = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in top)
    body.append(f'<path d="{rimline}" fill="none" stroke="{rim}" stroke-width="{max(1.5, W / 500):.1f}" stroke-opacity="0.55"/>')
    # stand tiers (subtle horizontal lines)
    for k in range(1, 4):
        tier = "M" + " L".join(f"{x:.1f},{y + (base_y - y) * k / 4:.1f}" for x, y in pts)
        body.append(f'<path d="{tier}" fill="none" stroke="#FFFFFF" stroke-opacity="0.05" stroke-width="{W / 400:.1f}"/>')
    # crowd speckle: tiny lit heads/phones scattered over the stands
    bottom_y = H if bottom is None else bottom
    for k in range(int(W * 0.45)):
        fx_ = rng.uniform(0, 1)
        i0 = min(n, int(fx_ * n))
        ytop = pts[i0][1]
        yy = rng.uniform(ytop + 4, min(bottom_y, base_y) - 2) if min(bottom_y, base_y) - 2 > ytop + 4 else ytop + 4
        op = rng.uniform(0.04, 0.16) * (1 - (yy - ytop) / max(1.0, base_y - ytop) * 0.6)
        body.append(f'<circle cx="{fx_ * W:.1f}" cy="{yy:.1f}" r="{rng.uniform(0.8, 2.0) * W / 1024:.1f}" '
                    f'fill="{rim}" fill-opacity="{op:.2f}"/>')
    lamps = []
    xs = np.linspace(0.12, 0.88, towers) if towers > 1 else [0.5]
    for i, fx in enumerate(xs):
        tx = W * (fx + rng.uniform(-0.03, 0.03))
        idx = int(tx / W * n)
        y_top_stand = top[min(idx, n)][1]
        th = H * 0.22 * hs * rng.uniform(0.85, 1.1)
        ty = y_top_stand - th
        pw = W * 0.006
        body.append(f'<path d="M{tx - pw:.1f},{y_top_stand + 4:.1f} L{tx - pw * 0.6:.1f},{ty:.1f} L{tx + pw * 0.6:.1f},{ty:.1f} '
                    f'L{tx + pw:.1f},{y_top_stand + 4:.1f}Z" fill="{color}"/>')
        bw, bh = W * 0.06, H * 0.045
        body.append(f'<rect x="{tx - bw / 2:.1f}" y="{ty - bh:.1f}" width="{bw:.1f}" height="{bh:.1f}" rx="{bw * 0.06:.1f}" fill="{color}"/>')
        rows, cols = 3, 6
        for r in range(rows):
            for c in range(cols):
                lx = tx - bw / 2 + bw * (c + 0.5) / cols
                ly = ty - bh + bh * (r + 0.5) / rows
                lr = min(bw / cols, bh / rows) * 0.32
                body.append(f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="{lr:.1f}" fill="{lamp}"/>')
        lamps.append((tx, ty - bh / 2, bw))
    return "".join(body), lamps


def lamp_glow(W, H, lamps, color="#FFE9B0", strength=1.0) -> np.ndarray:
    x, y = grid(H, W)
    out = np.zeros((H, W), np.float32)
    for lx, ly, bw in lamps:
        d = np.sqrt((x - lx) ** 2 + ((y - ly) * 1.4) ** 2)
        out += np.exp(-(d / (bw * 0.9)) ** 2) * 0.9 + np.exp(-(d / (bw * 3.0)) ** 2) * 0.35
        # horizontal anamorphic streak
        out += np.exp(-((y - ly) / (bw * 0.05)) ** 2) * np.exp(-(np.abs(x - lx) / (bw * 4)) ** 1.0) * 0.5
    return from_mask(np.clip(out * strength, 0, 1.5), color)


def crowd_svg(W, y_base, rows=3, seed=0, color="#0B1322", arms=0.4, scale=1.0, x0=0, x1=None,
              rim=None, rim_dx=0.0):
    """Silhouetted crowd: heads, shoulders and raised arms."""
    rng = np.random.default_rng(seed)
    x1 = W if x1 is None else x1
    body = []
    for r in range(rows):
        s = scale * (0.75 + 0.25 * r / max(1, rows - 1))
        yb = y_base + r * 38 * scale
        x = x0 - rng.uniform(0, 30) * s
        while x < x1 + 40:
            hw = rng.uniform(16, 22) * s
            hr = rng.uniform(10, 13) * s
            yy = yb + rng.uniform(-8, 6) * s
            hy = yy - hr * 2.4
            col = color
            body.append(f'<path d="M{x - hw:.1f},{yy + 80 * s:.1f} L{x - hw:.1f},{yy - hr * 0.6:.1f} '
                        f'Q{x - hw:.1f},{yy - hr * 1.3:.1f} {x - hw * 0.4:.1f},{yy - hr * 1.3:.1f} '
                        f'L{x + hw * 0.4:.1f},{yy - hr * 1.3:.1f} Q{x + hw:.1f},{yy - hr * 1.3:.1f} {x + hw:.1f},{yy - hr * 0.6:.1f} '
                        f'L{x + hw:.1f},{yy + 80 * s:.1f}Z" fill="{col}"/>')
            body.append(f'<circle cx="{x:.1f}" cy="{hy:.1f}" r="{hr:.1f}" fill="{col}"/>')
            if rng.random() < arms:
                for side in (-1, 1):
                    if rng.random() < 0.85:
                        ang = math.radians(rng.uniform(-30, 10)) * side
                        ln = rng.uniform(48, 66) * s
                        sx, sy = x + side * hw * 0.75, yy - hr * 0.9
                        ex = sx + math.sin(ang) * ln + side * 8 * s
                        ey = sy - math.cos(ang) * ln
                        aw = 7.5 * s
                        body.append(f'<path d="M{sx:.1f},{sy:.1f} L{ex:.1f},{ey:.1f}" stroke="{col}" '
                                    f'stroke-width="{aw:.1f}" stroke-linecap="round"/>')
                        body.append(f'<circle cx="{ex:.1f}" cy="{ey - 2 * s:.1f}" r="{aw * 0.8:.1f}" fill="{col}"/>')
            if rim:
                body.append(f'<circle cx="{x + rim_dx * hr:.1f}" cy="{hy - hr * 0.2:.1f}" r="{hr:.1f}" fill="none" '
                            f'stroke="{rim}" stroke-opacity="0.35" stroke-width="{1.5 * s:.1f}"/>')
            x += hw * 2 + rng.uniform(2, 14) * s
    return "".join(body)
