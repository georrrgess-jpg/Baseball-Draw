"""Mesh-builder helpers for the Baseball Draw prop generator.

All geometry is accumulated in an `MB` (mesh builder) as polygons with a
material *name* per face and per-corner UVs, then turned into one Blender mesh
object.  Conventions (Blender space): Z up, prop front faces -Y, metres.

Shading model: every face is marked smooth, and the topology decides the look:
flat pieces (boxes, hulls, prisms) get their own unshared vertices so they
render faceted; curved pieces (cylinders, lathes, tubes, spheres) share
vertices inside one smoothing group.

UVs: primitives that know their parametrisation (cylinders, lathes, grids)
write explicit UVs.  Everything else is box-projected in object space at a
per-material texel density (see `pmat.uv_scale`).
"""
import math
from contextlib import contextmanager

import bmesh
import bpy
from mathutils import Matrix, Vector

TAU = math.tau


def vec(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def frame_from_axis(z_axis, up_hint=None):
    """Return a 3x3 rotation whose Z column is `z_axis` (normalised)."""
    z = vec(z_axis).normalized()
    hint = vec(up_hint) if up_hint is not None else Vector((0, 0, 1))
    if abs(z.dot(hint.normalized())) > 0.99:
        hint = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    x = hint.cross(z).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()


def mat_at(origin, z_axis=None, rot3=None, up_hint=None):
    """4x4 matrix translating to `origin` with local Z along `z_axis`."""
    if rot3 is None:
        rot3 = frame_from_axis(z_axis, up_hint) if z_axis is not None else Matrix.Identity(3)
    m = rot3.to_4x4()
    m.translation = vec(origin)
    return m


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'X')


