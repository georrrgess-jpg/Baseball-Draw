"""Caps, visor, headband, hair styles, beards, glasses and catcher gear of
the stylised defenders (mixin)."""
import math
import numpy as np

import sdf
import geo
from geo import A, unit
from hutil import superellipsoid, orient_outward, column_dirs


def periodic(keys, mirror=True):
    """keys [(phi_deg, value)] for phi in [0, 180] (mirrored) -> f(phi)."""
    ks = sorted(keys)
    if mirror:
        full = [(-p, v) for p, v in ks[::-1] if 0 < p < 180] + ks
    else:
        full = ks
    xs = A([k[0] for k in full])
    vs = A([k[1] for k in full])

    def f(phi):
        p = ((phi + 180.0) % 360.0) - 180.0
        if p <= xs[0]:
            p += 360.0
        return float(geo.interp(xs, vs, [p], mono=True, closed=360.0)[0])
    return f


def ang_dist(a, b):
    return abs(((a - b + 180.0) % 360.0) - 180.0)


def cap_rim(ph):
    r = math.radians(ph)
    return 0.085 + 0.15 * math.cos(r) + 0.015 * math.cos(2 * r)


HAIRLINE = {
    "short": [(0, 0.27), (35, 0.23), (55, 0.15), (64, 0.05), (70, -0.10), (77, -0.11),
              (83, -0.02), (95, 0.04), (110, 0.02), (130, -0.14), (155, -0.24), (180, -0.28)],
    "pixie": [(0, 0.27), (35, 0.23), (55, 0.15), (64, 0.05), (70, -0.04), (77, -0.05),
              (83, 0.0), (95, 0.04), (110, 0.02), (130, -0.12), (155, -0.20), (180, -0.22)],
}


