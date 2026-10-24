"""Procedural, tileable textures for the "Steel Yard" prop set (numpy only).

Every function returns float32 arrays shaped (H, W, C) with values in 0..1,
row 0 = TOP of the image.  Colour textures are sRGB-encoded; normal maps are
OpenGL-style tangent-space (as glTF expects).  All noise is generated in the
frequency domain so it tiles perfectly.
"""
import math

import numpy as np


def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def fnoise(n, seed, beta=2.0, sx=1.0, sy=1.0, lo=1.0, m=None):
    """Periodic fractal noise, zero mean / unit std. sx, sy > 1 stretch features
    along x / y.  `lo` removes frequencies below lo cycles per tile."""
    m = n if m is None else m
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((m, n))
    F = np.fft.fft2(w)
    ky = np.fft.fftfreq(m)[:, None] * m * sy
    kx = np.fft.fftfreq(n)[None, :] * n * sx
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    filt = k ** (-beta / 2.0)
    filt[k < lo] = 0.0
    out = np.real(np.fft.ifft2(F * filt))
    out -= out.mean()
    out /= out.std() + 1e-8
    return out.astype(np.float32)


def blur_wrap(a, r):
    """Cheap periodic box blur (repeated) along both axes."""
    out = a.astype(np.float32)
    for _ in range(2):
        acc = np.zeros_like(out)
        for d in range(-r, r + 1):
            acc += np.roll(out, d, axis=0)
        out = acc / (2 * r + 1)
        acc = np.zeros_like(out)
        for d in range(-r, r + 1):
            acc += np.roll(out, d, axis=1)
        out = acc / (2 * r + 1)
    return out


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = t[..., None] if (np.ndim(t) == 2) else t
    return a * (1 - t) + b * t


def lines_mask(n, seed, count, length=(10, 60), m=None, angle_spread=math.pi, angle0=0.0):
    """Mask of random thin scratches (wrap-around)."""
    m = n if m is None else m
    rng = np.random.default_rng(seed)
    mask = np.zeros((m, n), np.float32)
    for _ in range(count):
        x0, y0 = rng.uniform(0, n), rng.uniform(0, m)
        a = angle0 + rng.uniform(-angle_spread / 2, angle_spread / 2)
        L = rng.uniform(*length)
        t = np.linspace(0, L, int(L * 2) + 2)
        xs = (x0 + np.cos(a) * t).astype(int) % n
        ys = (y0 + np.sin(a) * t).astype(int) % m
        mask[ys, xs] = np.maximum(mask[ys, xs], rng.uniform(0.4, 1.0))
    return mask


def grain(n, seed, m=None, amt=1.0):
    m = n if m is None else m
    rng = np.random.default_rng(seed)
    return (rng.standard_normal((m, n)) * amt).astype(np.float32)


# --------------------------------------------------------------------------
# material textures
# --------------------------------------------------------------------------

def painted_steel(color, seed=1, n=512, wear=1.0, rust=1.0, dirt=1.0):
    base = hex_rgb(color)
    mott = fnoise(n, seed, beta=2.6, lo=1)
    fine = fnoise(n, seed + 1, beta=1.2, lo=8)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (1 + 0.045 * mott[..., None] + 0.025 * fine[..., None])
    # dirt: grimy low-frequency patches (darker, slightly desaturated/brown)
    d = smooth(0.6, 2.4, fnoise(n, seed + 2, beta=3.0))
    grime = col * 0.6 + hex_rgb('#3A3530') * 0.25
    col = mix(col, grime, d * 0.45 * dirt)
    # rust streaks running downwards (stretched along y)
    if rust > 0:
        streak = fnoise(n, seed + 3, beta=2.2, sx=1.0, sy=10.0, lo=2)
        spots = fnoise(n, seed + 4, beta=2.4, lo=2)
        rmask = smooth(1.3, 2.6, streak * 0.6 + spots * 0.6) * rust
        rust_c = hex_rgb('#6E3A1E') * (1 + 0.25 * fine[..., None])
        col = mix(col, rust_c, rmask * 0.75)
    # scratches / chips showing bare metal
    if wear > 0:
        sc = lines_mask(n, seed + 5, int(90 * wear), (6, 34))
        chips = smooth(2.2, 2.8, fnoise(n, seed + 6, beta=1.6, lo=6)) * wear
        metal = np.array([0.55, 0.56, 0.58], np.float32)
        col = mix(col, metal, np.clip(sc * 0.6 + chips * 0.8, 0, 1))
    return np.clip(col, 0, 1)


