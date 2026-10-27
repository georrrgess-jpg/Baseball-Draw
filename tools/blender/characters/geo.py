"""Mesh-modelling helpers for the stylised defenders.

No SDF polygonisation: every surface is an intentional quad mesh --
parametric lofts (rings interpolated with cubic splines), mirrored box cages
smoothed with Catmull-Clark subdivision (with edge creases for crisp edges),
star-shaped projections of clean sphere grids onto smooth implicit shapes,
and thin surface decals (eyes, numbers, emblems) projected onto those meshes.
Decals copy the skin weights of the surface they sit on so they never float.
"""
import math
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
import mathutils.geometry as mg


def A(v):
    return np.asarray(v, dtype=np.float64)


def unit(v):
    v = A(v)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


# ---------------------------------------------------------------------------
# objects
# ---------------------------------------------------------------------------

def make_obj(name, verts, faces, mat, bones=None, rigid=None, smooth=True, creases=None,
             mirror=False, subsurf=0, sharp=None, weights_from=None, collect=None,
             mirror_merge=1e-5, overrides=None):
    """Create a mesh object from verts/faces (mixed n-gons ok).

    creases: list of (i, j, value) vertex index pairs (cage indices).
    mirror:  mirror the cage across X (centre verts must lie on x=0).
    subsurf: Catmull-Clark levels applied after mirroring.
    sharp:   auto-sharp angle (deg) for split normals on hard edges."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in verts], [],
                   [tuple(int(i) for i in f) for f in faces])
    me.update(calc_edges=True)
    if creases:
        lut = {}
        for i, e in enumerate(me.edges):
            a, b = e.vertices
            lut[(min(a, b), max(a, b))] = i
        at = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", 'FLOAT', 'EDGE')
        vals = np.zeros(len(me.edges), np.float32)
        for c in creases:
            a, b = int(c[0]), int(c[1])
            v = c[2] if len(c) > 2 else 1.0
            k = lut.get((min(a, b), max(a, b)))
            if k is not None:
                vals[k] = v
        at.data.foreach_set("value", vals)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if mirror:
        m = obj.modifiers.new("mirror", 'MIRROR')
        m.use_axis = (True, False, False)
        m.use_clip = True
        m.use_mirror_merge = True
        m.merge_threshold = mirror_merge
    if subsurf:
        m = obj.modifiers.new("subsurf", 'SUBSURF')
        m.levels = subsurf
        m.render_levels = subsurf
        m.quality = 3
        m.use_creases = True
        m.boundary_smooth = 'PRESERVE_CORNERS'
    if obj.modifiers:
        apply_modifiers(obj)
    me = obj.data
    if mat is not None:
        me.materials.clear()
        me.materials.append(mat)
    if smooth:
        me.shade_smooth()
        if sharp is not None:
            me.set_sharp_from_angle(angle=math.radians(sharp))
    else:
        me.shade_flat()
    obj["rigid"] = rigid or ""
    obj["bones"] = ",".join(bones) if bones else ""
    obj["weights_from"] = weights_from.name if weights_from is not None else ""
    if overrides:
        obj["weight_overrides"] = dict(overrides)
    if collect is not None:
        collect.append(obj)
    return obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    bpy.data.meshes.remove(old)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def verts_of(obj):
    me = obj.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3).astype(np.float64)


def set_verts(obj, co):
    obj.data.vertices.foreach_set("co", np.asarray(co, np.float32).ravel())
    obj.data.update()


def merge(objs, name):
    """Join several part objects (same material) into one."""
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
                                   selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


# ---------------------------------------------------------------------------
# interpolation
# ---------------------------------------------------------------------------

def interp(keys_t, keys_v, t, mono=False, closed=None):
    """Cubic Hermite interpolation through (keys_t, keys_v) evaluated at t
    (array).  Finite-difference (Catmull-Rom style) tangents; ``mono`` limits
    the tangents (Fritsch-Carlson) to avoid overshoot.  ``closed`` = period."""
    kt = A(keys_t)
    kv = A(keys_v)
    t = A(t)
    scalar = kv.ndim == 1
    if scalar:
        kv = kv[:, None]
    if closed:
        P = closed
        kt = np.concatenate([kt[-2:] - P, kt, kt[:2] + P])
        kv = np.concatenate([kv[-2:], kv, kv[:2]], 0)
        t = np.mod(t - keys_t[0], P) + keys_t[0]
    n = len(kt)
    m = np.zeros_like(kv)
    d = (kv[1:] - kv[:-1]) / (kt[1:] - kt[:-1])[:, None]
    m[1:-1] = (kv[2:] - kv[:-2]) / (kt[2:] - kt[:-2])[:, None]
    m[0] = d[0]
    m[-1] = d[-1]
    if mono:
        for i in range(n - 1):
            for c in range(kv.shape[1]):
                if abs(d[i, c]) < 1e-12:
                    m[i, c] = 0.0
                    m[i + 1, c] = 0.0
                else:
                    a = m[i, c] / d[i, c]
                    b = m[i + 1, c] / d[i, c]
                    if a < 0:
                        m[i, c] = 0.0
                    if b < 0:
                        m[i + 1, c] = 0.0
                    s = a * a + b * b
                    if s > 9:
                        tau = 3 / math.sqrt(s)
                        m[i, c] = tau * a * d[i, c]
                        m[i + 1, c] = tau * b * d[i, c]
    idx = np.clip(np.searchsorted(kt, t, side='right') - 1, 0, n - 2)
    t0 = kt[idx]
    t1 = kt[idx + 1]
    h = (t1 - t0)
    u = np.clip((t - t0) / h, 0.0, 1.0)[:, None]
    hh = h[:, None]
    h00 = 2 * u ** 3 - 3 * u ** 2 + 1
    h10 = u ** 3 - 2 * u ** 2 + u
    h01 = -2 * u ** 3 + 3 * u ** 2
    h11 = u ** 3 - u ** 2
    out = h00 * kv[idx] + h10 * hh * m[idx] + h01 * kv[idx + 1] + h11 * hh * m[idx + 1]
    return out[:, 0] if scalar else out


def smooth_polyline(pts, n, closed=False):
    """Resample a Catmull-Rom curve through pts with n points."""
    pts = A(pts)
    seg = np.linalg.norm(np.diff(pts if not closed else np.vstack([pts, pts[:1]]), axis=0), axis=1)
    kt = np.concatenate([[0], np.cumsum(seg)])
    if closed:
        L = kt[-1]
        ts = np.linspace(0, L, n, endpoint=False)
        return interp(kt[:-1], pts, ts, closed=L)
    ts = np.linspace(0, kt[-1], n)
    return interp(kt, pts, ts)


# ---------------------------------------------------------------------------
# frames / rings
# ---------------------------------------------------------------------------

def transport_frames(pts, up_hint):
    """Parallel-transport frames along a polyline: returns (T, U, V) arrays,
    U starts as up_hint made perpendicular to the first tangent."""
    pts = A(pts)
    n = len(pts)
    T = np.zeros_like(pts)
    T[1:-1] = pts[2:] - pts[:-2]
    T[0] = pts[1] - pts[0]
    T[-1] = pts[-1] - pts[-2]
    T = unit(T)
    U = np.zeros_like(pts)
    u = A(up_hint) - T[0] * np.dot(A(up_hint), T[0])
    U[0] = unit(u)
    for i in range(1, n):
        u = U[i - 1] - T[i] * np.dot(U[i - 1], T[i])
        if np.linalg.norm(u) < 1e-9:
            u = U[i - 1]
        U[i] = unit(u)
    V = np.cross(T, U)
    return T, U, V


def superellipse(ang, n):
    """(cos, sin) mapped onto a superellipse of exponent n (2 = ellipse)."""
    c, s = np.cos(ang), np.sin(ang)
    e = 2.0 / n
    return np.sign(c) * np.abs(c) ** e, np.sign(s) * np.abs(s) ** e


def loft_faces(nrings, nseg, closed=True, start=0):
    f = []
    for i in range(nrings - 1):
        for k in range(nseg if closed else nseg - 1):
            a = start + i * nseg + k
            b = start + i * nseg + (k + 1) % nseg
            c = start + (i + 1) * nseg + (k + 1) % nseg
            d = start + (i + 1) * nseg + k
            f.append((a, b, c, d))
    return f


def loft(rings, cap0=None, cap1=None, closed=True):
    """rings: (R, K, 3).  cap: None | 'pole' (point = ring mean) | 'flat' |
    an explicit 3D point.  Returns verts, faces."""
    rings = A(rings)
    R, Kn = rings.shape[:2]
    verts = list(rings.reshape(-1, 3))
    faces = loft_faces(R, Kn, closed)
    for which, cap in ((0, cap0), (R - 1, cap1)):
        if cap is None:
            continue
        base = which * Kn
        if isinstance(cap, str) and cap == 'flat':
            ring = list(range(base, base + Kn))
            faces.append(tuple(ring[::-1]) if which == 0 else tuple(ring))
            continue
        p = rings[which].mean(0) if isinstance(cap, str) else A(cap)
        verts.append(p)
        ci = len(verts) - 1
        for k in range(Kn):
            a = base + k
            b = base + (k + 1) % Kn
            faces.append((ci, b, a) if which == 0 else (ci, a, b))
    return np.array(verts), faces


def tube(pts, radii, nseg=8, up=(0, 0, 1), cap0='pole', cap1='pole', ovals=None,
         twist=0.0, closed_path=False):
    """Round tube along a polyline (piping, laces, bars, hair strands)."""
    pts = A(pts)
    n = len(pts)
    radii = np.broadcast_to(A(radii), (n,))
    T, U, V = transport_frames(pts, up)
    ang = np.linspace(0, 2 * np.pi, nseg, endpoint=False) + twist
    rings = []
    for i in range(n):
        ry = radii[i] * (ovals[i] if ovals is not None else 1.0)
        rings.append(pts[i] + np.outer(np.cos(ang), U[i]) * radii[i] +
                     np.outer(np.sin(ang), V[i]) * ry)
    if closed_path:
        verts = np.array(rings).reshape(-1, 3)
        faces = loft_faces(n, nseg, True)
        for k in range(nseg):
            a = (n - 1) * nseg + k
            b = (n - 1) * nseg + (k + 1) % nseg
            faces.append((a, b, (k + 1) % nseg, k))
        return verts, faces
    return loft(rings, cap0, cap1)


def uv_sphere(center, radii, nu=12, nv=8, rot=None):
    """Ellipsoid as a UV sphere (poles on local z).  rot: 3x3 columns =
    local axes."""
    c = A(center)
    r = A(radii)
    R = np.eye(3) if rot is None else A(rot)
    verts = [c + R @ (np.array([0, 0, -1.0]) * r)]
    for j in range(1, nv):
        th = math.pi * j / nv
        z = -math.cos(th)
        rr = math.sin(th)
        for i in range(nu):
            a = 2 * math.pi * i / nu
            verts.append(c + R @ (np.array([rr * math.cos(a), rr * math.sin(a), z]) * r))
    verts.append(c + R @ (np.array([0, 0, 1.0]) * r))
    faces = []
    for i in range(nu):
        faces.append((0, 1 + (i + 1) % nu, 1 + i))
    for j in range(nv - 2):
        for i in range(nu):
            a = 1 + j * nu + i
            b = 1 + j * nu + (i + 1) % nu
            faces.append((a, b, b + nu, a + nu))
    top = len(verts) - 1
    base = 1 + (nv - 2) * nu
    for i in range(nu):
        faces.append((base + i, base + (i + 1) % nu, top))
    return np.array(verts), faces


def rounded_box(center, half, rot=None, nseg=3):
    """Box cage (to be subdivided) -- 6 quads; with creases it stays boxy."""
    c = A(center)
    h = A(half)
    R = np.eye(3) if rot is None else A(rot)
    corners = []
    for z in (-1, 1):
        for y in (-1, 1):
            for x in (-1, 1):
                corners.append(c + R @ (np.array([x, y, z]) * h))
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return np.array(corners), faces


# ---------------------------------------------------------------------------
# star-shaped projection onto implicit shapes
# ---------------------------------------------------------------------------

def project_rays(fn, origins, dirs, r_max, iters=36):
    """For each ray (origin inside the shape) find the surface crossing by
    bisection.  fn: (N,3)->(N,) signed distance (negative inside)."""
    o = A(origins)
    d = unit(dirs)
    if o.ndim == 1:
        o = np.broadcast_to(o, d.shape)
    lo = np.zeros(len(d))
    hi = np.full(len(d), float(r_max))
    # make sure hi is outside
    for _ in range(4):
        v = fn(o + d * hi[:, None])
        bad = v < 0
        if not bad.any():
            break
        hi[bad] *= 1.6
    for _ in range(iters):
        mid = 0.5 * (lo + hi)
        v = fn(o + d * mid[:, None])
        inside = v < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    r = 0.5 * (lo + hi)
    return o + d * r[:, None], r


def sphere_dirs(nu, nv, frame, front_bias=0.0):
    """Direction grid (rings from the top pole to the bottom pole) in the
    local frame (columns x=left, y=back, z=up).  Azimuth 0 = front (-y);
    front_bias > 0 concentrates columns on the front."""
    F = A(frame)
    rows = []
    for j in range(1, nv):
        th = math.pi * j / nv
        row = []
        for i in range(nu):
            u = i / nu
            a = 2 * math.pi * u - front_bias * math.sin(2 * math.pi * u)
            x = math.sin(th) * math.sin(a)
            y = -math.sin(th) * math.cos(a)
            z = math.cos(th)
            row.append(F @ np.array([x, y, z]))
        rows.append(row)
    top = F @ np.array([0, 0, 1.0])
    bot = F @ np.array([0, 0, -1.0])
    return A(rows), top, bot


def sphere_mesh_from_rows(rows, top, bot):
    """rows (nv-1, nu, 3) of points + pole points -> verts, faces (outward)."""
    rows = A(rows)
    nr, nu = rows.shape[:2]
    verts = [A(top)] + list(rows.reshape(-1, 3)) + [A(bot)]
    faces = []
    for i in range(nu):
        faces.append((0, 1 + i, 1 + (i + 1) % nu))
    for j in range(nr - 1):
        for i in range(nu):
            a = 1 + j * nu + i
            b = 1 + j * nu + (i + 1) % nu
            faces.append((a, a + nu, b + nu, b))
    last = len(verts) - 1
    base = 1 + (nr - 1) * nu
    for i in range(nu):
        faces.append((base + i, last, base + (i + 1) % nu))
    return np.array(verts), faces


# ---------------------------------------------------------------------------
# surfaces (BVH) + decals
# ---------------------------------------------------------------------------

class Surface:
    """Ray-cast / nearest queries on a mesh (object or verts+faces)."""

    def __init__(self, obj=None, verts=None, faces=None):
        if obj is not None:
            verts = verts_of(obj)
            faces = [tuple(p.vertices) for p in obj.data.polygons]
        tris = []
        for f in faces:
            for k in range(1, len(f) - 1):
                tris.append((f[0], f[k], f[k + 1]))
        self.verts = A(verts)
        self.bvh = BVHTree.FromPolygons([Vector(v) for v in self.verts], tris)

    def ray(self, origin, direction, dist=10.0):
        loc, nor, idx, d = self.bvh.ray_cast(Vector(origin), Vector(direction), dist)
        if loc is None:
            return None, None
        return A(loc), A(nor)

    def hit(self, p, n, back=0.25):
        """Project point p onto the surface along -n (n points outward)."""
        n = unit(n)
        loc, nor = self.ray(A(p) + n * back, -n, back * 4)
        if loc is None:
            loc, nor = self.ray(A(p) - n * back, n, back * 4)
        if loc is None:
            loc, nor, _, _ = self.bvh.find_nearest(Vector(p))
            return A(loc), A(nor)
        return loc, nor

    def nearest(self, p):
        loc, nor, idx, d = self.bvh.find_nearest(Vector(p))
        return A(loc), A(nor)


def tessellate(loops2d):
    """Triangulate 2D loops (outer loops + their holes, each outer loop
    separately so overlapping shapes stay filled).  Returns verts2d, tris
    (indices into the concatenation of all loops)."""
    loops2d = [A(lp) for lp in loops2d]
    starts = np.cumsum([0] + [len(lp) for lp in loops2d])
    depth = []
    for i, lp in enumerate(loops2d):
        depth.append(sum(1 for j, o in enumerate(loops2d)
                         if j != i and point_in_poly(lp[0], o)))
    tris = []
    for i, lp in enumerate(loops2d):
        if depth[i] % 2:
            continue
        group = [i] + [j for j in range(len(loops2d)) if depth[j] == depth[i] + 1 and
                       point_in_poly(loops2d[j][0], lp)]
        vl = [[Vector((float(x), float(y), 0.0)) for x, y in loops2d[g]] for g in group]
        offs = []
        for g in group:
            offs += list(range(starts[g], starts[g] + len(loops2d[g])))
        if len(group) == 1:
            # single loop: ear clipping (scanfill leaves holes in concave
            # glyphs with collinear runs, e.g. the crossbar of a "4")
            ears = ear_clip(loops2d[i])
            if ears is not None:
                tris += [tuple(offs[k] for k in t) for t in ears]
                continue
        for t in mg.tessellate_polygon(vl):
            tris.append(tuple(offs[k] for k in t))
    return np.concatenate(loops2d, 0), tris


def ear_clip(P):
    """Ear-clipping triangulation of a simple 2D polygon (either winding).
    Returns index triangles, or None if it gets stuck (self-intersecting)."""
    P = A(P)
    n = len(P)
    sgn = 1.0 if _loop_area(P) > 0 else -1.0
    idx = list(range(n))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    out = []
    guard = 0
    while len(idx) > 3 and guard < 4 * n * n:
        guard += 1
        m = len(idx)
        clipped = False
        for k in range(m):
            a, b, c = idx[k - 1], idx[k], idx[(k + 1) % m]
            if cross(P[a], P[b], P[c]) * sgn <= 1e-14:
                continue        # reflex or degenerate corner
            ok = True
            for j in idx:
                if j in (a, b, c):
                    continue
                p = P[j]
                if (cross(P[a], P[b], p) * sgn >= 0 and cross(P[b], P[c], p) * sgn >= 0 and
                        cross(P[c], P[a], p) * sgn >= 0):
                    ok = False
                    break
            if ok:
                out.append((a, b, c))
                idx.pop(k)
                clipped = True
                break
        if not clipped:
            # drop a collinear / degenerate vertex if there is one, else give up
            for k in range(m):
                a, b, c = idx[k - 1], idx[k], idx[(k + 1) % m]
                if abs(cross(P[a], P[b], P[c])) <= 1e-12:
                    idx.pop(k)
                    clipped = True
                    break
            if not clipped:
                return None
    if len(idx) == 3:
        out.append(tuple(idx))
    return out


def subdivide_tris(p2, tris, boundary, levels):
    """Midpoint-subdivide triangles (so decals follow curved surfaces)."""
    p2 = [tuple(p) for p in p2]
    for _ in range(levels):
        mid = {}

        def m(a, b):
            k = (min(a, b), max(a, b))
            if k not in mid:
                p2.append(((p2[a][0] + p2[b][0]) / 2, (p2[a][1] + p2[b][1]) / 2))
                mid[k] = len(p2) - 1
            return mid[k]
        nt = []
        for a, b, c in tris:
            ab, bc, ca = m(a, b), m(b, c), m(c, a)
            nt += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        tris = nt
        nb = []
        for loop in boundary:
            nl = []
            for i in range(len(loop)):
                a, b = loop[i], loop[(i + 1) % len(loop)]
                nl.append(a)
                k = (min(a, b), max(a, b))
                if k in mid:
                    nl.append(mid[k])
            nb.append(nl)
        boundary = nb
    return A(p2), tris, boundary


def decal(surface, loops2d, center, u, v, n, offset, thick, bulge=None, depth=None,
          interior=None, interior_tris=None, subdiv=0):
    """Thin raised decal: 2D loops (u, v coordinates in metres) are projected
    onto ``surface`` along -n.  Top surface at offset+thick(+bulge), side
    walls down to offset-depth.  Returns verts, faces."""
    c, u, v, n = A(center), unit(u), unit(v), unit(n)
    if interior is not None:
        p2, tris = A(interior), list(interior_tris)
        boundary = loops2d   # list of index loops into p2
    else:
        p2, tris = tessellate(loops2d)
        boundary = []
        k = 0
        for lp in loops2d:
            boundary.append(list(range(k, k + len(lp))))
            k += len(lp)
        if subdiv:
            p2, tris, boundary = subdivide_tris(p2, tris, boundary, subdiv)
    depth = thick if depth is None else depth
    base = []
    for x, y in p2:
        loc, nor = surface.hit(c + u * x + v * y, n)
        base.append(loc)
    base = A(base)
    b = np.zeros(len(p2)) if bulge is None else A([bulge(x, y) for x, y in p2])
    top = base + n * (offset + thick + b)[:, None]
    verts = list(top)
    faces = [tuple(t) for t in tris]
    # orientation: make top faces point along n
    if faces:
        f0 = faces[0]
        nn = np.cross(top[f0[1]] - top[f0[0]], top[f0[2]] - top[f0[0]])
        if np.dot(nn, n) < 0:
            faces = [tuple(reversed(f)) for f in faces]
    bot_idx = {}
    for loop in boundary:
        for i in loop:
            bot_idx[i] = len(verts)
            verts.append(base[i] + n * (offset - depth))
    verts = A(verts)
    # edge -> a vertex of the filled face next to it (to know the outside)
    third = {}
    for t in tris:
        m = len(t)
        for k in range(m):
            a, b2 = t[k], t[(k + 1) % m]
            other = [x for x in t if x != a and x != b2]
            if other:
                third[(min(a, b2), max(a, b2))] = other[0]
    for loop in boundary:
        m = len(loop)
        for k in range(m):
            a, b2 = loop[k], loop[(k + 1) % m]
            if a == b2:
                continue
            f = (a, bot_idx[a], bot_idx[b2], b2)
            c3 = third.get((min(a, b2), max(a, b2)))
            if c3 is not None:
                e = p2[b2] - p2[a]
                out2 = np.array([e[1], -e[0]])
                if np.dot(out2, p2[c3] - p2[a]) > 0:
                    out2 = -out2
                fa = verts[a]
                nn = np.cross(verts[bot_idx[a]] - fa, verts[b2] - fa)
                w2 = np.array([np.dot(nn, u), np.dot(nn, v)])
                if np.dot(w2, out2) < 0:
                    f = tuple(reversed(f))
            faces.append(f)
    return verts, faces


def polar_disc(outline_fn, nr, nt, center=(0.0, 0.0)):
    """Polar grid inside a closed outline r(theta) (2D).  outline_fn(theta)
    -> (x, y) boundary point.  Returns pts2d, tris/quads, boundary index loop."""
    cx, cy = center
    pts = [(cx, cy)]
    th = np.linspace(0, 2 * np.pi, nt, endpoint=False)
    bnd = A([outline_fn(t) for t in th])
    for j in range(1, nr + 1):
        f = j / nr
        f = 1 - (1 - f) ** 1.3 if j < nr else 1.0
        for k in range(nt):
            pts.append((cx + (bnd[k, 0] - cx) * f, cy + (bnd[k, 1] - cy) * f))
    faces = []
    for k in range(nt):
        faces.append((0, 1 + k, 1 + (k + 1) % nt))
    for j in range(nr - 1):
        for k in range(nt):
            a = 1 + j * nt + k
            b = 1 + j * nt + (k + 1) % nt
            faces.append((a, a + nt, b + nt, b))
    boundary = list(range(1 + (nr - 1) * nt, 1 + nr * nt))
    return A(pts), faces, boundary


def grid2d(nu, nv, fn):
    """2D grid pts = fn(u, v) for u, v in [0, 1]; returns pts, quads and the
    boundary loop (indices, counter-clockwise in (u, v))."""
    pts = []
    for i in range(nu):
        for j in range(nv):
            pts.append(fn(i / (nu - 1), j / (nv - 1)))
    quads = []
    for i in range(nu - 1):
        for j in range(nv - 1):
            a = i * nv + j
            quads.append((a, a + nv, a + nv + 1, a + 1))
    loop = [i * nv for i in range(nu)] + [(nu - 1) * nv + j for j in range(1, nv)] + \
           [i * nv + nv - 1 for i in range(nu - 2, -1, -1)] + [j for j in range(nv - 2, 0, -1)]
    return A(pts), quads, loop


def pad(base, nrm, thick, depth):
    """Raised pad over a surface patch.  base/nrm: (nu, nv, 3), thick:
    (nu, nv).  Top grid + skirt walls down to base - nrm*depth."""
    base, nrm, thick = A(base), A(nrm), A(thick)
    nu, nv = base.shape[:2]
    top = base + nrm * thick[..., None]
    verts = list(top.reshape(-1, 3))
    faces = []
    for i in range(nu - 1):
        for j in range(nv - 1):
            a = i * nv + j
            faces.append((a, a + nv, a + nv + 1, a + 1))
    loop = [i * nv for i in range(nu)] + [(nu - 1) * nv + j for j in range(1, nv)] + \
           [i * nv + nv - 1 for i in range(nu - 2, -1, -1)] + [j for j in range(nv - 2, 0, -1)]
    bot = {}
    for k in loop:
        i, j = divmod(k, nv)
        bot[k] = len(verts)
        verts.append(base[i, j] - nrm[i, j] * depth)
    m = len(loop)
    for k in range(m):
        p, q = loop[k], loop[(k + 1) % m]
        faces.append((p, bot[p], bot[q], q))
    return A(verts), faces


def boundary_loops(me):
    """2D (x, y) boundary loops of a flat mesh (e.g. a filled text curve)."""
    from collections import defaultdict
    cnt = defaultdict(int)
    for poly in me.polygons:
        vs = list(poly.vertices)
        for i in range(len(vs)):
            a, b = vs[i], vs[(i + 1) % len(vs)]
            cnt[(min(a, b), max(a, b))] += 1
    bnd = [e for e, c in cnt.items() if c == 1]
    adj = defaultdict(list)
    for a, b in bnd:
        adj[a].append(b)
        adj[b].append(a)
    co = [(v.co.x, v.co.y) for v in me.vertices]
    seen = set()
    loops = []
    for a, b in bnd:
        if (a, b) in seen:
            continue
        loop = [a]
        prev, cur = a, b
        seen.add((a, b))
        while cur != a and len(loop) < 5000:
            loop.append(cur)
            nxts = [x for x in adj[cur] if x != prev]
            if not nxts:
                break
            nxt = nxts[0]
            seen.add((min(cur, nxt), max(cur, nxt)))
            prev, cur = cur, nxt
        loops.append(A([co[i] for i in loop]))
    return loops


def simplify_loop(loop, tol):
    """Douglas-Peucker simplification of a closed 2D loop."""
    P = A(loop)
    n = len(P)
    if n < 8:
        return P
    # split at the two farthest-apart points
    i0 = 0
    i1 = int(np.argmax(np.linalg.norm(P - P[0], axis=1)))

    def dp(pts):
        if len(pts) < 3:
            return [0, len(pts) - 1]
        a, b = pts[0], pts[-1]
        ab = b - a
        L = np.linalg.norm(ab)
        if L < 1e-12:
            d = np.linalg.norm(pts - a, axis=1)
        else:
            d = np.abs(ab[0] * (pts[:, 1] - a[1]) - ab[1] * (pts[:, 0] - a[0])) / L
        k = int(np.argmax(d))
        if d[k] <= tol:
            return [0, len(pts) - 1]
        left = dp(pts[:k + 1])
        right = dp(pts[k:])
        return left[:-1] + [k + r for r in right]
    first = P[i0:i1 + 1]
    second = np.vstack([P[i1:], P[:1]])
    k1 = dp(first)
    k2 = dp(second)
    idx = [i0 + k for k in k1[:-1]] + [(i1 + k) % n for k in k2[:-1]]
    return P[idx]


def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xc = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xc > x:
                inside = not inside
    return inside


def dilate_loops(loops, d):
    """Grow the filled region of 2D loops (outer loops outward, holes
    inward) by d."""
    out = []
    for i, lp in enumerate(loops):
        depth = sum(1 for j, o in enumerate(loops) if j != i and point_in_poly(lp[0], o))
        out.append(offset_loop(lp, d if depth % 2 == 0 else -d))
    return out


def offset_loop(loop, d):
    """Offset a closed 2D polygon outward by d (miter, clamped)."""
    P = A(loop)
    n = len(P)
    area = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    sgn = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        e1 = unit(b - a)
        e2 = unit(c - b)
        n1 = np.array([e1[1], -e1[0]]) * sgn
        n2 = np.array([e2[1], -e2[0]]) * sgn
        m = unit(n1 + n2)
        turn = (e1[0] * e2[1] - e1[1] * e2[0]) * sgn * (1 if d > 0 else -1)
        if turn < 0:
            # reflex corner (relative to the growth direction): no miter
            out.append(b + m * d)
            continue
        cosh = max(np.dot(m, n1), 0.5)
        out.append(b + m * d / cosh)
    return untangle_loop(A(out), sgn)


def _seg_hit(a, b, c, d):
    r, s = b - a, d - c
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-14:
        return None
    q = c - a
    t = (q[0] * s[1] - q[1] * s[0]) / den
    u = (q[0] * r[1] - q[1] * r[0]) / den
    if 1e-9 < t < 1 - 1e-9 and 1e-9 < u < 1 - 1e-9:
        return a + r * t
    return None


def _loop_area(P):
    return 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])


def untangle_loop(P, sgn, depth=0):
    """Remove the swallowtails an offset makes where it is wider than a slit
    or a thin notch (e.g. the open counter of a "4"): split the loop at its
    first self-intersection and keep the parts that wind like the input
    (the reversed ones are the inverted swallowtail loops)."""
    n = len(P)
    if n < 4 or depth > 40:
        return P
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            x = _seg_hit(a, b, P[j], P[(j + 1) % n])
            if x is None:
                continue
            l1 = np.concatenate([P[:i + 1], [x], P[j + 1:]], 0)
            l2 = np.concatenate([[x], P[i + 1:j + 1]], 0)
            keep = [l for l in (l1, l2) if len(l) >= 3 and _loop_area(l) * sgn > 0]
            if not keep:
                return P
            # one outline per input loop: keep the largest correctly-wound part
            best = max(keep, key=lambda l: abs(_loop_area(l)))
            return untangle_loop(best, sgn, depth + 1)
    return P


# ---------------------------------------------------------------------------
# weights
# ---------------------------------------------------------------------------

def transfer_weights(src, dst, k=4):
    """Copy skin weights from src (already weighted) to dst by inverse
    distance over the k nearest source vertices."""
    sv = verts_of(src)
    kd = KDTree(len(sv))
    for i, p in enumerate(sv):
        kd.insert(Vector(p), i)
    kd.balance()
    groups = {g.index: g.name for g in src.vertex_groups}
    W = {}
    for v in src.data.vertices:
        W[v.index] = {groups[g.group]: g.weight for g in v.groups if g.weight > 0}
    dv = verts_of(dst)
    out = {}
    for i, p in enumerate(dv):
        res = kd.find_n(Vector(p), k)
        acc = {}
        tot = 0.0
        for co, idx, d in res:
            w = 1.0 / max(d, 1e-5) ** 2
            tot += w
            for g, x in W[idx].items():
                acc[g] = acc.get(g, 0.0) + w * x
        for g in acc:
            acc[g] /= tot
        out[i] = acc
    names = set(n for a in out.values() for n in a)
    vgs = {n: (dst.vertex_groups.get(n) or dst.vertex_groups.new(name=n)) for n in names}
    for i, acc in out.items():
        # keep 4 strongest, renormalise
        items = sorted(acc.items(), key=lambda x: -x[1])[:4]
        s = sum(x for _, x in items)
        for g, x in items:
            if x / s > 0.005:
                vgs[g].add([i], x / s, 'REPLACE')
