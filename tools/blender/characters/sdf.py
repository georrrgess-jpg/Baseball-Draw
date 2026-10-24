"""Tiny numpy signed-distance-field toolkit + surface-nets polygoniser.

Every shape is a callable ``f(P) -> d`` where ``P`` is an (N, 3) float array of
points and ``d`` the (approximate) signed distance (negative inside).  Shapes
carry an axis-aligned bounding box in ``f.bbox = (min, max)`` so the
polygoniser knows where to sample.

Only numpy is used, so the module also works outside Blender.
"""
import math
import numpy as np

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _v(x):
    return np.asarray(x, dtype=np.float64)


def _shape(fn, lo, hi):
    fn.bbox = (_v(lo), _v(hi))
    return fn


def rot_matrix(rx=0.0, ry=0.0, rz=0.0):
    """XYZ euler (degrees) -> 3x3 rotation matrix (applied as R @ v)."""
    rx, ry, rz = (math.radians(a) for a in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = (math.cos(rx), math.sin(rx), math.cos(ry),
                              math.sin(ry), math.cos(rz), math.sin(rz))
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def frame_from(y_axis, z_hint):
    """Orthonormal 3x3 matrix whose columns are (x, y, z); y along y_axis."""
    y = _v(y_axis)
    y = y / np.linalg.norm(y)
    z = _v(z_hint)
    z = z - y * np.dot(z, y)
    n = np.linalg.norm(z)
    if n < 1e-9:
        z = np.cross(y, [1.0, 0, 0])
        if np.linalg.norm(z) < 1e-6:
            z = np.cross(y, [0, 1.0, 0])
        n = np.linalg.norm(z)
    z = z / n
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


# ---------------------------------------------------------------------------
# primitives
# ---------------------------------------------------------------------------

def sphere(c, r):
    c = _v(c)

    def f(P):
        return np.linalg.norm(P - c, axis=1) - r
    return _shape(f, c - r, c + r)


def ellipsoid(c, radii, rot=None):
    """Approximate ellipsoid distance (IQ).  ``rot`` maps local->world."""
    c = _v(c)
    r = _v(radii)
    R = None if rot is None else _v(rot)

    def f(P):
        Q = P - c
        if R is not None:
            Q = Q @ R  # world -> local (R orthonormal)
        k0 = np.linalg.norm(Q / r, axis=1)
        k1 = np.linalg.norm(Q / (r * r), axis=1)
        k1 = np.maximum(k1, 1e-12)
        return k0 * (k0 - 1.0) / k1
    ext = r.max() if R is not None else r
    return _shape(f, c - ext, c + ext)


def round_cone(a, b, ra, rb):
    """Capsule with different radii at both ends (exact, IQ)."""
    a = _v(a)
    b = _v(b)
    ba = b - a
    l2 = float(np.dot(ba, ba))
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    def f(P):
        pa = P - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - y[:, None] * ba
        x2 = np.einsum('ij,ij->i', xv, xv)
        y2 = y * y * l2
        z2 = z * z * l2
        k = math.copysign(1.0, rr) * rr * rr * x2
        d = np.empty(len(P))
        m1 = np.sign(z) * a2 * z2 > k
        m2 = (~m1) & (np.sign(y) * a2 * y2 < k)
        m3 = ~(m1 | m2)
        d[m1] = np.sqrt(x2[m1] + z2[m1]) * il2 - rb
        d[m2] = np.sqrt(x2[m2] + y2[m2]) * il2 - ra
        d[m3] = (np.sqrt(x2[m3] * a2 * il2) + y[m3] * rr) * il2 - ra
        return d
    lo = np.minimum(a - ra, b - rb)
    hi = np.maximum(a + ra, b + rb)
    return _shape(f, lo, hi)


def capsule(a, b, r):
    a = _v(a)
    b = _v(b)
    ba = b - a
    l2 = max(float(np.dot(ba, ba)), 1e-12)

    def f(P):
        pa = P - a
        h = np.clip(pa @ ba / l2, 0.0, 1.0)
        return np.linalg.norm(pa - h[:, None] * ba, axis=1) - r
    return _shape(f, np.minimum(a, b) - r, np.maximum(a, b) + r)


def box(c, half, rot=None, rnd=0.0):
    """Rounded box; ``half`` are half extents (rounding included)."""
    c = _v(c)
    h = _v(half) - rnd
    R = None if rot is None else _v(rot)

    def f(P):
        Q = P - c
        if R is not None:
            Q = Q @ R
        q = np.abs(Q) - h
        outside = np.linalg.norm(np.maximum(q, 0.0), axis=1)
        inside = np.minimum(np.max(q, axis=1), 0.0)
        return outside + inside - rnd
    ext = np.linalg.norm(_v(half)) if R is not None else _v(half)
    return _shape(f, c - ext, c + ext)


def torus(c, R_major, r_minor, rot=None):
    """Torus in local XY plane (axis local Z)."""
    c = _v(c)
    M = None if rot is None else _v(rot)

    def f(P):
        Q = P - c
        if M is not None:
            Q = Q @ M
        qx = np.sqrt(Q[:, 0] ** 2 + Q[:, 1] ** 2) - R_major
        return np.sqrt(qx * qx + Q[:, 2] ** 2) - r_minor
    e = R_major + r_minor
    return _shape(f, c - e, c + e)


def cylinder(a, b, r, rnd=0.0):
    """Capped cylinder between a and b (optionally rounded edges)."""
    a = _v(a)
    b = _v(b)
    ba = b - a
    L = np.linalg.norm(ba)
    u = ba / L
    mid = (a + b) * 0.5

    def f(P):
        Q = P - mid
        y = Q @ u
        rad = np.linalg.norm(Q - y[:, None] * u, axis=1)
        dx = rad - (r - rnd)
        dy = np.abs(y) - (L * 0.5 - rnd)
        out = np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2)
        return np.minimum(np.maximum(dx, dy), 0.0) + out - rnd
    e = r + 0.0
    return _shape(f, np.minimum(a, b) - e, np.maximum(a, b) + e)


