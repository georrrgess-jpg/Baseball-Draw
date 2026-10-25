"""Stylised "hero" defenders: proportions, build order and skin weights.

Bodies are clean quad meshes (see geo.py): parametric lofts for limbs,
torso and shoes, a mirrored box cage + Catmull-Clark for the pants, smooth
sphere grids projected onto soft implicit shapes for the head, hair, caps
and helmet, and thin projected decals (eyes, brows, mouth, numbers,
emblems) that copy the weights of the surface under them.

Head frame (``P``): origin at the eye line on the head axis, unit = head
height h (chin -> crown), x = character left, y = back (front is -y), z up.
"""
import numpy as np

import geo
from geo import A
import rig
import skin
from hero_head import HeadMixin
from hero_body import BodyMixin
from hero_wear import WearMixin

# s-units (multiplied by the global scale).  Big head (~1/5.6 of the height),
# short neck, broad shoulders, tapered waist, chunky hands and cleats.
HERO_BASE = dict(
    head=0.300, head_w=1.0,
    neck_len=0.055, neck_r=0.058,
    lumbar=0.08, spine_len=0.135, chest_len=0.24,
    sh_half=0.215, clav_z=-0.03,
    chest_w=0.184, chest_d=0.122, waist_w=0.128, waist_d=0.100,
    pelvis_w=0.150, pelvis_d=0.110, hip_half=0.098,
    upper_arm=0.28, forearm=0.255, hand=0.09,
    arm_r=0.057, forearm_r=0.050, wrist_r=0.031,
    thigh=0.375, shin=0.365, ankle=0.08, foot=0.27,
    thigh_r=0.095, knee_r=0.062, calf_r=0.062, ankle_r=0.034,
    a_pose=40.0, elbow_rest=6.0,
    hand_scale=1.32, foot_scale=1.10,
    muscle=1.0, belly=0.0,
)

# head-wear height above the crown (fraction of the head height)
TOP_EXTRA = {"cap": 0.075, "cap_back": 0.075, "visor": 0.10, "headband": 0.0,
             "catcher": 0.12}

FACE_DEFAULT = dict(
    width=1.0, jaw=0.6, jaw_w=1.0, chin=1.0, chin_w=1.0, cheek=1.0, brow=1.0,
    nose=1.0, nose_w=1.0, eye=1.0, eye_open=1.0, eye_tilt=0.0, brow_angle=0.3,
    brow_thick=1.0, mouth="smile", smile=0.5, smirk=0.0, mouth_w=1.0,
    lashes=False, ear=1.0, iris_look=0.0,
)


def hero_props(cfg):
    p = dict(HERO_BASE)
    p.update(cfg.get("body", {}))
    return p


def make_skeleton(cfg):
    p = hero_props(cfg)
    hw = cfg.get("headwear", "cap")
    extra = TOP_EXTRA.get(hw, 0.06) + cfg.get("top_extra", 0.0)
    sk1 = rig.Skeleton(dict(p, scale=1.0))
    o, h = sk1.head_frame()
    top = o.z + 0.53 * h + extra * h
    p["scale"] = cfg["height"] / top
    return rig.Skeleton(p)


class Hero(HeadMixin, BodyMixin, WearMixin):
    def __init__(self, cid, cfg, sk, mats, font):
        self.cid = cid
        self.cfg = cfg
        self.sk = sk
        self.p = sk.p
        self.s = sk.s
        self.m = mats
        self.font = font
        self.parts = []
        o, h = sk.head_frame()
        self.o = A(o)
        self.h = h
        self.f = dict(FACE_DEFAULT)
        self.f.update(cfg.get("face", {}))
        self.female = cfg.get("female", False)
        self.surf = {}

    def j(self, name, tail=False):
        return A(self.sk.tails[name] if tail else self.sk.heads[name])

    def lv(self, key):
        return self.sk.levels[key]

    def P(self, x, y, z):
        return self.o + A([x, y, z]) * self.h

    def add(self, name, verts, faces, mat, **kw):
        return geo.make_obj(name, verts, faces, mat, collect=self.parts, **kw)

    def add_decal(self, name, verts, faces, mat, **kw):
        # crisp edge between the decal top and its side walls
        return geo.make_obj(name, verts, faces, mat, collect=self.parts, sharp=38, **kw)

    # ------------------------------------------------------------------
    def build(self):
        cfg = self.cfg
        m = self.m
        hw = cfg.get("headwear", "cap")
        # head + face
        self.build_head()
        self.build_ears()
        self.build_nose()
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
        self.build_hair(cfg.get("hair_style", "short"), m["Hair"], hw)
        if hw in ("cap", "cap_back"):
            self.build_cap(yaw=180.0 if hw == "cap_back" else 0.0, emblem=cfg.get("emblem"))
        elif hw == "visor":
            self.build_visor(getattr(self, "bob_fn", None) or self.head_sdf(0.03))
        elif hw == "headband":
            self.build_headband()
        elif hw == "catcher":
            self.build_catcher_helmet()
        # body
        self.build_neck()
        self.build_torso()
        self.build_collar()
        gear = bool(cfg.get("gear"))
        self.build_vneck(placket=not gear)
        for sd in "LR":
            self.build_sleeve(sd)
            if cfg.get("undershirt") == "elbow":
                self.build_arm(sd, m["Undershirt"], 0.12, 1.10, cuff=True, name="ArmUpper." + sd)
                self.build_arm(sd, m["Skin"], 0.92, 2.0, cuff=False, name="Forearm." + sd)
            else:
                self.build_arm(sd, m["Undershirt"])
            if cfg.get("wristbands"):
                self.build_wristband(sd, m["Undershirt"])
        self.build_hand("R", m["Skin"])
        self.build_mitt("L", catcher=(cfg.get("mitt") == "catcher"))
        self.build_pants(knee_pants=gear)
        self.build_pant_stripes()
        self.build_belt()
        self.build_socks(stripes=not gear)
        self.build_shoes()
        self.build_numbers(front=not gear)
        if gear:
            self.build_chest_protector()
            self.build_shin_guards()
        return self.parts