class WearMixin:
    # =====================================================================
    # generic shells
    # =====================================================================
    def surface_at(self, fn, ph, z):
        """Point on the star-shaped surface fn at azimuth ph and local z."""
        c0 = self.head_center()
        betas = np.linspace(-1.5, 1.5707, 120)
        d = column_dirs(math.radians(ph), betas)
        pts, _ = geo.project_rays(fn, c0, d, 1.2 * self.h, iters=26)
        zz = np.maximum.accumulate((pts[:, 2] - self.o[2]) / self.h)
        b = float(np.interp(z, zz, betas))
        p, _ = geo.project_rays(fn, c0, column_dirs(math.radians(ph), [b]), 1.2 * self.h)
        return p[0]

    def beta_at(self, fn, ph, z):
        c0 = self.head_center()
        betas = np.linspace(-1.5, 1.5707, 120)
        pts, _ = geo.project_rays(fn, c0, column_dirs(math.radians(ph), betas), 1.2 * self.h,
                                  iters=26)
        zz = np.maximum.accumulate((pts[:, 2] - self.o[2]) / self.h)
        return float(np.interp(z, zz, betas))

    def skin_edge(self, pts, lift=0.004):
        """Project points (outside the head) back onto the skin along the
        ray from the head centre (+ a small lift)."""
        c0 = self.head_center()
        d = unit(A(pts) - c0)
        skin, _ = geo.project_rays(self.head_fn, c0, d, 0.9 * self.h)
        return skin + d * lift * self.h

    def shell(self, name, mat, fn, phis, z_lo, z_hi=None, nrows=7, closed=True, apex=False,
              edge="skin", row_bias=1.0, rigid="head", lip=0.03):
        """Shell on fn between z_lo(phi) and z_hi(phi) (or the apex).
        edge = 'skin' closes the bottom edge onto the skin, 'lip' rolls it
        inward (thick rim), None leaves it open."""
        G = self.shell_grid(fn, phis, z_lo, z_hi, nrows=nrows, apex=apex, row_bias=row_bias)
        h = self.h
        c0 = self.head_center()
        rows = [G[:, k] for k in range(G.shape[1])]
        if edge == "skin":
            rows = [self.skin_edge(rows[0])] + rows
        elif edge == "lip":
            r0 = rows[0]
            inw = c0[None] - r0
            inw[:, 2] = 0
            inw = unit(inw)
            l1 = r0 + A([0, 0, -0.005 * h]) + inw * 0.004 * h
            l2 = r0 + inw * lip * h + A([0, 0, 0.012 * h])
            rows = [l2, l1] + rows
        grid = np.stack(rows, 1)
        ncol, nrow = grid.shape[:2]
        verts = list(grid.reshape(-1, 3))
        faces = self.grid_faces(ncol, nrow, closed=closed)
        if apex:
            pole, _ = geo.project_rays(fn, c0, A([[0, 0, 1.0]]), 1.2 * h)
            verts.append(pole[0])
            pi = len(verts) - 1
            for i in range(ncol if closed else ncol - 1):
                i2 = (i + 1) % ncol
                faces.append((i * nrow + nrow - 1, i2 * nrow + nrow - 1, pi))
        faces = orient_outward(verts, faces, c0)
        obj = self.add(name, verts, faces, mat, rigid=rigid)
        return obj, grid

    def spike(self, name, mat, base, dirv, length, width, flat=0.45, curl=0.25, nr=6, ns=6,
              side=None, rigid="head"):
        """Tapered hair tuft from base along dirv (curling down)."""
        h = self.h
        d = unit(dirv)
        side = unit(np.cross(d, A([0, 0, 1.0]))) if side is None else unit(side)
        up = unit(np.cross(side, d))
        ts = np.linspace(0, 1, nr)
        pts = [base + d * length * t + A([0, 0, -1.0]) * curl * length * t * t for t in ts]
        T, U, V = geo.transport_frames(pts, up)
        ang = np.linspace(0, 2 * np.pi, ns, endpoint=False)
        rings = []
        for i, t in enumerate(ts[:-1]):
            w = width * (1 - t) ** 0.85
            rings.append(pts[i] + np.outer(np.cos(ang), U[i]) * w * flat +
                         np.outer(np.sin(ang), V[i]) * w)
        v, f = geo.loft(rings, cap0='pole', cap1=pts[-1])
        f = orient_outward(v, f, base)
        return self.add(name, v, f, mat, rigid=rigid)

    def radial(self, ph):
        r = math.radians(ph)
        return A([math.sin(r), -math.cos(r), 0.0])

    # =====================================================================
    # caps
    # =====================================================================
    def cap_sdf(self, grow=0.0):
        h = self.h
        P = self.P
        w = self.f["width"]
        g = grow * h
        dome = sdf.ellipsoid(P(0, 0.05, 0.085), (0.398 * w * h + g, 0.478 * h + g, 0.478 * h + g))
        front = sdf.ellipsoid(P(0, -0.09, 0.19), (0.31 * w * h + g, 0.34 * h + g, 0.34 * h + g))
        return sdf.blend(dome, 0.12 * h, front)

    def build_cap(self, yaw=0.0, emblem=None):
        h = self.h
        m = self.m
        fn = self.cap_sdf()
        self.cap_fn = fn
        oc = 180.0 + yaw

        def z_lo(ph):
            z = cap_rim(ph)
            d = ang_dist(ph, oc)
            if d < 25:
                z += 0.135 * math.cos(math.pi / 2 * d / 25) ** 0.8
            return z
        phis = np.linspace(0, 360, 36, endpoint=False)
        crown, grid = self.shell("CapCrown", m["Cap"], fn, phis, z_lo, nrows=11, apex=True,
                                 edge="lip", row_bias=0.85)
        # panel seams (subtle raised lines)
        for ph in (yaw + 34, yaw - 34, yaw + 110, yaw - 110):
            if ang_dist(ph, oc) < 30:
                continue
            pts = [self.surface_at(fn, ph, z) for z in np.linspace(z_lo(ph) + 0.03, 0.50, 7)]
            pts = [p + unit(p - self.head_center()) * 0.002 * h for p in pts]
            v, f = geo.tube(pts, 0.0065 * h, nseg=4, cap0='pole', cap1='pole')
            self.add("CapSeam", v, f, m["Cap"], rigid="head")
        # button on top (accent: readable from above)
        top, _ = geo.project_rays(fn, self.head_center(), A([[0, 0, 1.0]]), 1.2 * h)
        v, f = superellipsoid(top[0] + A([0, 0, 0.006 * h]), (0.05 * h, 0.05 * h, 0.022 * h),
                              nu=12, nv=6)
        f = orient_outward(v, f, top[0])
        self.add("CapButton", v, f, m["Undershirt"], rigid="head")
        # snapback strap across the opening
        sph = np.linspace(oc - 26, oc + 26, 9)
        base = A([[self.surface_at(fn, ph, cap_rim(ph) + z) for z in (0.0, 0.02, 0.04)]
                  for ph in sph])
        nrm = unit(base - self.head_center())
        thick = np.full(base.shape[:2], 0.010 * h)
        v, f = geo.pad(base, nrm, thick, 0.006 * h)
        f = orient_outward(v, f, self.head_center())
        self.add("CapStrap", v, f, m["Cap"], rigid="head")
        self.build_brim(fn, yaw, cap_rim, pitch=(-7 if yaw == 0 else 6))
        if emblem:
            self.build_emblem(fn, yaw, emblem)
        return crown

    def build_brim(self, fn, yaw, rim_fn, length=0.38, pitch=-7, curve=0.075, width=70,
                   name="Brim"):
        h = self.h
        m = self.m
        th = 0.026 * h
        axis = self.radial(yaw)
        cols = []
        edges = []
        us = np.linspace(-1, 1, 19)
        pr = math.radians(pitch)
        for u in us:
            ph = yaw + u * width
            rp = self.surface_at(fn, ph, rim_fn(ph) + 0.012)
            d = unit(self.radial(ph) * 0.40 + axis * 0.60)
            L = length * h * max(0.0, 1 - abs(u) ** 2.4) ** 0.5
            dn = d * math.cos(pr) + A([0, 0, 1.0]) * math.sin(pr)
            n = A([0, 0, 1.0]) * math.cos(pr) - d * math.sin(pr)
            col_t, col_b = [], []
            vs = [-0.10, 0.25, 0.55, 0.82, 1.0]
            for v in vs:
                sag = -curve * h * u * u * max(v, 0)
                c = rp + dn * L * v + n * sag
                col_t.append(c + n * th / 2)
                col_b.append(c - n * th / 2)
            sag = -curve * h * u * u
            ce = rp + dn * (L + th * 0.42) + n * sag
            e1 = ce + n * th * 0.24
            e2 = ce - n * th * 0.24
            cols.append(col_b + [e2, e1] + col_t[::-1])
            edges.append(rp + dn * (L + th * 0.15) + n * sag)
        cols = A(cols)
        nu, nv = cols.shape[:2]
        verts = list(cols.reshape(-1, 3))
        faces = []
        for i in range(nu - 1):
            for j in range(nv - 1):
                a = i * nv + j
                faces.append((a, a + nv, a + nv + 1, a + 1))
        faces = orient_outward(verts, faces, self.head_center() + A([0, 0, -0.3 * h]))
        brim = self.add(name, verts, faces, m["Cap"], rigid="head")
        # piping along the edge
        e = A(edges[1:-1])
        v, f = geo.tube(e, 0.0125 * h, nseg=6, cap0='pole', cap1='pole')
        self.add(name + "Trim", v, f, m["JerseyTrim"], rigid="head")
        return brim

    def emblem_loops(self, kind, size):
        if kind == "flame":
            pts = [(0.0, -0.50), (0.30, -0.42), (0.42, -0.18), (0.36, 0.08), (0.24, 0.20),
                   (0.30, 0.44), (0.12, 0.28), (0.04, 0.54), (-0.08, 0.30), (-0.18, 0.42),
                   (-0.22, 0.16), (-0.36, 0.26), (-0.42, -0.08), (-0.34, -0.36)]
            return [A(pts) * size]
        if kind == "bolt":
            pts = [(0.12, 0.52), (-0.24, 0.02), (-0.03, 0.02), (-0.16, -0.52), (0.26, 0.08),
                   (0.05, 0.08), (0.22, 0.52)]
            return [A(pts) * size]
        # diamond (home plate-ish diamond with a hole)
        o = A([(0, 0.52), (0.46, 0.06), (0.46, -0.10), (0, -0.52), (-0.46, -0.10), (-0.46, 0.06)])
        return [o * size]

    def build_emblem(self, fn, yaw, kind):
        h = self.h
        m = self.m
        crown =[o for o in self.parts if o.name.startswith("CapCrown")][-1]
        cs = geo.Surface(crown)
        p = self.surface_at(fn, yaw, 0.335)
        n = unit(p - self.head_center())
        n = unit(n + A([0, 0, 0.15]))
        u = unit(np.cross(A([0, 0, 1.0]), n))
        if np.dot(u, A([math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0])) < 0:
            u = -u
        v = unit(np.cross(n, u))
        if v[2] < 0:
            v = -v
        size = 0.25 * h
        loops = self.emblem_loops(kind, size)
        outl = [geo.offset_loop(l, 0.022 * h) for l in loops]
        vv, ff = geo.decal(cs, outl, p, u, v, n, 0.001 * h, 0.004 * h, depth=0.01 * h, subdiv=2)
        self.add_decal("EmblemOutline", vv, ff, m["Number"], rigid="head")
        vv, ff = geo.decal(cs, loops, p, u, v, n, 0.005 * h, 0.004 * h, depth=0.01 * h, subdiv=2)
        self.add_decal("Emblem", vv, ff, m["Undershirt"], rigid="head")
        if kind == "diamond":
            inner = [A([(0, 0.26), (0.22, 0.03), (0.22, -0.05), (0, -0.26), (-0.22, -0.05),
                        (-0.22, 0.03)]) * size]
            vv, ff = geo.decal(cs, inner, p, u, v, n, 0.0085 * h, 0.002 * h, depth=0.01 * h,
                               subdiv=2)
            self.add_decal("EmblemCore", vv, ff, m["Number"], rigid="head")

    def build_visor(self, base_fn):
        """Sun visor: band around the (hair-covered) head + brim."""
        h = self.h
        m = self.m
        fn = sdf.offset(base_fn, 0.012 * h)

        def z_lo(ph):
            return 0.095 + 0.085 * math.cos(math.radians(ph))
        phis = np.linspace(0, 360, 44, endpoint=False)
        base = A([[self.surface_at(fn, ph, z_lo(ph) + dz) for dz in (0.0, 0.035, 0.07, 0.10)]
                  for ph in phis])
        nrm = unit(base - self.head_center())
        thick = np.tile(A([0.007, 0.012, 0.012, 0.007]) * h, (len(phis), 1))
        # closed band: pad on a closed strip -> build manually
        top = base + nrm * thick[..., None]
        inner = base - nrm * 0.004 * h
        rows = [inner[:, 0], top[:, 0], top[:, 1], top[:, 2], top[:, 3], inner[:, 3]]
        grid = np.stack(rows, 1)
        ncol, nrow = grid.shape[:2]
        verts = list(grid.reshape(-1, 3))
        faces = self.grid_faces(ncol, nrow, closed=True)
        faces = orient_outward(verts, faces, self.head_center())
        self.add("VisorBand", verts, faces, m["Cap"], rigid="head")
        # accent stripe around the band
        stripe = A([[self.surface_at(fn, ph, z_lo(ph) + dz) for dz in (0.042, 0.062)]
                    for ph in phis])
        sn = unit(stripe - self.head_center())
        rows = [stripe[:, 0] + sn[:, 0] * 0.011 * h, stripe[:, 0] + sn[:, 0] * 0.0145 * h,
                stripe[:, 1] + sn[:, 1] * 0.0145 * h, stripe[:, 1] + sn[:, 1] * 0.011 * h]
        grid = np.stack(rows, 1)
        verts = list(grid.reshape(-1, 3))
        faces = self.grid_faces(len(phis), 4, closed=True)
        faces = orient_outward(verts, faces, self.head_center())
        self.add("VisorStripe", verts, faces, m["Undershirt"], rigid="head")
        self.build_brim(fn, 0.0, lambda ph: z_lo(ph) + 0.004, length=0.44, pitch=-14, width=72,
                        name="VisorBrim")

    def build_headband(self):
        h = self.h
        m = self.m
        fn = self.head_sdf(0.004)

        def z_lo(ph):
            return 0.085 + 0.075 * math.cos(math.radians(ph))
        phis = np.linspace(0, 360, 44, endpoint=False)
        base = A([[self.surface_at(fn, ph, z_lo(ph) + dz) for dz in (0.0, 0.03, 0.08, 0.11)]
                  for ph in phis])
        nrm = unit(base - self.head_center())
        th = A([0.010, 0.020, 0.020, 0.010]) * h
        top = base + nrm * th[None, :, None]
        inner = base - nrm * 0.006 * h
        rows = [inner[:, 0], top[:, 0], top[:, 1], top[:, 2], top[:, 3], inner[:, 3]]
        grid = np.stack(rows, 1)
        verts = list(grid.reshape(-1, 3))
        faces = self.grid_faces(len(phis), len(rows), closed=True)
        faces = orient_outward(verts, faces, self.head_center())
        self.add("Headband", verts, faces, m["Undershirt"], rigid="head")
        # knot + tails at the back
        kn = self.surface_at(fn, 180, z_lo(180) + 0.055) + A([0, 0.025 * h, 0])
        v, f = superellipsoid(kn, (0.045 * h, 0.03 * h, 0.04 * h), nu=10, nv=6)
        f = orient_outward(v, f, kn)
        self.add("HeadbandKnot", v, f, m["Undershirt"], rigid="head")
        for sx in (1, -1):
            pts = [kn, kn + A([sx * 0.05, 0.08, -0.07]) * h, kn + A([sx * 0.10, 0.12, -0.17]) * h]
            v, f = geo.tube(pts, [0.03 * h, 0.03 * h, 0.022 * h], nseg=8, up=(0, 1, 0),
                            ovals=[0.35, 0.35, 0.35], cap0='pole', cap1='pole')
            self.add("HeadbandTail", v, f, m["Undershirt"], rigid="head")

    # =====================================================================
    # hair
    # =====================================================================
    def hair_base(self, style, mat, under_cap=True, grow=0.022):
        keys = HAIRLINE.get(style, HAIRLINE["short"])
        lo = periodic(keys)
        fn = self.head_sdf(grow)
        if under_cap:
            def z_hi(ph):
                return cap_rim(ph) + 0.05

            def z_lo(ph):
                return min(lo(ph), z_hi(ph) - 0.04)
            phis = np.linspace(0, 360, 48, endpoint=False)
            obj, grid = self.shell("Hair", mat, fn, phis, z_lo, z_hi, nrows=5)
        else:
            phis = np.linspace(0, 360, 48, endpoint=False)
            obj, grid = self.shell("Hair", mat, fn, phis, lo, nrows=10, apex=True)
        return obj

    def tuft(self, mat, ph, z, length, width, droop, grow=0.02, curl=0.25, flat=0.45,
             lean=0.0, name="HairTuft"):
        h = self.h
        fn = self.head_sdf(grow)
        base = self.surface_at(fn, ph, z)
        rad = self.radial(ph + lean)
        dr = math.radians(droop)
        d = rad * math.cos(dr) + A([0, 0, 1.0]) * math.sin(dr)
        base = base - unit(base - self.head_center()) * 0.035 * h
        return self.spike(name, mat, base, d, length * h + 0.035 * h, width * h, flat=flat,
                          curl=curl)

    def build_hair(self, style, mat, headwear):
        h = self.h
        cap = headwear in ("cap", "cap_back")
        if style == "none":
            return
        if style == "bob":
            return self.build_bob(mat)
        if style in ("buzz",):
            if headwear == "catcher":
                return self.hair_base("short", mat, under_cap=True, grow=0.012)
            return self.hair_base("short", mat, under_cap=cap, grow=0.014)
        base_style = "pixie" if style == "pixie" else "short"
        self.hair_base(base_style, mat, under_cap=cap, grow=0.02)
        T = self.tuft
        if style == "spiky":
            for sx in (1, -1):
                T(mat, sx * 66, 0.07, 0.11, 0.05, -70, curl=0.1, lean=sx * -8)
                T(mat, sx * 100, 0.07, 0.14, 0.062, -28, lean=sx * 12)
                T(mat, sx * 124, 0.03, 0.15, 0.068, -26, lean=sx * 10)
                T(mat, sx * 150, -0.02, 0.15, 0.068, -34, lean=sx * 8)
                T(mat, sx * 172, 0.10, 0.11, 0.05, 30, curl=0.35)
            T(mat, 180, -0.05, 0.14, 0.065, -40)
        elif style == "short":
            for sx in (1, -1):
                T(mat, sx * 112, 0.02, 0.07, 0.05, -55)
                T(mat, sx * 140, -0.04, 0.08, 0.05, -60)
            T(mat, 180, -0.07, 0.07, 0.05, -65)
        elif style == "pixie":
            for sx in (1, -1):
                T(mat, sx * 112, 0.02, 0.08, 0.05, -60)
                T(mat, sx * 138, -0.08, 0.10, 0.05, -72)
                T(mat, sx * 162, -0.12, 0.11, 0.052, -76)
            T(mat, 180, -0.14, 0.10, 0.05, -78)
            T(mat, 68, 0.04, 0.11, 0.05, -78, curl=0.05)
            self.build_fringe(mat)
        elif style == "ponytail":
            for sx in (1, -1):
                T(mat, sx * 66, 0.08, 0.17, 0.045, -82, curl=0.05, flat=0.5, lean=sx * -10)
            self.build_ponytail(mat)
        elif style == "curly":
            self.build_curls(mat)

    def build_fringe(self, mat):
        h = self.h
        fn = self.head_sdf(0.03)
        pts = [self.surface_at(fn, ph, z) for ph, z in
               ((14, 0.22), (-6, 0.195), (-26, 0.15), (-46, 0.09), (-62, 0.02), (-74, -0.06))]
        c0 = self.head_center()
        pts = [p + unit(p - c0) * k * h for p, k in zip(pts, (0.02, 0.04, 0.045, 0.038, 0.026,
                                                                 0.012))]
        pts = geo.smooth_polyline(pts, 10)
        rad = geo.interp([0, 0.3, 1.0], [0.07, 0.085, 0.012], np.linspace(0, 1, 10)) * h
        T, U, V = geo.transport_frames(pts, A([0, 0, 1.0]))
        ang = np.linspace(0, 2 * np.pi, 8, endpoint=False)
        rings = []
        for i in range(len(pts) - 1):
            nrm = unit(pts[i] - c0)
            side = unit(np.cross(T[i], nrm))
            rings.append(pts[i] + np.outer(np.cos(ang), side) * rad[i] +
                         np.outer(np.sin(ang), nrm) * rad[i] * 0.32)
        v, f = geo.loft(rings, cap0='pole', cap1=pts[-1])
        f = orient_outward(v, f, c0)
        self.add("HairFringe", v, f, mat, rigid="head")

    def build_ponytail(self, mat):
        h = self.h
        P = self.P
        pts = [P(0, 0.36, 0.02), P(0, 0.50, 0.015), P(0.012, 0.62, -0.05), P(0.03, 0.71, -0.19),
               P(0.05, 0.72, -0.35), P(0.065, 0.66, -0.52), P(0.07, 0.59, -0.62)]
        pts = geo.smooth_polyline(pts, 16)
        rad = geo.interp([0, 0.15, 0.35, 0.6, 0.85, 1.0], [0.07, 0.078, 0.10, 0.095, 0.06, 0.012],
                         np.linspace(0, 1, 16)) * h
        v, f = geo.tube(pts, rad, nseg=12, up=(1, 0, 0), ovals=[0.82] * 16, cap0='pole',
                        cap1='pole')
        f = orient_outward(v, f, pts[8])
        self.add("Ponytail", v, f, mat, rigid="head")
        # hair tie (accent)
        c = pts[2]
        T, U, V = geo.transport_frames(pts, A([1.0, 0, 0]))
        ring = [c + (U[2] * math.cos(a) + V[2] * math.sin(a) * 0.82) * rad[2] * 1.02
                for a in np.linspace(0, 2 * np.pi, 16, endpoint=False)]
        v, f = geo.tube(ring, 0.022 * h, nseg=6, closed_path=True, up=T[2])
        self.add("HairTie", v, f, self.m["Undershirt"], rigid="head")

    def build_curls(self, mat):
        h = self.h
        fn = self.head_sdf(0.03)
        c0 = self.head_center()
        spots = []
        for sx in (1, -1):
            for ph, dz, r in ((56, -0.01, 0.062), (76, -0.03, 0.074), (98, -0.01, 0.084),
                              (122, -0.01, 0.088), (146, -0.02, 0.088), (166, 0.0, 0.08),
                              (110, -0.12, 0.074), (134, -0.13, 0.078), (158, -0.14, 0.078),
                              (66, -0.11, 0.052), (88, 0.03, 0.06)):
                spots.append((sx * ph, cap_rim(sx * ph) + dz, r))
        spots += [(180, cap_rim(180) - 0.03, 0.085), (180, -0.19, 0.074), (180, 0.10, 0.07),
                  (40, cap_rim(40) - 0.015, 0.05), (-40, cap_rim(40) - 0.015, 0.05)]
        for ph, z, r in spots:
            p = self.surface_at(fn, ph, z)
            d = unit(p - c0)
            c = p + d * r * h * 0.35
            R = np.stack([np.cross(A([0, 0, 1.0]), d) if abs(d[2]) < 0.95 else A([1.0, 0, 0]),
                          A([0, 0, 1.0]), d], 1)
            R[:, 0] = unit(R[:, 0])
            R[:, 1] = unit(np.cross(R[:, 2], R[:, 0]))
            v, f = superellipsoid(c, (r * h, r * h * 0.95, r * h * 0.85), R, nu=8, nv=5)
            f = orient_outward(v, f, c)
            self.add("Curl", v, f, mat, rigid="head")

    def build_bob(self, mat):
        h = self.h
        P = self.P
        w = self.f["width"]
        base = self.head_sdf(0.05)
        flare = sdf.ellipsoid(P(0, 0.07, -0.20), (0.43 * w * h, 0.50 * h, 0.27 * h))
        fn = sdf.blend(base, 0.12 * h, flare)
        self.bob_fn = fn
        keys = [(0, 0.165), (10, 0.158), (20, 0.170), (30, 0.158), (40, 0.150), (47, 0.07),
                (54, -0.18), (62, -0.30), (90, -0.31), (135, -0.33), (180, -0.33)]
        lo = periodic(keys)
        phis = np.linspace(0, 360, 48, endpoint=False)
        obj, grid = self.shell("Hair", mat, fn, phis, lo, nrows=10, apex=True, edge="lip",
                               lip=0.045)
        c0 = self.head_center()
        # pointed clumps along the bottom edge and the bangs
        for ph in list(range(56, 305, 21)):
            z = lo(ph) + 0.05
            b = self.surface_at(fn, ph, z)
            d = unit(A([0, 0, -1.0]) + self.radial(ph) * 0.18)
            b = b - unit(b - c0) * 0.012 * h
            self.spike("HairClump", mat, b, d, 0.10 * h, 0.07 * h, flat=0.42, curl=-0.25,
                       side=np.cross(self.radial(ph), A([0, 0, 1.0])))
        for ph in (-33, -16, 0, 16, 33):
            z = lo(ph) + 0.06
            b = self.surface_at(fn, ph, z) - unit(self.surface_at(fn, ph, z) - c0) * 0.01 * h
            d = unit(A([0, 0, -1.0]) + self.radial(ph) * 0.12)
            self.spike("HairClump", mat, b, d, 0.085 * h, 0.06 * h, flat=0.4, curl=-0.2,
                       side=np.cross(self.radial(ph), A([0, 0, 1.0])))
        # strand grooves (raised lines) from the crown
        for ph in range(0, 360, 30):
            pts = [self.surface_at(fn, ph + 8 * k, z) for k, z in
                   enumerate(np.linspace(0.50, lo(ph) + 0.15 if abs(((ph + 180) % 360) - 180) > 50 else 0.30, 6))]
            pts = [p + unit(p - c0) * 0.002 * h for p in pts]
            v, f = geo.tube(pts, 0.009 * h, nseg=4, cap0='pole', cap1='pole')
            self.add("HairStrand", v, f, mat, rigid="head")
        return obj

    # =====================================================================
    # face extras
    # =====================================================================
    def build_beard(self, full=False):
        h = self.h
        P = self.P
        m = self.m
        base = self.head_sdf(0.0)
        t0, t1 = (0.016, 0.032) if not full else (0.03, 0.07)
        oz = self.o[2]

        def fn0(Pts):
            zl = (Pts[:, 2] - oz) / h
            g = t0 + (t1 - t0) * np.clip((-zl - 0.15) / 0.30, 0, 1)
            return base(Pts) - g * h
        fn0.bbox = base.bbox
        fn = fn0
        if full:
            bulk = sdf.ellipsoid(P(0, -0.20, -0.47), (0.27 * h, 0.21 * h, 0.25 * h))
            fn = sdf.blend(fn0, 0.12 * h, bulk)
        self.beard_fn = fn
        if full:
            hi = periodic([(0, -0.215), (12, -0.232), (22, -0.19), (36, -0.125), (55, -0.085),
                           (75, -0.035), (98, 0.0), (180, 0.0)])
        else:
            hi = periodic([(0, -0.335), (14, -0.33), (26, -0.30), (36, -0.215), (50, -0.15),
                           (70, -0.07), (98, 0.0), (180, 0.0)])
        phis = np.linspace(-98, 98, 31)
        c0 = self.head_center()
        cols = []
        for ph in phis:
            bh = self.beta_at(fn, ph, hi(ph))
            bs = np.linspace(bh, -1.38, 11)
            p, _ = geo.project_rays(fn, c0, column_dirs(math.radians(ph), bs), 1.2 * h)
            cols.append(p[::-1])
        G = A(cols)                        # (ncol, nrow) bottom -> top
        top_edge = self.skin_edge(G[:, -1], lift=0.003)
        grid = np.concatenate([G, top_edge[:, None]], 1)
        # side columns onto the skin
        left = self.skin_edge(grid[0], lift=0.003)
        right = self.skin_edge(grid[-1], lift=0.003)
        grid = np.concatenate([left[None], grid, right[None]], 0)
        ncol, nrow = grid.shape[:2]
        verts = list(grid.reshape(-1, 3))
        faces = self.grid_faces(ncol, nrow, closed=False)
        faces = orient_outward(verts, faces, c0)
        beard = self.add("Beard", verts, faces, m["Hair"], rigid="head")
        # mustache
        bs = geo.Surface(beard)
        mpts = []
        for ph, z in ((-34, -0.300), (-20, -0.262), (-8, -0.240), (0, -0.238), (8, -0.240),
                      (20, -0.262), (34, -0.300)):
            p = self.surface_at(fn, ph, z)
            mpts.append(p + unit(p - c0) * 0.004 * h)
        mpts = geo.smooth_polyline(mpts, 14)
        r = (0.024 if not full else 0.036) * h
        rad = r * np.sin(np.linspace(0.25, math.pi - 0.25, 14)) ** 0.6
        v, f = geo.tube(mpts, rad, nseg=8, up=(0, -1, 0), ovals=[0.7] * 14, cap0='pole',
                        cap1='pole')
        self.add("Mustache", v, f, m["Hair"], rigid="head")
        return beard

    def build_eyeblack(self):
        h = self.h
        head = self.surf["head"]
        for sx in (1, -1):
            n = unit(A([sx * 0.35, -1.0, 0.0]))
            u = unit(A([1.0, 0, 0]) - n * n[0])
            v = unit(np.cross(n, u))
            if v[2] < 0:
                v = -v
            c = head.hit(self.o + A([sx * 0.17 * h, -0.6 * h, -0.118 * h]), A([0, -1, 0]),
                         back=0.05)[0]
            loop = A([(-0.062, -0.016), (0.062, -0.006), (0.060, 0.020), (-0.064, 0.012)]) * h
            loop[:, 0] *= sx
            vv, ff = geo.decal(head, [loop], c, u, v, n, 0.0012 * h, 0.0012 * h, depth=0.01 * h,
                               subdiv=1)
            self.add_decal("EyeBlack", vv, ff, self.m["Pupil"], rigid="head")

    def build_sunglasses(self):
        h = self.h
        m = self.m
        fn = self.head_sdf(0.062)
        c0 = self.head_center()
        phis = np.linspace(-80, 80, 27)

        def z_lo(ph):
            return -0.110 + 0.060 * math.exp(-(ph / 11.0) ** 2) + 0.03 * (abs(ph) / 80) ** 2

        def z_hi(ph):
            return 0.080 - 0.040 * (abs(ph) / 80) ** 2.2
        G = self.shell_grid(fn, phis, z_lo, z_hi, nrows=6)
        nrm = unit(G - c0)
        th = np.full(G.shape[:2], 0.012 * h)
        verts, faces = geo.pad(G, nrm, th, 0.0)
        # back face
        nb = len(verts)
        back = G.reshape(-1, 3)
        verts = np.concatenate([verts, back], 0)
        nu, nv = G.shape[:2]
        for i in range(nu - 1):
            for j in range(nv - 1):
                a = nb + i * nv + j
                faces.append((a, a + 1, a + nv + 1, a + nv))
        self.add("Sunglasses", verts, faces, m["Visor"], rigid="head")
        # frame: top bar + temple arms
        top = [G[i, -1] + nrm[i, -1] * 0.008 * h + A([0, 0, 0.006 * h]) for i in range(nu)]
        v, f = geo.tube(top, 0.013 * h, nseg=6, cap0='pole', cap1='pole')
        self.add("GlassesFrame", v, f, m["Pupil"], rigid="head")
        fn2 = self.head_sdf(0.022)
        for sx in (1, -1):
            pts = [G[0 if sx < 0 else -1, -2] + nrm[0 if sx < 0 else -1, -2] * 0.006 * h]
            for ph in (sx * 86, sx * 96, sx * 108):
                pts.append(self.surface_at(fn2, ph, 0.02))
            v, f = geo.tube(pts, 0.011 * h, nseg=6, cap0='pole', cap1='pole')
            self.add("GlassesArm", v, f, m["Pupil"], rigid="head")

    # =====================================================================
    # catcher gear
    # =====================================================================
    def build_catcher_helmet(self):
        h = self.h
        P = self.P
        m = self.m
        w = self.f["width"]
        base = self.head_sdf(0.075)
        ears = [sdf.ellipsoid(P(sx * 0.35 * w, 0.06, -0.14), (0.11 * h, 0.21 * h, 0.27 * h))
                for sx in (1, -1)]
        fn = sdf.blend(base, 0.08 * h, *ears)
        lo = periodic([(0, 0.27), (25, 0.255), (40, 0.16), (50, -0.05), (58, -0.24), (66, -0.42),
                       (100, -0.45), (140, -0.36), (180, -0.30)])
        phis = np.linspace(0, 360, 40, endpoint=False)
        shell, grid = self.shell("CatcherHelmet", m["Gear"], fn, phis, lo, nrows=14, apex=True,
                                 edge="lip", lip=0.06)
        # rubber trim around the opening / bottom edge
        edge = grid[::2, 2]
        c0 = self.head_center()
        edge = [p + unit(p - c0) * 0.002 * h for p in edge]
        v, f = geo.tube(edge, 0.020 * h, nseg=5, closed_path=True)
        self.add("HelmetTrim", v, f, m["Pupil"], rigid="head")
        # ridge over the top
        pts = [self.surface_at(fn, ph, z) for ph, z in ((0, 0.34), (0, 0.46), (0, 0.55))]
        pts += [self.surface_at(fn, 180, z) for z in (0.50, 0.36, 0.20)]
        pts = [p + unit(p - c0) * 0.006 * h for p in pts]
        pts = geo.smooth_polyline(pts, 14)
        v, f = geo.tube(pts, 0.040 * h, nseg=8, ovals=[0.45] * 14, up=(1, 0, 0), cap0='pole',
                        cap1='pole')
        self.add("HelmetRidge", v, f, m["Gear"], rigid="head")
        # face cage (bars)
        cage = self.head_sdf(0.17)
        bars = []
        for ph in (-14, 14):
            bars.append([self.surface_at(cage, ph, z) for z in np.linspace(0.20, -0.50, 7)])
        for z, span in ((0.17, 52), (0.0, 56), (-0.17, 54), (-0.34, 46), (-0.48, 30)):
            bars.append([self.surface_at(cage, ph, z) for ph in np.linspace(-span, span, 9)])
        for sx in (1, -1):
            for z in (0.17, -0.17):
                a = self.surface_at(cage, sx * 52, z)
                b = self.surface_at(fn, sx * 62, z)
                bars.append([a, b])
        for pts in bars:
            pts = geo.smooth_polyline(pts, max(2, len(pts)))
            v, f = geo.tube(pts, 0.018 * h, nseg=5, cap0='pole', cap1='pole')
            self.add("FaceCage", v, f, m["Metal"], rigid="head")

    def build_chest_protector(self):
        s = self.s
        m = self.m
        surf = self.surf["torso"]
        zn, zp, zc = self.lv("neck"), self.lv("pelvis"), self.lv("chest")
        cw = self.p["chest_w"] * s

        def uv(u, v):
            uu = u * 2 - 1
            W = cw * (0.80 + 0.20 * min(1.0, v * 4.0)) * (1.0 - 0.15 * v)
            ztop = zn - 0.004 * s - 0.05 * s * max(0.0, 1 - uu * uu) ** 1.5
            z = ztop + (zp + 0.035 * s - ztop) * v
            return uu * W, z
        nu, nv = 17, 15
        base = np.zeros((nu, nv, 3))
        nrm = np.zeros((nu, nv, 3))
        th = np.zeros((nu, nv))
        for i in range(nu):
            for j in range(nv):
                x, z = uv(i / (nu - 1), j / (nv - 1))
                hit, _ = surf.hit(A([x, -0.4, z]), A([0, -1.0, 0]))
                base[i, j] = hit
                rd = unit(A([hit[0], hit[1] - 0.0, 0]))
                nrm[i, j] = unit(rd * 0.7 + A([0, -1.0, 0]) * 0.3)
                uu = i / (nu - 1) * 2 - 1
                vv = j / (nv - 1)
                seg = vv * 4.0
                fr = seg - math.floor(seg)
                pillow = 0.72 + 0.28 * math.sin(math.pi * fr) ** 0.6
                edge = (1 - abs(uu) ** 6) ** 0.5 * (1 - abs(vv * 2 - 1) ** 10) ** 0.5
                th[i, j] = (0.010 + 0.024 * pillow * edge) * s
        v, f = geo.pad(base, nrm, th, 0.004 * s)
        f = orient_outward(v, f, A([0, 0.05 * s, zc]))
        prot = self.add("ChestProtector", v, f, m["Gear"], weights_from=self.torso_obj)
        # shoulder straps (dark), on the trapezius
        for sx in (1, -1):
            pts = []
            for ph, z in ((25, zn - 0.02 * s), (45, zn + 0.015 * s), (90, zn + 0.035 * s),
                          (135, zn + 0.01 * s), (155, zn - 0.04 * s), (165, zn - 0.10 * s)):
                a = math.radians(ph)
                d = A([sx * math.sin(a) * 0.55, -math.cos(a), 0.0])
                o = A([sx * 0.06 * s, 0.0, z])
                loc, _ = surf.ray(o + unit(d) * 0.5, -unit(d), 1.0)
                if loc is not None:
                    pts.append(loc + unit(d) * 0.006 * s)
            pts = geo.smooth_polyline(pts, 16)
            v, f = geo.tube(pts, 0.016 * s, nseg=6, ovals=[0.35] * 16, up=(0, 0, 1),
                            cap0='pole', cap1='pole')
            self.add("ProtectorStrap", v, f, m["Belt"], weights_from=self.torso_obj)
        return prot

    def build_shin_guards(self):
        s = self.s
        m = self.m
        for side in "LR":
            K = self.j("shin." + side)
            Ak = self.j("foot." + side)
            d = unit(Ak - K)
            fwd = A([0, -1.0, 0])
            U = unit(fwd - d * np.dot(fwd, d))
            V = np.cross(d, U)
            ts = np.linspace(0.05, 0.92, 11)
            thetas = np.linspace(-118, 118, 11)
            rings = self.sock_rings(side, ts, grow=0.004 * s, nseg=72)
            base = np.zeros((len(thetas), len(ts), 3))
            nrm = np.zeros_like(base)
            th = np.zeros(base.shape[:2])
            L = np.linalg.norm(Ak - K)
            for j, t in enumerate(ts):
                c = K + d * L * t
                ring = rings[j]
                for i, a in enumerate(thetas):
                    k = int(round((a % 360) / 5.0)) % 72
                    base[i, j] = ring[k]
                    nrm[i, j] = unit(ring[k] - c)
                    ridge = math.exp(-(a / 10.0) ** 2) + 0.6 * math.exp(-((abs(a) - 62) / 9.0) ** 2)
                    edge = (1 - (abs(a) / 118) ** 8) ** 0.5 * (1 - abs(2 * (j / (len(ts) - 1)) - 1) ** 8) ** 0.5
                    th[i, j] = (0.010 + 0.007 * ridge) * s * edge + 0.003 * s
            v, f = geo.pad(base, nrm, th, 0.004 * s)
            f = orient_outward(v, f, K + d * L * 0.5)
            self.add("ShinGuard." + side, v, f, m["Gear"], rigid="shin." + side)
            # knee cap
            kc = K + U * self.p["knee_r"] * s * 1.25 + d * 0.01 * s
            R = np.stack([V, -d, U], 1)
            v, f = superellipsoid(kc, (0.062 * s, 0.075 * s, 0.040 * s), R, nu=14, nv=8, e1=2.2,
                                  e2=2.2)
            f = orient_outward(v, f, kc - U * 0.02 * s)
            self.add("KneeCap." + side, v, f, m["Gear"], rigid="shin." + side)
            # foot flap over the instep
            fs = s * self.p["foot_scale"]
            fc = A([Ak[0], Ak[1] - 0.045 * fs, 0.118 * fs])
            R = np.stack([A([1.0, 0, 0]), unit(A([0, -0.9, -0.45])), unit(A([0, 0.45, -0.9]))], 1)
            R[:, 2] = np.cross(R[:, 0], R[:, 1])
            v, f = superellipsoid(fc, (0.050 * fs, 0.055 * fs, 0.014 * fs), R, nu=12, nv=6,
                                  e1=2.6, e2=2.4)
            f = orient_outward(v, f, fc - A([0, 0, 0.02]))
            self.add("FootFlap." + side, v, f, m["Gear"], rigid="foot." + side)