def bare_metal(color='#8A939E', seed=11, n=512, rust=0.5):
    base = hex_rgb(color)
    brushed = fnoise(n, seed, beta=1.4, sx=0.08, sy=1.0, lo=2)
    mott = fnoise(n, seed + 1, beta=2.6)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (1 + 0.05 * brushed[..., None] + 0.08 * mott[..., None])
    if rust > 0:
        r = smooth(1.4, 2.8, fnoise(n, seed + 2, beta=2.2, sy=6.0)) * rust
        col = mix(col, hex_rgb('#6B3B20'), r * 0.7)
    return np.clip(col, 0, 1)


def rust_metal(seed=21, n=512):
    a = fnoise(n, seed, beta=2.4)
    b = fnoise(n, seed + 1, beta=1.0, lo=10)
    c1, c2, c3 = hex_rgb('#5A2C17'), hex_rgb('#8B4513'), hex_rgb('#3A2418')
    col = mix(c1, c2, smooth(-1.2, 1.4, a))
    col = mix(col, c3, smooth(0.8, 2.4, -a + 0.4 * b) * 0.6)
    col *= (1 + 0.12 * b[..., None])
    return np.clip(col, 0, 1)


def concrete(seed=31, n=512, color='#8E8B84', stains=1.0, lines=True):
    base = hex_rgb(color)
    mott = fnoise(n, seed, beta=2.5)
    fine = fnoise(n, seed + 1, beta=0.6, lo=20)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (1 + 0.08 * mott[..., None] + 0.05 * fine[..., None])
    rng = np.random.default_rng(seed + 2)
    # pores
    pores = rng.random((n, n)) > 0.9965
    pores = blur_wrap(pores.astype(np.float32), 1) > 0.05
    col[pores] *= 0.6
    # vertical water stains
    st = smooth(0.6, 2.2, fnoise(n, seed + 3, beta=2.0, sy=12.0, lo=2)) * stains
    col = mix(col, col * 0.62, st * 0.7)
    # warm dust near patches
    dust = smooth(1.0, 2.5, fnoise(n, seed + 4, beta=2.8))
    col = mix(col, hex_rgb('#9C8A6C'), dust * 0.25)
    if lines:
        # formwork joints: one horizontal + one vertical line per tile
        yy = np.arange(n)
        joint = (np.abs(((yy + n // 2) % n) - n // 2) < 2)
        col[joint, :, :] *= 0.78
        col[:, joint, :] *= 0.82
        # tie holes
        for (x, y) in ((n // 4, n // 4), (3 * n // 4, n // 4), (n // 4, 3 * n // 4), (3 * n // 4, 3 * n // 4)):
            yy2, xx2 = np.ogrid[:n, :n]
            hole = (xx2 - x) ** 2 + (yy2 - y) ** 2 < 25
            col[hole] *= 0.5
    return np.clip(col, 0, 1)


def hazard(seed=41, n=512, stripes=4, yellow='#F5B82E', black='#16171A'):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    period = n / stripes
    s = ((xx + yy) / period) % 1.0
    # soft-ish edge for anti-aliasing
    edge = 1.5 / period
    t = smooth(0.5 - edge, 0.5 + edge, s) - smooth(1.0 - edge, 1.0, s) + (1 - smooth(0.0, edge, s))
    t = np.clip(t, 0, 1)
    y, b = hex_rgb(yellow), hex_rgb(black)
    col = mix(y, b, t)
    mott = fnoise(n, seed, beta=2.4)
    col *= (1 + 0.08 * mott[..., None])
    dirt = smooth(0.5, 2.3, fnoise(n, seed + 1, beta=2.8))
    col = mix(col, col * 0.5, dirt * 0.45)
    chips = smooth(2.0, 2.6, fnoise(n, seed + 2, beta=1.4, lo=6))
    sc = lines_mask(n, seed + 3, 120, (5, 30))
    col = mix(col, np.array([0.45, 0.45, 0.46], np.float32), np.clip(chips * 0.85 + sc * 0.5, 0, 1))
    return np.clip(col, 0, 1)


def padding(seed=51, n=512, color='#16253D'):
    base = hex_rgb(color)
    wr = fnoise(n, seed, beta=2.0, sx=1.0, sy=4.0, lo=2)
    fine = fnoise(n, seed + 1, beta=0.4, lo=40)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (1 + 0.06 * wr[..., None] + 0.03 * fine[..., None])
    scuff = smooth(1.5, 2.8, fnoise(n, seed + 2, beta=2.2))
    col = mix(col, col * 1.35, scuff * 0.4)
    return np.clip(col, 0, 1)


def brick(seed=61, n=512, cols=8, rows=24):
    m = n
    yy, xx = np.mgrid[0:m, 0:n].astype(np.float32)
    bh = m / rows
    bw = n / cols
    row = np.floor(yy / bh)
    off = (row % 2) * bw / 2
    bx = np.floor(((xx + off) % n) / bw)
    fy = (yy % bh) / bh
    fx = (((xx + off) % n) % bw) / bw
    mortar = (fy < 0.12) | (fx < 0.045)
    rng = np.random.default_rng(seed)
    tint = rng.uniform(-1, 1, (rows, cols, 3)).astype(np.float32)
    shade = rng.uniform(0.75, 1.15, (rows, cols)).astype(np.float32)
    ri = row.astype(int) % rows
    ci = bx.astype(int) % cols
    base = hex_rgb('#7A3A27')
    col = base[None, None, :] * shade[ri, ci][..., None] + tint[ri, ci] * np.array([0.05, 0.025, 0.02])
    n1 = fnoise(n, seed + 1, beta=1.0, lo=12)
    col *= (1 + 0.08 * n1[..., None])
    soot = smooth(0.2, 2.0, fnoise(n, seed + 2, beta=2.2, sy=8))
    col = mix(col, col * 0.45, soot * 0.6)
    mcol = hex_rgb('#6F6A62') * (1 + 0.1 * n1[..., None])
    col = np.where(mortar[..., None], mcol, col)
    return np.clip(col, 0, 1)


def corrugated(seed=71, n=512, color='#5E6E7E', ribs=16, rust=1.0, profile='sine'):
    """Returns (colour, normal) for vertical corrugation (ribs along v)."""
    xx = np.arange(n, dtype=np.float32)
    ph = xx / n * ribs
    if profile == 'sine':
        h = np.sin(ph * 2 * math.pi)
        dh = np.cos(ph * 2 * math.pi) * 2 * math.pi * ribs / n
    else:  # trapezoid (container)
        f = ph % 1.0
        h = np.clip(np.where(f < 0.5, (f - 0.125) * 8, (0.875 - f) * 8) * 0.5, -1, 1)
        dh = np.gradient(h) * 1.0
        dh = np.convolve(np.concatenate([dh[-3:], dh, dh[:3]]), np.ones(3) / 3, 'same')[3:-3]
    base = hex_rgb(color)
    col = np.ones((n, n, 3), np.float32) * base
    shade = (0.85 + 0.15 * h)[None, :, None]
    col = col * shade
    mott = fnoise(n, seed, beta=2.4)
    col *= (1 + 0.07 * mott[..., None])
    if rust > 0:
        st = smooth(1.0, 2.6, fnoise(n, seed + 1, beta=2.0, sy=14.0) + 0.5 * h[None, :]) * rust
        col = mix(col, hex_rgb('#6B3820'), st * 0.7)
    dirt = smooth(0.5, 2.5, fnoise(n, seed + 2, beta=3.0))
    col = mix(col, col * 0.6, dirt * 0.4)
    k = 6.0
    nx = -dh * k
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + nz * nz)
    nrm = np.zeros((n, n, 3), np.float32)
    nrm[..., 0] = (nx / ln)[None, :] * 0.5 + 0.5
    nrm[..., 1] = 0.5
    nrm[..., 2] = (nz / ln)[None, :] * 0.5 + 0.5
    return np.clip(col, 0, 1), nrm


def wood(seed=81, n=512, color='#8A6440', planks=4, m=None):
    """Planks running along u (x)."""
    m = n if m is None else m
    base = hex_rgb(color)
    g = fnoise(n, seed, beta=1.8, sx=0.04, sy=1.0, lo=2, m=m)
    rings = np.sin(g * 7.0)
    fine = fnoise(n, seed + 1, beta=0.6, sx=0.02, sy=1.0, lo=6, m=m)
    col = np.ones((m, n, 3), np.float32) * base
    col *= (1 + 0.16 * rings[..., None] + 0.14 * fine[..., None])
    yy = np.arange(m)
    ph = yy / m * planks
    seam = (ph % 1.0) < 0.025
    rng = np.random.default_rng(seed + 2)
    pl = np.floor(ph).astype(int)
    shade = rng.uniform(0.82, 1.12, planks)[pl]
    col *= shade[:, None, None]
    col[seam] *= 0.45
    weather = smooth(0.8, 2.4, fnoise(n, seed + 3, beta=2.5, m=m))
    col = mix(col, hex_rgb('#6E675C'), weather * 0.35)
    return np.clip(col, 0, 1)


def burlap(seed=91, n=256, color='#A38E68'):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin(xx / n * 2 * math.pi * 48) + 0.25 * np.sin(yy / n * 2 * math.pi * 48)
    base = hex_rgb(color)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (0.88 + 0.2 * weave[..., None])
    mott = fnoise(n, seed, beta=2.4)
    col *= (1 + 0.08 * mott[..., None])
    dirt = smooth(0.6, 2.4, fnoise(n, seed + 1, beta=2.6))
    col = mix(col, col * 0.6, dirt * 0.5)
    return np.clip(col, 0, 1)


def windows(seed=101, n=512, bays=4, floors=4, lit_frac=0.35, wall='#2A2F38',
            glass='#1A2533', lit='#FFC56E', lit2='#BFD8FF'):
    """Facade tile: returns (base colour, emission)."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    bw = n / bays
    fh = n / floors
    fx = (xx % bw) / bw
    fy = (yy % fh) / fh
    win = (fx > 0.12) & (fx < 0.88) & (fy > 0.22) & (fy < 0.86)
    mull = win & (np.abs(fx - 0.5) < 0.02)
    win = win & ~mull
    rng = np.random.default_rng(seed)
    state = rng.random((floors, bays))
    warm = rng.random((floors, bays)) > 0.25
    bi = (xx // bw).astype(int) % bays
    fi = (yy // fh).astype(int) % floors
    is_lit = state[fi, bi] < lit_frac
    col = np.ones((n, n, 3), np.float32) * hex_rgb(wall)
    mott = fnoise(n, seed + 1, beta=2.6)
    col *= (1 + 0.08 * mott[..., None])
    gl = hex_rgb(glass) * (1 + 0.25 * (1 - fy)[..., None])
    col = np.where(win[..., None], gl, col)
    emis = np.zeros((n, n, 3), np.float32)
    lc = np.where(warm[fi, bi][..., None], hex_rgb(lit), hex_rgb(lit2))
    # some blinds: partially lit windows
    blind = rng.random((floors, bays))[fi, bi]
    lit_mask = win & is_lit & (fy > 0.22 + 0.5 * (blind < 0.3) * (blind * 1.5))
    shade = (0.75 + 0.25 * (1 - fy))[..., None]
    emis = np.where(lit_mask[..., None], lc * shade, emis)
    col = np.where(lit_mask[..., None], lc * 0.8, col)
    # sills
    sill = (fy > 0.86) & (fy < 0.9) & (fx > 0.1) & (fx < 0.9)
    col[sill] *= 1.4
    return np.clip(col, 0, 1), np.clip(emis, 0, 1)


def chainlink(n=256, cells=4, wire=0.075):
    """RGBA chain-link diamonds; alpha 1 on wire."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n * cells
    a = (xx + yy) % 1.0
    b = (xx - yy) % 1.0
    da = np.minimum(a, 1 - a)
    db = np.minimum(b, 1 - b)
    d = np.minimum(da, db)
    alpha = 1.0 - smooth(wire * 0.6, wire, d)
    # wire shading: brighter in the middle
    sh = 0.75 + 0.35 * (1 - np.clip(d / wire, 0, 1))
    col = np.ones((n, n, 4), np.float32)
    col[..., :3] = hex_rgb('#9AA3AD') * sh[..., None]
    col[..., 3] = alpha
    return np.clip(col, 0, 1)


def speaker_grille(n=256, holes=24):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n * holes
    fx = xx % 1.0 - 0.5
    fy = (yy + 0.5 * (np.floor(xx) % 2)) % 1.0 - 0.5
    d = np.sqrt(fx * fx + fy * fy)
    hole = 1 - smooth(0.26, 0.32, d)
    col = np.ones((n, n, 3), np.float32) * hex_rgb('#2A2D33')
    col = mix(col, np.array([0.02, 0.02, 0.025], np.float32), hole)
    return np.clip(col, 0, 1)


def lamp_lens(n=256, color='#FFE7BE'):
    """Radial hot-spot for lamp faces (planar 0..1 UV): (base, emission)."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / (n - 1) * 2 - 1
    r = np.sqrt(xx * xx + yy * yy)
    c = hex_rgb(color)
    core = 1 - smooth(0.0, 0.55, r)
    rings = 0.85 + 0.15 * np.cos(r * 40)
    lv = (0.55 + 0.45 * core) * rings
    lv *= 1 - smooth(0.88, 1.0, r) * 0.5
    emis = c * lv[..., None]
    base = np.clip(emis * 0.9 + 0.1, 0, 1)
    return base, np.clip(emis, 0, 1)


def baseball(n=1024, leather='#F2EEE4', stitch='#C8232C'):
    """Equirectangular (u = longitude, v = latitude) baseball leather + seam
    with 108 V-shaped double stitches crossing the seam."""
    m = n // 2
    v = (np.arange(m, dtype=np.float32) + 0.5) / m          # 0 top .. 1 bottom
    u = (np.arange(n, dtype=np.float32) + 0.5) / n
    lat = (0.5 - v) * math.pi
    lon = u * 2 * math.pi
    LON, LAT = np.meshgrid(lon, lat)
    P = np.stack([np.cos(LAT) * np.cos(LON), np.cos(LAT) * np.sin(LON), np.sin(LAT)], -1)
    # seam curve on the unit sphere (exact: a + b = 1)
    K = 1500
    t = np.linspace(0, 2 * math.pi, K, endpoint=False)
    a, b = 0.6, 0.4
    C = np.stack([a * np.cos(t) + b * np.cos(3 * t), a * np.sin(t) - b * np.sin(3 * t),
                  2 * np.sqrt(a * b) * np.sin(2 * t)], -1)
    C /= np.linalg.norm(C, axis=1, keepdims=True)
    seglen = np.linalg.norm(np.roll(C, -1, axis=0) - C, axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seglen)[:-1]])
    total = float(seglen.sum())
    Tn = np.roll(C, -1, axis=0) - np.roll(C, 1, axis=0)
    Tn /= np.linalg.norm(Tn, axis=1, keepdims=True)
    flat = P.reshape(-1, 3).astype(np.float32)
    best = np.full(flat.shape[0], -2.0, np.float32)
    bidx = np.zeros(flat.shape[0], np.int32)
    Cf = C.astype(np.float32)
    for s0 in range(0, K, 300):
        d = flat @ Cf[s0:s0 + 300].T
        k = np.argmax(d, axis=1)
        val = d[np.arange(d.shape[0]), k]
        upd = val > best
        best[upd] = val[upd]
        bidx[upd] = (k + s0)[upd]
    ang = np.arccos(np.clip(best, -1, 1))
    side = np.sign(np.sum(flat * np.cross(Tn[bidx], C[bidx]), axis=1))
    sdist = (ang * side).reshape(m, n)                       # signed distance (rad)
    along = arc[bidx].reshape(m, n)                          # arc length along the seam (rad)
    col = np.ones((m, n, 3), np.float32) * hex_rgb(leather)
    mott = fnoise(n, 7, beta=2.0, m=m)
    col *= (1 + 0.03 * mott[..., None])
    absd = np.abs(sdist)
    # seam groove
    groove = 1 - smooth(0.004, 0.011, absd)
    col *= (1 - 0.3 * groove)[..., None]
    # stitches: chevrons, arms run from the seam outwards and backwards
    count = 108
    sp = total / count
    slant = 0.75
    a_rel = along - slant * absd
    q = a_rel / sp
    dl = (q - np.round(q)) * sp                              # along-seam offset from stitch centre line
    arm = (absd > 0.012) & (absd < 0.07)
    w = 0.011 * (1 - 0.35 * (absd / 0.07))
    st = arm & (np.abs(dl) < w)
    shade = 0.75 + 0.25 * (1 - np.abs(dl) / np.maximum(w, 1e-4))
    red = hex_rgb(stitch)
    col = np.where(st[..., None], red * shade[..., None], col)
    # stitch holes darken the leather slightly near the seam
    col *= (1 - 0.06 * smooth(0.09, 0.0, absd))[..., None]
    return np.clip(col, 0, 1)


def bat_wood(n=512, m=256, seed=111):
    """Ash wood along u (bat length), light finish."""
    g = fnoise(n, seed, beta=1.6, sx=1.0, sy=0.03, lo=2, m=m)
    rings = np.sin(g * 9.0)
    base = hex_rgb('#C9A066')
    col = np.ones((m, n, 3), np.float32) * base
    col *= (1 + 0.10 * rings[..., None])
    col *= (1 + 0.04 * fnoise(n, seed + 1, beta=0.6, lo=10, m=m)[..., None])
    return np.clip(col, 0, 1)


def grip_tape(n=256):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    wrap = ((xx * 6 + yy * 3) % 1.0)
    edge = smooth(0.0, 0.08, wrap) * (1 - smooth(0.92, 1.0, wrap))
    col = np.ones((n, n, 3), np.float32) * hex_rgb('#1E2026')
    col *= (0.75 + 0.25 * edge)[..., None]
    return np.clip(col, 0, 1)


def flat(color, n=8):
    return np.ones((n, n, 3), np.float32) * hex_rgb(color)


def plastic(color, seed=121, n=256, scuff=1.0):
    base = hex_rgb(color)
    col = np.ones((n, n, 3), np.float32) * base
    col *= (1 + 0.04 * fnoise(n, seed, beta=2.4)[..., None])
    sc = lines_mask(n, seed + 1, int(40 * scuff), (4, 20))
    col = mix(col, col * 1.25 + 0.05, sc * 0.5)
    dirt = smooth(1.0, 2.6, fnoise(n, seed + 2, beta=2.6))
    col = mix(col, col * 0.7, dirt * 0.4 * scuff)
    return np.clip(col, 0, 1)


def container_paint(seed=131, n=512):
    """Light neutral corrugated container skin meant to be tinted in-engine."""
    col, nrm = corrugated(seed, n, color='#D6D6D2', ribs=10, rust=0.6, profile='trap')
    return col, nrm


def roof_sheet(seed=141, n=512):
    return corrugated(seed, n, color='#3A3F47', ribs=12, rust=0.8, profile='sine')