def _sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def shoe_top(tab, x, y):
    """Height of the shoe upper's top surface above (x, y) (see build_shoes)."""
    x0, y0, fs, chunky, rows = tab
    ys = A([r[0] for r in rows])
    yr = np.clip((y - y0) / fs, ys[-1], ys[0])
    w = geo.interp(-ys, [r[1] for r in rows], [-yr], mono=True)[0] * chunky
    ht = geo.interp(-ys, [r[2] for r in rows], [-yr], mono=True)[0]
    z0 = 0.022
    zc, hz = (z0 + ht) / 2, (ht - z0) / 2
    e = 2.0 / 2.4
    c = min(abs(x - x0) / fs / w, 1.0) ** (1.0 / e)
    si = max(1.0 - c * c, 0.0) ** 0.5
    return (zc + hz * si ** e) * fs, fs


def axial_weights(obj, sk):
    """Weights that depend only on the position along the leg (not on the
    distance to the bone), shared by the pant leg below the knee and the sock
    under it: in any pose a sock point and the pant point radially outside it
    get the same blended bone matrix, so the tucked-in sock cannot poke out.
    The part of the sock inside the shoe follows the foot like the shoe."""
    import json
    cfg = json.loads(obj["axial"])
    me = obj.data
    n = len(me.vertices)
    P = np.empty(n * 3)
    me.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3)
    names = [g.name for g in obj.vertex_groups]
    W = np.zeros((n, len(names)))
    for v in me.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    sides = [cfg["side"]] * n if cfg["kind"] == "sock" else ["L" if x > 0 else "R" for x in P[:, 0]]
    for sd in "LR":
        idx = np.array([i for i in range(n) if sides[i] == sd], np.int64)
        if not len(idx):
            continue
        K = A(sk.heads["shin." + sd])
        Ak = A(sk.tails["shin." + sd])
        d = Ak - K
        u = (P[idx] - K) @ d / (d @ d)
        # thigh -> shin blend centred just above the knee joint
        wt = 1.0 - _sstep(-0.14, 0.02, u)
        wf = np.zeros(len(idx))
        if cfg["kind"] == "sock":
            m = np.ones(len(idx))
            for j, i in enumerate(idx):
                zt, fs = shoe_top(cfg["shoe"], P[i, 0], P[i, 1])
                wf[j] = 1.0 - _sstep(zt - 0.025 * fs, zt + 0.010 * fs, P[i, 2])
        else:
            um = cfg["u_mask"]
            m = _sstep(um - 0.30, um - 0.02, u)
        Ax = np.zeros((len(idx), len(names)))
        for b, w in (("thigh." + sd, wt * (1 - wf)), ("shin." + sd, (1 - wt) * (1 - wf)),
                     ("foot." + sd, wf)):
            if b not in names:
                if not np.any(w * m > 0):
                    continue
                obj.vertex_groups.new(name=b)
                names.append(b)
                W = np.hstack([W, np.zeros((n, 1))])
                Ax = np.hstack([Ax, np.zeros((len(idx), 1))])
            Ax[:, names.index(b)] += w
        W[idx] = W[idx] * (1 - m)[:, None] + Ax * m[:, None]
    # keep the 4 strongest, renormalise, rewrite the groups
    if W.shape[1] > 4:
        cut = np.argsort(-W, axis=1)[:, 4:]
        np.put_along_axis(W, cut, 0.0, axis=1)
    W[W < 0.005] = 0.0
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for j, b in enumerate(names):
        vg = obj.vertex_groups[b]
        vg.remove(list(range(n)))
        nz = np.nonzero(W[:, j] > 0)[0]
        for i in nz:
            vg.add([int(i)], float(W[i, j]), 'REPLACE')


def apply_weights(parts, sk):
    """Rigid / distance-based weights (axial for pant legs + socks), then copy
    weights onto decals."""
    by_name = {p.name: p for p in parts}
    later = []
    for p in parts:
        if p.get("weights_from"):
            later.append(p)
            continue
        skin.apply_weights(p, sk)
        if p.get("axial"):
            axial_weights(p, sk)
    for p in later:
        src = by_name.get(p["weights_from"])
        geo.transfer_weights(src, p)


def report(parts):
    tot = 0
    rows = []
    for p in parts:
        n = geo.tri_count(p)
        tot += n
        rows.append((n, p.name))
    rows.sort(reverse=True)
    return tot, rows