def RY(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Y')


def RZ(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


# maps local (a, b, c) -> global (c, a, b): profile in (y, z), extrude along x
AX = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return Matrix.Diagonal((x, y, z, 1.0))


class MB:
    """Accumulates polygons; `build()` turns them into a Blender object."""

    def __init__(self, uv_scale_fn=None):
        self.verts = []
        self.faces = []
        self.face_mat = []
        self.face_uv = []
        self.M = Matrix.Identity(4)
        self._stack = []
        self.uv_scale_fn = uv_scale_fn or (lambda name: 2.0)

    # ------------------------------------------------------------ transforms
    @contextmanager
    def xf(self, m):
        self._stack.append(self.M)
        self.M = self.M @ m
        try:
            yield self
        finally:
            self.M = self._stack.pop()

    def _v(self, p):
        self.verts.append(self.M @ vec(p))
        return len(self.verts) - 1

    # ------------------------------------------------------------ raw faces
    def poly(self, pts, mat, uvs=None):
        """Flat polygon with its own vertices. pts CCW seen from the front."""
        idx = [self._v(p) for p in pts]
        self.faces.append(tuple(idx))
        self.face_mat.append(mat)
        self.face_uv.append(list(uvs) if uvs is not None else None)
        return len(self.faces) - 1

    def grid(self, rows, mat, uvs=None, wrap=False):
        """Smooth quad grid from rows of points (rows[i][j]).

        Faces are (i,j),(i,j+1),(i+1,j+1),(i+1,j) so with j running CCW around
        an axis and i going up, normals face outward.  `uvs` mirrors `rows`
        (and needs one extra column when wrap=True for the seam).  A row whose
        points collapse to one location produces triangles.
        """
        nr = len(rows)
        nc = len(rows[0])
        ids = [[self._v(p) for p in row] for row in rows]
        ncell = nc if wrap else nc - 1
        for i in range(nr - 1):
            for j in range(ncell):
                j1 = (j + 1) % nc
                quad = [ids[i][j], ids[i][j1], ids[i + 1][j1], ids[i + 1][j]]
                uvq = None
                if uvs is not None:
                    jj1 = j + 1
                    uvq = [uvs[i][j], uvs[i][jj1], uvs[i + 1][jj1], uvs[i + 1][j]]
                # collapse degenerate corners (cone tips / poles)
                pos = [tuple(round(c, 7) for c in self.verts[k]) for k in quad]
                keep = []
                for k in range(4):
                    if pos[k] != pos[(k - 1) % 4]:
                        keep.append(k)
                if len(keep) < 3:
                    continue
                self.faces.append(tuple(quad[k] for k in keep))
                self.face_mat.append(mat)
                self.face_uv.append([uvq[k] for k in keep] if uvq else None)

    # ------------------------------------------------------------ primitives
    def box(self, c, s, mat, skip=(), mats=None, uvs=None):
        """Axis-aligned (in current transform) box. `skip` face keys like '-z'."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2

        def P(a, b, d):
            return (cx + a * hx, cy + b * hy, cz + d * hz)
        faces = {
            '+x': [P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)],
            '-x': [P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)],
            '+y': [P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)],
            '-y': [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
            '+z': [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
            '-z': [P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1)],
        }
        out = {}
        for k, pts in faces.items():
            if k in skip:
                continue
            m = mats.get(k, mat) if mats else mat
            uv = uvs.get(k) if uvs else None
            out[k] = self.poly(pts, m, uv)
        return out

    def box_mm(self, lo, hi, mat, **kw):
        c = [(a + b) / 2 for a, b in zip(lo, hi)]
        s = [abs(b - a) for a, b in zip(lo, hi)]
        return self.box(c, s, mat, **kw)

    def hull(self, pts, mat, skip_down=False):
        """Convex hull of points as flat polygons (coplanar tris merged)."""
        bm = bmesh.new()
        for p in pts:
            bm.verts.new(vec(p))
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
        # remove interior / unused geometry
        bmesh.ops.delete(bm, geom=list(set(res['geom_interior']) | set(res['geom_unused'])), context='VERTS')
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts[:], edges=bm.edges[:])
        bm.faces.ensure_lookup_table()
        cen = Vector((0, 0, 0))
        for v in bm.verts:
            cen += v.co
        cen /= max(1, len(bm.verts))
        for f in bm.faces:
            co = [v.co.copy() for v in f.verts]
            n = f.normal
            if n.dot(f.calc_center_median() - cen) < 0:
                co.reverse()
                n = -n
            if skip_down and n.z < -0.99:
                continue
            self.poly(co, mat)
        bm.free()

    def cbox(self, c, s, mat, ch=0.05, skip_down=False):
        """Chamfered box (one-segment bevel of size `ch`)."""
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        ch = min(ch, hx * 0.49, hy * 0.49, hz * 0.49)
        pts = []
        for a in (-1, 1):
            for b in (-1, 1):
                for d in (-1, 1):
                    pts.append((c[0] + a * hx, c[1] + b * (hy - ch), c[2] + d * (hz - ch)))
                    pts.append((c[0] + a * (hx - ch), c[1] + b * hy, c[2] + d * (hz - ch)))
                    pts.append((c[0] + a * (hx - ch), c[1] + b * (hy - ch), c[2] + d * hz))
        self.hull(pts, mat, skip_down=skip_down)

    def cbox_mm(self, lo, hi, mat, ch=0.05, **kw):
        c = [(a + b) / 2 for a, b in zip(lo, hi)]
        s = [abs(b - a) for a, b in zip(lo, hi)]
        self.cbox(c, s, mat, ch=ch, **kw)

    def beam(self, p0, p1, w, h, mat, up=(0, 0, 1), skip_ends=False, chamfer=0.0):
        """Rectangular member from p0 to p1; w across, h along the `up` side."""
        p0, p1 = vec(p0), vec(p1)
        d = p1 - p0
        L = d.length
        if L < 1e-6:
            return
        rot = frame_from_axis(d, up)       # local Z along the beam
        m = mat_at(p0, rot3=rot)
        with self.xf(m):
            if chamfer > 0:
                self.cbox((0, 0, L / 2), (w, h, L), mat, ch=chamfer)
            else:
                self.box((0, 0, L / 2), (w, h, L), mat, skip=('-z', '+z') if skip_ends else ())

    def strut(self, p0, p1, r, mat, sides=4, caps=False, rot0=45.0):
        """Cheap n-sided prism (no caps by default) - lattice members, wires."""
        p0, p1 = vec(p0), vec(p1)
        d = p1 - p0
        if d.length < 1e-6:
            return
        rot = frame_from_axis(d)
        m = mat_at(p0, rot3=rot)
        L = d.length
        ring0, ring1 = [], []
        for i in range(sides):
            a = math.radians(rot0) + TAU * i / sides
            ring0.append((r * math.cos(a), r * math.sin(a), 0.0))
            ring1.append((r * math.cos(a), r * math.sin(a), L))
        with self.xf(m):
            for i in range(sides):
                j = (i + 1) % sides
                self.poly([ring0[i], ring0[j], ring1[j], ring1[i]], mat)
            if caps:
                self.poly(list(reversed(ring0)), mat)
                self.poly(ring1, mat)

    def cyl(self, p0, p1, r0, mat, r1=None, seg=12, caps=(True, True), cap_mat=None,
            smooth=True, uv_scale=None, rot0=0.0, up_hint=None):
        """Cylinder / frustum from p0 to p1 (radii r0 -> r1)."""
        r1 = r0 if r1 is None else r1
        p0, p1 = vec(p0), vec(p1)
        d = p1 - p0
        L = d.length
        if L < 1e-7:
            return
        rot = frame_from_axis(d, up_hint)
        m = mat_at(p0, rot3=rot)
        sc = uv_scale or self.uv_scale_fn(mat)
        circ = TAU * max(r0, r1)
        ang = [math.radians(rot0) + TAU * i / seg for i in range(seg)]
        with self.xf(m):
            if smooth:
                rows = [[(r0 * math.cos(a), r0 * math.sin(a), 0.0) for a in ang],
                        [(r1 * math.cos(a), r1 * math.sin(a), L) for a in ang]]
                uvs = [[(circ * i / seg / sc, 0.0) for i in range(seg + 1)],
                       [(circ * i / seg / sc, L / sc) for i in range(seg + 1)]]
                self.grid(rows, mat, uvs=uvs, wrap=True)
            else:
                for i in range(seg):
                    a, b = ang[i], ang[(i + 1) % seg]
                    self.poly([(r0 * math.cos(a), r0 * math.sin(a), 0), (r0 * math.cos(b), r0 * math.sin(b), 0),
                               (r1 * math.cos(b), r1 * math.sin(b), L), (r1 * math.cos(a), r1 * math.sin(a), L)], mat)
            cm = cap_mat or mat
            if caps[0] and r0 > 1e-6:
                self.poly([(r0 * math.cos(a), r0 * math.sin(a), 0.0) for a in reversed(ang)], cm,
                          uvs=[(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)) for a in reversed(ang)] if cap_mat else None)
            if caps[1] and r1 > 1e-6:
                self.poly([(r1 * math.cos(a), r1 * math.sin(a), L) for a in ang], cm,
                          uvs=[(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)) for a in ang] if cap_mat else None)

    def disc(self, c, normal, r, mat, seg=12, uv01=True, rot0=0.0):
        """Flat disc facing `normal` with 0..1 planar UVs."""
        m = mat_at(c, normal)
        ang = [math.radians(rot0) + TAU * i / seg for i in range(seg)]
        with self.xf(m):
            self.poly([(r * math.cos(a), r * math.sin(a), 0.0) for a in ang], mat,
                      uvs=[(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)) for a in ang] if uv01 else None)

    def lathe(self, profile, mat, seg=12, sharp=(), uv_scale=None, rot0=0.0, vmode='len'):
        """Revolve [(r, z), ...] around local Z.  Indices in `sharp` crease."""
        sc = uv_scale or self.uv_scale_fn(mat)
        rmax = max(p[0] for p in profile) or 1.0
        runs, cur = [], [0]
        for i in range(1, len(profile)):
            cur.append(i)
            if i in sharp and i != len(profile) - 1:
                runs.append(cur)
                cur = [i]
        runs.append(cur)
        # arc length for V
        acc = [0.0]
        for i in range(1, len(profile)):
            dr = profile[i][0] - profile[i - 1][0]
            dz = profile[i][1] - profile[i - 1][1]
            acc.append(acc[-1] + math.hypot(dr, dz))
        ang = [math.radians(rot0) + TAU * i / seg for i in range(seg)]
        for run in runs:
            rows, uvs = [], []
            for i in run:
                r, z = profile[i]
                rows.append([(r * math.cos(a), r * math.sin(a), z) for a in ang])
                if vmode == 'len':
                    v = acc[i] / sc
                else:
                    v = acc[i] / acc[-1]
                uvs.append([(TAU * rmax * k / seg / sc if vmode == 'len' else k / seg, v) for k in range(seg + 1)])
            self.grid(rows, mat, uvs=uvs, wrap=True)

    def sphere(self, c, r, mat, seg=12, rings=8, uv01=False, squash=1.0):
        prof = []
        for i in range(rings + 1):
            t = -math.pi / 2 + math.pi * i / rings
            prof.append((r * math.cos(t), r * math.sin(t) * squash))
        with self.xf(T(*c)):
            self.lathe(prof, mat, seg=seg, vmode='01' if uv01 else 'len')

    def dome(self, c, r, mat, seg=12, rings=4, h=None, normal=(0, 0, 1)):
        """Hemisphere (open bottom) of radius r, height h, along `normal`."""
        h = r if h is None else h
        prof = []
        for i in range(rings + 1):
            t = math.pi / 2 * i / rings
            prof.append((r * math.cos(t), h * math.sin(t)))
        with self.xf(mat_at(c, normal)):
            self.lathe(prof, mat, seg=seg)

    def rivet(self, c, normal, mat, r=0.03, h=0.018, seg=6):
        with self.xf(mat_at(c, normal)):
            self.lathe([(r, 0.0), (r * 0.75, h * 0.7), (0.0, h)], mat, seg=seg, rot0=30)

    def prism(self, poly2d, z0, z1, mat, cap_mat=None, caps=(True, True), side_mats=None):
        """Extrude a 2D polygon in local XY from z0 to z1 along local Z.
        Winding is normalised to CCW so faces always point outward."""
        n = len(poly2d)
        if z0 > z1:
            z0, z1 = z1, z0
        area = sum(poly2d[i][0] * poly2d[(i + 1) % n][1] - poly2d[(i + 1) % n][0] * poly2d[i][1]
                   for i in range(n))
        if area < 0:
            poly2d = list(reversed(poly2d))
            if side_mats:
                side_mats = [side_mats[(n - 2 - j) % n] for j in range(n)]
        for i in range(n):
            a, b = poly2d[i], poly2d[(i + 1) % n]
            m = side_mats[i] if side_mats else mat
            self.poly([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], m)
        cm = cap_mat or mat
        if caps[0]:
            self.poly([(p[0], p[1], z0) for p in reversed(poly2d)], cm)
        if caps[1]:
            self.poly([(p[0], p[1], z1) for p in poly2d], cm)

    def prism_x(self, poly_yz, x0, x1, mat, **kw):
        """Prism whose profile is given as (y, z) pairs, extruded along X."""
        with self.xf(AX):
            self.prism(poly_yz, x0, x1, mat, **kw)

    def prism_y(self, poly_xz, y0, y1, mat, **kw):
        """Prism whose profile is given as (x, z) pairs, extruded along Y."""
        with self.xf(RX(90)):
            self.prism(poly_xz, -y1, -y0, mat, **kw)

    def flip_from(self, start):
        """Reverse winding of faces added since index `start` (after mirroring)."""
        for i in range(start, len(self.faces)):
            self.faces[i] = tuple(reversed(self.faces[i]))
            if self.face_uv[i] is not None:
                self.face_uv[i] = list(reversed(self.face_uv[i]))

    @contextmanager
    def mirrored(self, axis='x'):
        """Mirror geometry built inside the block, keeping normals outward."""
        start = len(self.faces)
        sc = {'x': S(-1, 1, 1), 'y': S(1, -1, 1), 'z': S(1, 1, -1)}[axis]
        with self.xf(sc):
            yield self
        self.flip_from(start)

    def tube(self, pts, r, mat, seg=6, closed=False, caps=False, uv_scale=None):
        """Swept tube along a polyline (parallel-transport frames)."""
        P = [vec(p) for p in pts]
        n = len(P)
        if n < 2:
            return
        tang = []
        for i in range(n):
            if closed:
                t = P[(i + 1) % n] - P[(i - 1) % n]
            else:
                t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
            tang.append(t.normalized())
        rot = frame_from_axis(tang[0])
        nrm = Vector(rot.col[0])
        rows = []
        sc = uv_scale or self.uv_scale_fn(mat)
        uvs = []
        acc = 0.0
        for i in range(n):
            if i > 0:
                acc += (P[i] - P[i - 1]).length
                # transport the normal
                nrm = nrm - tang[i] * nrm.dot(tang[i])
                if nrm.length < 1e-6:
                    nrm = Vector(frame_from_axis(tang[i]).col[0])
                nrm.normalize()
            bin_ = tang[i].cross(nrm)
            ring = []
            for k in range(seg):
                a = TAU * k / seg
                ring.append(P[i] + (nrm * math.cos(a) + bin_ * math.sin(a)) * r)
            rows.append(ring)
            uvs.append([(k / seg * TAU * r / sc, acc / sc) for k in range(seg + 1)])
        # transform-independent: rows already in local coords of current xf
        if closed:
            rows.append(rows[0])
            uvs.append([(u, (acc + (P[0] - P[-1]).length) / sc) for u, _ in uvs[0]])
        self.grid(rows, mat, uvs=uvs, wrap=True)
        if caps and not closed:
            self.poly(list(reversed(rows[0])), mat)
            self.poly(rows[-1], mat)

    def quad_grid(self, origin, u_vec, v_vec, nu, nv, mat, uv_rect=(0, 0, 1, 1)):
        """Subdivided flat quad. origin + s*u_vec + t*v_vec; normal = u x v.
        UV (u0 + s*(u1-u0), v0 + t*(v1-v0)) in Blender convention (v up)."""
        o, U, Vv = vec(origin), vec(u_vec), vec(v_vec)
        u0, v0, u1, v1 = uv_rect
        rows, uvs = [], []
        for j in range(nv + 1):
            t = j / nv
            rows.append([o + U * (i / nu) + Vv * t for i in range(nu + 1)])
            uvs.append([(u0 + (u1 - u0) * i / nu, v0 + (v1 - v0) * t) for i in range(nu + 1)])
        self.grid(rows, mat, uvs=uvs, wrap=False)

    def text(self, s, font, size, mat, depth=0.02, align='CENTER', resolution=2, valign='CENTER'):
        """Text geometry in local XY (reads left->right along +X, up +Y),
        extruded towards local +Z by `depth` (front cap at +depth/2... +depth)."""
        cu = bpy.data.curves.new('tmp_text', 'FONT')
        cu.body = s
        cu.font = font
        cu.size = size
        cu.extrude = depth / 2
        cu.resolution_u = resolution
        cu.align_x = align
        cu.align_y = valign
        cu.fill_mode = 'BOTH'
        ob = bpy.data.objects.new('tmp_text', cu)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        base = len(self.verts)
        for v in me.vertices:
            self._v((v.co.x, v.co.y, v.co.z + depth / 2))
        for p in me.polygons:
            self.faces.append(tuple(base + i for i in p.vertices))
            self.face_mat.append(mat)
            self.face_uv.append(None)
        ev.to_mesh_clear()
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)

    # ------------------------------------------------------------ output
    def tri_count(self):
        return sum(len(f) - 2 for f in self.faces)

    def build(self, name, get_material, parent=None, collection=None):
        """Create the mesh object.  `get_material(name)` returns a bpy material."""
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        names = []
        for m in self.face_mat:
            if m not in names:
                names.append(m)
        for n in names:
            me.materials.append(get_material(n))
        midx = {n: i for i, n in enumerate(names)}
        uvl = me.uv_layers.new(name='UVMap')
        uvdata = [0.0] * (len(me.loops) * 2)
        for fi, poly in enumerate(me.polygons):
            poly.material_index = midx[self.face_mat[fi]]
            uv = self.face_uv[fi]
            if uv is None:
                uv = self._auto_uv(fi)
            for k, li in enumerate(poly.loop_indices):
                uvdata[li * 2] = uv[k][0]
                uvdata[li * 2 + 1] = uv[k][1]
        uvl.data.foreach_set('uv', uvdata)
        me.shade_smooth()
        me.validate(clean_customdata=False)
        me.update()
        ob = bpy.data.objects.new(name, me)
        (collection or bpy.context.scene.collection).objects.link(ob)
        if parent is not None:
            ob.parent = parent
        return ob

    def _auto_uv(self, fi):
        f = self.faces[fi]
        co = [self.verts[i] for i in f]
        n = Vector((0, 0, 0))
        for i in range(len(co)):
            a, b = co[i], co[(i + 1) % len(co)]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        sc = self.uv_scale_fn(self.face_mat[fi])
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        out = []
        for p in co:
            if az >= ax and az >= ay:
                u, v = (p.x, p.y) if n.z >= 0 else (-p.x, p.y)
            elif ax >= ay:
                u, v = (p.y, p.z) if n.x >= 0 else (-p.y, p.z)
            else:
                u, v = (-p.x, p.z) if n.y >= 0 else (p.x, p.z)
            out.append((u / sc, v / sc))
        return out


def tri_count_obj(ob):
    me = ob.data
    return sum(len(p.vertices) - 2 for p in me.polygons)
