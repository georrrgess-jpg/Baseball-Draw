"""Procedural body (torso/jersey, arms, hands, pants, socks, shoes, belt)
built as SDF sculpts around the rest skeleton (A-pose)."""
import math
import numpy as np
from mathutils import Vector

import sdf
import meshutil as mu


def A(v):
    return np.array(v, dtype=np.float64)


def frame_np(y_dir, z_hint):
    return sdf.frame_from(A(y_dir), A(z_hint))


def oriented_ellipsoid(c, along, r_side, r_front, r_along, front=(0, -1, 0)):
    """Ellipsoid whose local Y follows ``along``."""
    R = frame_np(along, front)
    return sdf.ellipsoid(A(c), (r_side, r_along, r_front), R)


class BodyBuilder:
    def __init__(self, sk, mats, cfg):
        self.sk = sk
        self.p = sk.p
        self.s = sk.s
        self.m = mats
        self.cfg = cfg
        self.shapes = {}

    # handy accessors ---------------------------------------------------
    def j(self, name, tail=False):
        return A(self.sk.tails[name] if tail else self.sk.heads[name])

    def r(self, key, mul=1.0):
        return self.p[key] * self.s * mul

    def lv(self, key):
        return self.sk.levels[key]

    # ------------------------------------------------------------------
    def torso_sdf(self, with_sleeves=True, extra=0.0):
        """Jersey torso (with short sleeves)."""
        s = self.s
        p = self.p
        cfg = self.cfg
        cw, cd = p["chest_w"] * s + extra, p["chest_d"] * s + extra
        ww, wd = p["waist_w"] * s + extra, p["waist_d"] * s + extra
        zc = self.lv("chest")
        zs = self.lv("spine")
        zp = self.lv("pelvis")
        zn = self.lv("neck")
        mus = p["muscle"]
        belly = p["belly"]
        base = sdf.ellipsoid([0, 0.008 * s, zc + 0.11 * s],
                             [cw, cd, 0.175 * s])
        parts = []
        # pecs
        for sx in (1, -1):
            parts.append((0.06 * s, sdf.ellipsoid(
                [sx * 0.075 * s, -0.045 * s - (cd - 0.125 * s) * 0.6, zc + 0.12 * s],
                [0.085 * s * mus, 0.07 * s, 0.075 * s])))
        # upper back / lats
        parts.append((0.08 * s, sdf.ellipsoid([0, 0.03 * s, zc + 0.10 * s],
                                              [cw * 1.02, cd * 0.85, 0.15 * s])))
        # abdomen / waist
        parts.append((0.10 * s, sdf.ellipsoid(
            [0, -0.005 * s - belly * 0.03 * s, zs + 0.03 * s],
            [ww + belly * 0.03 * s, wd + belly * 0.05 * s, 0.16 * s])))
        parts.append((0.08 * s, sdf.ellipsoid([0, 0.0, zp + 0.01 * s],
                                              [ww * 1.02 + belly * 0.02 * s,
                                               wd * 1.0 + belly * 0.03 * s,
                                               0.11 * s])))
        if belly > 0:
            parts.append((0.10 * s, sdf.ellipsoid(
                [0, -wd * 0.4 - belly * 0.03 * s, zs + 0.0 * s],
                [ww * 0.9, wd * 0.8 + belly * 0.04 * s, 0.13 * s])))
        # trapezius / shoulder line
        for side, sx in (("L", 1), ("R", -1)):
            S = self.j("upper_arm." + side)
            parts.append((0.07 * s, sdf.round_cone(
                [sx * 0.06 * s, 0.035 * s, zn - 0.07 * s],
                S + A([-sx * 0.03 * s, 0.008 * s, -0.005 * s]),
                0.048 * s * (0.9 + 0.1 * mus), 0.056 * s * mus + extra)))
            parts.append((0.05 * s, sdf.sphere(S + A([sx * 0.002 * s, 0, -0.006 * s]),
                                               0.057 * s * mus + extra)))
            if with_sleeves:
                E = self.j("forearm." + side)
                d = (E - S) / np.linalg.norm(E - S)
                L = cfg.get("sleeve_len", 0.15) * s
                rs = self.sleeve_radius(side)
                parts.append((0.04 * s, sdf.round_cone(
                    S + d * 0.01 * s, S + d * L, rs + extra, rs * 0.97 + extra)))
        shape = sdf.blend(base, *parts)
        return shape

    def sleeve_radius(self, side):
        """Sleeve radius = max arm radius over the sleeve span + clearance."""
        key = "sleeve_r_" + side
        if key in self.shapes:
            return self.shapes[key]
        s = self.s
        S = self.j("upper_arm." + side)
        E = self.j("forearm." + side)
        d = (E - S) / np.linalg.norm(E - S)
        L = self.cfg.get("sleeve_len", 0.15) * s
        arm = self.arm_sdf(side, upper=True, lower=False)
        R = frame_np(d, [0, -1, 0])
        u, w = R[:, 0], R[:, 2]
        rmax = 0.0
        rs_ = np.linspace(0.0, 0.2 * s, 200)
        for k in np.linspace(0.35, 1.0, 6):
            c = S + d * L * k
            for a in np.linspace(0, 2 * np.pi, 16, endpoint=False):
                dirv = u * np.cos(a) + w * np.sin(a)
                P = c + rs_[:, None] * dirv
                v = arm(P)
                idx = np.argmax(v > 0)
                rmax = max(rmax, rs_[idx])
        r = rmax + self.cfg.get("sleeve_gap", 0.011) * s
        self.shapes[key] = r
        return r

    def sleeve_end(self, side):
        S = self.j("upper_arm." + side)
        E = self.j("forearm." + side)
        d = (E - S) / np.linalg.norm(E - S)
        L = self.cfg.get("sleeve_len", 0.15) * self.s
        rs = self.sleeve_radius(side)
        return S + d * L, d, rs * 0.97

    def build_torso(self, mat, tris=2200, name="Torso"):
        s = self.s
        shape = self.torso_sdf()
        cfg = self.cfg
        cut = []
        zn = self.lv("neck")
        # neck opening / V-neck notch
        nr = self.p["neck_r"] * s
        cut.append(sdf.round_cone([0, 0.01 * s, zn - 0.03 * s],
                                  [0, 0.02 * s, zn + 0.2 * s], nr * 1.05, nr * 1.1))
        if cfg.get("vneck", True):
            v = self.vneck_sdf()
            cut.append(v)
        # bottom (tucked into pants)
        shape = sdf.subtract(shape, *cut, k=0.006 * s)
        shape = sdf.intersect(shape, sdf.halfspace([0, 0, self.lv("pelvis") - 0.06 * s],
                                                   [0, 0, -1]))
        self.shapes["torso"] = shape
        bones = ["hips", "spine", "chest", "neck", "shoulder.L", "shoulder.R",
                 "upper_arm.L", "upper_arm.R"]
        return mu.sdf_part(name, shape, mat, 0.0075 * s, tris, bones=bones, sym=True,
                           extra={"weight_overrides": {"upper_arm.L": 1.7, "upper_arm.R": 1.7}})

    def vneck_sdf(self):
        s = self.s
        zn = self.lv("neck")
        depth = self.cfg.get("vneck_depth", 0.09) * s
        # wedge = intersection of two slanted half spaces in front
        top = zn + 0.03 * s
        bot = top - depth - 0.04 * s
        w = 0.055 * s
        hs1 = sdf.halfspace([w, 0, top], [1.0, 0, -(w / (top - bot))])
        hs2 = sdf.halfspace([-w, 0, top], [-1.0, 0, -(w / (top - bot))])
        front = sdf.halfspace([0, -0.04 * s, 0], [0, 1, 0])
        wedge = sdf.intersect(sdf.intersect(hs1, hs2), front)
        wedge = sdf.intersect(wedge, sdf.halfspace([0, 0, bot], [0, 0, -1]))
        wedge.bbox = (A([-0.3, -0.4, bot - 0.1]), A([0.3, 0.1, top + 0.2]))
        return wedge

    def build_collar_trim(self, mat, tris=500):
        """Piping along the V-neck edge (edge band of torso x notch)."""
        s = self.s
        torso = self.torso_sdf(with_sleeves=False)
        v = self.vneck_sdf()
        zn = self.lv("neck")
        nr = self.p["neck_r"] * s
        ring = sdf.round_cone([0, 0.01 * s, zn - 0.03 * s],
                              [0, 0.02 * s, zn + 0.2 * s], nr * 1.05, nr * 1.1)
        notch = sdf.union(v, ring)
        t = 0.010 * s
        band = sdf.intersect(sdf.shell(sdf.offset(torso, 0.0005 * s), 0.009 * s),
                             sdf.shell(notch, 0.016 * s))
        band = sdf.intersect(band, sdf.halfspace([0, 0, zn - 0.16 * s], [0, 0, -1]))
        band.bbox = (A([-0.16 * s, -0.2 * s, zn - 0.17 * s]),
                     A([0.16 * s, 0.15 * s, zn + 0.08 * s]))
        return mu.sdf_part("CollarTrim", band, mat, 0.004 * s, tris,
                           bones=["chest", "neck", "spine"], sym=True)

    def build_undershirt_collar(self, mat, tris=300):
        s = self.s
        zn = self.lv("neck")
        nr = self.p["neck_r"] * s
        sh = sdf.round_cone([0, 0.0, zn - 0.13 * s], [0, 0.012 * s, zn + 0.0 * s],
                            nr * 1.32, nr * 1.13)
        sh = sdf.intersect(sh, sdf.halfspace([0, 0, zn + 0.0 * s], [0, 0, 1]))
        return mu.sdf_part("UndershirtCollar", sh, mat, 0.005 * s, tris,
                           bones=["chest", "neck"], sym=True)

    def build_placket(self, mat_trim, mat_button, tris=300):
        s = self.s
        torso = self.torso_sdf(with_sleeves=False)
        zn = self.lv("neck")
        depth = self.cfg.get("vneck_depth", 0.09) * s
        top = zn + 0.03 * s - depth - 0.04 * s
        bot = self.lv("pelvis") - 0.01 * s
        strip = sdf.box([0, -0.2 * s, (top + bot) / 2],
                        [0.009 * s, 0.2 * s, (top - bot) / 2])
        band = sdf.intersect(sdf.shell(sdf.offset(torso, 0.0015 * s), 0.004 * s), strip)
        band = sdf.intersect(band, sdf.halfspace([0, 0, 0], [0, 1, 0]))
        band.bbox = (A([-0.03 * s, -0.25 * s, bot - 0.01]),
                     A([0.03 * s, 0.0, top + 0.01]))
        parts = [mu.sdf_part("Placket", band, mat_trim, 0.0035 * s, tris,
                             bones=["hips", "spine", "chest"], sym=True)]
        # buttons: find surface y at each height by marching
        n_b = 4
        for i in range(n_b):
            z = top - 0.02 * s - i * (top - bot - 0.06 * s) / (n_b - 1)
            y = self._surface_y(torso, 0.0, z) - 0.004 * s
            parts.append(mu.uv_sphere("Button%d" % i, (0, y, z), 0.0075 * s,
                                      mat_button, seg=8, rings=4,
                                      scale=(1, 0.45, 1),
                                      bones=["spine", "chest"]))
        return parts

    def _surface_y(self, shape, x, z, front=True):
        ys = np.linspace(-0.5 * self.s, 0.0, 400) if front else np.linspace(0.5 * self.s, 0, 400)
        P = np.stack([np.full_like(ys, x), ys, np.full_like(ys, z)], 1)
        d = shape(P)
        idx = np.argmax(d < 0)
        return ys[idx]

    def build_sleeve_trim(self, mat, tris=160):
        out = []
        for side in ("L", "R"):
            c, d, rs = self.sleeve_end(side)
            R = frame_np(d, [0, -1, 0])
            # torus axis along d: local Z of torus = arm dir
            M = np.stack([R[:, 0], R[:, 2], R[:, 1]], 1)
            tor = sdf.torus(c - d * 0.006 * self.s, rs * 0.985, 0.0085 * self.s, M)
            out.append(mu.sdf_part("SleeveTrim." + side, tor, mat, 0.0035 * self.s,
                                   tris, bones=["upper_arm." + side]))
        return out

    # ------------------------------------------------------------------
    def arm_sdf(self, side, upper=True, lower=True, extra=0.0):
        s = self.s
        p = self.p
        mus = 1.0 + 0.45 * (p["muscle"] - 1.0)
        S = self.j("upper_arm." + side)
        E = self.j("forearm." + side)
        W = self.j("hand." + side)
        sx = 1 if side == "L" else -1
        d1 = (E - S) / np.linalg.norm(E - S)
        d2 = (W - E) / np.linalg.norm(W - E)
        ar = p["arm_r"] * s + extra
        fr = p["forearm_r"] * s + extra
        wr = p["wrist_r"] * s + extra
        shapes = []
        if upper:
            base = sdf.round_cone(S + d1 * 0.02 * s, E, ar, fr * 0.95)
            bic = oriented_ellipsoid(S + (E - S) * 0.5 + A([0, -0.012 * s, 0]), d1,
                                     ar * 0.85 * mus, ar * 0.9 * mus,
                                     0.09 * s)
            tri = oriented_ellipsoid(S + (E - S) * 0.45 + A([0, 0.014 * s, 0]), d1,
                                     ar * 0.85 * mus, ar * 0.8 * mus, 0.09 * s)
            shapes.append(sdf.blend(base, 0.03 * s, bic, tri))
        if lower:
            base = sdf.round_cone(E, W, fr, wr)
            fm = oriented_ellipsoid(E + (W - E) * 0.28 + A([sx * 0.006 * s, -0.004 * s, 0]),
                                    d2, fr * 1.0 * mus, fr * 0.9 * mus, 0.08 * s)
            shapes.append(sdf.blend(base, 0.03 * s, fm,
                                    sdf.sphere(E, fr * 0.95)))
        if len(shapes) == 2:
            return sdf.smooth_union(0.02 * s, *shapes)
        return shapes[0]

    def build_arm(self, side, mat, tris=700, upper=True, lower=True, name=None,
                  extra=0.0):
        sh = self.arm_sdf(side, upper, lower, extra)
        # same bone set + overrides as the jersey sleeve so the arm stays inside it
        bones = ["chest", "shoulder." + side, "upper_arm." + side, "forearm." + side,
                 "hand." + side]
        if not upper:
            bones = ["upper_arm." + side, "forearm." + side, "hand." + side]
        return mu.sdf_part(name or ("Arm." + side), sh, mat, 0.0055 * self.s, tris,
                           bones=bones,
                           extra={"weight_overrides": {"upper_arm." + side: 1.7}})

    def build_wrist_band(self, side, mat, width=0.05, tris=200, extra=0.006):
        s = self.s
        E = self.j("forearm." + side)
        W = self.j("hand." + side)
        d = (W - E) / np.linalg.norm(W - E)
        arm = self.arm_sdf(side, upper=False, lower=True)
        slab = sdf.round_cone(W - d * (width + 0.005) * s, W - d * 0.005 * s, 0.2 * s, 0.2 * s)
        slab = sdf.intersect(slab, sdf.halfspace(W - d * 0.005 * s, d))
        band = sdf.intersect(sdf.offset(arm, extra * s), slab, k=0.004 * s)
        band.bbox = (W - 0.12 * s, W + 0.12 * s)
        return mu.sdf_part("WristBand." + side, band, mat, 0.004 * s, tris,
                           bones=["forearm." + side, "hand." + side])

    # ------------------------------------------------------------------
    def hand_frame(self, side):
        sk = self.sk
        M = sk.rest["hand." + side]
        f = A(M.to_3x3().col[1])
        n = A(sk.palm_rest[side])
        t = A([0, -1, 0])
        t = t - f * np.dot(t, f) - n * np.dot(t, n)
        t /= np.linalg.norm(t)
        return self.j("hand." + side), f, n, t

    def hand_sdf(self, side, curl=1.0, fist=False, mitten=False):
        s = self.s * self.p["hand_scale"]
        W, f, n, t = self.hand_frame(side)

        def H(a, b, c):  # along fingers, toward palm normal, toward thumb
            return W + f * a * s + n * b * s + t * c * s
        palm = sdf.box(H(0.048, -0.002, 0.0), [0.042 * s, 0.017 * s, 0.047 * s],
                       rot=np.stack([t, n, f], 1), rnd=0.013 * s)
        # re-map box local axes: rot columns map local x->t, y->n, z->f
        parts = [sdf.ellipsoid(H(0.02, 0.004, 0.012), [0.03 * s, 0.026 * s, 0.022 * s],
                               np.stack([t, f, n], 1))]  # thumb pad
        fingers = []
        specs = [(0.031, 0.072, 0.0102, 5), (0.010, 0.080, 0.0108, 1.5),
                 (-0.011, 0.075, 0.0104, -1.5), (-0.030, 0.061, 0.0094, -5)]
        if mitten:
            m = sdf.round_cone(H(0.075, 0.0, 0.0), H(0.135, 0.02 * curl, 0.0),
                               0.036 * s, 0.03 * s)
            m2 = sdf.box(H(0.105, 0.004, 0.0), [0.04 * s, 0.017 * s, 0.035 * s],
                         rot=np.stack([t, n, f], 1), rnd=0.014 * s)
            fingers.append(sdf.smooth_union(0.02 * s, m, m2))
        else:
            for (off, ln, rad, spread) in specs:
                a = 0.088
                base = H(a, 0.0, off)
                sp = math.radians(spread)
                dirv = f * math.cos(sp) + t * math.sin(sp)
                c1 = math.radians((25 if not fist else 80) * curl)
                c2 = math.radians((30 if not fist else 95) * curl)
                c3 = math.radians((25 if not fist else 70) * curl)
                seg = [ln * 0.45, ln * 0.32, ln * 0.28]
                pts = [base]
                ang = 0.0
                for k, c in enumerate((c1, c2, c3)):
                    ang += c
                    dd = dirv * math.cos(ang) + n * math.sin(ang)
                    pts.append(pts[-1] + dd * seg[k] * s)
                rads = [rad * s * 1.05, rad * s, rad * s * 0.95, rad * s * 0.86]
                fingers.append(sdf.polyline_tube(pts, rads))
        # thumb
        tb = H(0.022, 0.012, 0.030)
        td = (f * 0.70 + t * 0.50 + n * 0.50)
        td /= np.linalg.norm(td)
        td2 = (f * 0.75 + t * 0.0 + n * (0.65 if not fist else 0.9))
        td2 /= np.linalg.norm(td2)
        p1 = tb + td * 0.040 * s
        p2 = p1 + td2 * 0.034 * s
        thumb = sdf.polyline_tube([tb, p1, p2], [0.0135 * s, 0.0125 * s, 0.0105 * s])
        wrist = sdf.round_cone(W - f * 0.03 * s, W + f * 0.02 * s,
                               self.p["wrist_r"] * self.s * 0.95, 0.03 * s)
        shape = sdf.blend(palm, (0.012 * s, parts[0]), (0.008 * s, thumb),
                          (0.02 * s, wrist))
        shape = sdf.blend(shape, *[(0.006 * s, fg) for fg in fingers])
        return shape

    def build_hand(self, side, mat, tris=900, name=None, **kw):
        sh = self.hand_sdf(side, **kw)
        return mu.sdf_part(name or ("Hand." + side), sh, mat, 0.0024 * self.s, tris,
                           rigid="hand." + side)

    # ------------------------------------------------------------------
    def pants_sdf(self, extra=0.0, full=False):
        s = self.s
        p = self.p
        zp = self.lv("pelvis")
        pw, pd = p["pelvis_w"] * s + extra, p["pelvis_d"] * s + extra
        base = sdf.ellipsoid([0, 0.005 * s, zp - 0.025 * s], [pw, pd, 0.105 * s])
        parts = []
        parts.append((0.06 * s, sdf.ellipsoid([0, -0.0, zp + 0.035 * s],
                                              [pw * 0.93, pd * 0.92, 0.07 * s])))
        for sx in (1, -1):
            parts.append((0.05 * s, sdf.ellipsoid([sx * 0.065 * s, 0.045 * s, zp - 0.09 * s],
                                                  [0.085 * s, 0.075 * s, 0.085 * s])))
        legs = []
        loose = self.cfg.get("pants_loose", 0.012) * s + extra
        for side, sx in (("L", 1), ("R", -1)):
            H = self.j("thigh." + side)
            K = self.j("shin." + side)
            Ak = self.j("foot." + side)
            tr = p["thigh_r"] * s + loose
            kr = p["knee_r"] * s + loose
            th = sdf.round_cone(H + A([sx * 0.008 * s, 0, 0.02 * s]), K, tr, kr)
            quad = oriented_ellipsoid((H * 0.55 + K * 0.45) + A([0, -0.018 * s, 0]),
                                      K - H, tr * 0.92, tr * 0.85, 0.16 * s)
            knee = sdf.sphere(K + A([0, -0.005 * s, 0]), kr * 1.02)
            hem_z = self.cfg.get("pants_hem", 0.40) * s if not full else Ak[2] + 0.04 * s
            Lo = K + (Ak - K) * ((K[2] - hem_z) / (K[2] - Ak[2]))
            cr = p["calf_r"] * s + loose * 1.2
            low = sdf.round_cone(K, Lo + A([0, 0.0, -0.02 * s]), kr, cr * 1.04)
            blouse = oriented_ellipsoid(Lo + A([0, 0.004 * s, 0.03 * s]), K - Ak,
                                        cr * 1.12, cr * 1.15, 0.055 * s)
            leg = sdf.blend(th, (0.05 * s, quad), (0.03 * s, knee), (0.03 * s, low),
                            (0.03 * s, blouse))
            leg = sdf.intersect(leg, sdf.halfspace([0, 0, hem_z], [0, 0, -1]))
            legs.append(leg)
        shape = sdf.blend(base, *parts)
        shape = sdf.blend(shape, *[(0.03 * s, l) for l in legs])
        return shape

    def build_pants(self, mat, tris=2000, name="Pants", top=None, full=False):
        s = self.s
        shape = self.pants_sdf(full=full)
        top = top if top is not None else self.belt_z() + 0.022 * s
        shape = sdf.intersect(shape, sdf.halfspace([0, 0, top], [0, 0, 1]))
        self.shapes["pants"] = shape
        bones = ["hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R"]
        return mu.sdf_part(name, shape, mat, 0.0075 * s, tris, bones=bones, sym=True)

    def belt_z(self):
        return self.lv("pelvis") + 0.035 * self.s

    def build_belt(self, mat, mat_buckle, mat_loops=None, tris=500):
        s = self.s
        zb = self.belt_z()
        pants = self.pants_sdf()
        slab = sdf.box([0, 0, zb], [0.5 * s, 0.5 * s, 0.021 * s])
        belt = sdf.intersect(sdf.offset(pants, 0.008 * s), slab, k=0.003 * s)
        belt.bbox = (A([-0.3 * s, -0.3 * s, zb - 0.03 * s]),
                     A([0.3 * s, 0.3 * s, zb + 0.03 * s]))
        out = [mu.sdf_part("Belt", belt, mat, 0.004 * s, tris,
                           bones=["hips", "spine"], sym=True)]
        y = self._surface_y(pants, 0.0, zb) - 0.010 * s
        bk = sdf.box([0, y, zb], [0.032 * s, 0.008 * s, 0.024 * s], rnd=0.004 * s)
        hole = sdf.box([0, y - 0.01 * s, zb], [0.018 * s, 0.02 * s, 0.011 * s], rnd=0.002 * s)
        bk = sdf.subtract(bk, hole)
        out.append(mu.sdf_part("Buckle", bk, mat_buckle, 0.002 * s, 120,
                               bones=["hips"], sym=True))
        if mat_loops is not None:
            loops = []
            for ang in (35, 75, 145):
                for sx in (1, -1):
                    a = math.radians(ang)
                    dirv = np.array([sx * math.sin(a), -math.cos(a), 0])
                    # find surface along dirv
                    ts = np.linspace(0, 0.4 * s, 300)
                    P = np.array([0, 0, zb]) + ts[:, None] * dirv
                    dd = pants(P)
                    k = np.argmax(dd > 0)
                    c = P[k] + dirv * 0.012 * s
                    R = frame_np([0, 0, 1], dirv)
                    loops.append(sdf.box(c, [0.006 * s, 0.026 * s, 0.004 * s], R,
                                         rnd=0.002 * s))
            lp = sdf.union(*loops)
            out.append(mu.sdf_part("BeltLoops", lp, mat_loops, 0.0025 * s, 200,
                                   bones=["hips"], sym=True))
        return out

    # ------------------------------------------------------------------
    def sock_sdf(self, side, extra=0.0):
        s = self.s
        p = self.p
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        cr = p["calf_r"] * s + extra
        ar = p["ankle_r"] * s + extra
        base = sdf.round_cone(K - (K - Ak) * 0.02, Ak + A([0, 0, 0.0]), p["knee_r"] * s * 0.92 + extra, ar)
        calf = oriented_ellipsoid(K + (Ak - K) * 0.30 + A([0, 0.016 * s, 0]), K - Ak,
                                  cr * 1.0, cr * 1.05, 0.11 * s)
        return sdf.blend(base, 0.04 * s, calf)

    def build_socks(self, mat, tris=500, stripe_mat=None, stripes=(0.31, 0.285)):
        out = []
        s = self.s
        for side in ("L", "R"):
            sh = self.sock_sdf(side)
            out.append(mu.sdf_part("Sock." + side, sh, mat, 0.006 * s, tris,
                                   bones=["shin." + side, "foot." + side, "thigh." + side]))
            if stripe_mat is not None:
                sl = []
                for z in stripes:
                    sl.append(sdf.box([0, 0, z * s], [1.0, 1.0, 0.0065 * s]))
                band = sdf.intersect(sdf.offset(sh, 0.0025 * s), sdf.union(*sl))
                K = self.j("shin." + side)
                band.bbox = (K - 0.12 * s - A([0, 0, 0.35 * s]), K + 0.12 * s)
                out.append(mu.sdf_part("SockStripe." + side, band, stripe_mat,
                                       0.003 * s, 260, bones=["shin." + side]))
        return out

    # ------------------------------------------------------------------
    def foot_outline(self, chunky=1.0):
        """2D footprint (x lateral, y along the foot; forward = -y) in metres."""
        s = self.s * self.p["foot_scale"]
        ys = [0.072, 0.050, 0.020, -0.030, -0.080, -0.120, -0.160, -0.190, -0.210, -0.222]
        ws = [0.0, 0.030, 0.036, 0.034, 0.044, 0.048, 0.046, 0.038, 0.024, 0.0]
        right = []
        for y, w in zip(ys, ws):
            right.append((w * chunky, y))
        # densify the rounded ends
        pts = []
        for i in range(len(right) - 1):
            (x0, y0), (x1, y1) = right[i], right[i + 1]
            for k in range(3):
                u = k / 3.0
                pts.append((x0 + (x1 - x0) * u, y0 + (y1 - y0) * u))
        pts.append(right[-1])
        loop = pts + [(-x, y) for x, y in reversed(pts[1:-1])]
        # rounded heel/toe: smooth with a small circle pass
        loop = np.array(loop) * s
        return loop

    def shoe_sdf(self, side, chunky=1.0):
        s = self.s * self.p["foot_scale"]
        Ak = self.j("foot." + side)
        x = Ak[0]
        y0 = Ak[1]
        ss = self.s

        def P(dx, dy, z):
            return A([x + dx * s, y0 + dy * s, z * s])
        outline = self.foot_outline(chunky)
        sole = sdf.extrude2d(outline, [x, y0, 0.012 * s], [1, 0, 0], [0, 1, 0], 0.024 * s,
                             rnd=0.007 * s)
        w = 0.046 * chunky
        heel = sdf.ellipsoid(P(0, 0.032, 0.062), [w * 0.92 * s, 0.046 * s, 0.058 * s])
        mid = sdf.ellipsoid(P(0, -0.045, 0.056), [w * 1.0 * s, 0.085 * s, 0.048 * s])
        toe = sdf.ellipsoid(P(0, -0.150, 0.042), [w * 1.0 * s, 0.072 * s, 0.036 * s])
        tongue = sdf.ellipsoid(P(0, -0.035, 0.085), [w * 0.62 * s, 0.06 * s, 0.03 * s],
                               sdf.rot_matrix(-30, 0, 0))
        col = sdf.round_cone(P(0, 0.018, 0.07), A([x, y0 + 0.010 * ss, Ak[2] + 0.045 * ss]),
                             0.044 * s, self.p["ankle_r"] * ss * 1.2)
        upper = sdf.blend(heel, (0.05 * s, mid), (0.05 * s, toe), (0.03 * s, col),
                          (0.02 * s, tongue))
        upper = sdf.intersect(upper, sdf.prism2d([outline], [x, y0, 0], [1, 0, 0], [0, 1, 0],
                                                 dilate=-0.002 * s))
        upper = sdf.intersect(upper, sdf.halfspace([0, 0, 0.012 * s], [0, 0, -1]))
        upper.bbox = (A([x - 0.1 * s, y0 - 0.3 * s, 0]), A([x + 0.1 * s, y0 + 0.12 * s, Ak[2] + 0.1 * ss]))
        shape = sdf.blend(sole, 0.004 * s, upper)
        shape = sdf.intersect(shape, sdf.halfspace([0, 0, 0.0], [0, 0, -1]))
        shape.bbox = (A([x - 0.1 * s, y0 - 0.3 * s, -0.01]), A([x + 0.1 * s, y0 + 0.12 * s, Ak[2] + 0.1 * ss]))
        return shape

    def build_shoes(self, mat, tris=700, stripe_mat=None, chunky=1.0):
        import outfit
        out = []
        s = self.s * self.p["foot_scale"]
        for side in ("L", "R"):
            sh = self.shoe_sdf(side, chunky)
            out.append(mu.sdf_part("Shoe." + side, sh, mat, 0.0038 * s, tris,
                                   bones=["shin." + side, "foot." + side, "toe." + side],
                                   extra={"weight_overrides": {"toe." + side: 1.5}}))
            if stripe_mat is not None:
                Ak = self.j("foot." + side)
                # swoosh: u = forward (-y), v = up
                poly = np.array([(-0.035, 0.064), (0.0, 0.050), (0.05, 0.036), (0.115, 0.028),
                                 (0.135, 0.032), (0.085, 0.044), (0.02, 0.060), (-0.02, 0.078)])
                poly[:, 1] -= 0.05
                loops = [poly * s]
                ctr = A([Ak[0], Ak[1], 0.05 * s])
                sx = 1.0 if side == "L" else -1.0
                out.append(outfit.surface_decal(
                    "ShoeStripe." + side, loops, sh, ctr, [0, -1, 0], [0, 0, 1], [sx, 0, 0],
                    stripe_mat, lo=-0.001 * s, hi=0.0035 * s, voxel=0.0025 * s, tris=220,
                    bones=["foot." + side, "toe." + side, "shin." + side]))
        return out
