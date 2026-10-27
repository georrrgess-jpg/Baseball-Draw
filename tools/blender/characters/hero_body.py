"""Body of the stylised defenders (mixin): neck, jersey torso + sleeves,
undershirt arms, hands, mitt, pants (mirrored cage + Catmull-Clark), belt,
socks, cleats, jersey numbers and piping."""
import math
import json
import numpy as np

import geo
from geo import A, unit
from hutil import superellipsoid, orient_outward


class BodyMixin:
    # =====================================================================
    # neck / torso
    # =====================================================================
    def build_neck(self):
        s = self.s
        p = self.p
        nr = p["neck_r"] * s
        a = self.j("neck") + A([0, 0.004 * s, -0.075 * s])
        b = self.j("head") + A([0, 0.0, 0.045 * s])
        ts = np.linspace(0, 1, 7)
        pts = a[None] + (b - a)[None] * ts[:, None]
        r = geo.interp([0, 0.35, 0.7, 1.0], [1.35, 1.02, 0.98, 0.95], ts)
        T, U, V = geo.transport_frames(pts, (0, -1, 0))
        ang = np.linspace(0, 2 * np.pi, 16, endpoint=False)
        rings = []
        for i in range(len(ts)):
            rx = nr * r[i] * 1.06
            ry = nr * r[i] * 0.96
            rings.append(pts[i] + np.outer(np.cos(ang), U[i]) * ry +
                         np.outer(np.sin(ang), V[i]) * rx)
        v, f = geo.loft(rings, None, None)
        f = orient_outward(v, f, (a + b) / 2)
        self.neck_obj = self.add("Neck", v, f, self.m["Skin"], bones=["chest", "neck", "head"])
        return self.neck_obj

    def torso_stations(self):
        s = self.s
        p = self.p
        cw, cd = p["chest_w"], p["chest_d"]
        ww, wd = p["waist_w"], p["waist_d"]
        sh, nr = p["sh_half"], p["neck_r"]
        mus, bel = p["muscle"], p["belly"]
        zp, zs, zc, zn = self.lv("pelvis"), self.lv("spine"), self.lv("chest"), self.lv("neck")
        shz = self.j("upper_arm.L")[2]
        fem = 1.0 if self.female else 0.0
        # z, W, F, B, n, pec, blade, yc, dip  (W/F/B/pec/blade/yc/dip in s-units)
        return [
            # hem tucked ~7 cm (x scale) under the waistband, clear of the hip
            # crease so a raised thigh cannot fold the pants over it
            (zp - 0.005 * s, ww * 1.00, wd * 1.00, wd * 1.02, 2.4, 0, 0, 0, 0),
            (zp + 0.045 * s, ww * 1.00 + 0.02 * bel, wd + 0.035 * bel, wd * 1.02, 2.4, 0, 0, 0, 0),
            (zs + 0.03 * s, ww * 1.04 + 0.03 * bel, wd * 1.03 + 0.06 * bel, wd * 1.03, 2.4, 0, 0,
             0, 0),
            (zc + 0.01 * s, cw * 0.95 + 0.02 * bel, cd * 0.97 + 0.04 * bel, cd * 0.95, 2.3,
             0.006 * mus, 0.004, 0, 0),
            (zc + 0.09 * s, cw, cd, cd * 0.98, 2.2, (0.018 + 0.006 * fem) * mus, 0.010, 0, 0),
            (zc + 0.15 * s, cw * 1.0, cd * 0.96, cd * 0.99, 2.2, 0.012 * mus, 0.012, 0, 0),
            (shz - 0.01 * s, sh * 0.90, cd * 0.82, cd * 0.91, 2.2, 0.003, 0.008, 0.004, 0),
            (shz + 0.035 * s, sh * 0.79, cd * 0.66, cd * 0.80, 2.2, 0, 0.004, 0.008, 0.004),
            (zn + 0.035 * s, nr * 2.0, nr * 1.40, nr * 1.70, 2.2, 0, 0, 0.012, 0.016),
            (zn + 0.055 * s, nr * 1.28, nr * 1.10, nr * 1.22, 2.0, 0, 0, 0.012, 0.030),
        ]

    def torso_ring(self, z, W, F, B, n_exp, pec, blade, yc, dip, phis):
        s = self.s
        c, si = np.cos(phis), np.sin(phis)
        e = 2.0 / n_exp
        xs = W * s * np.sign(si) * np.abs(si) ** e
        ys = np.where(c > 0, -F * s * np.abs(c) ** e, B * s * np.abs(c) ** e)
        ap = np.abs(np.mod(phis + np.pi, 2 * np.pi) - np.pi)
        ys = ys - pec * s * np.exp(-((ap - 0.62) / 0.40) ** 2)
        ys = ys + blade * s * np.exp(-((ap - 2.45) / 0.45) ** 2)
        ys = ys - 0.003 * s * np.exp(-(ap / 0.10) ** 2) + \
            0.004 * s * np.exp(-((ap - np.pi) / 0.12) ** 2)
        ys = ys + yc * s
        zs = z - dip * s * np.maximum(c, 0) ** 2
        return np.stack([xs, ys, zs], 1)

    def torso_rings(self, nseg=30, nrings=22):
        st = A(self.torso_stations())
        d = np.sqrt(np.diff(st[:, 0]) ** 2 + (np.diff(st[:, 1]) * self.s) ** 2)
        kt = np.concatenate([[0], np.cumsum(d)])
        ts = np.linspace(0, kt[-1], nrings)
        prm = geo.interp(kt, st, ts, mono=True)
        phis = np.linspace(0, 2 * np.pi, nseg, endpoint=False)
        return [self.torso_ring(*row, phis) for row in prm]

    def build_torso(self):
        rings = self.torso_rings()
        v, f = geo.loft(rings, None, None)
        f = orient_outward(v, f, A([0, 0, self.lv("chest")]))
        obj = self.add("Torso", v, f, self.m["Jersey"],
                       bones=["hips", "spine", "chest", "neck", "shoulder.L", "shoulder.R",
                              "upper_arm.L", "upper_arm.R"])
        self.torso_obj = obj
        self.torso_bottom = float(A(rings[0])[:, 2].min())
        if getattr(self, "neck_obj", None) is not None:
            # the neck base inside the collar moves with the jersey
            zt = float(A(rings[-1])[:, 2].max())
            s = self.s
            self.neck_obj["share"] = json.dumps(dict(src=obj.name, a=[0, 0, zt - 0.015 * s],
                                                     b=[0, 0, zt + 0.03 * s], u0=0.0, u1=1.0))
        self.collar_ring = A(rings[-1])
        self.surf["torso"] = geo.Surface(obj)
        return obj

    # =====================================================================
    # sleeves / arms
    # =====================================================================
    def arm_axis(self, side):
        return self.j("upper_arm." + side), self.j("forearm." + side), self.j("hand." + side)

    def build_sleeve(self, side):
        s = self.s
        p = self.p
        S, E, W = self.arm_axis(side)
        d = unit(E - S)
        Lua = np.linalg.norm(E - S)
        mus = p["muscle"]
        rd = p["arm_r"] * s * 1.10 * (0.9 + 0.1 * mus)
        S = S + d * 0.014 * s
        rh = p["arm_r"] * s * 1.26
        L = 0.46 * Lua
        fwd = A([0, -1.0, 0])
        U = unit(fwd - d * np.dot(fwd, d))
        V = np.cross(d, U)
        ang = np.linspace(0, 2 * np.pi, 14, endpoint=False)
        ts, rs = [], []
        for a in np.linspace(0, math.pi / 2, 7)[1:]:
            ts.append(-rd * math.cos(a))
            rs.append(rd * math.sin(a))
        for t in np.linspace(0, L, 5)[1:]:
            k = t / L
            ts.append(t)
            rs.append(rd + (rh - rd) * (3 * k * k - 2 * k ** 3))
        ts += [L + 0.004 * s, L + 0.002 * s, L - 0.03 * s]
        rs += [rh * 0.985, rh - 0.007 * s, rh - 0.010 * s]
        rings = []
        for t, r in zip(ts, rs):
            c = S + d * t
            rings.append(c + np.outer(np.cos(ang), U) * r * 1.04 + np.outer(np.sin(ang), V) * r)
        v, f = geo.loft(rings, cap0=S - d * rd, cap1=None)
        f = orient_outward(v, f, S + d * 0.05 * s)
        obj = self.add("Sleeve." + side, v, f, self.m["Jersey"],
                       bones=["chest", "shoulder." + side, "upper_arm." + side])
        if not hasattr(self, "sleeve_obj"):
            self.sleeve_obj, self.sleeve_u = {}, {}
        self.sleeve_obj[side] = obj
        self.sleeve_u[side] = (0.014 * s + L) / Lua      # hem, in upper-arm lengths
        c = S + d * (L - 0.002 * s)
        ring = [c + (U * math.cos(a) * 1.04 + V * math.sin(a)) * (rh + 0.0015 * s)
                for a in np.linspace(0, 2 * np.pi, 20, endpoint=False)]
        pv, pf = geo.tube(ring, 0.0062 * s, nseg=4, closed_path=True, up=d)
        self.add("SleeveTrim." + side, pv, pf, self.m["JerseyTrim"], weights_from=obj)
        return obj

    def arm_profile(self, side, u0, u1, cuff=True, nseg=10, rings=18, grow=1.0, tuck=None):
        """Loft rings along shoulder->elbow->wrist; u in [0, 2] (0 shoulder,
        1 elbow, 2 wrist)."""
        s = self.s
        p = self.p
        S, E, W = self.arm_axis(side)
        ar, fr, wr = p["arm_r"] * s, p["forearm_r"] * s, p["wrist_r"] * s
        mus = p["muscle"]

        def axis(u):
            if u <= 1:
                return S + (E - S) * u
            return E + (W - E) * (u - 1)
        ku = [0.0, 0.30, 0.55, 0.85, 1.0, 1.20, 1.55, 1.86, 2.0]
        krx = [ar * 0.88, ar * 0.98, ar * 1.0, ar * 0.86, fr * 0.96, fr * 1.08, fr * 0.92,
               wr * 1.12, wr * 1.10]
        kry = [ar * 0.90, ar * 1.02, ar * (1.0 + 0.10 * mus), ar * 0.90, fr * 0.92, fr * 1.0,
               fr * 0.86, wr * 1.0, wr * 1.0]
        if cuff:
            us = list(np.linspace(u0, u1 - 0.10, rings - 4)) + list(np.linspace(u1 - 0.07, u1, 4))
        else:
            us = list(np.linspace(u0, u1, rings))
        pts = A([axis(u) for u in us])
        rx = geo.interp(ku, krx, us) * grow
        ry = geo.interp(ku, kry, us) * grow
        if tuck:
            # (u_end, scale): hidden under another sleeve up to u_end - 0.03
            ue, sc = tuck
            g = np.clip((ue - 0.03 - A(us)) / 0.05, 0.0, 1.0)
            rx = rx * (1 - (1 - sc) * g)
            ry = ry * (1 - (1 - sc) * g)
        if cuff:
            for i, u in enumerate(us):
                if u >= u1 - 0.07:
                    rx[i] *= 1.14
                    ry[i] *= 1.14
        T, U, V = geo.transport_frames(pts, (0, -1, 0))
        ang = np.linspace(0, 2 * np.pi, nseg, endpoint=False)
        rr = []
        for i in range(len(us)):
            rr.append(pts[i] + np.outer(np.cos(ang), U[i]) * ry[i] +
                      np.outer(np.sin(ang), V[i]) * rx[i])
        if cuff:
            i = len(us) - 1
            c = pts[i] + T[i] * 0.003 * s
            rr.append(c + np.outer(np.cos(ang), U[i]) * ry[i] * 0.80 +
                      np.outer(np.sin(ang), V[i]) * rx[i] * 0.80)
            rr.append(c - T[i] * 0.02 * s + np.outer(np.cos(ang), U[i]) * ry[i] * 0.72 +
                      np.outer(np.sin(ang), V[i]) * rx[i] * 0.72)
        return rr, pts

    def build_arm(self, side, mat, u0=0.12, u1=2.0, cuff=True, name=None, tuck=None):
        rings, pts = self.arm_profile(side, u0, u1, cuff=cuff, tuck=tuck)
        v, f = geo.loft(rings, None, None)
        f = orient_outward(v, f, pts[len(pts) // 2])
        obj = self.add(name or ("Arm." + side), v, f, mat,
                       bones=["shoulder." + side, "upper_arm." + side, "forearm." + side,
                              "hand." + side])
        if u0 < self.sleeve_u.get(side, 0.0):
            # under the jersey sleeve the arm moves with the sleeve (its
            # weights), blending back to its own just below the hem
            S, E, W = self.arm_axis(side)
            uh = self.sleeve_u[side]
            obj["share"] = json.dumps(dict(src=self.sleeve_obj[side].name, a=list(S), b=list(E),
                                           u0=uh - 0.04, u1=uh + 0.24))
        return obj

    def build_wristband(self, side, mat):
        s = self.s
        wr = self.p["wrist_r"] * s * 1.38
        S, E, W = self.arm_axis(side)
        d = unit(W - E)
        U = unit(A([0, -1.0, 0]) - d * np.dot(A([0, -1.0, 0]), d))
        V = np.cross(d, U)
        ang = np.linspace(0, 2 * np.pi, 16, endpoint=False)
        rr = []
        for t, r in ((-0.075, 0.90), (-0.071, 1.0), (-0.012, 1.0), (-0.008, 0.90)):
            c = W + d * t * s
            rr.append(c + (np.outer(np.cos(ang), U) * 0.95 + np.outer(np.sin(ang), V)) * wr * r)
        v, f = geo.loft(rr, 'flat', 'flat')
        f = orient_outward(v, f, W - d * 0.04 * s)
        return self.add("WristBand." + side, v, f, mat, bones=["forearm." + side, "hand." + side])

    # =====================================================================
    # hands / mitt
    # =====================================================================
    def hand_frame(self, side):
        sk = self.sk
        M = sk.rest["hand." + side]
        f = A(M.to_3x3().col[1])
        n = A(sk.palm_rest[side])
        t = A([0, -1.0, 0])
        t = t - f * np.dot(t, f) - n * np.dot(t, n)
        return self.j("hand." + side), f, n, unit(t)

    def finger(self, pts, r0, r1, nseg=7):
        pts = geo.smooth_polyline(pts, 7)
        d = unit(pts[-1] - pts[-2])
        rad = list(np.linspace(r0, r1, len(pts)))
        pts = list(pts) + [pts[-1] + d * r1 * 0.55]
        rad = rad + [r1 * 0.72]
        return geo.tube(pts, rad, nseg=nseg, cap0=None, cap1=pts[-1] + d * r1 * 0.45)

    def build_hand(self, side, mat):
        k = self.s * self.p["hand_scale"]
        W, f, n, t = self.hand_frame(side)
        rig_ = "hand." + side

        def H(a, b, c):
            return W + f * a * k + n * b * k + t * c * k
        R = np.stack([t, n, f], 1)
        v, fc = superellipsoid(H(0.046, -0.001, 0.0), (0.041 * k, 0.018 * k, 0.046 * k), R,
                               nu=16, nv=10, e1=3.2, e2=2.6)
        fc = orient_outward(v, fc, H(0.046, -0.001, 0.0))
        self.add("Palm." + side, v, fc, mat, rigid=rig_)
        specs = [(0.026, 0.066, 4, 0), (0.009, 0.072, 1, 4), (-0.009, 0.068, -2, 9),
                 (-0.025, 0.055, -6, 15)]
        for cb, ln, spread, extra in specs:
            sp = math.radians(spread)
            dirv = f * math.cos(sp) + t * math.sin(sp)
            base = H(0.078, 0.0, cb)
            pts = [base - dirv * 0.012 * k, base]
            ang = 0.0
            segs = [ln * 0.45, ln * 0.31, ln * 0.24]
            for i, c in enumerate((14 + extra, 26 + extra, 20 + extra * 0.6)):
                ang += math.radians(c)
                dd = dirv * math.cos(ang) + n * math.sin(ang)
                pts.append(pts[-1] + dd * segs[i] * k)
            v, fc = self.finger(pts, 0.0112 * k, 0.0095 * k)
            self.add("Finger." + side, v, fc, mat, rigid=rig_)
        tb = H(0.016, 0.010, 0.024)
        d1 = unit(f * 0.55 + t * 0.62 + n * 0.45)
        d2 = unit(f * 0.85 + t * 0.12 + n * 0.45)
        p1 = tb + d1 * 0.034 * k
        p2 = p1 + d2 * 0.030 * k
        v, fc = self.finger([tb - d1 * 0.01 * k, tb, p1, p2], 0.0135 * k, 0.0112 * k)
        self.add("Thumb." + side, v, fc, mat, rigid=rig_)
        wr = self.p["wrist_r"] * self.s
        v, fc = geo.tube([W - f * 0.03 * k, W, H(0.03, 0, 0)], [wr * 0.95, wr * 1.0, 0.036 * k],
                         nseg=12, cap0=None, cap1=None, up=n, ovals=[0.8, 0.8, 0.55])
        self.add("Wrist." + side, v, fc, mat, rigid=rig_)

    def build_mitt(self, side, catcher=False):
        k = self.s * self.p["hand_scale"] * 0.92
        W, f, n, t = self.hand_frame(side)
        g = self.m["Glove"]
        lace = self.m["Undershirt"]
        rig_ = "hand." + side

        def H(a, b, c):
            return W + f * a * k + n * b * k + t * c * k
        R = np.stack([t, n, f], 1)

        def blob(name, c, r, mat, e1=2.4, e2=2.2, nu=16, nv=10):
            v, fc = superellipsoid(c, r, R, nu=nu, nv=nv, e1=e1, e2=e2)
            fc = orient_outward(v, fc, c)
            return self.add(name, v, fc, mat, rigid=rig_)

        def stall(name, pts, r0, r1, mat=g, nseg=7):
            v, fc = self.finger(pts, r0, r1, nseg=nseg)
            return self.add(name, v, fc, mat, rigid=rig_)

        def lace_line(name, pts, r=0.0062, closed=False):
            pts = geo.smooth_polyline(pts, max(8, len(pts) * 3), closed=closed)
            if closed:
                v, fc = geo.tube(pts, r * k, nseg=6, closed_path=True, up=n)
            else:
                v, fc = geo.tube(pts, r * k, nseg=6, up=n)
            return self.add(name, v, fc, lace, rigid=rig_)
        if catcher:
            blob("Mitt", H(0.11, -0.012, 0.005), (0.125 * k, 0.052 * k, 0.13 * k), g, e1=2.1,
                 e2=2.4, nu=20, nv=12)
            ring = [H(0.11 + 0.112 * math.cos(a), 0.022, 0.005 + 0.112 * math.sin(a))
                    for a in np.linspace(0, 2 * np.pi, 20, endpoint=False)]
            v, fc = geo.tube(ring, 0.032 * k, nseg=8, closed_path=True, up=n)
            self.add("MittRim", v, fc, g, rigid=rig_)
            stall("MittThumb", [H(0.03, 0.0, 0.09), H(0.10, 0.012, 0.13), H(0.17, 0.03, 0.145)],
                  0.036 * k, 0.031 * k)
            for cc in (0.06, 0.02, -0.02, -0.06):
                stall("MittRidge", [H(0.05, -0.05, cc), H(0.14, -0.058, cc * 1.15),
                                    H(0.22, -0.035, cc * 1.3)], 0.018 * k, 0.016 * k)
            ring = [H(0.11 + 0.124 * math.cos(a), 0.046, 0.005 + 0.124 * math.sin(a))
                    for a in np.linspace(0, 2 * np.pi, 20, endpoint=False)]
            v, fc = geo.tube(geo.smooth_polyline(ring, 30, closed=True), 0.0075 * k, nseg=5,
                             closed_path=True, up=n)
            self.add("MittLace", v, fc, lace, rigid=rig_)
            for a in np.linspace(-0.9, 0.9, 5):
                v, fc = geo.tube([H(0.11 + 0.10 * math.cos(a), 0.05, 0.005 + 0.10 * math.sin(a)),
                                  H(0.11 + 0.15 * math.cos(a), 0.0, 0.005 + 0.15 * math.sin(a))],
                                 0.0065 * k, nseg=4, up=n)
                self.add("MittTie", v, fc, lace, rigid=rig_)
            return
        blob("Mitt", H(0.085, -0.010, -0.004), (0.074 * k, 0.030 * k, 0.088 * k), g,
             e1=2.6, e2=2.2)
        tips = []
        for cb, ln in ((0.046, 0.255), (0.016, 0.270), (-0.015, 0.262), (-0.044, 0.240)):
            base = H(0.11, -0.006, cb)
            mid = H(0.11 + (ln - 0.11) * 0.55, 0.004, cb * 1.22)
            tip = H(ln, 0.026, cb * 1.36)
            stall("MittStall", [H(0.07, -0.01, cb), base, mid, tip], 0.0265 * k, 0.0235 * k)
            tips.append(H(ln + 0.016, 0.034, cb * 1.36))
        stall("MittThumb", [H(0.02, -0.006, 0.058), H(0.035, -0.004, 0.064),
                            H(0.115, 0.008, 0.100), H(0.188, 0.030, 0.114)], 0.029 * k, 0.024 * k)
        # smooth leather pocket face over the stall roots
        blob("MittPocket", H(0.150, 0.012, -0.002), (0.074 * k, 0.015 * k, 0.088 * k), g,
             e1=2.8, e2=2.4, nu=14, nv=8)
        v, fc = geo.tube([H(0.040, 0.012, 0.070), H(0.016, 0.020, 0.030),
                          H(0.014, 0.020, -0.030), H(0.040, 0.012, -0.068)],
                         0.021 * k, nseg=10, cap0='pole', cap1='pole', up=f)
        self.add("MittHeel", v, fc, g, rigid=rig_)
        blob("MittWeb", H(0.200, 0.018, 0.090), (0.032 * k, 0.010 * k, 0.064 * k), g,
             e1=2.8, e2=2.6, nu=12, nv=8)
        blob("MittStrap", H(0.022, -0.034, -0.004), (0.070 * k, 0.014 * k, 0.024 * k), g,
             e1=3.0, e2=2.4, nu=14, nv=8)
        blob("MittPatch", H(0.022, -0.047, -0.004), (0.030 * k, 0.004 * k, 0.013 * k), lace,
             e1=3.0, e2=2.4, nu=12, nv=6)
        lace_line("MittLace", [H(0.205, 0.040, 0.116)] + tips)
        for i in range(5):
            a_ = 0.148 + i * 0.024
            v, fc = geo.tube([H(a_, 0.029, 0.058), H(a_ + 0.006, 0.031, 0.088), H(a_ + 0.012, 0.029, 0.118)],
                             0.0058 * k, nseg=4, up=n)
            self.add("MittWebLace", v, fc, lace, rigid=rig_)
        lace_line("MittHeelLace", [H(-0.022, 0.0, 0.058), H(-0.034, 0.0, 0.0),
                                   H(-0.022, 0.0, -0.06)], 0.0058)

    # =====================================================================
    # pants (mirrored cage + Catmull-Clark)
    # =====================================================================
    def build_pants(self, hem_drop=0.165, knee_pants=False):
        s = self.s
        p = self.p
        pw, pd = p["pelvis_w"], p["pelvis_d"]
        zp = self.lv("pelvis")
        hz = self.lv("hip")
        Hj = self.j("thigh.L")
        K = self.j("shin.L")
        Ak = self.j("foot.L")
        tr, kr, cr = p["thigh_r"], p["knee_r"], p["calf_r"]
        bel = p["belly"]
        verts = []
        faces = []
        creases = []

        def half_ring(z, Wd, F, B, n=2.5):
            idx = []
            for k in range(11):
                ph = math.radians(18 * k)
                c, si = math.cos(ph), math.sin(ph)
                e = 2.0 / n
                x = 0.0 if k in (0, 10) else Wd * s * abs(si) ** e
                y = (-F if c > 0 else B) * s * abs(c) ** e
                verts.append((x, y, z))
                idx.append(len(verts) - 1)
            return idx
        R0 = half_ring(zp + 0.064 * s, pw * 1.07 + 0.02 * bel, pd * 1.06 + 0.04 * bel, pd * 1.10)
        R1 = half_ring(zp - 0.015 * s, pw * 1.20 + 0.02 * bel, pd * 1.12 + 0.03 * bel, pd * 1.32)
        R2 = half_ring(hz - 0.055 * s, pw * 1.24, pd * 1.08, pd * 1.26)
        verts.append((0.0, 0.012 * s, hz - 0.125 * s))
        C = len(verts) - 1
        for ra, rb in ((R0, R1), (R1, R2)):
            for k in range(10):
                faces.append((ra[k], ra[k + 1], rb[k + 1], rb[k]))
        thetas = [-50, -15, 15, 40, 65, 90, 115, 140, 165, 195, 228, 270]

        def bone_pt(z):
            if z >= K[2]:
                u = (Hj[2] - z) / (Hj[2] - K[2])
                return Hj + (K - Hj) * u
            u = (K[2] - z) / (K[2] - Ak[2])
            return K + (Ak - K) * u
        ks = K[2]
        stations = [
            (hz - 0.15 * s, 0.020, tr * 1.36, tr * 1.24, tr * 1.36),
            (hz - 0.31 * s, 0.006, tr * 1.20, tr * 1.14, tr * 1.22),
        ]
        if knee_pants:
            hem_drop = 0.025
        else:
            stations += [(ks + 0.02 * s, 0.002, kr * 1.56, kr * 1.62, kr * 1.48),
                         (ks - 0.105 * s, 0.002, cr * 1.62, cr * 1.58, cr * 1.72)]
        hem_z = ks - hem_drop * s
        rh = cr * 1.30 if not knee_pants else kr * 1.45
        stations += [(hem_z, 0.0, rh, rh * 0.97, rh * 1.04),
                     (hem_z + 0.014 * s, 0.0, rh * 0.87, rh * 0.85, rh * 0.89),
                     (hem_z + 0.06 * s, 0.0, rh * 0.80, rh * 0.78, rh * 0.82)]
        rings = [R2[:] + [C]]
        for (z, dx, ro, rf, rb) in stations:
            c = bone_pt(z) + A([dx * s, 0, 0])
            c[2] = z
            ri = min(ro, (c[0] - 0.006 * s) / s)
            idx = []
            for th in thetas:
                a = math.radians(th)
                sx_, cy = math.sin(a), math.cos(a)
                rx = (ro if sx_ > 0 else ri) * s
                ry = (rf if cy > 0 else rb) * s
                verts.append((c[0] + rx * sx_, c[1] - ry * cy, z))
                idx.append(len(verts) - 1)
            rings.append(idx)
        for a, b in zip(rings[:-1], rings[1:]):
            for k in range(12):
                faces.append((a[k], a[(k + 1) % 12], b[(k + 1) % 12], b[k]))
        hem_ring = rings[-3]
        fold = rings[-2]
        for k in range(12):
            creases.append((hem_ring[k], hem_ring[(k + 1) % 12], 1.0))
            creases.append((fold[k], fold[(k + 1) % 12], 0.8))
        faces = orient_outward(verts, faces, A([0.06 * s, 0, hz]))
        obj = self.add("Pants", verts, faces, self.m["Pants"], mirror=True, subsurf=1,
                       creases=creases,
                       bones=["hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R"])
        # lower legs (cuff + inner fold) get the same axial weights as the
        # sock tucked under them (hero.axial_weights), so they cannot separate
        obj["axial"] = json.dumps(dict(kind="pants", u_mask=self.sock_top_u(hem_z, knee_pants)))
        # waistband: moves with the tucked jersey under it (the torso's
        # weights) down to the jersey hem, then blends to its own weights
        zb = self.torso_bottom
        obj["share"] = json.dumps(dict(src=self.torso_obj.name, a=[0, 0, zb], b=[0, 0, zb - 0.07 * s],
                                       u0=-0.15, u1=1.0))
        self.pants_obj = obj
        self.surf["pants"] = geo.Surface(obj)
        self.tuck_torso()
        self.hem_z = hem_z
        self.hem_r = rh * s
        self.knee_pants = knee_pants
        return obj

    def tuck_torso(self):
        """Keep the tucked-in jersey inside the pants: below the waistband the
        torso is pulled in to 1.4 cm (x scale) inside the pant surface (heavy
        bellies and backs used to stick out through the waistband)."""
        s = self.s
        P = geo.verts_of(self.pants_obj)
        zt = float(P[np.abs(P[:, 0]) < 0.6 * self.p["pelvis_w"] * s, 2].max())
        T = geo.verts_of(self.torso_obj)
        surf = self.surf["pants"]
        changed = False
        for i, v in enumerate(T):
            k = 1.0 - min(max((v[2] - (zt - 0.014 * s)) / (0.010 * s), 0.0), 1.0)
            if k <= 0:
                continue
            r = math.hypot(v[0], v[1])
            if r < 1e-6:
                continue
            d = A([v[0] / r, v[1] / r, 0.0])
            loc, nor = surf.ray(A([0, 0, v[2]]), d, 1.0)
            if loc is None:
                continue
            cap = math.hypot(loc[0], loc[1]) - 0.014 * s
            if r > cap:
                rn = r + (cap - r) * k
                T[i, 0], T[i, 1] = d[0] * rn, d[1] * rn
                changed = True
        if changed:
            geo.set_verts(self.torso_obj, T)
            self.torso_obj.data.update()

    def build_pant_stripes(self):
        """JerseyTrim stripe down the outer side of each pant leg."""
        s = self.s
        surf = self.surf["pants"]
        for side, sx in (("L", 1), ("R", -1)):
            Hj = self.j("thigh." + side)
            zs = np.linspace(self.lv("pelvis") + 0.01 * s, self.hem_z + 0.035 * s, 22)
            pts = []
            for z in zs:
                o = A([Hj[0] if z < Hj[2] else 0.0, 0.0, z])
                loc, nor = surf.ray(o + A([sx * 0.5, 0, 0]), A([-sx, 0, 0]), 1.0)
                if loc is not None:
                    pts.append(loc + A([sx, 0, 0]) * 0.001 * s)
            pts = geo.smooth_polyline(pts, 18)
            v, f = geo.tube(pts, 0.0068 * s, nseg=4, up=(0, -1, 0), ovals=[0.4] * 18,
                            cap0='pole', cap1='pole')
            self.add("PantStripe." + side, v, f, self.m["JerseyTrim"],
                     weights_from=self.pants_obj)

    # =====================================================================
    # belt
    # =====================================================================
    @staticmethod
    def rrect(w, h_, r, n=5):
        pts = []
        for cx, cy, a0 in ((w - r, h_ - r, 0), (-w + r, h_ - r, 90), (-w + r, -h_ + r, 180),
                           (w - r, -h_ + r, 270)):
            for k in range(n):
                a = math.radians(a0 + 90 * k / (n - 1))
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        return A(pts)

    def build_belt(self):
        s = self.s
        surf = self.surf["pants"]
        zp = self.lv("pelvis")
        z0, z1 = zp + 0.016 * s, zp + 0.060 * s
        nphi = 36
        phis = np.linspace(0, 2 * np.pi, nphi, endpoint=False)
        prof = [(0.0, -0.002, 0), (0.0, 0.0055, 0), (0.0, 0.0085, 0.003), (1.0, 0.0085, -0.003),
                (1.0, 0.0055, 0), (1.0, -0.002, 0)]
        rings = []
        for fz, out, dz in prof:
            z = z0 + (z1 - z0) * fz + dz * s
            ring = []
            for ph in phis:
                d = A([math.sin(ph), -math.cos(ph), 0.0])
                o = A([0, 0.0, z])
                loc, nor = surf.ray(o, d, 1.0)
                if loc is None:
                    loc = o + d * 0.15 * s
                ring.append(loc + d * out * s)
            rings.append(ring)
        R = A(rings)
        verts = R.reshape(-1, 3)
        faces = []
        for i in range(len(prof) - 1):
            for k in range(nphi):
                a = i * nphi + k
                b = i * nphi + (k + 1) % nphi
                faces.append((a, b, b + nphi, a + nphi))
        faces = orient_outward(verts, faces, A([0, 0, (z0 + z1) / 2]))
        belt = self.add("Belt", verts, faces, self.m["Belt"], weights_from=self.pants_obj)
        bs = geo.Surface(belt)
        c = bs.ray(A([0, -0.5, (z0 + z1) / 2]), A([0, 1.0, 0]), 1.0)[0]
        hw, hh = 0.040 * s, 0.027 * s
        outer = self.rrect(hw, hh, 0.008 * s)
        inner = self.rrect(hw * 0.52, hh * 0.42, 0.004 * s)[::-1]
        v, f = geo.decal(bs, [outer, inner], c, A([1, 0, 0]), A([0, 0, 1]), A([0, -1, 0]),
                         0.0005 * s, 0.006 * s, depth=0.004 * s)
        self.add_decal("Buckle", v, f, self.m["Metal"], weights_from=self.pants_obj)
        for ph in (40, 95, 150, -40, -95, -150):
            a = math.radians(ph)
            d = A([math.sin(a), -math.cos(a), 0.0])
            cc = bs.ray(A([0, 0, (z0 + z1) / 2]) + d * 0.5, -d, 1.0)[0]
            if cc is None:
                continue
            uu = unit(np.cross(A([0, 0, 1.0]), d))
            loop = self.rrect(0.0075 * s, (z1 - z0) * 0.5 + 0.007 * s, 0.003 * s, n=3)
            v, f = geo.decal(bs, [loop], cc, uu, A([0, 0, 1]), d, 0.0005 * s, 0.0035 * s,
                             depth=0.006 * s)
            self.add_decal("BeltLoop", v, f, self.m["Pants"], weights_from=self.pants_obj)
        return belt

    # =====================================================================
    # socks / shoes
    # =====================================================================
    def hem_t(self, side):
        """Pant hem height as a fraction of the shin (knee 0 -> ankle 1)."""
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        return (K[2] - self.hem_z) / (K[2] - Ak[2])

    def sock_top_u(self, hem_z, knee_pants):
        """Sock top (fraction of the shin): tucked well under the cuff, but
        below the knee crease for full-length pants."""
        K = self.j("shin.L")
        Ak = self.j("foot.L")
        lz = K[2] - Ak[2]
        t_hem = (K[2] - hem_z) / lz
        return t_hem - (0.045 if knee_pants else 0.075) * self.s / lz

    def sock_rings(self, side, ts, grow=0.0, nseg=12, cap=False):
        s = self.s
        p = self.p
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        cr, ar = p["calf_r"] * s, p["ankle_r"] * s
        kt = [0.0, 0.12, 0.30, 0.50, 0.70, 0.88, 1.06]
        kside = [cr * 1.0, cr * 1.02, cr * 1.04, cr * 0.92, cr * 0.76, ar * 1.30, ar * 1.40]
        kfr = [cr * 1.0, cr * 0.98, cr * 0.97, cr * 0.88, cr * 0.74, ar * 1.25, ar * 1.45]
        kbk = [cr * 1.02, cr * 1.10, cr * 1.24, cr * 1.04, cr * 0.82, ar * 1.35, ar * 1.50]
        rsd = geo.interp(kt, kside, ts, mono=True)
        rfr = geo.interp(kt, kfr, ts, mono=True)
        rbk = geo.interp(kt, kbk, ts, mono=True)
        if cap:
            # under the cuff the sock stays inside the pant's inner fold (its
            # radius after subdivision ~0.955 x the cage) with a 12 % margin;
            # the calf bulge only starts below the hem
            th = self.hem_t(side)
            g = 1.0 - np.clip((A(ts) - (th - 0.05)) / 0.10, 0.0, 1.0)
            g = g * g * (3 - 2 * g)
            k = 0.955 * 0.88 * self.hem_r
            for r, c in ((rsd, 0.80), (rfr, 0.78), (rbk, 0.82)):
                r[:] = r * (1 - g) + np.minimum(r, c * k) * g
        rsd, rfr, rbk = rsd + grow, rfr + grow, rbk + grow
        d = unit(Ak - K)
        fwd = A([0, -1.0, 0])
        U = unit(fwd - d * np.dot(fwd, d))
        V = np.cross(d, U)
        ang = np.linspace(0, 2 * np.pi, nseg, endpoint=False)
        L = np.linalg.norm(Ak - K)
        rings = []
        for i, t in enumerate(ts):
            c = K + d * L * t
            cy = np.cos(ang)
            ry = np.where(cy > 0, rfr[i], rbk[i])
            rings.append(c + np.outer(cy * ry, U) + np.outer(np.sin(ang) * rsd[i], V))
        return rings

    def build_socks(self, stripes=True):
        s = self.s
        for side in "LR":
            K = self.j("shin." + side)
            Ak = self.j("foot." + side)
            t_top = self.sock_top_u(self.hem_z, self.knee_pants)
            rings = self.sock_rings(side, np.linspace(t_top, 1.06, 13), cap=True)
            v, f = geo.loft(rings, None, None)
            f = orient_outward(v, f, K + (Ak - K) * 0.5)
            sock = self.add("Sock." + side, v, f, self.m["Socks"],
                            bones=["thigh." + side, "shin." + side, "foot." + side])
            sock["axial"] = json.dumps(dict(kind="sock", side=side,
                                            shoe=self.shoe_top_table(side)))
            if not stripes:
                continue
            L = np.linalg.norm(Ak - K)
            for t0 in (0.50, 0.585):
                w = 0.024 * s / L
                ts2 = [t0 - w / 2, t0 - w / 2 + 0.002, t0 + w / 2 - 0.002, t0 + w / 2]
                rr = self.sock_rings(side, ts2, grow=0.0028 * s, cap=True)
                rr[0] = self.sock_rings(side, [ts2[0]], grow=-0.001 * s, cap=True)[0]
                rr[-1] = self.sock_rings(side, [ts2[-1]], grow=-0.001 * s, cap=True)[0]
                v, f = geo.loft(rr, None, None)
                f = orient_outward(v, f, K + (Ak - K) * t0)
                self.add("SockStripe." + side, v, f, self.m["JerseyTrim"], weights_from=sock)

    SHOE = [  # y (back +), half width, top height (units of s*foot_scale)
        (0.088, 0.020, 0.072),
        (0.078, 0.036, 0.102),
        (0.054, 0.046, 0.122),
        (0.012, 0.050, 0.124),
        (-0.038, 0.054, 0.100),
        (-0.098, 0.058, 0.078),
        (-0.158, 0.055, 0.063),
        (-0.204, 0.046, 0.054),
        (-0.232, 0.031, 0.046),
        (-0.247, 0.013, 0.040),
    ]

    def shoe_top_table(self, side, chunky=1.0):
        """[x0, fs, chunky, [(y, half width, top)...]] of the shoe upper (absolute
        y), for the sock weights: the part of the sock inside the shoe follows
        the foot exactly like the shoe."""
        fs = self.s * self.p["foot_scale"]
        Ak = self.j("foot." + side)
        return [float(Ak[0]), float(Ak[1]), float(fs), chunky,
                [[float(r[0]), float(r[1]), float(r[2])] for r in self.SHOE]]

    def shoe_outline(self, side, margin=0.006, n=40):
        fs = self.s * self.p["foot_scale"]
        Ak = self.j("foot." + side)
        ys = A([r[0] for r in self.SHOE])
        ws = A([r[1] for r in self.SHOE])
        yy = np.linspace(ys[0] + 0.004, ys[-1] - 0.006, n // 2)
        ww = np.interp(-yy, -ys, ws) + margin
        mid = (yy[0] + yy[-1]) / 2
        half = (yy[0] - yy[-1]) / 2
        ends = np.clip(1 - ((yy - mid) / half) ** 8, 0, 1) ** 0.5
        ww = ww * (0.3 + 0.7 * ends)
        right = [(Ak[0] + w * fs, Ak[1] + y * fs) for y, w in zip(yy, ww)]
        left = [(Ak[0] - w * fs, Ak[1] + y * fs) for y, w in zip(yy[::-1], ww[::-1])]
        return A(right + left)

    def build_shoes(self, chunky=1.0):
        s = self.s
        fs = s * self.p["foot_scale"]
        for side in "LR":
            Ak = self.j("foot." + side)
            # foot + toe only: the heel must follow the foot when it pitches
            bones = ["foot." + side, "toe." + side]
            ov = {"toe." + side: 1.5}
            ol = self.shoe_outline(side, 0.008, n=28)
            cxy = ol.mean(0)
            rings = []
            for z, ins in ((0.0, 0.004), (0.006, 0.0), (0.026, 0.0), (0.032, 0.004)):
                pts = []
                for (x, y) in ol:
                    d = A([x, y]) - cxy
                    dn = d / max(np.linalg.norm(d), 1e-9)
                    q = A([x, y]) - dn * ins * fs
                    pts.append((q[0], q[1], z * fs))
                rings.append(pts)
            v, f = geo.loft(rings, 'flat', 'flat')
            f = orient_outward(v, f, A([cxy[0], cxy[1], 0.016 * fs]))
            self.add("Sole." + side, v, f, self.m["Sole"], bones=bones, overrides=ov)
            ys = A([r[0] for r in self.SHOE])
            yy = np.linspace(ys[0], ys[-1], 13)
            ws = geo.interp(-ys, [r[1] for r in self.SHOE], -yy, mono=True)
            hs = geo.interp(-ys, [r[2] for r in self.SHOE], -yy, mono=True)
            z0 = 0.022
            ang = np.linspace(0, 2 * np.pi, 12, endpoint=False)
            rings = []
            for y, w, ht in zip(yy, ws, hs):
                zc = (z0 + ht) / 2
                hz = (ht - z0) / 2
                pts = []
                for a in ang:
                    c, si = math.cos(a), math.sin(a)
                    e = 2.0 / (2.4 if si > 0 else 6.0)
                    x = w * chunky * np.sign(c) * abs(c) ** e
                    z = zc + hz * np.sign(si) * abs(si) ** e
                    pts.append((Ak[0] + x * fs, Ak[1] + y * fs, z * fs))
                rings.append(pts)
            heel = A([Ak[0], Ak[1] + (ys[0] + 0.006) * fs, 0.05 * fs])
            toe = A([Ak[0], Ak[1] + (ys[-1] - 0.005) * fs, 0.032 * fs])
            v, f = geo.loft(rings, heel, toe)
            f = orient_outward(v, f, A([Ak[0], Ak[1] - 0.05 * fs, 0.05 * fs]))
            up = self.add("Shoe." + side, v, f, self.m["Shoes"], bones=bones, overrides=ov)
            us = geo.Surface(up)
            # laces (white) on the instep
            nrm = unit(A([0, -0.35, 1.0]))
            uu = A([1.0, 0, 0])
            vv_ = unit(np.cross(nrm, uu))
            if vv_[1] > 0:
                vv_ = -vv_          # +v points toward the toe
            c = us.ray(A([Ak[0], Ak[1] - 0.062 * fs, 0.5]), A([0, 0, -1.0]), 1.0)[0]
            loop = []
            for t in np.linspace(-1, 1, 6):
                loop.append((-0.020 * fs * (1 - 0.18 * (t + 1) / 2), t * 0.052 * fs))
            loop += [(-x, y) for x, y in loop[::-1]]
            vv, ff = geo.decal(us, [A(loop)], c, uu, vv_, nrm, 0.0008 * fs, 0.0025 * fs,
                               depth=0.004 * fs, subdiv=1)
            self.add_decal("Laces." + side, vv, ff, self.m["Sole"], weights_from=up)
            # accent swoosh on both sides
            for so in (1, -1):
                poly = A([(-0.075, 0.000), (-0.030, -0.012), (0.020, -0.014), (0.070, -0.006),
                          (0.112, 0.010), (0.060, 0.004), (0.010, 0.003), (-0.035, 0.013),
                          (-0.070, 0.024)]) * fs
                nrm = A([so, 0, 0.0])
                hitc = us.ray(A([Ak[0] + so * 0.3, Ak[1] - 0.03 * fs, 0.055 * fs]), -nrm, 1.0)[0]
                vv, ff = geo.decal(us, [poly], hitc, A([0, -1.0, 0]), A([0, 0, 1.0]), nrm,
                                   0.0008 * fs, 0.0025 * fs, depth=0.004 * fs)
                self.add_decal("ShoeStripe." + side, vv, ff, self.m["Undershirt"], weights_from=up)

    # =====================================================================
    # jersey details
    # =====================================================================
    def build_collar(self):
        s = self.s
        ring = self.collar_ring
        c = ring.mean(0)
        pts = [c + (p - c) * 1.0 + A([0, 0, 0.002 * s]) + unit(p - c) * 0.002 * s for p in ring]
        v, f = geo.tube(pts[::2], 0.0080 * s, nseg=5, closed_path=True, up=(0, 0, 1))
        return self.add("Collar", v, f, self.m["JerseyTrim"], weights_from=self.torso_obj)

    def build_vneck(self, placket=True):
        s = self.s
        surf = self.surf["torso"]
        zn = self.lv("neck")
        zp = self.lv("pelvis")
        top = zn + 0.036 * s
        vw = 0.058 * s
        vb = zn - 0.082 * s
        loop = A([(-vw, top), (0.0, vb), (vw, top)])
        c = surf.ray(A([0, -0.6, (top + vb) / 2]), A([0, 1.0, 0]), 1.0)[0]
        c[0] = 0.0
        # V insert (undershirt seen through the V)
        lp = A([(x, z - c[2]) for x, z in [(-vw * 1.05, top + 0.01 * s), (0.0, vb - 0.004 * s),
                                           (vw * 1.05, top + 0.01 * s)]])
        v, f = geo.decal(surf, [lp], c, A([1, 0, 0]), A([0, 0, 1]), A([0, -1, 0]), 0.0008 * s,
                         0.0012 * s, depth=0.004 * s, subdiv=2)
        self.add_decal("VInsert", v, f, self.m["Undershirt"], weights_from=self.torso_obj)
        # piping along the V and down the placket
        pts = []
        for (x0, z0), (x1, z1) in ((loop[0], loop[1]), (loop[1], loop[2])):
            for t in np.linspace(0, 1, 9)[:-1] if x0 < 0 else np.linspace(0, 1, 9):
                x = x0 + (x1 - x0) * t
                z = z0 + (z1 - z0) * t
                hit = surf.hit(A([x, -0.3, z]), A([0, -1.0, 0]))[0]
                pts.append(hit + A([0, -0.0035 * s, 0]))
        v, f = geo.tube(pts, 0.0058 * s, nseg=6, up=(0, -1, 0))
        self.add("VTrim", v, f, self.m["JerseyTrim"], weights_from=self.torso_obj)
        if placket:
            pts = []
            for z in np.linspace(vb, zp + 0.03 * s, 14):
                hit = surf.hit(A([0.0, -0.3, z]), A([0, -1.0, 0]))[0]
                pts.append(hit + A([0, -0.003 * s, 0]))
            v, f = geo.tube(pts, 0.0052 * s, nseg=6, up=(1, 0, 0), ovals=[0.6] * len(pts))
            self.add("PlacketTrim", v, f, self.m["JerseyTrim"], weights_from=self.torso_obj)

    def glyph_loops(self, text, height, dilate=0.0):
        import bpy

        def mk(off):
            cu = bpy.data.curves.new("glyph_tmp", 'FONT')
            cu.body = text
            cu.font = bpy.data.fonts.load(self.font, check_existing=True)
            cu.size = 1.0
            cu.resolution_u = 4
            cu.fill_mode = 'BOTH'
            cu.align_x = 'CENTER'
            cu.space_character = 1.12
            cu.offset = off
            ob = bpy.data.objects.new("glyph_tmp", cu)
            bpy.context.scene.collection.objects.link(ob)
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
            bpy.data.objects.remove(ob)
            bpy.data.curves.remove(cu)
            loops = geo.boundary_loops(me)
            bpy.data.meshes.remove(me)
            return loops
        base = mk(0.0)
        allp = np.concatenate(base, 0)
        lo, hi = allp.min(0), allp.max(0)
        c = (lo + hi) / 2
        sc = height / (hi[1] - lo[1])
        loops = mk(dilate / sc) if dilate else base
        return [geo.simplify_loop((l - c) * sc, 0.009 * height) for l in loops]

    def build_numbers(self, front=True, back_h=0.155, front_h=0.066):
        s = self.s
        surf = self.surf["torso"]
        zc = self.lv("chest")
        txt = str(self.cfg["number"])
        jobs = [("Back", back_h, A([0, 0.5, zc + 0.085 * s]), A([-1.0, 0, 0]), A([0, 1.0, 0]))]
        if front:
            jobs.append(("Front", front_h, A([0.088 * s, -0.5, zc + 0.125 * s]), A([1.0, 0, 0]),
                         unit(A([0.28, -1.0, 0.08]))))
        for name, ht, o, u, n in jobs:
            sub = 1 if name == "Back" else 0
            c = surf.ray(o, -unit(A([n[0], n[1], 0])), 1.0)[0]
            u = unit(u - n * np.dot(u, n))
            v = unit(np.cross(n, u))
            if v[2] < 0:
                v = -v
            loops = self.glyph_loops(txt, ht * s)
            out = geo.dilate_loops(loops, 0.085 * ht * s)
            vv, ff = geo.decal(surf, out, c, u, v, n, 0.0010 * s, 0.0016 * s, depth=0.004 * s,
                               subdiv=sub)
            self.add_decal("Number%sOutline" % name, vv, ff, self.m["NumberOutline"],
                     weights_from=self.torso_obj)
            # fill raised well above the outline: their flat triangles sag
            # differently on round backs (Bruno), and the outline must never
            # show through the fill
            vv, ff = geo.decal(surf, loops, c, u, v, n, 0.0040 * s, 0.0014 * s, depth=0.006 * s,
                               subdiv=sub)
            self.add_decal("Number" + name, vv, ff, self.m["Number"], weights_from=self.torso_obj)
