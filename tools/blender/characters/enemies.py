"""The Wreckers (runners + bosses) in the stylised "hero" style of the defenders.

Same pipeline as hero.py (clean lofted / projected quad meshes, decals that
copy the weights under them) with the opponents' own pieces: batting helmets
with ear flaps, a sprinter's aero helmet, the trickster's stocking cap and
domino mask, armour plates, pauldrons, gauntlets, springs and knee pads,
sliding mitts, capes, horns and giant bats.  Every type has its own
silhouette and accent colour (roster.ENEMIES).
"""
import math
import json

import numpy as np

import sdf
import geo
from geo import A, unit
from hero import Hero
from hero_wear import periodic, ang_dist
from hutil import superellipsoid, orient_outward, rot_about


def frame_from_z(z, x_hint=(1.0, 0, 0)):
    """3x3 rotation with columns (x, y, z), local z = ``z``."""
    z = unit(z)
    x = A(x_hint) - z * np.dot(A(x_hint), z)
    if np.linalg.norm(x) < 1e-6:
        x = A([0, 1.0, 0]) - z * z[1]
    x = unit(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], 1)


class EnemyHero(Hero):
    """Hero builder with the Wreckers' head-wear, gear and extras."""

    # ------------------------------------------------------------------
    def build(self):
        cfg = self.cfg
        m = self.m
        hw = cfg.get("headwear", "helmet")
        self.build_head()
        self.build_ears()
        self.build_nose()
        if cfg.get("mask"):
            self.build_mask()
        self.build_eyes()
        self.build_brows(m["Hair"] if not cfg.get("brow_col") else m["Brow"])
        mouth_surf = None
        if cfg.get("beard") or cfg.get("full_beard"):
            beard = self.build_beard(full=bool(cfg.get("full_beard")))
            if cfg.get("full_beard"):
                mouth_surf = geo.Surface(beard)
        self.build_mouth(mouth_surf)
        if cfg.get("eyeblack"):
            self.build_eyeblack()
        if cfg.get("sunglasses"):
            self.build_sunglasses()
        # hair + head-wear
        if hw in ("helmet", "aero"):
            if cfg.get("hair_style", "short") != "none":
                self.hair_base("short", m["Hair"], under_cap=True, grow=0.014)
            if hw == "helmet":
                self.build_batting_helmet(brim=cfg.get("brim", True),
                                          cage=cfg.get("cage", False),
                                          horns=cfg.get("horns", False))
            else:
                self.build_aero_helmet()
        elif hw == "beanie":
            self.build_hair("short", m["Hair"], "cap")
            self.build_beanie()
        elif hw in ("cap", "cap_back"):
            self.build_hair(cfg.get("hair_style", "short"), m["Hair"], hw)
            self.build_cap(yaw=180.0 if hw == "cap_back" else 0.0, emblem=cfg.get("emblem"))
        elif hw == "headband":
            self.build_hair(cfg.get("hair_style", "spiky"), m["Hair"], "headband")
            self.build_headband()
        # body
        self.build_neck()
        self.build_torso()
        self.build_collar()
        self.build_vneck(placket=True)
        bare = cfg.get("bare_arms", False)
        for sd in "LR":
            self.build_sleeve(sd)
            if bare:
                up = self.build_arm(sd, m["Undershirt"], 0.12, 0.62, cuff=True,
                                    name="ArmUpper." + sd)
                fo = self.build_arm(sd, m["Skin"], 0.55, 2.0, cuff=False,
                                    name="Forearm." + sd, tuck=(0.62, 0.84))
                S, E, W = self.arm_axis(sd)
                fo["share"] = json.dumps(dict(src=up.name, a=list(S), b=list(E), u0=0.58,
                                              u1=0.72))
            else:
                self.build_arm(sd, m["Undershirt"])
            if cfg.get("wristbands"):
                self.build_wristband(sd, m["JerseyTrim"])
            if cfg.get("mitts"):
                self.build_slide_mitt(sd)
            else:
                self.build_hand(sd, m["Glove"])
        self.build_pants(knee_pants=False)
        self.build_pant_stripes()
        self.build_belt()
        self.build_socks(stripes=True)
        self.build_shoes(chunky=cfg.get("chunky", 1.0))
        self.build_numbers(front=True)
        self.extras()
        return self.parts

    # ------------------------------------------------------------------
    # helmets / hats
    # ------------------------------------------------------------------
    def helmet_sdf(self, grow=0.0):
        h = self.h
        P = self.P
        w = self.f["width"]
        g = grow * h
        dome = sdf.ellipsoid(P(0, 0.06, 0.07), (0.425 * w * h + g, 0.50 * h + g, 0.50 * h + g))
        flaps = [sdf.ellipsoid(P(sx * 0.33 * w, 0.06, -0.15), (0.13 * h + g, 0.22 * h + g,
                                                               0.26 * h + g)) for sx in (1, -1)]
        return sdf.blend(dome, 0.10 * h, *flaps)

    def build_batting_helmet(self, brim=True, cage=False, horns=False):
        h = self.h
        m = self.m
        fn = self.helmet_sdf()
        self.cap_fn = fn
        # rim: high over the brow, down over both ears (flaps), back of the head
        lo = periodic([(0, 0.25), (25, 0.225), (40, 0.15), (50, 0.02), (58, -0.16),
                       (68, -0.36), (100, -0.40), (122, -0.30), (145, -0.17), (180, -0.13)])
        phis = np.linspace(0, 360, 44, endpoint=False)
        shell, grid = self.shell("Helmet", m["Cap"], fn, phis, lo, nrows=13, apex=True,
                                 edge="lip", lip=0.05)
        c0 = self.head_center()
        # dark rubber trim around the opening
        edge = [p + unit(p - c0) * 0.003 * h for p in grid[:, 2]]
        v, f = geo.tube(edge, 0.019 * h, nseg=5, closed_path=True)
        self.add("HelmetTrim", v, f, m["Belt"], rigid="head")
        # accent stripe over the crown (front to back): reads from above
        pts = [self.surface_at(fn, 0, z) for z in (0.30, 0.42, 0.52)]
        pts += [self.surface_at(fn, 180, z) for z in (0.50, 0.36, 0.18, 0.02)]
        pts = [p + unit(p - c0) * 0.004 * h for p in pts]
        pts = geo.smooth_polyline(pts, 16)
        v, f = geo.tube(pts, 0.045 * h, nseg=8, ovals=[0.28] * 16, up=(1, 0, 0), cap0='pole',
                        cap1='pole')
        self.add("HelmetStripe", v, f, m["JerseyTrim"] if not self.cfg.get("stripe_mat") else
                 m[self.cfg["stripe_mat"]], rigid="head")
        # ear holes (dark discs on the flaps)
        for sx in (1, -1):
            p = self.surface_at(fn, sx * 90, -0.08)
            n = unit(p - c0)
            R = frame_from_z(n, (0, 0, 1.0))
            v, f = superellipsoid(p + n * 0.002 * h, (0.05 * h, 0.05 * h, 0.010 * h), R,
                                  nu=12, nv=5)
            self.add("EarHole", v, f, m["Belt"], rigid="head")
        if brim:
            self.build_brim(fn, 0.0, lo, length=0.22, pitch=-2, width=40, curve=0.03,
                            name="HelmetBrim")
        if cage:
            self.build_face_cage(fn)
        if horns:
            self.build_horns(fn)
        return shell

    def build_face_cage(self, fn):
        h = self.h
        m = self.m
        cage = self.head_sdf(0.19)
        bars = []
        for z, span in ((-0.13, 50), (-0.30, 44)):
            bars.append([self.surface_at(cage, ph, z) for ph in np.linspace(-span, span, 9)])
        bars.append([self.surface_at(cage, 0, z) for z in np.linspace(-0.13, -0.44, 5)])
        for sx in (1, -1):
            a = self.surface_at(cage, sx * 50, -0.13)
            b = self.surface_at(fn, sx * 64, -0.05)
            bars.append([a, (a + b) / 2, b])
            a = self.surface_at(cage, sx * 44, -0.30)
            b = self.surface_at(fn, sx * 66, -0.24)
            bars.append([a, (a + b) / 2, b])
        for pts in bars:
            pts = geo.smooth_polyline(pts, max(2, len(pts)))
            v, f = geo.tube(pts, 0.022 * h, nseg=6, cap0='pole', cap1='pole')
            self.add("FaceCage", v, f, m["Metal"], rigid="head")

    def build_horns(self, fn):
        h = self.h
        m = self.m
        for sx in (1, -1):
            b = self.surface_at(fn, sx * 78, 0.26)
            n = unit(b - self.head_center())
            pts = [b - n * 0.04 * h, b + n * 0.08 * h, b + n * 0.20 * h + A([0, -0.02, 0.10]) * h,
                   b + n * 0.25 * h + A([0, -0.08, 0.28]) * h,
                   b + n * 0.22 * h + A([0, -0.14, 0.42]) * h]
            pts = geo.smooth_polyline(pts, 12)
            rad = geo.interp([0, 0.3, 1.0], [0.085, 0.07, 0.006], np.linspace(0, 1, 12)) * h
            v, f = geo.tube(pts, rad, nseg=10, cap0='pole', cap1='pole')
            self.add("Horn", v, f, m["Metal"], rigid="head")

    def build_aero_helmet(self):
        """Streamlined sprint helmet: swept-back tail, no brim, accent fin."""
        h = self.h
        m = self.m
        P = self.P
        w = self.f["width"]
        dome = sdf.ellipsoid(P(0, 0.05, 0.06), (0.405 * w * h, 0.49 * h, 0.48 * h))
        tail = sdf.round_cone(P(0, 0.15, 0.12), P(0, 0.62, -0.06), 0.30 * h, 0.07 * h)
        fn = sdf.blend(dome, 0.18 * h, tail)
        self.cap_fn = fn
        lo = periodic([(0, 0.24), (30, 0.20), (55, 0.10), (80, 0.02), (110, -0.02),
                       (150, -0.12), (180, -0.16)])
        phis = np.linspace(0, 360, 44, endpoint=False)
        shell, grid = self.shell("Helmet", m["Cap"], fn, phis, lo, nrows=13, apex=True,
                                 edge="lip", lip=0.04)
        c0 = self.head_center()
        edge = [p + unit(p - c0) * 0.003 * h for p in grid[:, 2]]
        v, f = geo.tube(edge, 0.016 * h, nseg=5, closed_path=True)
        self.add("HelmetTrim", v, f, m["Belt"], rigid="head")
        # two speed stripes along the shell
        for sx in (1, -1):
            pts = [self.surface_at(fn, sx * ph, z) for ph, z in
                   ((14, 0.36), (40, 0.36), (80, 0.30), (120, 0.20), (155, 0.08), (172, -0.02))]
            pts = [p + unit(p - c0) * 0.004 * h for p in pts]
            pts = geo.smooth_polyline(pts, 14)
            v, f = geo.tube(pts, geo.interp([0, 1], [0.030, 0.012], np.linspace(0, 1, 14)) * h,
                            nseg=6, ovals=[0.3] * 14, cap0='pole', cap1='pole')
            self.add("HelmetStripe", v, f, m["JerseyTrim"], rigid="head")
        return shell

    def build_beanie(self):
        """Trickster's stocking cap: snug crown, rolled cuff, a long floppy
        tail bent to one side with a pompom."""
        h = self.h
        m = self.m
        fn = self.head_sdf(0.045)
        self.cap_fn = fn

        def lo(ph):
            return 0.17 + 0.07 * math.cos(math.radians(ph))
        phis = np.linspace(0, 360, 40, endpoint=False)
        crown, grid = self.shell("Beanie", m["Cap"], fn, phis, lo, nrows=10, apex=True,
                                 edge="lip", lip=0.03)
        # rolled cuff
        fn2 = self.head_sdf(0.075)
        base = A([[self.surface_at(fn2, ph, lo(ph) + dz) for dz in (-0.01, 0.03, 0.07, 0.10)]
                  for ph in phis])
        nrm = unit(base - self.head_center())
        th = A([0.006, 0.016, 0.016, 0.006]) * h
        top = base + nrm * th[None, :, None]
        inner = base - nrm * 0.03 * h
        rows = [inner[:, 0], top[:, 0], top[:, 1], top[:, 2], top[:, 3], inner[:, 3]]
        g = np.stack(rows, 1)
        verts = list(g.reshape(-1, 3))
        faces = self.grid_faces(len(phis), len(rows), closed=True)
        faces = orient_outward(verts, faces, self.head_center())
        self.add("BeanieCuff", verts, faces, m["Cloth"], rigid="head")
        # floppy tail from the crown, curling over to the character's right
        apex, _ = geo.project_rays(fn, self.head_center(), A([[0, 0.25, 1.0]]), 1.2 * h)
        a = apex[0]
        pts = [a - A([0, 0, 0.10]) * h, a + A([0, 0.02, 0.10]) * 1.6 * h, a + A([-0.10, 0.10, 0.26]) * 1.6 * h,
               a + A([-0.28, 0.18, 0.30]) * 1.6 * h, a + A([-0.42, 0.22, 0.18]) * 1.6 * h,
               a + A([-0.50, 0.22, 0.02]) * 1.6 * h]
        pts = geo.smooth_polyline(pts, 16)
        rad = geo.interp([0, 0.15, 0.6, 1.0], [0.30, 0.27, 0.15, 0.06],
                         np.linspace(0, 1, 16)) * h
        v, f = geo.tube(pts, rad, nseg=12, cap0='pole', cap1='pole', up=(0, -1, 0))
        self.add("BeanieTail", v, f, m["Cap"], rigid="head")
        # stripes around the tail
        for k in (5, 9):
            d = unit(pts[k + 1] - pts[k - 1])
            R = frame_from_z(d)
            ring = [pts[k] + R @ A([math.cos(t), math.sin(t), 0]) * (rad[k] + 0.006 * h)
                    for t in np.linspace(0, 2 * np.pi, 16, endpoint=False)]
            v, f = geo.tube(ring, 0.022 * h, nseg=5, closed_path=True, up=d)
            self.add("BeanieStripe", v, f, m["Cloth"], rigid="head")
        pc = pts[-1] + unit(pts[-1] - pts[-2]) * 0.05 * h
        v, f = superellipsoid(pc, (0.09 * h,) * 3, nu=12, nv=8)
        f = orient_outward(v, f, pc)
        self.add("Pompom", v, f, m["Number"], rigid="head")

    def build_mask(self):
        """Domino mask across the eyes (under the eye decals)."""
        h = self.h
        head = self.surf["head"]
        n = A([0, -1.0, 0.0])
        u = A([1.0, 0, 0])
        v = A([0, 0, 1.0])
        c = head.hit(self.o + A([0, -0.6 * h, -0.03 * h]), A([0, -1, 0]), back=0.05)[0]
        half = [(0.0, 0.040), (0.08, 0.090), (0.18, 0.105), (0.27, 0.090), (0.34, 0.075),
                (0.38, 0.020), (0.33, -0.050), (0.24, -0.090), (0.14, -0.090), (0.05, -0.050),
                (0.0, -0.030)]
        loop = [(x, y) for x, y in half] + [(-x, y) for x, y in half[::-1][1:-1]]
        loop = A(loop[::-1]) * A([1.18, 1.25]) * h * self.f["width"]
        vv, ff = geo.decal(head, [loop], c, u, v, n, 0.0015 * h, 0.006 * h, depth=0.03 * h,
                           subdiv=1)
        self.add_decal("Mask", vv, ff, m_or(self.m, "Mask", "Cloth"), rigid="head")

    # ------------------------------------------------------------------
    # hands
    # ------------------------------------------------------------------
    def build_slide_mitt(self, side):
        """Padded sliding mitt (base stealer): one big rounded paw + cuff."""
        k = self.s * self.p["hand_scale"]
        W, f, n, t = self.hand_frame(side)
        R = np.stack([t, n, f], 1)
        c = W + f * 0.060 * k + n * 0.004 * k
        v, fc = superellipsoid(c, (0.058 * k, 0.034 * k, 0.082 * k), R, nu=16, nv=10, e1=2.4,
                               e2=2.2)
        fc = orient_outward(v, fc, c)
        self.add("Mitt." + side, v, fc, self.m["Glove"], rigid="hand." + side)
        tb = W + f * 0.035 * k + t * 0.045 * k + n * 0.012 * k
        v, fc = superellipsoid(tb, (0.024 * k, 0.022 * k, 0.040 * k),
                               np.stack([n, f, unit(t + f * 0.6)], 1), nu=10, nv=6)
        fc = orient_outward(v, fc, tb)
        self.add("MittThumb." + side, v, fc, self.m["Glove"], rigid="hand." + side)
        wr = self.p["wrist_r"] * self.s
        v, fc = geo.tube([W - f * 0.035 * k, W + f * 0.005 * k], [wr * 1.45, wr * 1.5], nseg=14,
                         cap0='flat', cap1='flat', up=n)
        self.add("MittCuff." + side, v, fc, self.m["Belt"], bones=["forearm." + side,
                                                                    "hand." + side])

    # ------------------------------------------------------------------
    # armour
    # ------------------------------------------------------------------
    def torso_pad(self, name, mat, front=True, z0=None, z1=None, wfrac=0.86, segs=2,
                  thick=0.024, grow=0.004):
        """Raised plate over the front (or back) of the jersey torso."""
        s = self.s
        surf = self.surf["torso"]
        zn, zp = self.lv("neck"), self.lv("pelvis")
        z0 = zp + 0.06 * s if z0 is None else z0
        z1 = zn - 0.01 * s if z1 is None else z1
        cw = self.p["chest_w"] * s
        sy = -1.0 if front else 1.0
        nu, nv = 17, 15
        base = np.zeros((nu, nv, 3))
        nrm = np.zeros((nu, nv, 3))
        th = np.zeros((nu, nv))
        for i in range(nu):
            for j in range(nv):
                uu = i / (nu - 1) * 2 - 1
                vv = j / (nv - 1)
                W = cw * wfrac * (1.0 - 0.12 * vv)
                ztop = z1 - 0.045 * s * max(0.0, 1 - uu * uu) ** 1.5 * (1 if front else 0.3)
                z = ztop + (z0 - ztop) * vv
                hit, _ = surf.hit(A([uu * W, sy * 0.4, z]), A([0, sy, 0]))
                base[i, j] = hit
                rd = unit(A([hit[0], hit[1], 0]))
                nrm[i, j] = unit(rd * 0.6 + A([0, sy, 0]) * 0.4)
                seg = vv * segs
                fr = seg - math.floor(seg)
                pillow = 0.78 + 0.22 * math.sin(math.pi * fr) ** 0.5
                edge = (1 - abs(uu) ** 6) ** 0.5 * (1 - abs(vv * 2 - 1) ** 10) ** 0.5
                th[i, j] = (grow + thick * pillow * edge) * s
        v, f = geo.pad(base, nrm, th, 0.004 * s)
        f = orient_outward(v, f, A([0, 0, (z0 + z1) / 2]))
        return self.add(name, v, f, mat, weights_from=self.torso_obj)

    def pauldron(self, side, mat, size=1.0, layers=2, spikes=0, spike_mat=None):
        s = self.s
        sx = 1 if side == "L" else -1
        S = self.j("upper_arm." + side)
        out = A([sx, 0, 0])
        for i in range(layers):
            r = (0.118 - 0.020 * i) * s * size
            c = S + A([sx * (0.010 + 0.040 * i) * s * size, 0.0, (0.045 - 0.050 * i) * s * size])
            zt = unit(A([sx * (0.55 + 0.25 * i), 0, 1.0]))
            R = frame_from_z(zt, (0, 1.0, 0))
            v, f = superellipsoid(c, (r, r * 0.98, r * 0.52), R, nu=18, nv=10, e1=2.2, e2=2.4)
            f = orient_outward(v, f, c)
            o = self.add("Pauldron." + side, v, f, mat, bones=["shoulder." + side,
                                                                "upper_arm." + side])
            o["fixed"] = json.dumps({"shoulder." + side: 0.55, "upper_arm." + side: 0.45})
            # rim
            ring = [c + R @ A([math.cos(t) * r, math.sin(t) * r * 0.98, -0.02 * r])
                    for t in np.linspace(0, 2 * np.pi, 24, endpoint=False)]
            v, f = geo.tube(ring, 0.012 * s * size, nseg=5, closed_path=True, up=zt)
            o = self.add("PauldronRim." + side, v, f, m_or(self.m, "Trim2", "Belt"),
                         bones=["shoulder." + side, "upper_arm." + side])
            o["fixed"] = json.dumps({"shoulder." + side: 0.55, "upper_arm." + side: 0.45})
        top = S + A([sx * 0.02 * s * size, 0, 0.045 * s * size]) + \
            A([sx * 0.55, 0, 1.0]) / np.linalg.norm([0.55, 1.0]) * 0.06 * s * size
        for k in range(spikes):
            yy = (k - (spikes - 1) / 2) * 0.06 * s * size
            b = top + A([0, yy, 0])
            d = unit(A([sx * 0.5, yy / (0.1 * s), 1.0]))
            pts = [b - d * 0.01 * s, b + d * 0.05 * s * size, b + d * 0.10 * s * size]
            v, f = geo.tube(pts, A([0.026, 0.016, 0.003]) * s * size, nseg=8, cap0='pole',
                            cap1='pole')
            o = self.add("Spike." + side, v, f, spike_mat or mat,
                         bones=["shoulder." + side, "upper_arm." + side])
            o["fixed"] = json.dumps({"shoulder." + side: 0.55, "upper_arm." + side: 0.45})

    def gauntlet(self, side, mat):
        rings, pts = self.arm_profile(side, 1.22, 1.93, cuff=False, nseg=14, rings=8, grow=1.32)
        v, f = geo.loft(rings, 'flat', 'flat')
        f = orient_outward(v, f, pts[len(pts) // 2])
        return self.add("Gauntlet." + side, v, f, mat, rigid="forearm." + side)

    def armband(self, side, mat):
        rings, pts = self.arm_profile(side, 0.60, 0.78, cuff=False, nseg=16, rings=4, grow=1.16)
        v, f = geo.loft(rings, 'flat', 'flat')
        f = orient_outward(v, f, pts[len(pts) // 2])
        return self.add("Armband." + side, v, f, mat, rigid="upper_arm." + side)

    def knee_pad(self, side, mat, size=1.0):
        s = self.s
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        d = unit(Ak - K)
        fwd = A([0, -1.0, 0])
        U = unit(fwd - d * np.dot(fwd, d))
        V = np.cross(d, U)
        kc = K + U * self.p["knee_r"] * s * 1.15 + d * 0.012 * s
        R = np.stack([V, -d, U], 1)
        v, f = superellipsoid(kc, A([0.075, 0.085, 0.048]) * s * size, R, nu=16, nv=9,
                              e1=2.4, e2=2.4)
        f = orient_outward(v, f, kc - U * 0.02 * s)
        self.add("KneePad." + side, v, f, mat, rigid="shin." + side)

    def spring(self, side, mat):
        s = self.s
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        d = unit(Ak - K)
        L = np.linalg.norm(Ak - K)
        u = unit(np.cross(d, A([1.0, 0, 0])))
        v = np.cross(d, u)
        cr = self.p["calf_r"] * s
        pts = []
        turns = 5.0
        N = 90
        for i in range(N + 1):
            k = i / N
            a = 2 * math.pi * turns * k
            r = cr * (1.38 - 0.42 * k) + 0.012 * s
            c = K + d * (0.30 * L + 0.48 * L * k)
            pts.append(c + (u * math.cos(a) + v * math.sin(a)) * r)
        vv, ff = geo.tube(pts, 0.010 * s, nseg=6, cap0='pole', cap1='pole')
        self.add("Spring." + side, vv, ff, mat, rigid="shin." + side)

    def shin_plate(self, side, mat):
        """Greave over the front of the sock (heavy types)."""
        s = self.s
        K = self.j("shin." + side)
        Ak = self.j("foot." + side)
        d = unit(Ak - K)
        ts = np.linspace(0.30, 0.86, 9)
        thetas = np.linspace(-110, 110, 11)
        rings = self.sock_rings(side, ts, grow=0.006 * s, nseg=72)
        L = np.linalg.norm(Ak - K)
        base = np.zeros((len(thetas), len(ts), 3))
        nrm = np.zeros_like(base)
        th = np.zeros(base.shape[:2])
        for j, t in enumerate(ts):
            c = K + d * L * t
            for i, a in enumerate(thetas):
                k = int(round((a % 360) / 5.0)) % 72
                base[i, j] = rings[j][k]
                nrm[i, j] = unit(rings[j][k] - c)
                ridge = math.exp(-(a / 12.0) ** 2)
                edge = (1 - (abs(a) / 110) ** 8) ** 0.5 * \
                    (1 - abs(2 * (j / (len(ts) - 1)) - 1) ** 8) ** 0.5
                th[i, j] = (0.012 + 0.010 * ridge) * s * edge + 0.003 * s
        v, f = geo.pad(base, nrm, th, 0.004 * s)
        f = orient_outward(v, f, K + d * L * 0.6)
        self.add("Greave." + side, v, f, mat, rigid="shin." + side)

    def track_spikes(self, side, mat):
        fs = self.s * self.p["foot_scale"]
        Ak = self.j("foot." + side)
        for x, y in ((-0.028, -0.17), (0.028, -0.17), (0.0, -0.21), (-0.03, -0.12),
                     (0.03, -0.12)):
            b = A([Ak[0] + x * fs, Ak[1] + y * fs, 0.004 * fs])
            pts = [b + A([0, 0, 0.004]) * fs, b, b - A([0, 0, 0.016]) * fs]
            v, f = geo.tube(pts, A([0.010, 0.008, 0.001]) * fs, nseg=6, cap0='pole',
                            cap1='pole')
            self.add("TrackSpike." + side, v, f, mat, rigid="toe." + side if y < -0.15
                     else "foot." + side)

    # ------------------------------------------------------------------
    # cloth + props
    # ------------------------------------------------------------------
    def cape(self, mat, length=0.55, flare=1.0, tattered=False, spread=0.80, rows=14,
             cols=18, thickness=0.012, seed=1):
        s = self.s
        p = self.p
        zs = self.j("upper_arm.L")[2] + 0.030 * s
        zk = self.lv("knee")
        z_bot = zs - (zs - zk) * length / 0.55 * 0.92
        ax0 = p["sh_half"] * s + 0.05 * s
        ay0 = p["chest_d"] * s + 0.045 * s
        ax1 = ax0 + 0.08 * s * flare
        ay1 = ay0 + 0.12 * s * flare
        rng = np.random.RandomState(seed)
        jag = rng.uniform(0, 1, cols + 1)
        verts = []
        for i in range(rows + 1):
            v = i / rows
            for j in range(cols + 1):
                u = j / cols
                th = math.pi * (u - 0.5) * spread
                ax = ax0 + (ax1 - ax0) * v ** 1.3
                ay = ay0 + (ay1 - ay0) * v ** 1.1
                fold = 0.014 * s * math.sin(u * math.pi * 6) * v
                zb = z_bot
                if tattered:
                    zb = z_bot + (0.12 * s if j % 2 else 0.0) * (0.5 + 0.5 * jag[j]) + \
                        0.03 * s * jag[j]
                z = zs + (zb - zs) * v
                verts.append(((ax + fold) * math.sin(th), (ay + fold) * math.cos(th) + 0.01 * s,
                              z + (0.012 * s if i == 0 else 0.0)))
        faces = []
        W = cols + 1
        for i in range(rows):
            for j in range(cols):
                a = i * W + j
                faces.append((a, a + 1, a + W + 1, a + W))
        obj = self.add("Cape", verts, faces, mat, bones=["spine", "chest", "hips"],
                       overrides={"hips": 1.6, "spine": 1.4})
        sol = obj.modifiers.new("sol", 'SOLIDIFY')
        sol.thickness = thickness * s
        sol.offset = 0.0
        geo.apply_modifiers(obj)
        obj.data.shade_smooth()
        return obj

    def bat(self, mat, band_mat=None, length=1.0, barrel=0.05, spikes=0, spike_mat=None):
        """Bat rigid to hand.R along the hand's thumb axis (t)."""
        s = self.s
        W, f, n, t = self.hand_frame("R")
        hs = self.p["hand_scale"]
        grip = W + f * 0.050 * s * hs + n * 0.020 * s * hs
        knob = grip - t * 0.15 * s * hs
        L = length * s
        hr = 0.017 * s * hs
        br = barrel * s
        ks = [(-0.020 * s, 0.0), (-0.012 * s, 0.026 * s * hs), (0.0, 0.026 * s * hs),
              (0.012 * s, hr), (0.10 * s, hr * 1.05), (0.30 * L, br * 0.55), (0.45 * L, br * 0.88),
              (0.60 * L, br), (L - 0.06 * s, br), (L - 0.02 * s, br * 0.85), (L, 0.0)]
        pts = [knob + t * d for d, _ in ks]
        rad = [max(r, 1e-4) for _, r in ks]
        v, fc = geo.tube(pts[1:-1], rad[1:-1], nseg=16, cap0=pts[0], cap1=pts[-1], up=n)
        self.add("Bat", v, fc, mat, rigid="hand.R")
        if band_mat is not None:
            for k in (0.52, 0.70, 0.88):
                c = knob + t * (k * L)
                ring = [c + (n * math.cos(a) + f * math.sin(a)) * br * 1.02
                        for a in np.linspace(0, 2 * np.pi, 20, endpoint=False)]
                v, fc = geo.tube(ring, 0.014 * s, nseg=6, closed_path=True, up=t)
                self.add("BatBand", v, fc, band_mat, rigid="hand.R")
        for k in range(spikes):
            kk = 0.62 + 0.30 * (k // 4) / max(1, (spikes - 1) // 4)
            ang = (k % 4) * math.pi / 2 + (k // 4) * math.pi / 4
            c = knob + t * (kk * L)
            d = n * math.cos(ang) + f * math.sin(ang)
            sp = [c + d * br * 0.8, c + d * (br + 0.04 * s), c + d * (br + 0.085 * s)]
            v, fc = geo.tube(sp, A([0.022, 0.013, 0.002]) * s, nseg=7, cap0='pole', cap1='pole')
            self.add("BatSpike", v, fc, spike_mat or band_mat or mat, rigid="hand.R")

    def glow_seams(self, mat, z_list, front=True):
        """Glowing lines across the chest plate (Iron Slugger)."""
        s = self.s
        surf = geo.Surface([o for o in self.parts if o.name.startswith("ChestPlate")][-1])
        cw = self.p["chest_w"] * s
        for z in z_list:
            pts = []
            for uu in np.linspace(-0.75, 0.75, 11):
                hit, _ = surf.hit(A([uu * cw, -0.5, z]), A([0, -1.0, 0]))
                pts.append(hit + A([0, -0.004 * s, 0]))
            v, f = geo.tube(pts, 0.010 * s, nseg=6, cap0='pole', cap1='pole')
            self.add("Glow", v, f, mat, weights_from=self.torso_obj)

    # ------------------------------------------------------------------
    def extras(self):
        cfg = self.cfg
        m = self.m
        s = self.s
        kind = cfg.get("kit", "")
        if cfg.get("knee_pads"):
            for sd in "LR":
                self.knee_pad(sd, m["Gear"], size=cfg.get("knee_size", 1.0))
        if cfg.get("springs"):
            for sd in "LR":
                self.spring(sd, m["Metal"])
        if cfg.get("track_spikes"):
            for sd in "LR":
                self.track_spikes(sd, m["Metal"])
        if cfg.get("pauldrons"):
            pd = cfg["pauldrons"]
            for sd in "LR":
                self.pauldron(sd, m[pd.get("mat", "Metal")], size=pd.get("size", 1.0),
                              layers=pd.get("layers", 2), spikes=pd.get("spikes", 0),
                              spike_mat=m.get(pd.get("spike_mat", "")))
        if cfg.get("chest_plate"):
            cp = cfg["chest_plate"]
            self.torso_pad("ChestPlate", m[cp.get("mat", "Metal")], front=True,
                           segs=cp.get("segs", 2), thick=cp.get("thick", 0.024))
            if cp.get("back"):
                self.torso_pad("BackPlate", m[cp.get("mat", "Metal")], front=False,
                               segs=1, thick=cp.get("thick", 0.024) * 0.8)
            if cp.get("glow"):
                zc = self.lv("chest")
                self.glow_seams(m["Glow"], [zc + 0.02 * s, zc - 0.10 * s])
        if cfg.get("gauntlets"):
            for sd in "LR":
                self.gauntlet(sd, m[cfg["gauntlets"]])
        if cfg.get("greaves"):
            for sd in "LR":
                self.shin_plate(sd, m[cfg["greaves"]])
        if cfg.get("armband"):
            self.armband("L", m[cfg["armband"]])
        if cfg.get("cape"):
            cp = cfg["cape"]
            self.cape(m["Cloth"], length=cp.get("length", 0.55), flare=cp.get("flare", 1.0),
                      tattered=cp.get("tattered", False), rows=cp.get("rows", 14),
                      cols=cp.get("cols", 18))
        if cfg.get("bat"):
            b = cfg["bat"]
            self.bat(m["Bat"], m.get(b.get("band", "Metal")), length=b.get("length", 1.0),
                     barrel=b.get("barrel", 0.06), spikes=b.get("spikes", 0),
                     spike_mat=m.get(b.get("spike_mat", "")))
        return kind


def m_or(mats, name, fallback):
    return mats.get(name) or mats[fallback]


def apply_fixed_weights(parts):
    """Parts with obj["fixed"] = {bone: w} get the same blend on every vertex
    (rigid armour riding between two bones, e.g. pauldrons)."""
    for p in parts:
        fx = p.get("fixed")
        if not fx:
            continue
        w = json.loads(fx)
        n = len(p.data.vertices)
        for g in list(p.vertex_groups):
            p.vertex_groups.remove(g)
        for b, val in w.items():
            vg = p.vertex_groups.new(name=b)
            vg.add(list(range(n)), float(val), 'REPLACE')
