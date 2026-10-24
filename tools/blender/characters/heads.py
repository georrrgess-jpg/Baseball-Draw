"""Stylised heads (SDF sculpt) with separate eyes, brows and mouth parts.

Head-local units: ``h`` = head height (chin -> crown); origin at the centre of
the eye line; front = -Y, up = +Z, character left = +X.
"""
import math
import numpy as np
from mathutils import Vector

import sdf
import meshutil as mu

DEFAULT_FACE = dict(
    jaw=1.0,          # 0 = soft/female, 1 = square/male
    jaw_w=1.0,        # lower face width
    chin=1.0,         # chin size
    nose=1.0,         # nose size
    nose_w=1.0,
    lips=1.0,         # lip fullness
    eye=1.0,          # eye size
    eye_open=1.0,     # upper lid position (smaller = more lidded)
    eye_tilt=0.0,     # outer corner tilt (deg, + = up)
    eye_gap=1.0,
    brow=1.0,         # brow ridge strength
    brow_thick=1.0,   # eyebrow hair thickness
    brow_angle=0.0,   # + = angry (inner end low)
    cheek=1.0,
    ear=1.0,
    width=1.0,
    smile=0.0,        # mouth corner curve (+ up)
    smirk=0.0,        # asymmetric (+ = right corner up)
    mouth_w=1.0,
    lashes=False,
    asian=0.0,        # 0..1 stylised East Asian eye/lid shape
)