def halfspace(p, n):
    """Inside where dot(P - p, n) < 0 (n = outward normal)."""
    p = _v(p)
    n = _v(n)
    n = n / np.linalg.norm(n)

    def f(P):
        return (P - p) @ n
    return _shape(f, np.full(3, -1e3), np.full(3, 1e3))


def polyline_tube(points, radii):
    """Union of round cones along a polyline (hard union)."""
    parts = [round_cone(points[i], points[i + 1], radii[i], radii[i + 1])
             for i in range(len(points) - 1)]
    return union(*parts)


def _poly_edges(loops):
    A_ = []
    B_ = []
    for poly in loops:
        poly = _v(poly)
        n = len(poly)
        for i in range(n):
            A_.append(poly[i])
            B_.append(poly[(i - 1) % n])
    return np.array(A_), np.array(B_)


def sd_polygon2d(loops, px, py):
    """Signed distance to a set of closed 2D loops (even-odd fill)."""
    VA, VB = _poly_edges(loops)
    d = np.full(len(px), np.inf)
    s = np.ones(len(px))
    for vi, vj in zip(VA, VB):
        e = vj - vi
        wx = px - vi[0]
        wy = py - vi[1]
        ee = e @ e
        if ee < 1e-16:
            continue
        t = np.clip((wx * e[0] + wy * e[1]) / ee, 0, 1)
        bx = wx - e[0] * t
        by = wy - e[1] * t
        d = np.minimum(d, bx * bx + by * by)
        c1 = py >= vi[1]
        c2 = py < vj[1]
        c3 = e[0] * wy > e[1] * wx
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s = np.where(flip, -s, s)
    return s * np.sqrt(d)


def prism2d(loops, origin, x_axis, y_axis, dilate=0.0):
    """Infinite prism of 2D loops (u along x_axis, v along y_axis) through
    ``origin``; extends along x_axis cross y_axis.  ``dilate`` grows it."""
    o = _v(origin)
    ax = _v(x_axis) / np.linalg.norm(x_axis)
    ay = _v(y_axis) / np.linalg.norm(y_axis)
    allp = np.concatenate([_v(l) for l in loops], 0)
    ext = np.abs(allp).max() + abs(dilate) + 0.01

    def f(P):
        Q = P - o
        u = Q @ ax
        v = Q @ ay
        out = np.full(len(P), 1.0)
        m = (np.abs(u) < ext) & (np.abs(v) < ext)
        if m.any():
            out[m] = sd_polygon2d(loops, u[m], v[m]) - dilate
        out[~m] = np.maximum(np.abs(u[~m]), np.abs(v[~m])) - ext + 0.01
        return out
    return _shape(f, o - ext - 1.0, o + ext + 1.0)


def extrude2d(poly2d, origin, x_axis, y_axis, depth, rnd=0.0):
    """Extruded 2D polygon (single loop or list of loops)."""
    loops = poly2d if (len(poly2d) and np.ndim(poly2d[0]) == 2) else [poly2d]
    o = _v(origin)
    ax = _v(x_axis) / np.linalg.norm(x_axis)
    ay = _v(y_axis) / np.linalg.norm(y_axis)
    az = np.cross(ax, ay)
    allp = np.concatenate([_v(l) for l in loops], 0)

    def f(P):
        Q = P - o
        u = Q @ ax
        v = Q @ ay
        w = Q @ az
        d2 = sd_polygon2d(loops, u, v) + rnd
        dz = np.abs(w) - (depth * 0.5 - rnd)
        out = np.sqrt(np.maximum(d2, 0) ** 2 + np.maximum(dz, 0) ** 2)
        return np.minimum(np.maximum(d2, dz), 0) + out - rnd
    ext = np.abs(allp).max() + depth
    return _shape(f, o - ext, o + ext)


