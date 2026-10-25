"""Head, face and facial features of the stylised defenders (mixin)."""
import math
import numpy as np

import sdf
import geo
from geo import A, unit
from hutil import rot_about, superellipsoid, orient_outward, ray_poly, column_dirs


class HeadMixin:

    # =====================================================================
    # HEAD
    # =====================================================================
    def head_sdf(self, grow=0.0):
        f = self.f
        h = self.h
        P = self.P
        w = f["width"]
        jaw = f["jaw"]
        jw = f["jaw_w"]
        g = grow * h
        cran = sdf.ellipsoid(P(0, 0.05, 0.09), (0.355 * w * h + g, 0.44 * h + g, 0.45 * h + g))
        face = sdf.ellipsoid(P(0, -0.06, -0.135),
                             (0.300 * w * jw * h + g, 0.33 * h + g, 0.33 * h + g))
        chin = sdf.ellipsoid(P(0, -0.25, -0.355),
                             (0.115 * h * f["chin_w"] * (0.85 + 0.3 * jaw) + g, 0.11 * h + g,
                              0.095 * h * f["chin"] + g))
        shapes = [(0.10 * h, face), (0.09 * h, chin)]
        for sx in (1, -1):
            shapes.append((0.10 * h, sdf.ellipsoid(P(sx * 0.185 * w, -0.235, -0.10),
                                                   (0.12 * h * f["cheek"] + g, 0.11 * h + g,
                                                    0.095 * h + g))))
            if jaw > 0:
                shapes.append((0.09 * h, sdf.ellipsoid(
                    P(sx * 0.215 * w * jw, -0.05, -0.255),
                    (0.085 * h * (0.6 + 0.4 * jaw) + g, 0.13 * h + g, 0.11 * h * jaw + g))))
        brow = sdf.capsule(P(-0.15 * w, -0.345, 0.115), P(0.15 * w, -0.345, 0.115),
                           0.05 * h * f["brow"] + g)
        shapes.append((0.07 * h, brow))
        return sdf.blend(cran, *shapes)

    def head_center(self):
        return self.P(0, 0.03, -0.02)

    def build_head(self):
        h = self.h
        fn = self.head_sdf()
        self.head_fn = fn
        tilt = math.radians(20)
        frame = np.array([[1, 0, 0], [0, math.cos(tilt), math.sin(tilt)],
                          [0, -math.sin(tilt), math.cos(tilt)]]).T
        rows, top, bot = geo.sphere_dirs(32, 23, frame, front_bias=0.3)
        c0 = self.head_center()
        pts, _ = geo.project_rays(fn, c0, rows.reshape(-1, 3), 0.8 * h)
        ptop, _ = geo.project_rays(fn, c0, top[None], 0.8 * h)
        pbot, _ = geo.project_rays(fn, c0, bot[None], 0.8 * h)
        verts, faces = geo.sphere_mesh_from_rows(pts.reshape(rows.shape), ptop[0], pbot[0])
        faces = orient_outward(verts, faces, c0)
        obj = self.add("Head", verts, faces, self.m["Skin"], rigid="head")
        self.head_obj = obj
        self.surf["head"] = geo.Surface(obj)
        return obj

    def head_point(self, phi_deg, z, grow=0.0):
        """Point on the (grown) head surface at azimuth phi and head-local z."""
        fn = self.head_sdf(grow) if grow else self.head_fn
        c0 = self.head_center()
        betas = np.linspace(-1.45, 1.5, 90)
        d = column_dirs(math.radians(phi_deg), betas)
        pts, _ = geo.project_rays(fn, c0, d, 0.8 * self.h, iters=28)
        zz = (pts[:, 2] - self.o[2]) / self.h
        k = int(np.clip(np.searchsorted(zz, z), 1, len(zz) - 1))
        u = (z - zz[k - 1]) / max(zz[k] - zz[k - 1], 1e-9)
        b = betas[k - 1] + (betas[k] - betas[k - 1]) * u
        p, _ = geo.project_rays(fn, c0, column_dirs(math.radians(phi_deg), [b]), 0.8 * self.h)
        return p[0]

    # -- shells around the head (hair, caps, helmets) -----------------------
    def shell_grid(self, fn, phis, z_lo, z_hi=None, nrows=8, center=None, apex=False,
                   row_bias=1.0):
        """Grid on the surface of ``fn`` (star-shaped about ``center``):
        columns at azimuths ``phis`` (deg), rows from head-local z_lo(phi)
        up to z_hi(phi) (or to the apex pole).  Returns (ncol, nrow, 3)."""
        c0 = self.head_center() if center is None else A(center)
        h = self.h
        betas = np.linspace(-1.5, 1.5707, 120)
        out = []
        for ph in phis:
            d = column_dirs(math.radians(ph), betas)
            pts, _ = geo.project_rays(fn, c0, d, 1.2 * h, iters=26)
            zz = (pts[:, 2] - self.o[2]) / h
            zz = np.maximum.accumulate(zz)
            lo = z_lo(ph)
            if apex:
                hi_b = 1.5707
                b_lo = np.interp(lo, zz, betas)
                bs = b_lo + (hi_b - b_lo) * (np.linspace(0, 1, nrows) ** row_bias)
                bs = bs[:-1]   # apex handled separately
            else:
                hi = z_hi(ph)
                ts = np.linspace(0, 1, nrows) ** row_bias
                zs = lo + (hi - lo) * ts
                bs = np.interp(zs, zz, betas)
            p, _ = geo.project_rays(fn, c0, column_dirs(math.radians(ph), bs), 1.2 * h)
            out.append(p)
        return A(out)

    @staticmethod
    def grid_faces(ncol, nrow, closed=True, start=0):
        """Faces for a (ncol, nrow) grid stored column-major."""
        f = []
        for i in range(ncol if closed else ncol - 1):
            i2 = (i + 1) % ncol
            for r in range(nrow - 1):
                a = start + i * nrow + r
                b = start + i2 * nrow + r
                f.append((a, b, b + 1, a + 1))
        return f

    # -- ears / nose --------------------------------------------------------
    def build_ears(self):
        h = self.h
        f = self.f
        out = []
        for sx in (1, -1):
            # surface point at the side of the head
            sp = self.head_point(sx * 92, -0.085)
            c = sp + A([sx * 0.018 * h, 0.016 * h, 0.0])
            ry, rz = 0.072 * h * f["ear"], 0.105 * h * f["ear"]
            rx = 0.036 * h
            # local axes: z_loc = outward (thickness), x_loc = forward/back, y_loc = up
            out_dir = unit(A([sx, 0.42, 0.0]))
            up = A([0, 0.15, 1.0])
            up = unit(up - out_dir * np.dot(up, out_dir))
            fwd = np.cross(up, out_dir) * sx
            R = np.stack([fwd, up, out_dir], 1)

            def squash(p, rx=rx, ry=ry, rz=rz):
                # dish on the outer face
                rho2 = (p[0] / ry) ** 2 + (p[1] / rz) ** 2
                if p[2] > 0:
                    p = p.copy()
                    p[2] -= 0.9 * rx * max(0.0, 1 - rho2) ** 1.5
                return p
            v, fc = superellipsoid(c, (ry, rz, rx), R, nu=12, nv=7, e1=2.2, e2=2.0,
                                   squash=squash)
            fc = orient_outward(v, fc, c - out_dir * rx * 3)
            out.append(self.add("Ear." + ("L" if sx > 0 else "R"), v, fc, self.m["Skin"],
                                rigid="head"))
        return out

    def build_nose(self):
        h = self.h
        f = self.f
        P = self.P
        root = self.surf["head"].hit(P(0, -0.2, -0.12), A([0, -1, 0]))[0]
        nz = f["nose"]
        nw = f["nose_w"]
        R = rot_about([1, 0, 0], -18)
        bridge = sdf.ellipsoid(root + A([0, -0.012, 0.035]) * h,
                               (0.042 * h * nw, 0.048 * h, 0.085 * h * nz), R)
        tip = sdf.ellipsoid(root + A([0, -0.048, -0.040 * nz]) * h,
                            (0.048 * h * nw, 0.042 * h, 0.040 * h))
        wings = [sdf.ellipsoid(root + A([sx * 0.040 * nw, -0.026, -0.058 * nz]) * h,
                               (0.032 * h * nw, 0.03 * h, 0.026 * h)) for sx in (1, -1)]
        shape = sdf.blend(bridge, 0.03 * h, tip, *wings)
        c = root + A([0, 0.01, -0.02]) * h
        rows, top, bot = geo.sphere_dirs(16, 10, np.eye(3), front_bias=0.0)
        pts, _ = geo.project_rays(shape, c, rows.reshape(-1, 3), 0.3 * h)
        pt, _ = geo.project_rays(shape, c, top[None], 0.3 * h)
        pb, _ = geo.project_rays(shape, c, bot[None], 0.3 * h)
        v, fc = geo.sphere_mesh_from_rows(pts.reshape(rows.shape), pt[0], pb[0])
        fc = orient_outward(v, fc, c)
        return self.add("Nose", v, fc, self.m["Skin"], rigid="head")

    # -- eyes --------------------------------------------------------------
    def eye_dims(self):
        f = self.f
        h = self.h
        hw = (0.088 if not self.female else 0.092) * h * f["eye"]
        top = (0.056 if not self.female else 0.070) * h * f["eye"] * f["eye_open"]
        bot = (0.058 if not self.female else 0.062) * h * f["eye"]
        tilt = (0.012 if self.female else 0.003) * h + f["eye_tilt"] * 0.02 * h
        return hw, top, bot, tilt

    def eye_curve(self, sx, t, upper=True):
        """Point of the upper/lower eye contour; t = -1 inner .. +1 outer."""
        hw, top, bot, tilt = self.eye_dims()
        base = tilt * (t + 1) / 2 - tilt * 0.45
        if upper:
            y = base + top * (1 - t * t) ** 0.55 * (1 - 0.16 * t)
        else:
            y = base - bot * (1 - t * t) ** 0.70 * (1 + 0.10 * t)
        return sx * t * hw, y

    def eye_outline(self, sx, n=40):
        """Eye-white outline in face-plane coordinates (x world, z up),
        relative to the eye centre.  sx = +1 left eye, -1 right eye."""
        hw, top, bot, tilt = self.eye_dims()
        k = n // 2
        ts = -np.cos(np.linspace(0, math.pi, k + 1))      # -1 .. 1, dense at the corners
        up = [self.eye_curve(sx, t, True) for t in ts]
        lo = [self.eye_curve(sx, t, False) for t in ts[::-1][1:-1]]
        return A(up + lo), hw, top, bot

    def build_eyes(self):
        h = self.h
        f = self.f
        m = self.m
        head = self.surf["head"]
        out = []
        ex = (0.158 if not self.female else 0.160) * h * f["width"]
        ez = -0.035 * h
        for sx in (1, -1):
            side = "L" if sx > 0 else "R"
            n = unit(A([sx * 0.22, -1.0, 0.04]))
            u = unit(A([1.0, 0, 0]) - n * n[0])
            v = unit(np.cross(n, u))
            if v[2] < 0:
                v = -v
            c_guess = self.o + A([sx * ex, 0, ez])
            c, _ = head.hit(c_guess + A([0, -0.6 * h, 0]), A([0, -1, 0]), back=0.05)
            c = head.hit(c, n)[0]
            poly, hw, top, bot = self.eye_outline(sx)

            def oline(t, poly=poly):
                d = A([math.cos(t), math.sin(t)])
                r = ray_poly(A([0.0, 0.0]), d, poly)
                return d * r
            pts, faces, bnd = geo.polar_disc(oline, 4, 22)
            rad = np.linalg.norm(pts / A([hw, (top + bot) / 2]), axis=1)
            bul = 0.030 * h * np.clip(1 - rad ** 2, 0, 1) ** 0.8

            def bulge(x, y, _p=pts, _b=bul):
                k = int(np.argmin(np.sum((_p - A([x, y])) ** 2, 1)))
                return _b[k]
            vv, ff = geo.decal(head, [bnd], c, u, v, n, 0.004 * h, 0.002 * h, bulge=bulge,
                               depth=0.012 * h, interior=pts, interior_tris=faces)
            white = self.add_decal("EyeWhite." + side, vv, ff, m["Eyes"], rigid="head")
            ws = geo.Surface(white)
            # iris (clipped by the eye outline)
            ir = (0.060 if not self.female else 0.064) * h * f["eye"]
            ic = A([sx * 0.002 * h + sx * f["iris_look"] * 0.012 * h, -0.004 * h])

            def clip_disc(r_max, center, nr, nt, shrink=0.97):
                def ol(t):
                    d = A([math.cos(t), math.sin(t)])
                    r = min(r_max, ray_poly(center, d, poly) * shrink)
                    return center + d * r
                return geo.polar_disc(ol, nr, nt, center=tuple(center))
            ip, ifc, ib = clip_disc(ir, ic, 2, 20)
            vv, ff = geo.decal(ws, [ib], c, u, v, n, 0.0022 * h, 0.0008 * h, depth=0.004 * h,
                               interior=ip, interior_tris=ifc)
            iris = self.add_decal("Iris." + side, vv, ff, m["Iris"], rigid="head")
            isurf = geo.Surface(iris)
            pp, pfc, pb = clip_disc(ir * 0.50, ic, 1, 18, shrink=0.95)
            vv, ff = geo.decal(isurf, [pb], c, u, v, n, 0.0014 * h, 0.0008 * h, depth=0.003 * h,
                               interior=pp, interior_tris=pfc)
            self.add_decal("Pupil." + side, vv, ff, m["Pupil"], rigid="head")
            # highlights (same world side for both eyes: key light from the
            # character's right, i.e. -x)
            for (hx, hy, hr) in ((-0.36, 0.40, 0.30), (0.34, -0.36, 0.13)):
                hc = ic + A([hx * ir, hy * ir])
                hp, hfc, hb = geo.polar_disc(
                    lambda t, hc=hc, hr=hr: hc + A([math.cos(t), math.sin(t)]) * hr * ir,
                    1, 10, center=tuple(hc))
                vv, ff = geo.decal(isurf, [hb], c, u, v, n, 0.0040 * h, 0.0008 * h,
                                   depth=0.004 * h, interior=hp, interior_tris=hfc)
                self.add_decal("EyeHi." + side, vv, ff, m["EyeHighlight"], rigid="head")
            # upper lid line (+ lashes flick for the women)
            out.append(self.build_lid(head, c, u, v, n, poly, hw, sx, side))
            self.eye_c = getattr(self, "eye_c", {})
            self.eye_c[side] = (c, u, v, n, hw, top, bot)
        return out

    def build_lid(self, surf, c, u, v, n, poly, hw, sx, side):
        h = self.h
        f = self.f
        # sample the upper contour from inner to outer corner
        xs = np.linspace(-1.0, 1.0, 18)
        upper = A([self.eye_curve(sx, t, True) for t in xs])
        th = (0.016 if not self.female else 0.020) * h
        lo, hi = [], []
        for k, (x, y) in enumerate(upper):
            t = xs[k]
            w = th * (0.35 + 0.65 * math.sin(math.pi * (t + 1) / 2) ** 0.7)
            if t > 0.3:
                w *= 1.0 + 0.4 * (t - 0.3)
            lo.append((x, y - w * 0.30))
            hi.append((x, y + w * 0.70))
        loop = lo + hi[::-1]
        if self.female or f["lashes"]:
            # flick at the outer corner
            xo, yo = upper[-1]
            loop = lo + [(xo + sx * 0.030 * h, yo + 0.022 * h)] + hi[::-1]
        loop = A(loop)
        if sx < 0:
            loop = loop[::-1]
        vv, ff = geo.decal(surf, [loop], c, u, v, n, 0.004 * h + 0.008 * h, 0.004 * h,
                           depth=0.014 * h)
        return self.add_decal("Lid." + side, vv, ff, self.m["Pupil"], rigid="head")

    def build_brows(self, mat):
        h = self.h
        f = self.f
        head = self.surf["head"]
        out = []
        for sx in (1, -1):
            side = "L" if sx > 0 else "R"
            n = unit(A([sx * 0.30, -1.0, 0.25]))
            u = A([1.0, 0, 0])
            u = unit(u - n * np.dot(u, n))
            v = unit(np.cross(n, u))
            if v[2] < 0:
                v = -v
            c = head.hit(self.o + A([sx * 0.16 * h, -0.5 * h, 0.098 * h]), A([0, -1, 0]),
                         back=0.05)[0]
            ang = f["brow_angle"]
            th = 0.042 * h * f["brow_thick"] * (0.8 if self.female else 1.0)
            pts_lo, pts_hi = [], []
            for k in range(9):
                t = k / 8.0                  # 0 inner .. 1 outer
                x = (-0.085 + 0.175 * t) * h
                arch = 0.020 * h * math.sin(math.pi * min(1.0, t * 1.15)) * (1.3 if self.female else 1.0)
                y = arch - ang * 0.035 * h * (0.5 - t) * -1 - 0.01 * h
                w = th * (1.0 - 0.55 * t) if not self.female else th * (0.85 - 0.5 * t)
                pts_lo.append((sx * x, y - w * 0.45))
                pts_hi.append((sx * x, y + w * 0.55))
            loop = A(pts_lo + pts_hi[::-1])
            if sx < 0:
                loop = loop[::-1]
            vv, ff = geo.decal(head, [loop], c, u, v, n, 0.002 * h, 0.010 * h, depth=0.02 * h,
                               subdiv=1)
            out.append(self.add_decal("Brow." + side, vv, ff, mat, rigid="head"))
        return out

    def build_mouth(self, surf=None):
        h = self.h
        f = self.f
        surf = surf or self.surf["head"]
        n = A([0, -1.0, 0.05])
        n = unit(n)
        u = A([1.0, 0, 0])
        v = unit(np.cross(n, u))
        if v[2] < 0:
            v = -v
        c = surf.hit(self.o + A([0, -0.6 * h, -0.268 * h]), A([0, -1, 0]), back=0.1)[0]
        hw = (0.112 if not self.female else 0.092) * h * f["mouth_w"]
        sm = f["smile"]
        sk_ = f["smirk"]
        kind = f["mouth"]
        out = []
        xs = np.linspace(-1, 1, 15)

        def ycen(t):
            # smile curve + smirk (raises the character's left corner)
            return sm * 0.030 * h * (t * t) + sk_ * 0.024 * h * max(0, t) ** 2 - 0.008 * h * sm
        if kind in ("grin", "open"):
            open_h = (0.060 if kind == "grin" else 0.045) * h
            top, bot = [], []
            for t in xs:
                x = t * hw * (1.0 if kind == "grin" else 0.9)
                y0 = ycen(t)
                top.append((x, y0 + 0.006 * h * (1 - t * t)))
                bot.append((x, y0 - open_h * (1 - abs(t) ** 2.2) ** 0.9))
            loop = A(top[::-1] + bot[1:-1])
            loop = loop[::-1]
            vv, ff = geo.decal(surf, [loop], c, u, v, n, 0.0015 * h, 0.002 * h, depth=0.01 * h,
                               subdiv=1)
            mo = self.add_decal("Mouth", vv, ff, self.m["Mouth"], rigid="head")
            out.append(mo)
            # teeth band along the top of the opening
            msurf = geo.Surface(mo)
            tt, tb = [], []
            for t in xs[2:-2]:
                x = t * hw * (1.0 if kind == "grin" else 0.9)
                y0 = ycen(t)
                tt.append((x * 0.92, y0 - 0.002 * h))
                depth_t = 0.020 * h * (1 - abs(t) ** 2) ** 0.6
                tb.append((x * 0.92, y0 - 0.004 * h - depth_t))
            loop = A(tt[::-1] + tb)
            loop = loop[::-1]
            vv, ff = geo.decal(msurf, [loop], c, u, v, n, 0.0012 * h, 0.001 * h, depth=0.004 * h,
                               subdiv=1)
            out.append(self.add_decal("Teeth", vv, ff, self.m["Eyes"], rigid="head"))
        else:
            top, bot = [], []
            for t in xs:
                x = t * hw * 0.85
                y0 = ycen(t)
                w = 0.016 * h * (1 - abs(t) ** 2.5) ** 0.8 + 0.005 * h
                top.append((x, y0 + w * 0.40))
                bot.append((x, y0 - w * 0.60))
            loop = A(top[::-1] + bot[1:-1])
            loop = loop[::-1]
            vv, ff = geo.decal(surf, [loop], c, u, v, n, 0.0015 * h, 0.002 * h, depth=0.01 * h,
                               subdiv=1)
            out.append(self.add_decal("Mouth", vv, ff, self.m["Mouth"], rigid="head"))
        # lower lip highlight: a soft bump under the mouth
        return out