class HeadBuilder:
    def __init__(self, origin, h, face=None, neck_r=0.058, neck_base=None):
        self.o = Vector(origin)
        self.h = h
        f = dict(DEFAULT_FACE)
        f.update(face or {})
        self.f = f
        self.neck_r = neck_r
        self.neck_base = neck_base

    def P(self, x, y, z):
        return np.array(self.o + Vector((x, y, z)) * self.h)

    def R(self, *r):
        return np.array(r) * self.h

    # ------------------------------------------------------------------
    def eye_center(self, side):
        f = self.f
        sx = 1 if side == "L" else -1
        return self.P(sx * 0.138 * f["eye_gap"] * f["width"], -0.288, 0.0)

    def eye_radius(self):
        return 0.072 * self.h * self.f["eye"]

    def skin_sdf(self, face=True):
        f = self.f
        P, R = self.P, self.R
        w = f["width"]
        jw = f["jaw_w"]
        cr = sdf.ellipsoid(P(0, 0.05, 0.08), R(0.335 * w, 0.40, 0.44))
        parts = []
        lower = sdf.ellipsoid(P(0, -0.07, -0.19),
                              R(0.30 * w * jw, 0.31, 0.31))
        parts.append((0.12 * self.h, lower))
        jaw = f["jaw"]
        if jaw > 0.05:
            for sx in (1, -1):
                parts.append((0.10 * self.h, sdf.ellipsoid(
                    P(sx * 0.215 * w * jw, 0.0, -0.25 - 0.02 * jaw),
                    R(0.07 + 0.025 * jaw, 0.12, 0.10 + 0.01 * jaw))))
        ch = f["chin"]
        parts.append((0.08 * self.h, sdf.ellipsoid(
            P(0, -0.26 - 0.01 * ch, -0.405 - 0.015 * jaw),
            R((0.085 + 0.045 * jaw) * ch, 0.085 * ch, 0.08 * ch))))
        if face:
            for sx in (1, -1):
                parts.append((0.11 * self.h, sdf.ellipsoid(
                    P(sx * 0.20 * w, -0.20, -0.06),
                    R(0.10 * f["cheek"], 0.09, 0.07))))
            br = f["brow"]
            parts.append((0.07 * self.h, sdf.round_cone(
                P(-0.20 * w, -0.315, 0.09), P(0.0, -0.335, 0.10),
                0.045 * self.h * br, 0.040 * self.h * br)))
            parts.append((0.07 * self.h, sdf.round_cone(
                P(0.20 * w, -0.315, 0.09), P(0.0, -0.335, 0.10),
                0.045 * self.h * br, 0.040 * self.h * br)))
            # nose
            n = f["nose"]
            nw = f["nose_w"]
            parts.append((0.035 * self.h, sdf.round_cone(
                P(0, -0.355, 0.04), P(0, -0.420 - 0.02 * n, -0.125),
                0.028 * self.h, 0.040 * self.h * n)))
            parts.append((0.03 * self.h, sdf.sphere(
                P(0, -0.428 - 0.025 * n, -0.148), 0.046 * self.h * n)))
            for sx in (1, -1):
                parts.append((0.025 * self.h, sdf.sphere(
                    P(sx * 0.052 * nw * n, -0.41 - 0.01 * n, -0.168),
                    0.034 * self.h * n * nw)))
            # lips
            lp = f["lips"]
            parts.append((0.03 * self.h, sdf.ellipsoid(
                P(0, -0.385, -0.245), R(0.105 * f["mouth_w"], 0.055,
                                        0.036 * (0.8 + 0.3 * lp)))))
            parts.append((0.03 * self.h, sdf.ellipsoid(
                P(0, -0.365, -0.300), R(0.09 * f["mouth_w"], 0.05 * lp,
                                        0.034 * lp))))
        # ears
        e = f["ear"]
        ears = []
        for sx in (1, -1):
            rot = sdf.rot_matrix(0, sx * 8, sx * -12)
            ears.append(sdf.ellipsoid(P(sx * 0.325 * w, 0.06, -0.035),
                                      R(0.05 * e, 0.105 * e, 0.155 * e), rot))
        # neck
        nb = self.neck_base if self.neck_base is not None else P(0, 0.08, -0.85)
        neck = sdf.round_cone(P(0, 0.08, -0.22), np.array(nb),
                              self.neck_r * 0.92, self.neck_r * 1.05)
        parts.append((0.10 * self.h, neck))
        shape = sdf.blend(cr, *[(k, s) for k, s in parts])
        shape = sdf.blend(shape, *[(0.03 * self.h, s) for s in ears])
        cut = []
        for sx in (1, -1):
            cut.append(sdf.ellipsoid(P(sx * 0.375 * w, 0.04, -0.045),
                                     R(0.03 * e, 0.065 * e, 0.10 * e),
                                     sdf.rot_matrix(0, sx * 8, sx * -12)))
        if face:
            for side in ("L", "R"):
                c = self.eye_center(side)
                cut.append(sdf.ellipsoid(c + self.R(0, -0.085, 0.0),
                                         self.R(0.095, 0.075, 0.068) * f["eye"]))
            # nostrils
            n = f["nose"]
            for sx in (1, -1):
                cut.append(sdf.ellipsoid(P(sx * 0.03 * n, -0.44 - 0.01 * n,
                                           -0.19), R(0.018, 0.022, 0.012) * n))
            # mouth slit
            pts = self.mouth_points()
            for i in range(len(pts) - 1):
                for dy in (-0.07, -0.045, -0.02):
                    cut.append(sdf.capsule(pts[i] + self.R(0, dy, 0),
                                           pts[i + 1] + self.R(0, dy, 0),
                                           0.0075 * self.h))
        shape = sdf.subtract(shape, *cut, k=0.012 * self.h)
        if face:
            lids = []
            for side in ("L", "R"):
                lids += self.lid_sdfs(side)
            shape = sdf.blend(shape, *[(0.012 * self.h, s) for s in lids])
        return shape

    def mouth_points(self):
        f = self.f
        mw = 0.088 * f["mouth_w"]
        sm = f["smile"]
        sk = f["smirk"]
        pts = []
        for i, t in enumerate(np.linspace(-1, 1, 7)):
            x = t * mw
            corner = abs(t) ** 2
            z = -0.272 + corner * 0.02 * sm + (0.03 * sk * max(0, -t) ** 2 if sk > 0 else 0)
            z += (0.03 * -sk * max(0, t) ** 2) if sk < 0 else 0
            y = -0.415 + corner * 0.05
            pts.append(self.P(x, y, z))
        return pts

    def lid_sdfs(self, side):
        f = self.f
        c = self.eye_center(side)
        r = self.eye_radius()
        sx = 1 if side == "L" else -1
        tilt = math.radians(f["eye_tilt"]) * sx
        r_ = r
        lid_z = r_ * (0.38 + 0.25 * (f["eye_open"] - 1.0) - 0.15 * f["asian"])
        n_up = np.array([-sx * math.sin(tilt), 0.12, 1.0])
        n_up /= np.linalg.norm(n_up)
        upper = sdf.intersect(sdf.sphere(c, r + 0.010 * self.h),
                              sdf.halfspace(c + np.array([0, 0, lid_z]), -n_up))
        low_z = -0.66 * r
        lower = sdf.intersect(sdf.sphere(c, r + 0.005 * self.h),
                              sdf.halfspace(c + np.array([0, 0, low_z]),
                                            np.array([0, -0.2, 1.0])))
        return [upper, lower]

    # ------------------------------------------------------------------
    def build_skin(self, mat, tris=2600, voxel=None, name="Head", face=True,
                   bones=("head", "neck", "chest")):
        shape = self.skin_sdf(face=face)
        vox = voxel or self.h * 0.0105
        lo = np.array(self.o) + np.array([-0.45, -0.62, -1.0]) * self.h
        hi = np.array(self.o) + np.array([0.45, 0.52, 0.55]) * self.h
        if self.neck_base is not None:
            lo[2] = min(lo[2], self.neck_base[2] - self.neck_r * 1.2)
        return mu.sdf_part(name, shape, mat, vox, tris, bones=list(bones),
                           sym=True, bbox=(lo, hi))

    def build_eyes(self, mats, iris_scale=1.0, look=(0.0, 0.0)):
        """Sclera + iris + pupil + catchlight per eye (rigid to head)."""
        r = self.eye_radius()
        out = []
        for side in ("L", "R"):
            c = Vector(self.eye_center(side))
            sx = 1 if side == "L" else -1
            out.append(mu.uv_sphere("Eye." + side, c, r, mats["Eyes"], seg=16,
                                    rings=10, rigid="head"))
            # gaze direction: forward, slight outward
            gx = math.radians(look[0]) + sx * math.radians(2)
            gz = math.radians(look[1])
            d = Vector((math.sin(gx), -math.cos(gx) * math.cos(gz), math.sin(gz)))
            d.normalize()
            from mathutils import Matrix
            rot = Vector((0, 0, 1)).rotation_difference(-d).to_matrix()
            ir = r * 0.62 * iris_scale
            # iris: flattened sphere sitting on the eyeball surface
            ic = c + d * (r * 0.88)
            out.append(mu.uv_sphere("Iris." + side, ic, 1.0, mats["Iris"], seg=14,
                                    rings=6, scale=(ir, ir, r * 0.20), rot=rot,
                                    rigid="head"))
            pc = c + d * (r * 0.965)
            pr = ir * 0.48
            out.append(mu.uv_sphere("Pupil." + side, pc, 1.0, mats["Pupil"], seg=10,
                                    rings=5, scale=(pr, pr, r * 0.12), rot=rot,
                                    rigid="head"))
            # catchlight (upper outer)
            hl = c + d * (r * 1.0) + Vector((-0.30 * ir, 0, 0.38 * ir))
            out.append(mu.uv_sphere("Glint." + side, hl, ir * 0.17, mats["Eyes"],
                                    seg=6, rings=4, rigid="head"))
        return out

    def build_brows(self, mat, tris=500):
        f = self.f
        P = self.P
        parts = []
        th = f["brow_thick"]
        ang = f["brow_angle"]
        for sx in (1, -1):
            gx = f["eye_gap"] * f["width"]
            pts = [P(sx * 0.050 * gx, -0.372, 0.108 - 0.012 * ang),
                   P(sx * 0.130 * gx, -0.372, 0.128 - 0.004 * ang),
                   P(sx * 0.215 * gx, -0.322, 0.118 + 0.008 * ang)]
            rad = np.array([0.030, 0.027, 0.014]) * self.h * th
            parts.append(sdf.polyline_tube(pts, rad))
        shape = sdf.union(*parts)
        # flatten slightly into the forehead
        return mu.sdf_part("Brows", shape, mat, self.h * 0.007, tris,
                           rigid="head", sym=True)

    def build_mouth(self, mat, tris=160):
        pts = self.mouth_points()
        pts = [p + self.R(0, -0.004, 0) for p in pts]
        shape = sdf.polyline_tube(pts, [0.0085 * self.h] * len(pts))
        return mu.sdf_part("Mouth", shape, mat, self.h * 0.004, tris,
                           rigid="head")

    def build_lashes(self, mat, tris=200):
        parts = []
        r = self.eye_radius()
        for side in ("L", "R"):
            c = self.eye_center(side)
            sx = 1 if side == "L" else -1
            pts = []
            for t in np.linspace(-0.9, 1.0, 5):
                ang = t * 1.05
                x = math.sin(ang) * (r + 0.012 * self.h)
                y = -math.cos(ang) * (r + 0.012 * self.h)
                z = (0.024 + 0.012 * max(t, 0)) * self.h
                pts.append(c + np.array([sx * x, y, z]))
            rad = [0.006 * self.h, 0.008 * self.h, 0.009 * self.h, 0.010 * self.h,
                   0.012 * self.h]
            parts.append(sdf.polyline_tube(pts, rad))
        return mu.sdf_part("Lashes", sdf.union(*parts), mat, self.h * 0.005, tris,
                           rigid="head", sym=True)