# ---------------------------------------------------------------------------
# operators
# ---------------------------------------------------------------------------

def _bb_union(shapes, pad=0.0):
    lo = np.min([s.bbox[0] for s in shapes], axis=0) - pad
    hi = np.max([s.bbox[1] for s in shapes], axis=0) + pad
    return lo, hi


def union(*shapes):
    shapes = [s for s in shapes if s is not None]

    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = np.minimum(d, s(P))
        return d
    return _shape(f, *_bb_union(shapes))


def smin_arr(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax_arr(a, b, k):
    return -smin_arr(-a, -b, k)


def smooth_union(k, *shapes):
    shapes = [s for s in shapes if s is not None]

    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = smin_arr(d, s(P), k)
        return d
    return _shape(f, *_bb_union(shapes, k * 0.25))


def blend(base, k, *shapes):
    """Smooth-union several shapes onto base, each with its own k:
    blend(base, (k1, s1), (k2, s2)) or blend(base, k, s1, s2, ...)."""
    pairs = []
    if isinstance(k, tuple):
        pairs = [k] + list(shapes)
    else:
        pairs = [(k, s) for s in shapes]
    all_s = [base] + [s for _, s in pairs]

    def f(P):
        d = base(P)
        for kk, s in pairs:
            d = smin_arr(d, s(P), kk)
        return d
    return _shape(f, *_bb_union(all_s, 0.01))


def subtract(a, *cutters, k=0.0):
    def f(P):
        d = a(P)
        for c in cutters:
            d = smax_arr(d, -c(P), k)
        return d
    return _shape(f, *a.bbox)


def intersect(a, b, k=0.0):
    def f(P):
        return smax_arr(a(P), b(P), k)
    lo = np.maximum(a.bbox[0], b.bbox[0])
    hi = np.minimum(a.bbox[1], b.bbox[1])
    return _shape(f, lo, hi)


def shell(a, thickness):
    def f(P):
        return np.abs(a(P)) - thickness * 0.5
    return _shape(f, a.bbox[0] - thickness, a.bbox[1] + thickness)


def offset(a, amount):
    def f(P):
        return a(P) - amount
    return _shape(f, a.bbox[0] - max(amount, 0), a.bbox[1] + max(amount, 0))


def warp(a, fn_warp, pad=0.0):
    """Evaluate ``a`` at warped points (fn_warp maps world P -> P')."""
    def f(P):
        return a(fn_warp(P))
    return _shape(f, a.bbox[0] - pad, a.bbox[1] + pad)


def scaled(a, s, center=(0, 0, 0)):
    c = _v(center)

    def f(P):
        return a((P - c) / s + c) * s
    lo = (a.bbox[0] - c) * s + c
    hi = (a.bbox[1] - c) * s + c
    return _shape(f, lo, hi)


def mirror_x(a):
    """Shape mirrored to both sides (|x|)."""
    def f(P):
        Q = P.copy()
        Q[:, 0] = np.abs(Q[:, 0])
        return a(Q)
    lo, hi = a.bbox
    m = max(abs(lo[0]), abs(hi[0]))
    return _shape(f, [-m, lo[1], lo[2]], [m, hi[1], hi[2]])


# ---------------------------------------------------------------------------
# polygoniser (naive surface nets + projection)
# ---------------------------------------------------------------------------

def polygonize(fn, voxel, bbox=None, pad=None, project_iters=2,
               max_cells=9_000_000):
    """Return (verts (N,3), quads (M,4)) of the zero iso-surface."""
    lo, hi = bbox if bbox is not None else fn.bbox
    lo = _v(lo)
    hi = _v(hi)
    pad = voxel * 2.0 if pad is None else pad
    lo = lo - pad
    hi = hi + pad
    dims = np.ceil((hi - lo) / voxel).astype(int) + 1
    while np.prod(dims.astype(np.int64)) > max_cells:
        voxel *= 1.15
        dims = np.ceil((hi - lo) / voxel).astype(int) + 1
    nx, ny, nz = (int(d) for d in dims)
    xs = lo[0] + np.arange(nx) * voxel
    ys = lo[1] + np.arange(ny) * voxel
    zs = lo[2] + np.arange(nz) * voxel
    # evaluate in slabs to limit memory
    F = np.empty((nx, ny, nz), dtype=np.float64)
    YY, ZZ = np.meshgrid(ys, zs, indexing='ij')
    yz = np.stack([YY.ravel(), ZZ.ravel()], axis=1)
    slab = max(1, int(2_000_000 // (ny * nz)))
    for i0 in range(0, nx, slab):
        i1 = min(nx, i0 + slab)
        cnt = i1 - i0
        P = np.empty((cnt * ny * nz, 3))
        P[:, 0] = np.repeat(xs[i0:i1], ny * nz)
        P[:, 1:] = np.tile(yz, (cnt, 1))
        F[i0:i1] = fn(P).reshape(cnt, ny, nz)
    inside = F < 0.0
    cshape = (nx - 1, ny - 1, nz - 1)
    vsum = np.zeros(cshape + (3,))
    vcnt = np.zeros(cshape)
    grid = (xs, ys, zs)
    quads = []
    edge_info = []
    for ax in range(3):
        sl0 = [slice(None)] * 3
        sl1 = [slice(None)] * 3
        sl0[ax] = slice(0, -1)
        sl1[ax] = slice(1, None)
        f0 = F[tuple(sl0)]
        f1 = F[tuple(sl1)]
        m = (f0 < 0) != (f1 < 0)
        idx = np.nonzero(m)
        if len(idx[0]) == 0:
            continue
        a0 = f0[idx]
        a1 = f1[idx]
        t = a0 / (a0 - a1)
        pos = np.stack([grid[0][idx[0]], grid[1][idx[1]], grid[2][idx[2]]], 1)
        pos[:, ax] += t * voxel
        b = (ax + 1) % 3
        c = (ax + 2) % 3
        for db in (-1, 0):
            for dc in (-1, 0):
                cell = [idx[0].copy(), idx[1].copy(), idx[2].copy()]
                cell[b] = cell[b] + db
                cell[c] = cell[c] + dc
                ok = np.ones(len(t), bool)
                for d in range(3):
                    ok &= (cell[d] >= 0) & (cell[d] < cshape[d])
                ci = tuple(cc[ok] for cc in cell)
                np.add.at(vsum, ci, pos[ok])
                np.add.at(vcnt, ci, 1.0)
        edge_info.append((ax, idx, f0[idx] < 0))
    active = vcnt > 0
    vid = -np.ones(cshape, dtype=np.int64)
    nverts = int(active.sum())
    vid[active] = np.arange(nverts)
    verts = vsum[active] / vcnt[active][:, None]
    for ax, idx, inside0 in edge_info:
        b = (ax + 1) % 3
        c = (ax + 2) % 3
        cells = []
        ok = np.ones(len(idx[0]), bool)
        for db, dc in ((-1, -1), (0, -1), (0, 0), (-1, 0)):
            cell = [idx[0].copy(), idx[1].copy(), idx[2].copy()]
            cell[b] = cell[b] + db
            cell[c] = cell[c] + dc
            for d in range(3):
                ok &= (cell[d] >= 0) & (cell[d] < cshape[d])
            cells.append(cell)
        q = np.zeros((int(ok.sum()), 4), dtype=np.int64)
        for n, cell in enumerate(cells):
            q[:, n] = vid[tuple(cc[ok] for cc in cell)]
        flip = ~inside0[ok]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    quads = np.concatenate(quads, axis=0) if quads else np.zeros((0, 4), int)
    quads = quads[(quads >= 0).all(axis=1)]
    # project vertices onto the surface
    eps = voxel * 0.25
    for _ in range(project_iters):
        d = fn(verts)
        g = np.zeros_like(verts)
        for k in range(3):
            o = np.zeros(3)
            o[k] = eps
            g[:, k] = (fn(verts + o) - fn(verts - o)) / (2 * eps)
        gl2 = np.maximum((g * g).sum(1), 1e-12)
        step = -(d / gl2)[:, None] * g
        sl = np.linalg.norm(step, axis=1)
        lim = np.minimum(1.0, voxel * 0.75 / np.maximum(sl, 1e-12))
        verts = verts + step * lim[:, None]
    return verts, quads


def quads_to_tris(quads, verts):
    """Split quads along the shorter diagonal."""
    a, b, c, d = quads.T
    d1 = np.linalg.norm(verts[a] - verts[c], axis=1)
    d2 = np.linalg.norm(verts[b] - verts[d], axis=1)
    use1 = d1 <= d2
    t1 = np.where(use1[:, None], np.stack([a, b, c], 1), np.stack([a, b, d], 1))
    t2 = np.where(use1[:, None], np.stack([a, c, d], 1), np.stack([b, c, d], 1))
    return np.concatenate([t1, t2], 0)
