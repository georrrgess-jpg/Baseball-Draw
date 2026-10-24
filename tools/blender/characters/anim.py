"""Animation clips (ASSET_SPEC 3.2) authored procedurally with the FK/IK pose
solver in rig.py and baked at 30 fps into Blender actions.

Every clip is a function ``clip(c, t) -> rig.Pose`` where ``c`` is a ``Ctx``
holding the character's skeleton/proportions and style.  Loops are built from
periodic functions so frame 0 == last frame exactly.
"""
import math
import numpy as np
from mathutils import Vector, Matrix, Quaternion

import rig
from rig import rx, ry, rz, body_rot, Pose

FPS = 60   # bake rate (0.35 s / 0.75 s clips are exact at 60 Hz, not at 30 Hz)


# ---------------------------------------------------------------------------
# interpolation helpers
# ---------------------------------------------------------------------------

def clamp01(x):
    return max(0.0, min(1.0, x))


def sstep(a, b, x):
    if b == a:
        return 1.0 if x >= b else 0.0
    t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def hermite(t, keys, loop=None):
    """Cubic Hermite through keys [(time, value)], finite-difference
    tangents; zero tangents at the ends unless ``loop`` (clip length)."""
    ks = [(float(k[0]), np.asarray(k[1], dtype=np.float64)) for k in keys]
    if loop:
        L = loop
        if abs(ks[-1][0] - L) < 1e-6:
            ks = ks[:-1]
        t = t % L
        ext = [(ks[-2][0] - L, ks[-2][1]), (ks[-1][0] - L, ks[-1][1])] + ks + \
              [(ks[0][0] + L, ks[0][1]), (ks[1 % len(ks)][0] + L, ks[1 % len(ks)][1])]
        ks2 = ext
        lo = 1
        hi = len(ks2) - 2
    else:
        ks2 = ks
        if t <= ks2[0][0]:
            return ks2[0][1].copy()
        if t >= ks2[-1][0]:
            return ks2[-1][1].copy()
        lo = 0
        hi = len(ks2) - 1
    i = lo
    while i < hi - 1 and t > ks2[i + 1][0]:
        i += 1
    t0, v0 = ks2[i]
    t1, v1 = ks2[i + 1]

    def tan(j):
        if j - 1 < 0 or j + 1 >= len(ks2):
            return np.zeros_like(ks2[j][1])
        if not loop and (j == 0 or j == len(ks2) - 1):
            return np.zeros_like(ks2[j][1])
        tp, vp = ks2[j - 1]
        tn, vn = ks2[j + 1]
        return (vn - vp) / (tn - tp)
    m0 = tan(i)
    m1 = tan(i + 1)
    h = t1 - t0
    u = (t - t0) / h if h > 1e-9 else 0.0
    h00 = 2 * u ** 3 - 3 * u ** 2 + 1
    h10 = u ** 3 - 2 * u ** 2 + u
    h01 = -2 * u ** 3 + 3 * u ** 2
    h11 = u ** 3 - u ** 2
    return h00 * v0 + h10 * h * m0 + h01 * v1 + h11 * h * m1


def K(t, keys, loop=None):
    v = hermite(t, keys, loop)
    return v if v.ndim else float(v)


def KV(t, keys, loop=None):
    return Vector(hermite(t, keys, loop))


def wave(t, L, cycles=1.0, phase=0.0):
    return math.sin(2 * math.pi * (cycles * t / L + phase))


# ---------------------------------------------------------------------------
# context
# ---------------------------------------------------------------------------

class Ctx:
    def __init__(self, sk, kind="defender", style=None):
        self.sk = sk
        self.s = sk.s
        self.kind = kind
        self.style = dict(heavy=0.0, bat=False, aggro=0.0, small=False)
        self.style.update(style or {})
        L = sk.levels
        self.L = L
        s = self.s
        self.S = {sd: sk.heads["upper_arm." + sd].copy() for sd in "LR"}
        self.l1 = sk.length["upper_arm.L"]
        self.l2 = sk.length["forearm.L"]
        self.la = self.l1 + self.l2
        self.leg = sk.length["thigh.L"] + sk.length["shin.L"]
        self.ank = {sd: sk.heads["foot." + sd].copy() for sd in "LR"}
        self.ball = {sd: sk.heads["toe." + sd].copy() for sd in "LR"}
        self.hipj = {sd: sk.heads["thigh." + sd].copy() for sd in "LR"}
        self.fx = abs(self.ball["L"].x)
        self.fy = self.ball["L"].y
        self.ho, self.hh = sk.head_frame()
        self.chest_c = Vector((0, 0, L["chest"] + 0.12 * s))
        # hand frames (rest) for orientation helpers
        self.t_rest = {}
        for sd in "LR":
            M = sk.rest["hand." + sd].to_3x3()
            f = M.col[1]
            n = sk.palm_rest[sd]
            t = Vector((0, -1, 0))
            t = t - f * t.dot(f) - n * t.dot(n)
            t.normalize()
            self.t_rest[sd] = (n.copy(), f.copy(), t)

    def v(self, x, y, z):
        return Vector((x, y, z)) * self.s

    def new(self):
        return Pose(self.sk)

    # torso ----------------------------------------------------------------
    def torso(self, P, hips=(0, 0, 0), hips_rot=(0, 0, 0), spine=(0, 0, 0),
              chest=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), sh_L=None, sh_R=None):
        P.hips_off = Vector(hips) * self.s
        P.rot["hips"] = body_rot(*hips_rot)
        P.rot["spine"] = body_rot(*spine)
        P.rot["chest"] = body_rot(*chest)
        P.rot["neck"] = body_rot(*neck)
        P.rot["head"] = body_rot(*head)
        if sh_L:
            P.rot["shoulder.L"] = body_rot(*sh_L)
        if sh_R:
            P.rot["shoulder.R"] = body_rot(*sh_R)

    # legs ------------------------------------------------------------------
    def plant(self, P, side, x=None, y=None, yaw=0.0, heel=0.0, toe=0.0, z=0.0,
              knee_out=0.12, knee_yaw=None):
        """Foot on the ground: (x, y) = ball-of-foot position (world, metres
        already scaled), heel = heel-raise angle about the ball, toe = toes
        raised about the heel (heel strike)."""
        s = self.s
        sx = 1 if side == "L" else -1
        if x is None:
            x = self.ball[side].x
        if y is None:
            y = self.ball[side].y
        ball_r = self.ball[side]
        ank_r = self.ank[side]
        bj = Vector((x, y, ball_r.z + z))
        Ry = rz(yaw)
        if toe > 0:
            heel_r = Vector((ank_r.x, ank_r.y + 0.065 * s * self.sk.p["foot_scale"], 0.012 * s))
            heel_w = bj + Ry @ (heel_r - ball_r)
            R = Ry @ rx(-toe)
            ankle = heel_w + R @ (ank_r - heel_r)
            toe_R = R
        else:
            R = Ry @ rx(heel)
            ankle = bj + R @ (ank_r - ball_r)
            toe_R = Ry
        ky = yaw if knee_yaw is None else knee_yaw
        pole = rz(ky) @ Vector((sx * knee_out, -1.0, 0.0))
        P.leg[side] = dict(ankle=ankle, pole=pole, foot=R, toe=toe_R)
        return ankle

    def free_foot(self, P, side, ankle, pitch=0.0, yaw=0.0, knee_out=0.12, pole=None,
                  toe_bend=0.0):
        sx = 1 if side == "L" else -1
        R = rz(yaw) @ rx(pitch)
        if pole is None:
            pole = rz(yaw) @ Vector((sx * knee_out, -1.0, 0.0))
        P.leg[side] = dict(ankle=Vector(ankle), pole=pole, foot=R, toe=R @ rx(toe_bend))

    def ankle_of(self, side, x, y, yaw=0.0, heel=0.0, z=0.0):
        ball_r = self.ball[side]
        ank_r = self.ank[side]
        bj = Vector((x, y, ball_r.z + z))
        return bj + rz(yaw) @ rx(heel) @ (ank_r - ball_r)

    # arms ------------------------------------------------------------------
    def arm(self, P, side, target, pole=(0, 1, -0.3), space="chest", fingers=None,
            palm=None, wrist=None):
        spec = dict(target=Vector(target), pole=Vector(pole), space=space)
        if fingers is not None:
            spec["fingers"] = Vector(fingers).normalized()
            spec["palm"] = Vector(palm).normalized()
        if wrist is not None:
            spec["wrist"] = wrist
        P.arm[side] = spec

    def hang(self, P, side, swing=0.0, out=8.0, bend=15.0, pole=(0, 1, -0.2),
             fingers=None, palm=None, twist=0.0):
        """Relaxed arm: swing = forward angle (deg), out = abduction."""
        sx = 1 if side == "L" else -1
        d = rx(-swing) @ ry(-sx * out) @ Vector((0, 0, -1))
        b = math.radians(bend)
        D = math.sqrt(self.l1 ** 2 + self.l2 ** 2 + 2 * self.l1 * self.l2 * math.cos(b))
        tgt = self.S[side] + d * D
        if fingers is None and twist:
            self.arm(P, side, tgt, pole, wrist=ry(twist))
        else:
            self.arm(P, side, tgt, pole, fingers=fingers, palm=palm)
        return tgt

    def bat_grip(self, side, bat_dir, fingers_hint):
        """(fingers, palm) so that the hand's thumb axis (bat axis) points
        along bat_dir."""
        n0, f0, t0 = self.t_rest[side]
        sigma = 1.0 if t0.dot(n0.cross(f0)) > 0 else -1.0
        b = Vector(bat_dir).normalized()
        f = Vector(fingers_hint)
        f = (f - b * f.dot(b)).normalized()
        p = sigma * f.cross(b)
        return f, p


# ---------------------------------------------------------------------------
# reusable poses
# ---------------------------------------------------------------------------

def base_stand(c, P, width=1.25, toe_out=8.0, hips_dz=-0.012, shift=0.0):
    x = c.fx * width
    c.plant(P, "L", x + shift * c.s, c.fy, yaw=toe_out)
    c.plant(P, "R", -x + shift * c.s, c.fy, yaw=-toe_out)


def defender_hands_idle(c, P, t, L):
    br = wave(t, L, 1, 0.1)
    c.hang(P, "R", swing=4 + 2 * br, out=10, bend=18)
    # glove hand: relaxed, a little forward and out (mitt hangs clear of leg)
    c.hang(P, "L", swing=8 + 2 * br, out=16, bend=28)


def enemy_hands_idle(c, P, t, L, menace=1.0):
    br = wave(t, L, 1, 0.1)
    c.hang(P, "R", swing=10 + 3 * br, out=14 * menace, bend=35)
    c.hang(P, "L", swing=10 + 3 * br, out=14 * menace, bend=35)


# ---------------------------------------------------------------------------
# clips
# ---------------------------------------------------------------------------

def clip_idle(c, t):
    L = 2.0
    P = c.new()
    br = wave(t, L)                 # breathing
    sw = wave(t, L, 1, 0.25)        # weight shift
    heavy = c.style["heavy"]
    hunch = 6 + 8 * heavy if c.kind != "defender" else 0
    c.torso(P, hips=(0.012 * sw, 0.0, -0.018 + 0.004 * br),
            hips_rot=(2, -2.0 * sw, 2.5 * sw),
            spine=(1 + hunch * 0.4, 1.0 * sw, -1.0 * sw),
            chest=(-1.5 * br + hunch * 0.6, 0.5 * sw, -1.5 * sw),
            neck=(-hunch * 0.5, 0, 2 * wave(t, L, 1, 0.6)),
            head=(-hunch * 0.4 + 1.5 * br, 0, 3 * wave(t, L, 1, 0.6)),
            sh_L=(0, 0, 0), sh_R=(0, 0, 0))
    base_stand(c, P, width=1.3 + 0.25 * heavy)
    if c.kind == "defender":
        defender_hands_idle(c, P, t, L)
    else:
        if c.style["bat"]:
            bat_rest_pose(c, P, t, L)
        else:
            enemy_hands_idle(c, P, t, L)
    return P


def bat_rest_pose(c, P, t, L, bounce=0.0):
    """Bat resting on the right shoulder, left hand low on the handle."""
    s = c.s
    br = wave(t, L) if L else 0.0
    grip = c.S["R"] + c.v(0.06, -0.20, -0.20 + 0.01 * br + bounce)
    bat_dir = Vector((-0.25, 0.55, 0.80)).normalized()
    f, p = c.bat_grip("R", bat_dir, Vector((0.8, -0.2, 0.0)))
    c.arm(P, "R", grip, pole=(-0.6, 0.6, -0.5), fingers=f, palm=p)
    lg = grip - bat_dir * 0.10 * s * c.sk.p["hand_scale"]
    f2, p2 = c.bat_grip("L", bat_dir, Vector((-0.8, -0.2, 0.0)))
    c.arm(P, "L", lg, pole=(0.5, 0.3, -1.0), fingers=f2, palm=p2)


# --- locomotion -------------------------------------------------------------

def _loco(c, t, L, stance, d_st, lift, lean, bob, arm_amp, arm_bend, kick,
          width=1.05, heavy=0.0, sprint=False):
    """Generic in-place locomotion cycle.  Left foot contacts at t=0."""
    s = c.s
    P = c.new()
    ph = (t / L) % 1.0
    # hips vertical: lowest at mid-stance of each foot (2 per cycle)
    ms = stance * 0.5
    zb = -bob * math.cos(4 * math.pi * (ph - ms))
    hip_drop = -(0.03 + 0.06 * (d_st / s / 0.66)) if not sprint else -0.10
    hip_drop -= 0.03 * heavy
    yaw = -9 * math.cos(2 * math.pi * ph) * (1 + 0.3 * heavy)
    roll = 4 * heavy * math.sin(2 * math.pi * (ph - ms))
    c.torso(P, hips=(0.012 * heavy * math.sin(2 * math.pi * (ph - ms)), -0.01, hip_drop + zb / s),
            hips_rot=(lean * 0.4, -roll, yaw),
            spine=(lean * 0.3, roll * 0.5, -yaw * 0.6),
            chest=(lean * 0.3, roll * 0.4, -yaw * 0.9),
            neck=(-lean * 0.4, 0, yaw * 0.3),
            head=(-lean * 0.35 + 2 * math.sin(4 * math.pi * ph), -roll * 0.5, yaw * 0.4))
    for side, off in (("L", 0.0), ("R", 0.5)):
        u = (ph + off) % 1.0
        sx = 1 if side == "L" else -1
        x = c.fx * width * sx
        fy_off = c.ball[side].y - c.ank[side].y   # ball relative to ankle
        if u < stance:
            k = u / stance
            ya = -d_st / 2 + d_st * k            # ankle y
            heel = 55 * sstep(0.55, 1.0, k) * (0.7 if heavy else 1.0)
            toe = 12 * (1 - sstep(0.0, 0.18, k)) if not sprint else 0.0
            # convert ankle-y to ball-y for plant
            c.plant(P, side, x, ya + fy_off, yaw=sx * 4, heel=heel, toe=toe)
        else:
            k = (u - stance) / (1 - stance)
            a0 = c.ankle_of(side, x, d_st / 2 + fy_off, yaw=sx * 4, heel=55 * (0.7 if heavy else 1.0))
            # end of swing = contact pose (toe up 12 deg)
            P2 = c.new()
            a1 = c.plant(P2, side, x, -d_st / 2 + fy_off, yaw=sx * 4,
                         toe=12 if not sprint else 0.0)
            hz = c.ank[side].z
            keys = [(0.0, a0),
                    (0.30, Vector((x, d_st / 2 + 0.05 * s, hz + kick * 0.85))),
                    (0.62, Vector((x, -0.05 * s, hz + lift))),
                    (0.85, Vector((x, -d_st / 2 - 0.06 * s, hz + lift * 0.35))),
                    (1.0, a1)]
            ank = KV(k, keys)
            pitch = K(k, [(0, -40 if not heavy else -30), (0.3, -55), (0.62, -10),
                          (0.85, 8), (1.0, 12 if not sprint else 0.0)])
            c.free_foot(P, side, ank, pitch=pitch, yaw=sx * 4)
    # arms: opposite to legs.  Right arm forward when left foot forward (ph=0)
    for side, off in (("L", 0.5), ("R", 0.0)):
        sx = 1 if side == "L" else -1
        sw = math.cos(2 * math.pi * (ph + off))  # +1 = forward
        S = c.S[side]
        if c.kind == "defender" and side == "L" and not sprint:
            amp = arm_amp * 0.8
        else:
            amp = arm_amp
        fwd = Vector((sx * -0.02, -0.26, 0.06)) * s
        back = Vector((sx * 0.07, 0.20, -0.22)) * s
        k = 0.5 + 0.5 * sw * amp
        tgt = S + back.lerp(fwd, k) + Vector((0, 0, -0.33 * s * (1 - arm_bend)))
        tgt.z = min(tgt.z, S.z + 0.02 * s)
        tgt += Vector((sx * 0.03 * heavy * s, 0, 0))
        c.arm(P, side, tgt, pole=(sx * 0.35, 1.0, -0.45))
    return P


def clip_run(c, t):
    h = c.style["heavy"]
    s = c.s
    return _loco(c, t, 0.70, stance=0.36, d_st=0.66 * s, lift=0.30 * s, lean=12 + 4 * h,
                 bob=0.022 * s, arm_amp=1.0, arm_bend=0.15, kick=0.36 * s, heavy=h)


def clip_sprint(c, t):
    s = c.s
    return _loco(c, t, 0.55, stance=0.32, d_st=0.74 * s, lift=0.36 * s, lean=26,
                 bob=0.02 * s, arm_amp=1.15, arm_bend=0.05, kick=0.42 * s, sprint=True,
                 heavy=c.style["heavy"] * 0.5)


def clip_walk(c, t):
    """Relaxed walk (defenders/enemies) or heavy stomp (heavy style)."""
    s = c.s
    L = 1.0
    h = c.style["heavy"]
    P = c.new()
    ph = (t / L) % 1.0
    stance = 0.62
    d_st = (0.50 + 0.06 * h) * s
    # hips: highest at mid-stance in walking (inverted pendulum), stomp drop
    zb = 0.012 * math.cos(4 * math.pi * (ph - stance * 0.5)) * (1 - 0.5 * h)
    stomp = 0.0
    if h > 0:
        for c0 in (0.0, 0.5):
            dt = ((ph - c0 + 0.5) % 1.0) - 0.5
            stomp += -0.035 * math.exp(-((dt - 0.05) / 0.05) ** 2)
    yaw = -6 * math.cos(2 * math.pi * ph) * (1 + 0.6 * h)
    roll = (3 + 6 * h) * math.sin(2 * math.pi * (ph - 0.25))
    lean = 3 + (10 if c.kind != "defender" else 0) * (0.4 + h)
    c.torso(P, hips=(0.02 * h * math.sin(2 * math.pi * (ph - 0.25)), 0, -0.035 - 0.03 * h + zb + stomp),
            hips_rot=(lean * 0.3, -roll, yaw),
            spine=(lean * 0.3, roll * 0.6, -yaw * 0.5),
            chest=(lean * 0.4, roll * 0.5, -yaw * 0.9),
            neck=(-lean * 0.4 - 5 * h, 0, yaw * 0.3),
            head=(-lean * 0.3 - 4 * h, -roll * 0.6, yaw * 0.3))
    for side, off in (("L", 0.0), ("R", 0.5)):
        u = (ph + off) % 1.0
        sx = 1 if side == "L" else -1
        x = c.fx * (1.1 + 0.5 * h) * sx
        fy_off = c.ball[side].y - c.ank[side].y
        if u < stance:
            k = u / stance
            ya = -d_st / 2 + d_st * k
            heel = 35 * sstep(0.62, 1.0, k)
            toe = 18 * (1 - sstep(0.0, 0.16, k)) * (1 - 0.6 * h)
            c.plant(P, side, x, ya + fy_off, yaw=sx * 6, heel=heel, toe=toe)
        else:
            k = (u - stance) / (1 - stance)
            a0 = c.ankle_of(side, x, d_st / 2 + fy_off, yaw=sx * 6, heel=35)
            P2 = c.new()
            a1 = c.plant(P2, side, x, -d_st / 2 + fy_off, yaw=sx * 6,
                         toe=18 * (1 - 0.6 * h))
            hz = c.ank[side].z
            lift = (0.09 + 0.12 * h) * s
            keys = [(0.0, a0),
                    (0.35, Vector((x, d_st * 0.22, hz + lift * 0.8))),
                    (0.65, Vector((x, -d_st * 0.25, hz + lift))),
                    (1.0, a1)]
            ank = KV(k, keys)
            pitch = K(k, [(0, -35), (0.35, -20), (0.65, 5 + 8 * h), (1.0, 18 * (1 - 0.6 * h))])
            c.free_foot(P, side, ank, pitch=pitch, yaw=sx * 6)
    for side, off in (("L", 0.5), ("R", 0.0)):
        sx = 1 if side == "L" else -1
        sw = math.cos(2 * math.pi * (ph + off))
        if c.style["bat"] and side in ("L", "R") and h > 0:
            pass
        c.hang(P, side, swing=16 * sw * (1 + 0.3 * h) + 4, out=10 + 10 * h,
               bend=18 + 10 * max(sw, 0) + 20 * h)
    if c.style["bat"]:
        bat_rest_pose(c, P, t, 0, bounce=0.01 * math.cos(4 * math.pi * ph))
    return P


# --- reactions ------------------------------------------------------------------

def clip_hit(c, t):
    s = c.s
    P = c.new()
    a = K(t, [(0, 0), (0.07, 1.0), (0.16, 0.75), (0.35, 0.0)])
    b = K(t, [(0, 0), (0.05, 0.4), (0.12, 1.0), (0.24, 0.3), (0.35, 0.0)])
    c.torso(P, hips=(0, 0.035 * a, -0.02 - 0.02 * a),
            hips_rot=(-6 * a, 0, 5 * a),
            spine=(-10 * a, 2 * a, 4 * a),
            chest=(-12 * a, 3 * a, 6 * a),
            neck=(-8 * b, 0, -4 * b),
            head=(-14 * b, 6 * b, -6 * b))
    base_stand(c, P, width=1.3)
    if c.style["bat"]:
        bat_rest_pose(c, P, t, 0)
        return P
    up = a
    c.hang(P, "R", swing=8 + 35 * up, out=14 + 20 * up, bend=25 + 50 * up)
    c.hang(P, "L", swing=10 + 30 * up, out=16 + 22 * up, bend=30 + 45 * up)
    return P


def clip_stunned(c, t):
    s = c.s
    L = 1.2
    P = c.new()
    w1 = wave(t, L)
    w2 = wave(t, L, 1, 0.25)
    c.torso(P, hips=(0.03 * w1, 0.02 * w2, -0.05),
            hips_rot=(4 + 3 * w2, -5 * w1, 6 * w1),
            spine=(6, 4 * w1, -4 * w1),
            chest=(6 + 3 * w2, 6 * w1, -5 * w1),
            neck=(8, -6 * w1, 6 * w2),
            head=(6 + 6 * w2, -12 * w1, 8 * w2))
    c.plant(P, "L", c.fx * 1.45, c.fy - 0.03 * s, yaw=14)
    c.plant(P, "R", -c.fx * 1.45, c.fy + 0.04 * s, yaw=-18)
    # hand to head (head space: side of forehead)
    tgt = Vector(c.ho) + c.v(-0.05, -0.06, 0.10)
    hz = c.hh
    tgt = Vector(c.ho) + Vector((-0.10 * hz / 0.28, -0.12 * hz / 0.28, 0.06 * hz / 0.28))
    tgt = tgt + Vector((-0.05, 0.0, -0.03)) * s
    fingers = Vector((0.5, 0.3, 0.8))
    palm = Vector((0.6, 0.6, -0.3))
    c.arm(P, "R", tgt, pole=(-1, 0.2, -0.4), space="head", fingers=fingers, palm=palm)
    c.hang(P, "L", swing=6 + 8 * w2, out=16 + 5 * w1, bend=25)
    if c.style["bat"]:
        c.hang(P, "L", swing=6 + 8 * w2, out=18 + 5 * w1, bend=25)
    return P


def clip_defeat(c, t):
    """Knocked down, ends lying on the back."""
    s = c.s
    P = c.new()
    L = c.L
    lie_z = (c.sk.p["pelvis_d"] * 0.95) * s - (L["pelvis"] - L["hip"]) * 0.0
    # hips offset relative to rest pelvis height
    dz_end = lie_z - L["pelvis"]
    y_end = 0.55 * s
    hz = K(t, [(0, -0.02 * s), (0.18, -0.06 * s), (0.42, -0.30 * s), (0.66, dz_end + 0.02 * s),
               (0.74, dz_end + 0.045 * s), (0.84, dz_end), (1.2, dz_end)])
    hy = K(t, [(0, 0), (0.18, 0.10 * s), (0.42, 0.30 * s), (0.66, y_end), (1.2, y_end)])
    pitch = K(t, [(0, 0), (0.18, -12), (0.42, -40), (0.66, -84), (0.74, -80), (0.84, -88),
                  (1.2, -88)])
    tw = K(t, [(0, 0), (0.2, 10), (0.6, 4), (1.2, 2)])
    P.hips_off = Vector((0, hy, hz))
    P.rot["hips"] = body_rot(pitch, 0, tw)
    sp = K(t, [(0, 0), (0.15, -10), (0.4, -6), (0.66, 4), (0.74, 8), (0.9, 0), (1.2, 0)])
    P.rot["spine"] = body_rot(sp, 0, -tw * 0.5)
    P.rot["chest"] = body_rot(sp, 3, -tw * 0.3)
    nk = K(t, [(0, 0), (0.15, -20), (0.45, 10), (0.66, 25), (0.74, 30), (0.9, 18), (1.2, 18)])
    P.rot["neck"] = body_rot(nk, 0, 0)
    P.rot["head"] = body_rot(nk * 0.6, K(t, [(0, 0), (0.9, 0), (1.2, 12)]), K(t, [(0, 0), (0.9, 5), (1.2, 18)]))
    # legs: first planted, then thrown up, end lying with knees slightly bent
    # foot targets in world.
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        if t < 0.30:
            k = sstep(0.12, 0.30, t)
            heel = 30 * k
            c.plant(P, side, c.fx * 1.3 * sx, c.fy + (0.03 if side == "L" else -0.06) * s,
                    yaw=sx * 10, heel=heel)
        else:
            P0 = c.new()
            a0 = c.ankle_of(side, c.fx * 1.3 * sx, c.fy + (0.03 if side == "L" else -0.06) * s,
                            yaw=sx * 10, heel=30)
            # final: lying, ankle on ground in front of hips (toward -Y)
            knee_bend = 0.88 if side == "L" else 0.80
            a_end = Vector((c.fx * (1.6 if side == "L" else 1.2) * sx,
                            y_end - c.leg * knee_bend, c.sk.p["ankle_r"] * s * 1.3 + 0.03 * s))
            a_air = Vector((c.fx * 1.4 * sx, 0.05 * s, 0.45 * s))
            ank = KV(t, [(0.30, a0), (0.55, a_air + Vector((0, -0.05 * s * sx, 0.05 * s))),
                         (0.74, a_end + Vector((0, 0, 0.10 * s))), (0.88, a_end), (1.2, a_end)])
            pitch_f = K(t, [(0.3, 30), (0.6, -40), (0.8, -75), (1.2, -80)])
            pole = Vector((sx * 0.3, -0.4, 1.0))
            if t < 0.45:
                pole = Vector((sx * 0.2, -1.0, 0.2)).lerp(pole, sstep(0.3, 0.45, t))
            c.free_foot(P, side, ank, pitch=pitch_f, yaw=sx * 12, pole=pole)
    # arms fly up, end spread on the ground
    k = sstep(0.0, 0.25, t)
    k2 = sstep(0.55, 0.9, t)
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        if k2 <= 0:
            c.hang(P, side, swing=20 + 50 * k, out=20 + 40 * k, bend=40 + 30 * k)
        else:
            sw = lerp(70, 160, k2)
            c.hang(P, side, swing=sw, out=lerp(60, 70, k2), bend=lerp(70, 25, k2),
                   pole=(sx * 0.2, 1.0, 0.6))
    if c.style["bat"]:
        pass
    return P


def clip_celebrate(c, t):
    s = c.s
    L = 1.0
    P = c.new()
    ph = t / L
    # hop: crouch -> jump -> land (loop)
    hz = K(t, [(0, -0.05), (0.18, -0.10), (0.30, 0.02), (0.42, 0.10), (0.55, 0.03),
               (0.68, -0.10), (0.85, -0.06), (1.0, -0.05)], loop=L)
    air = max(0.0, hz - (-0.03))
    c.torso(P, hips=(0, 0, hz), hips_rot=(4, 0, 0),
            spine=(K(t, [(0, 4), (0.42, -4), (0.7, 6), (1, 4)], loop=L), 0, 0),
            chest=(K(t, [(0, 2), (0.42, -8), (0.7, 4), (1, 2)], loop=L), 0, -6),
            neck=(-4, 0, 0), head=(K(t, [(0, 0), (0.42, -12), (0.7, 0), (1, 0)], loop=L), 0, 6))
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        if air > 0:
            a = c.ankle_of(side, c.fx * 1.25 * sx, c.fy, yaw=sx * 8)
            a = a + Vector((0, 0.02 * s, air * s * 0.75))
            c.free_foot(P, side, a, pitch=-10 * min(1, air / 0.05), yaw=sx * 8)
        else:
            c.plant(P, side, c.fx * 1.25 * sx, c.fy, yaw=sx * 8)
    # right fist pump overhead, left arm out
    pump = K(t, [(0, 0.2), (0.25, 0.35), (0.42, 1.0), (0.6, 0.8), (0.8, 0.25), (1.0, 0.2)], loop=L)
    S = c.S["R"]
    low = S + c.v(-0.05, -0.12, -0.20)
    high = S + c.v(-0.04, -0.08, 0.52)
    tgt = low.lerp(high, pump)
    c.arm(P, "R", tgt, pole=(-1, 0.4, -0.5),
          fingers=Vector((0, -0.4, 1)).lerp(Vector((0, -0.2, 1)), pump),
          palm=Vector((0.8, -0.3, 0)))
    if c.style["bat"]:
        bat_up = c.S["L"] + c.v(0.10, -0.10, 0.25 + 0.2 * pump)
        c.arm(P, "L", bat_up, pole=(1, 0.3, -0.6))
    else:
        c.hang(P, "L", swing=30 + 15 * pump, out=35 + 20 * pump, bend=60)
    return P


# --- defender-only ------------------------------------------------------------

def ready_pose(c, P, t=0.0, bounce=0.0, width=2.1, depth=0.13):
    s = c.s
    c.torso(P, hips=(0, 0.045, -depth + bounce), hips_rot=(18, 0, 0),
            spine=(8, 0, 0), chest=(6, 0, 0), neck=(-12, 0, 0), head=(-14, 0, 0))
    c.plant(P, "L", c.fx * width, c.fy - 0.02 * s, yaw=14, knee_out=0.35)
    c.plant(P, "R", -c.fx * width, c.fy + 0.02 * s, yaw=-14, knee_out=0.35)
    glove_ready(c, P, bounce)


# ready-pose hand targets (chest space, relative to the shoulder joints)
READY_GL = dict(pos=(-0.12, -0.30, -0.42), fingers=(-0.12, -0.93, -0.36), palm=(0.1, -0.36, 0.93))
READY_R = dict(pos=(0.15, -0.30, -0.42), fingers=(0.12, -0.93, -0.36), palm=(0.9, -0.15, 0.4))


def glove_ready(c, P, bounce=0.0):
    """Glove low in front of the knees, pocket open toward the ball."""
    SL = c.S["L"]
    SR = c.S["R"]
    c.arm(P, "L", SL + c.v(*READY_GL["pos"]), pole=(0.9, 0.5, -0.6),
          fingers=Vector(READY_GL["fingers"]), palm=Vector(READY_GL["palm"]))
    c.arm(P, "R", SR + c.v(*READY_R["pos"]), pole=(-0.9, 0.5, -0.6),
          fingers=Vector(READY_R["fingers"]), palm=Vector(READY_R["palm"]))


def clip_ready(c, t):
    L = 1.6
    P = c.new()
    b = 0.010 * math.sin(2 * math.pi * 2 * t / L)
    ready_pose(c, P, t, bounce=b)
    P.rot["head"] = body_rot(-14, 0, 3 * wave(t, L))
    return P


def _throw_core(c, P, t, keys_t, stride_y=0.30, stride_lift=0.16, jump=0.0):
    """Overhand throw toward -Y.  keys_t = dict of key times:
    start, gather, cock, release, follow, settle, end"""
    s = c.s
    T0, Tg, Tc, Tr, Tf, Ts, Te = (keys_t[k] for k in
                                  ("start", "gather", "cock", "release", "follow", "settle", "end"))
    # torso yaw (- = closed/turned right), pitch forward
    yaw_h = K(t, [(T0, 0), (Tg, -30), (Tc, -55), (Tr, 5), (Tf, 30), (Ts, 10), (Te, 0)])
    yaw_c = K(t, [(T0, 0), (Tg, -25), (Tc, -45), (Tr, 18), (Tf, 30), (Ts, 8), (Te, 0)])
    fwd = K(t, [(T0, 18), (Tg, 6), (Tc, -4), (Tr, 16), (Tf, 32), (Ts, 20), (Te, 18)])
    hz = K(t, [(T0, -0.13), (Tg, -0.10), (Tc, -0.11), (Tr, -0.13 + jump), (Tf, -0.15), (Ts, -0.14),
               (Te, -0.13)])
    hy = K(t, [(T0, 0.045), (Tg, 0.05), (Tc, 0.04), (Tr, -0.06), (Tf, -0.10), (Ts, -0.02),
               (Te, 0.045)])
    hx = K(t, [(T0, 0), (Tg, -0.03), (Tc, -0.05), (Tr, 0.02), (Tf, 0.04), (Ts, 0.0), (Te, 0)])
    c.torso(P, hips=(hx, hy, hz), hips_rot=(fwd * 0.5, K(t, [(T0, 0), (Tc, -6), (Tr, 4), (Te, 0)]), yaw_h),
            spine=(fwd * 0.25, 0, (yaw_c - yaw_h) * 0.4),
            chest=(fwd * 0.3, K(t, [(T0, 0), (Tc, -8), (Tr, 6), (Te, 0)]), (yaw_c - yaw_h) * 0.6),
            neck=(-fwd * 0.45, 0, -yaw_c * 0.45),
            head=(-fwd * 0.4, 0, -yaw_c * 0.5))
    # feet: right foot (back) pivots, left foot strides forward
    wR = 2.0
    rx_ = -c.fx * wR
    c.plant(P, "R", rx_, c.fy + 0.02 * s,
            yaw=K(t, [(T0, -14), (Tc, -40), (Tr, -30), (Tf, -10), (Te, -14)]),
            heel=K(t, [(T0, 0), (Tc, 0), (Tr, 25), (Tf, 50), (Ts, 15), (Te, 0)]),
            knee_out=0.35, knee_yaw=K(t, [(T0, -14), (Tc, -45), (Tr, 10), (Te, -14)]))
    lx = c.fx * 2.1
    ly_ready = c.fy - 0.02 * s
    ly_str = ly_ready - stride_y * s
    if t <= Tg:
        c.plant(P, "L", lx, ly_ready, yaw=14, knee_out=0.35)
    elif t < Tc + (Tr - Tc) * 0.35:
        k = (t - Tg) / (Tc + (Tr - Tc) * 0.35 - Tg)
        a0 = c.ankle_of("L", lx, ly_ready, yaw=14)
        a1 = c.ankle_of("L", lx - 0.03 * s, ly_str, yaw=-10)
        mid = a0.lerp(a1, 0.5) + Vector((0.04 * s, 0, stride_lift * s))
        ank = KV(k, [(0, a0), (0.5, mid), (1.0, a1)])
        c.free_foot(P, "L", ank, pitch=K(k, [(0, 0), (0.5, -10), (1.0, 0)]),
                    yaw=K(k, [(0, 14), (1, -10)]), knee_out=0.3)
    elif t < Ts:
        c.plant(P, "L", lx - 0.03 * s, ly_str, yaw=-10, knee_out=0.25)
    else:
        k = sstep(Ts, Te, t)
        a0 = c.ankle_of("L", lx - 0.03 * s, ly_str, yaw=-10)
        a1 = c.ankle_of("L", lx, ly_ready, yaw=14)
        if k >= 0.999:
            c.plant(P, "L", lx, ly_ready, yaw=14, knee_out=0.35)
        else:
            mid = a0.lerp(a1, 0.5) + Vector((0, 0, 0.08 * s))
            ank = KV(k, [(0, a0), (0.5, mid), (1.0, a1)])
            c.free_foot(P, "L", ank, pitch=0, yaw=lerp(-10, 14, k), knee_out=0.3)
    # throwing arm (chest space): key positions relative to right shoulder
    S = c.S["R"]
    la = c.la
    ready_R = None
    keysR = [
        (T0, S + c.v(*READY_R["pos"])),
        (Tg, S + c.v(0.13, -0.24, -0.12)),          # ball at chest with glove
        (Tc - (Tc - Tg) * 0.4, S + c.v(-0.12, 0.14, -0.10)),  # arm swings down/back
        (Tc, S + c.v(-0.14, 0.20, 0.22)),            # cocked: hand up behind head
        (Tr, S + c.v(0.02, -0.30, 0.40)),            # release: high and forward
        (Tf, S + c.v(0.30, -0.36, -0.28)),           # across body
        (Ts, S + c.v(0.22, -0.30, -0.34)),
        (Te, S + c.v(*READY_R["pos"])),
    ]
    tgt = KV(t, keysR)
    pole = KV(t, [(T0, (-0.9, 0.5, -0.6)), (Tg, (-1, 0.3, -0.6)), (Tc, (-1, 0.4, -0.9)),
                  (Tr, (-1, 0.2, -0.3)), (Tf, (-0.4, 0.4, -1.0)), (Te, (-0.9, 0.5, -0.6))])
    fing = KV(t, [(T0, READY_R["fingers"]), (Tg, (0.4, -0.3, 0.5)), (Tc, (0.0, 0.6, 0.8)),
                  (Tr, (0.0, -0.55, 0.85)), (Tf, (0.3, -0.5, -0.8)), (Te, READY_R["fingers"])])
    palm = KV(t, [(T0, READY_R["palm"]), (Tg, (0.9, -0.2, 0.0)), (Tc, (0.2, 0.7, -0.4)),
                  (Tr, (0.15, -0.85, -0.45)), (Tf, (0.5, 0.3, 0.6)), (Te, READY_R["palm"])])
    c.arm(P, "R", tgt, pole=pole, fingers=fing, palm=palm)
    # glove arm: points at the target while cocking, tucks at release
    SL = c.S["L"]
    keysL = [
        (T0, SL + c.v(*READY_GL["pos"])),
        (Tg, SL + c.v(-0.22, -0.26, -0.12)),
        (Tc, SL + c.v(0.05, -0.42, -0.02)),
        (Tr, SL + c.v(0.06, -0.10, -0.24)),
        (Tf, SL + c.v(0.12, 0.05, -0.30)),
        (Ts, SL + c.v(-0.08, -0.28, -0.38)),
        (Te, SL + c.v(*READY_GL["pos"])),
    ]
    gl = KV(t, keysL)
    gfing = KV(t, [(T0, READY_GL["fingers"]), (Tg, (-0.5, -0.2, 0.6)), (Tc, (0.1, -0.8, 0.5)),
                   (Tr, (0.0, -0.3, 1.0)), (Tf, (0.2, 0.2, 1.0)), (Te, READY_GL["fingers"])])
    gpalm = KV(t, [(T0, READY_GL["palm"]), (Tg, (-0.6, -0.5, -0.4)), (Tc, (-0.9, 0.0, -0.4)),
                   (Tr, (-0.6, 0.6, -0.3)), (Tf, (-0.7, 0.5, 0.0)), (Te, READY_GL["palm"])])
    c.arm(P, "L", gl, pole=(0.9, 0.4, -0.7), fingers=gfing, palm=gpalm)
    return P


def clip_throw(c, t):
    P = c.new()
    keys = dict(start=0.0, gather=0.08, cock=0.19, release=0.30, follow=0.42, settle=0.60,
                end=0.75)
    return _throw_core(c, P, t, keys)


def clip_special(c, t):
    s = c.s
    P = c.new()
    if t < 0.45:
        # power-up crouch: coil, gather, slight shake
        k = sstep(0.0, 0.40, t)
        shake = 0.004 * math.sin(t * 90) * k
        c.torso(P, hips=(shake, 0.06 * k, -0.13 - 0.12 * k), hips_rot=(18 + 12 * k, 0, -25 * k),
                spine=(8 + 6 * k, 0, -10 * k), chest=(6 + 8 * k, -4 * k, -15 * k),
                neck=(-12 - 8 * k, 0, 15 * k), head=(-14 - 6 * k, 0, 18 * k))
        c.plant(P, "L", c.fx * 2.1, c.fy - 0.02 * s, yaw=14, knee_out=0.35)
        c.plant(P, "R", -c.fx * 2.3, c.fy + 0.05 * s * k, yaw=-14 - 20 * k, knee_out=0.35,
                knee_yaw=-14 - 30 * k)
        S = c.S["R"]
        c.arm(P, "R", (S + c.v(*READY_R["pos"])).lerp(S + c.v(0.0, 0.10, -0.30), k),
              pole=(-1, 0.4, -0.6),
              fingers=Vector(READY_R["fingers"]).lerp(Vector((0.1, -0.3, 0.9)), k),
              palm=Vector(READY_R["palm"]).lerp(Vector((0.8, -0.5, 0.0)), k))
        SL = c.S["L"]
        c.arm(P, "L", (SL + c.v(*READY_GL["pos"])).lerp(SL + c.v(-0.18, -0.22, -0.25), k),
              pole=(0.9, 0.4, -0.7),
              fingers=Vector(READY_GL["fingers"]).lerp(Vector((-0.5, -0.2, 0.6)), k),
              palm=Vector(READY_GL["palm"]).lerp(Vector((-0.6, -0.5, -0.4)), k))
        return P
    # explosive throw: reuse throw core with a jump (time remapped)
    keys = dict(start=0.45, gather=0.50, cock=0.58, release=0.70, follow=0.84, settle=1.02,
                end=1.20)
    P = _throw_core(c, P, t, keys, stride_y=0.36, stride_lift=0.22, jump=0.0)
    # blend in from the crouch (hips lower at start)
    k = 1 - sstep(0.45, 0.62, t)
    P.hips_off = P.hips_off + Vector((0, 0.02 * k, -0.12 * k)) * s
    return P


def clip_pitch(c, t):
    """Full wind-up with leg kick, release at 0.85 s."""
    s = c.s
    P = c.new()
    T = dict(set=0.18, turn=0.32, kick=0.50, stride=0.72, release=0.85, follow=1.05, field=1.25,
             end=1.40)
    yaw_h = K(t, [(0, 0), (T["set"], -20), (T["turn"], -80), (T["kick"], -95), (T["stride"], -60),
                  (T["release"], -5), (T["follow"], 20), (T["field"], 5), (T["end"], 0)])
    yaw_c = K(t, [(0, 0), (T["set"], -15), (T["turn"], -75), (T["kick"], -100), (T["stride"], -70),
                  (T["release"], 15), (T["follow"], 30), (T["field"], 5), (T["end"], 0)])
    fwd = K(t, [(0, 4), (T["set"], 2), (T["kick"], -6), (T["stride"], 4), (T["release"], 22),
                (T["follow"], 40), (T["field"], 22), (T["end"], 18)])
    hz = K(t, [(0, -0.03), (T["set"], -0.05), (T["kick"], -0.07), (T["stride"], -0.17),
               (T["release"], -0.17), (T["follow"], -0.20), (T["field"], -0.15), (T["end"], -0.13)])
    hy = K(t, [(0, 0.0), (T["set"], 0.0), (T["kick"], 0.02), (T["stride"], -0.10),
               (T["release"], -0.24), (T["follow"], -0.30), (T["field"], -0.14), (T["end"], 0.045)])
    hx = K(t, [(0, 0), (T["turn"], -0.02), (T["kick"], -0.03), (T["stride"], 0.0),
               (T["release"], 0.03), (T["end"], 0)])
    lean = K(t, [(0, 0), (T["kick"], -6), (T["stride"], -3), (T["release"], 6), (T["end"], 0)])
    c.torso(P, hips=(hx, hy, hz), hips_rot=(fwd * 0.45, lean * 0.5, yaw_h),
            spine=(fwd * 0.25, lean * 0.3, (yaw_c - yaw_h) * 0.4),
            chest=(fwd * 0.3, lean * 0.4, (yaw_c - yaw_h) * 0.6),
            neck=(-fwd * 0.45, 0, -yaw_c * 0.55),
            head=(-fwd * 0.4, 0, -yaw_c * 0.45))
    # --- right (pivot) foot: turns 80 deg, pushes off, drags, steps forward
    rxp = -c.fx * 1.2
    if t < T["release"]:
        c.plant(P, "R", rxp, c.fy, yaw=K(t, [(0, -6), (T["set"], -10), (T["turn"], -85),
                                             (T["stride"], -85), (T["release"], -60)]),
                heel=K(t, [(0, 0), (T["stride"], 0), (T["release"], 40)]),
                knee_out=0.4, knee_yaw=K(t, [(0, -6), (T["turn"], -80), (T["stride"], -70),
                                            (T["release"], -20)]))
    elif t < T["field"]:
        k = (t - T["release"]) / (T["field"] - T["release"])
        a0 = c.ankle_of("R", rxp, c.fy, yaw=-60, heel=40)
        a1 = c.ankle_of("R", -c.fx * 2.0, c.fy - 0.42 * s, yaw=-14)
        mid = a0.lerp(a1, 0.5) + Vector((0.05 * s, 0.0, 0.30 * s))
        ank = KV(k, [(0, a0), (0.45, mid), (1.0, a1)])
        c.free_foot(P, "R", ank, pitch=K(k, [(0, 30), (0.45, -30), (1, 0)]), yaw=lerp(-60, -14, k),
                    knee_out=0.3)
    else:
        k = sstep(T["field"], T["end"], t)
        if k < 0.999:
            a0 = c.ankle_of("R", -c.fx * 2.0, c.fy - 0.42 * s, yaw=-14)
            a1 = c.ankle_of("R", -c.fx * 2.0, c.fy + 0.02 * s, yaw=-14)
            ank = KV(k, [(0, a0), (0.5, a0.lerp(a1, 0.5) + Vector((0, 0, 0.07 * s))), (1, a1)])
            c.free_foot(P, "R", ank, pitch=0, yaw=-14, knee_out=0.35)
        else:
            c.plant(P, "R", -c.fx * 2.0, c.fy + 0.02 * s, yaw=-14, knee_out=0.35)
    # --- left (stride) leg: kick then stride to -Y
    lx0 = c.fx * 1.2
    ly_str = c.fy - 0.72 * s
    if t < T["set"] * 0.6:
        c.plant(P, "L", lx0, c.fy, yaw=6)
    elif t < T["stride"]:
        k0 = T["set"] * 0.6
        a0 = c.ankle_of("L", lx0, c.fy, yaw=6)
        a_set = c.ankle_of("L", c.fx * 0.4, c.fy + 0.05 * s, yaw=-60, z=0.0)
        a_kick = Vector((c.fx * 0.1, 0.06 * s, c.L["hip"] - 0.16 * s))
        a_reach = Vector((c.fx * 0.8, c.fy - 0.55 * s, 0.22 * s))
        a_land = c.ankle_of("L", lx0, ly_str, yaw=-10)
        ank = KV(t, [(k0, a0), (T["turn"], a_set + Vector((0, 0, 0.06 * s))),
                     (T["kick"], a_kick), (T["kick"] + 0.12, a_reach), (T["stride"], a_land)])
        pitch = K(t, [(k0, 0), (T["turn"], -10), (T["kick"], -35), (T["kick"] + 0.12, 5),
                      (T["stride"], 0)])
        yaw = K(t, [(k0, 6), (T["turn"], -60), (T["kick"], -80), (T["stride"], -10)])
        pole = KV(t, [(k0, (0.1, -1, 0)), (T["turn"], (-0.6, -0.8, 0.2)),
                      (T["kick"], (-0.8, -0.3, 0.6)), (T["stride"], (0.15, -1, 0))])
        c.free_foot(P, "L", ank, pitch=pitch, yaw=yaw, pole=pole)
    elif t < T["follow"] + 0.05:
        c.plant(P, "L", lx0, ly_str, yaw=-10, knee_out=0.2)
    else:
        k = sstep(T["follow"] + 0.05, T["end"], t)
        a0 = c.ankle_of("L", lx0, ly_str, yaw=-10)
        a1 = c.ankle_of("L", c.fx * 2.1, c.fy - 0.02 * s, yaw=14)
        if k < 0.999:
            ank = KV(k, [(0, a0), (0.5, a0.lerp(a1, 0.5) + Vector((0, 0, 0.08 * s))), (1, a1)])
            c.free_foot(P, "L", ank, pitch=0, yaw=lerp(-10, 14, k), knee_out=0.3)
        else:
            c.plant(P, "L", c.fx * 2.1, c.fy - 0.02 * s, yaw=14, knee_out=0.35)
    # --- arms
    S = c.S["R"]
    SL = c.S["L"]
    chest_set = S + c.v(0.18, -0.22, -0.16)
    keysR = [(0, S + c.v(0.02, -0.02, -0.52)), (T["set"], chest_set), (T["kick"], chest_set + c.v(0.0, 0.0, 0.02)),
             (T["kick"] + 0.08, S + c.v(-0.05, 0.12, -0.38)),
             (T["stride"], S + c.v(-0.16, 0.22, 0.20)),
             (T["release"], S + c.v(0.02, -0.30, 0.42)),
             (T["follow"], S + c.v(0.34, -0.36, -0.40)),
             (T["field"], S + c.v(0.18, -0.32, -0.30)),
             (T["end"], S + c.v(0.14, -0.30, -0.30))]
    c.arm(P, "R", KV(t, keysR),
          pole=KV(t, [(0, (-0.5, 1, -0.3)), (T["set"], (-1, 0.3, -0.6)), (T["kick"], (-1, 0.3, -0.6)),
                      (T["stride"], (-1, 0.4, -0.9)), (T["release"], (-1, 0.2, -0.3)),
                      (T["follow"], (-0.4, 0.4, -1.0)), (T["end"], (-0.9, 0.5, -0.6))]),
          fingers=KV(t, [(0, (0, -0.2, -1)), (T["set"], (0.4, -0.3, 0.5)), (T["kick"], (0.4, -0.3, 0.5)),
                         (T["kick"] + 0.08, (0.0, 0.3, -1.0)), (T["stride"], (0.0, 0.6, 0.8)),
                         (T["release"], (0.0, -0.55, 0.85)), (T["follow"], (0.3, -0.5, -0.8)),
                         (T["end"], (0.15, -0.5, 0.8))]),
          palm=KV(t, [(0, (1, 0, 0)), (T["set"], (0.9, -0.2, 0.0)), (T["kick"], (0.9, -0.2, 0.0)),
                      (T["kick"] + 0.08, (-0.2, 0.9, 0.2)), (T["stride"], (0.2, 0.7, -0.4)),
                      (T["release"], (0.15, -0.85, -0.45)), (T["follow"], (0.5, 0.3, 0.6)),
                      (T["end"], (0.8, -0.5, 0.0))]))
    glove_set = SL + c.v(-0.20, -0.24, -0.15)
    keysL = [(0, SL + c.v(0.0, -0.02, -0.52)), (T["set"], glove_set), (T["kick"], glove_set + c.v(0, 0, 0.02)),
             (T["stride"], SL + c.v(0.05, -0.44, -0.02)),
             (T["release"], SL + c.v(0.06, -0.10, -0.24)),
             (T["follow"], SL + c.v(0.12, 0.05, -0.30)),
             (T["field"], SL + c.v(-0.05, -0.28, -0.34)),
             (T["end"], SL + c.v(-0.10, -0.32, -0.36))]
    c.arm(P, "L", KV(t, keysL), pole=(0.9, 0.4, -0.7),
          fingers=KV(t, [(0, (0, -0.2, -1)), (T["set"], (-0.5, -0.2, 0.6)), (T["kick"], (-0.5, -0.2, 0.6)),
                         (T["stride"], (0.1, -0.8, 0.5)), (T["release"], (0.0, -0.3, 1.0)),
                         (T["follow"], (0.2, 0.2, 1.0)), (T["end"], (-0.15, -0.35, 1.0))]),
          palm=KV(t, [(0, (-1, 0, 0)), (T["set"], (-0.6, -0.5, -0.4)), (T["kick"], (-0.6, -0.5, -0.4)),
                      (T["stride"], (-0.9, 0.0, -0.4)), (T["release"], (-0.6, 0.6, -0.3)),
                      (T["follow"], (-0.7, 0.5, 0.0)), (T["end"], (0.1, -1.0, -0.2))]))
    return P


def clip_catch(c, t):
    s = c.s
    P = c.new()
    k = K(t, [(0, 0), (0.25, 1.0), (0.32, 0.92), (0.45, 0.45), (0.6, 0.0)])
    give = K(t, [(0, 0), (0.25, 0), (0.33, 1), (0.45, 0.6), (0.6, 0)])
    c.torso(P, hips=(0.02 * k, 0.045 - 0.04 * k, -0.13 + 0.08 * k), hips_rot=(18 - 14 * k, 2 * k, 6 * k),
            spine=(8 - 8 * k - 3 * give, 2 * k, 4 * k), chest=(6 - 10 * k - 4 * give, 3 * k, 8 * k),
            neck=(-12 + 2 * k, 0, -6 * k), head=(-14 - 6 * k, 0, -6 * k))
    c.plant(P, "L", c.fx * 2.1, c.fy - 0.02 * s, yaw=14, knee_out=0.35,
            heel=8 * k)
    c.plant(P, "R", -c.fx * 2.1, c.fy + 0.02 * s, yaw=-14, knee_out=0.35)
    # glove: from the ready pose (chest space) to high forward, pocket to the ball
    SL = c.S["L"]
    SR = c.S["R"]
    g0 = SL + c.v(*READY_GL["pos"])
    g1 = SL + c.v(-0.06, -0.40, 0.22)
    gc = SL + c.v(-0.18, -0.26, -0.18)
    gl = KV(t, [(0, g0), (0.25, g1), (0.33, g1 + c.v(0, 0.06, -0.03)), (0.45, gc), (0.6, g0)])
    c.arm(P, "L", gl, pole=(0.9, 0.4, -0.7),
          fingers=KV(t, [(0, READY_GL["fingers"]), (0.25, (0.0, -0.3, 1.0)), (0.45, (-0.3, -0.2, 1.0)),
                         (0.6, READY_GL["fingers"])]),
          palm=KV(t, [(0, READY_GL["palm"]), (0.25, (0.05, -1.0, 0.1)), (0.45, (-0.5, -0.8, 0.0)),
                      (0.6, READY_GL["palm"])]))
    r0 = SR + c.v(*READY_R["pos"])
    r1 = SR + c.v(0.18, -0.34, 0.05)
    rc = SR + c.v(0.22, -0.26, -0.20)
    c.arm(P, "R", KV(t, [(0, r0), (0.25, r1), (0.45, rc), (0.6, r0)]), pole=(-0.9, 0.5, -0.6),
          fingers=KV(t, [(0, READY_R["fingers"]), (0.25, (0.2, -0.6, 0.75)), (0.6, READY_R["fingers"])]),
          palm=KV(t, [(0, READY_R["palm"]), (0.25, (0.8, -0.3, -0.4)), (0.6, READY_R["palm"])]))
    return P


def clip_victory(c, t):
    s = c.s
    L = 2.0
    P = c.new()
    b = 0.5 - 0.5 * math.cos(2 * math.pi * 2 * t / L)   # 2 bounces
    c.torso(P, hips=(0, 0, -0.02 - 0.035 * b), hips_rot=(0, 0, 4 * wave(t, L)),
            spine=(-2, 0, 0), chest=(-6 + 3 * b, 0, -4 * wave(t, L)),
            neck=(-2, 0, 0), head=(-10 + 6 * b, 4 * wave(t, L), 8 * wave(t, L, 1, 0.2)))
    base_stand(c, P, width=1.5, toe_out=12)
    # glove raised high, right fist pumping
    SL = c.S["L"]
    c.arm(P, "L", SL + c.v(0.10, -0.06, 0.50 - 0.04 * b), pole=(1, 0.3, -0.6),
          fingers=(0.1, -0.1, 1), palm=(0.0, -1.0, 0.1))
    pump = 0.5 - 0.5 * math.cos(2 * math.pi * 2 * t / L)
    S = c.S["R"]
    c.arm(P, "R", S + c.v(-0.10, -0.20, -0.05 + 0.40 * pump), pole=(-1, 0.4, -0.7),
          fingers=(0.0, -0.3, 1.0), palm=(0.9, -0.3, 0.0))
    return P


# --- enemy-only ------------------------------------------------------------------

def clip_leap(c, t):
    s = c.s
    P = c.new()
    hz = K(t, [(0, -0.03), (0.15, -0.20), (0.25, 0.02), (0.45, 0.02), (0.65, 0.0), (0.80, -0.18)])
    tuck = K(t, [(0, 0), (0.22, 0), (0.30, 0.4), (0.45, 1.0), (0.62, 0.6), (0.74, 0.1), (0.8, 0)])
    fwd = K(t, [(0, 8), (0.15, 30), (0.25, 10), (0.45, 20), (0.7, 6), (0.80, 28)])
    c.torso(P, hips=(0, 0.02, hz), hips_rot=(fwd * 0.5, 0, 0), spine=(fwd * 0.25, 0, 0),
            chest=(fwd * 0.25, 0, 0), neck=(-fwd * 0.5, 0, 0), head=(-fwd * 0.4, 0, 0))
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        if t <= 0.22 or t >= 0.78:
            heel = K(t, [(0, 0), (0.15, 0), (0.22, 35), (0.78, 10), (0.8, 0)])
            c.plant(P, side, c.fx * 1.4 * sx, c.fy, yaw=sx * 10, heel=heel, knee_out=0.25)
        else:
            a0 = c.ankle_of(side, c.fx * 1.4 * sx, c.fy, yaw=sx * 10, heel=35)
            a1 = c.ankle_of(side, c.fx * 1.4 * sx, c.fy, yaw=sx * 10, heel=10)
            up = Vector((c.fx * 1.6 * sx, -0.02 * s, c.L["hip"] - 0.30 * s))
            ank = a0.lerp(up, sstep(0.22, 0.42, t)).lerp(a1, sstep(0.55, 0.78, t))
            c.free_foot(P, side, ank, pitch=-25 * tuck + 10, yaw=sx * 10,
                        pole=Vector((sx * 0.25, -1, 0.3 * tuck)))
    arm_up = K(t, [(0, 0), (0.15, -0.6), (0.3, 1.0), (0.5, 0.7), (0.8, -0.2)])
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        c.hang(P, side, swing=20 + 90 * arm_up, out=18 + 10 * abs(arm_up), bend=35)
    return P


def clip_swing(c, t):
    """Two-handed bat swing, impact at 0.50 s (contact in front, -Y)."""
    s = c.s
    P = c.new()
    yaw_h = K(t, [(0, 0), (0.15, -10), (0.35, -30), (0.50, 25), (0.65, 45), (0.85, 20), (1.0, 0)])
    yaw_c = K(t, [(0, 0), (0.15, -15), (0.35, -45), (0.50, 20), (0.65, 60), (0.85, 25), (1.0, 0)])
    fwd = K(t, [(0, 8), (0.35, 12), (0.5, 16), (0.65, 10), (1.0, 8)])
    hz = K(t, [(0, -0.05), (0.35, -0.08), (0.5, -0.11), (0.65, -0.09), (1.0, -0.05)])
    hy = K(t, [(0, 0), (0.35, 0.04), (0.5, -0.04), (0.65, -0.05), (1.0, 0)])
    c.torso(P, hips=(0, hy, hz), hips_rot=(fwd * 0.5, 0, yaw_h),
            spine=(fwd * 0.25, 0, (yaw_c - yaw_h) * 0.4),
            chest=(fwd * 0.3, K(t, [(0, 0), (0.35, -6), (0.5, 4), (1, 0)]), (yaw_c - yaw_h) * 0.6),
            neck=(-fwd * 0.5, 0, -yaw_c * 0.5), head=(-fwd * 0.4, 0, -yaw_c * 0.5))
    c.plant(P, "R", -c.fx * 1.9, c.fy + 0.05 * s, yaw=K(t, [(0, -15), (0.35, -25), (0.5, 0), (0.7, 20), (1, -15)]),
            heel=K(t, [(0, 0), (0.4, 0), (0.5, 30), (0.7, 45), (0.9, 10), (1, 0)]), knee_out=0.3,
            knee_yaw=K(t, [(0, -15), (0.35, -30), (0.5, 15), (0.7, 30), (1, -15)]))
    # front foot: small lift and stride at 0.2-0.38
    if 0.15 < t < 0.40:
        k = (t - 0.15) / 0.25
        a0 = c.ankle_of("L", c.fx * 1.9, c.fy - 0.02 * s, yaw=15)
        a1 = c.ankle_of("L", c.fx * 1.9, c.fy - 0.18 * s, yaw=5)
        ank = KV(k, [(0, a0), (0.5, a0.lerp(a1, 0.5) + Vector((0, 0, 0.10 * s))), (1, a1)])
        c.free_foot(P, "L", ank, pitch=K(k, [(0, 0), (0.5, -8), (1, 0)]), yaw=lerp(15, 5, k))
    elif t <= 0.15:
        c.plant(P, "L", c.fx * 1.9, c.fy - 0.02 * s, yaw=15, knee_out=0.25)
    elif t < 0.80:
        c.plant(P, "L", c.fx * 1.9, c.fy - 0.18 * s, yaw=5, knee_out=0.2)
    else:
        k = sstep(0.80, 1.0, t)
        a0 = c.ankle_of("L", c.fx * 1.9, c.fy - 0.18 * s, yaw=5)
        a1 = c.ankle_of("L", c.fx * 1.9, c.fy - 0.02 * s, yaw=15)
        if k < 0.999:
            ank = KV(k, [(0, a0), (0.5, a0.lerp(a1, 0.5) + Vector((0, 0, 0.05 * s))), (1, a1)])
            c.free_foot(P, "L", ank, pitch=0, yaw=lerp(5, 15, k))
        else:
            c.plant(P, "L", c.fx * 1.9, c.fy - 0.02 * s, yaw=15, knee_out=0.25)
    # hands together, bat direction keyed (chest space)
    S = c.S["R"]
    grip = KV(t, [(0, S + c.v(0.10, -0.20, -0.18)), (0.35, S + c.v(0.0, 0.0, 0.0)),
                  (0.45, S + c.v(0.12, -0.26, -0.22)), (0.50, S + c.v(0.22, -0.40, -0.26)),
                  (0.58, S + c.v(0.40, -0.32, -0.20)), (0.70, S + c.v(0.42, -0.05, 0.02)),
                  (0.85, S + c.v(0.30, -0.15, -0.10)), (1.0, S + c.v(0.10, -0.20, -0.18))])
    bat = KV(t, [(0, (-0.25, 0.55, 0.80)), (0.35, (-0.3, 0.7, 0.6)), (0.45, (-0.9, 0.1, 0.1)),
                 (0.50, (0.15, -1.0, 0.08)), (0.58, (0.9, -0.3, 0.1)), (0.70, (0.6, 0.6, 0.4)),
                 (0.85, (0.1, 0.6, 0.8)), (1.0, (-0.25, 0.55, 0.80))])
    bat.normalize()
    f, p = c.bat_grip("R", bat, Vector((0, 0, -1)).lerp(Vector((0.8, -0.2, 0)), 0.5))
    c.arm(P, "R", grip, pole=KV(t, [(0, (-0.6, 0.6, -0.5)), (0.35, (-0.8, 0.4, -0.6)),
                                    (0.5, (-0.6, 0.3, -1.0)), (0.7, (-0.2, 0.5, -1)), (1, (-0.6, 0.6, -0.5))]),
          fingers=f, palm=p)
    hs = c.sk.p["hand_scale"]
    lg = grip - bat * 0.10 * s * hs
    f2, p2 = c.bat_grip("L", bat, Vector((0, 0, -1)).lerp(Vector((-0.8, -0.2, 0)), 0.5))
    c.arm(P, "L", lg, pole=KV(t, [(0, (0.5, 0.3, -1.0)), (0.5, (0.8, 0.2, -0.6)), (0.7, (0.6, -0.2, -0.8)),
                                  (1, (0.5, 0.3, -1.0))]), fingers=f2, palm=p2)
    return P


def clip_slam(c, t):
    """Overhead two-handed ground slam, impact at 0.90 s."""
    s = c.s
    P = c.new()
    up = K(t, [(0, 0), (0.45, 1.0), (0.62, 1.0), (0.80, 0.4), (0.90, -0.1), (1.1, -0.05), (1.4, 0)])
    fwd = K(t, [(0, 6), (0.45, -10), (0.62, -12), (0.82, 30), (0.90, 45), (1.1, 40), (1.4, 8)])
    hz = K(t, [(0, -0.04), (0.45, 0.0), (0.62, -0.01), (0.90, -0.24), (1.1, -0.22), (1.4, -0.05)])
    hy = K(t, [(0, 0), (0.45, 0.04), (0.9, 0.10), (1.1, 0.08), (1.4, 0)])
    c.torso(P, hips=(0, hy, hz), hips_rot=(fwd * 0.5, 0, 0), spine=(fwd * 0.25, 0, 0),
            chest=(fwd * 0.25, 0, 0), neck=(-fwd * 0.45, 0, 0), head=(-fwd * 0.35, 0, 0))
    heel = K(t, [(0, 0), (0.4, 20), (0.62, 25), (0.8, 0), (1.4, 0)])
    c.plant(P, "L", c.fx * 2.0, c.fy - 0.02 * s, yaw=14, heel=heel, knee_out=0.3)
    c.plant(P, "R", -c.fx * 2.0, c.fy + 0.02 * s, yaw=-14, heel=heel, knee_out=0.3)
    # both hands together, overhead -> ground in front (world space)
    top = Vector((0.0, 0.10, c.ho.z + 0.38 * s))
    hit = Vector((0.0, -0.62 * s, 0.30 * s))
    mid = Vector((0.0, -0.45 * s, c.ho.z + 0.10 * s))
    start = Vector((0.0, -0.28 * s, c.L["pelvis"] + 0.05 * s))
    grip = KV(t, [(0, start), (0.45, top), (0.62, top + Vector((0, 0.04 * s, 0))), (0.80, mid),
                  (0.90, hit), (1.1, hit + Vector((0, 0.03 * s, 0.05 * s))), (1.4, start)])
    bat = KV(t, [(0, (0, -0.5, 0.85)), (0.45, (0, 0.8, 0.6)), (0.62, (0, 0.9, 0.2)),
                 (0.80, (0, -0.4, 0.9)), (0.90, (0, -0.95, -0.25)), (1.1, (0, -0.9, -0.3)),
                 (1.4, (0, -0.5, 0.85))])
    bat.normalize()
    hs = c.sk.p["hand_scale"]
    side_off = Vector((-0.045 * s, 0, 0))
    f, p = c.bat_grip("R", bat, Vector((1, 0, 0)))
    c.arm(P, "R", grip + side_off * 0.0, pole=(-1, 0.3, -0.5), space="world", fingers=f, palm=p)
    f2, p2 = c.bat_grip("L", bat, Vector((-1, 0, 0)))
    c.arm(P, "L", grip - bat * 0.10 * s * hs, pole=(1, 0.3, -0.5), space="world", fingers=f2, palm=p2)
    return P


def clip_taunt(c, t):
    s = c.s
    P = c.new()
    spread = K(t, [(0, 0), (0.30, 1.0), (0.9, 1.0), (1.05, 0.2), (1.5, 0)])
    laugh = math.sin(t * 2 * math.pi * 5) * K(t, [(0, 0), (0.35, 1), (0.85, 1), (1.0, 0)])
    point = K(t, [(0, 0), (0.9, 0), (1.1, 1.0), (1.3, 1.0), (1.5, 0)])
    c.torso(P, hips=(0, 0, -0.04 + 0.006 * laugh), hips_rot=(-2 * spread, 0, 0),
            spine=(-4 * spread, 0, 0), chest=(-8 * spread + 2 * laugh + 10 * point, 0, 6 * point),
            neck=(-6 * spread, 0, 0), head=(-14 * spread + 4 * laugh, 0, -6 * point),
            sh_L=(0, 0, 0), sh_R=(0, 0, 0))
    base_stand(c, P, width=1.6, toe_out=14)
    for side in ("L", "R"):
        sx = 1 if side == "L" else -1
        c.hang(P, side, swing=lerp(10, 25, spread), out=lerp(14, 70, spread) + 3 * laugh,
               bend=lerp(35, 50, spread), pole=(sx * 0.2, 1.0, -0.4))
    if point > 0.01:
        S = c.S["R"]
        tgt0 = c.hang(c.new(), "R", swing=lerp(10, 25, spread), out=lerp(14, 70, spread), bend=40)
        tgt1 = S + c.v(0.10, -0.55, 0.05)
        c.arm(P, "R", tgt0.lerp(tgt1, point), pole=(-1, 0.3, -0.5))
    if c.style["bat"]:
        # bat raised overhead in the right hand while taunting
        S = c.S["R"]
        tg = S + c.v(-0.10, -0.10, 0.10 + 0.35 * spread)
        bat = Vector((-0.2, 0.2, 1.0)).normalized()
        f, p = c.bat_grip("R", bat, Vector((0.8, -0.3, 0)))
        c.arm(P, "R", tg, pole=(-1, 0.3, -0.5), fingers=f, palm=p)
    return P


# ---------------------------------------------------------------------------
# registry + baking
# ---------------------------------------------------------------------------

COMMON = [("idle", 2.0, True, clip_idle), ("run", 0.70, True, clip_run),
          ("hit", 0.35, False, clip_hit), ("stunned", 1.2, True, clip_stunned),
          ("defeat", 1.2, False, clip_defeat), ("celebrate", 1.0, True, clip_celebrate)]
DEFENDER = [("ready", 1.6, True, clip_ready), ("throw", 0.75, False, clip_throw),
            ("pitch", 1.40, False, clip_pitch), ("catch", 0.60, False, clip_catch),
            ("special", 1.20, False, clip_special), ("victory", 2.0, True, clip_victory),
            ("walk", 1.0, True, clip_walk)]
ENEMY = [("sprint", 0.55, True, clip_sprint), ("leap", 0.80, False, clip_leap),
         ("swing", 1.0, False, clip_swing), ("slam", 1.4, False, clip_slam),
         ("taunt", 1.5, False, clip_taunt), ("walk", 1.0, True, clip_walk)]

EVENTS = {"throw": ("release", 0.30), "pitch": ("release", 0.85), "catch": ("catch", 0.25),
          "special": ("impact", 0.70), "swing": ("impact", 0.50), "slam": ("impact", 0.90),
          "leap": ("land", 0.80)}


def clip_list(kind):
    return COMMON + (DEFENDER if kind == "defender" else ENEMY)


def sample_clip(c, fn, length, loop):
    n = int(round(length * FPS))
    frames = []
    warn_d = {}
    for f in range(n + 1):
        t = f / FPS
        if loop and f == n:
            t = 0.0
        P = fn(c, t)
        P.solve()
        for w, d in P.clamped:
            key = w
            if d > warn_d.get(key, (0, 0))[0]:
                warn_d[key] = (d, round(t, 3))
        frames.append(P.basis())
    if loop:
        frames[-1] = frames[0]
    warn = ["%s:%.3fm@%.2fs" % (k, v[0], v[1]) for k, v in sorted(warn_d.items())
            if v[0] > (0.003 if "leg" in k else 0.02)]
    return frames, warn


def _new_action(arm_obj, name):
    import bpy
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = None
    cbag = None
    if hasattr(act, "slots"):
        slot = act.slots.new(id_type='OBJECT', name=arm_obj.name)
        layer = act.layers.new("Layer")
        strip = layer.strips.new(type='KEYFRAME')
        cbag = strip.channelbags.new(slot)
    return act, slot, cbag


def bake(arm_obj, c, kind, only=None):
    import bpy
    actions = []
    report = {}
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    for name, length, loop, fn in clip_list(kind):
        if only and name not in only:
            continue
        frames, warn = sample_clip(c, fn, length, loop)
        act, slot, cbag = _new_action(arm_obj, name)
        fcs = cbag.fcurves if cbag is not None else act.fcurves
        n = len(frames)
        xs = np.arange(n, dtype=np.float64)
        for bname in rig.BONE_NAMES:
            pb = arm_obj.pose.bones[bname]
            grp = bname
            qs = [frames[i][bname][1] for i in range(n)]
            # sign continuity
            for i in range(1, n):
                if qs[i].dot(qs[i - 1]) < 0:
                    qs[i] = -qs[i]
            if loop and n > 1 and qs[-1].dot(qs[0]) < 0:
                pass
            path = 'pose.bones["%s"].rotation_quaternion' % bname
            for k in range(4):
                fc = fcs.new(path, index=k, group_name=grp) if cbag is not None else \
                    fcs.new(path, index=k, action_group=grp)
                fc.keyframe_points.add(n)
                vals = np.array([q[k] for q in qs])
                co = np.stack([xs, vals], 1).ravel()
                fc.keyframe_points.foreach_set("co", co)
                fc.keyframe_points.foreach_set("interpolation", [1] * n)  # LINEAR
                fc.update()
            if bname in ("hips", "root"):
                path = 'pose.bones["%s"].location' % bname
                for k in range(3):
                    fc = fcs.new(path, index=k, group_name=grp) if cbag is not None else \
                        fcs.new(path, index=k, action_group=grp)
                    fc.keyframe_points.add(n)
                    vals = np.array([frames[i][bname][0][k] for i in range(n)])
                    co = np.stack([xs, vals], 1).ravel()
                    fc.keyframe_points.foreach_set("co", co)
                    fc.keyframe_points.foreach_set("interpolation", [1] * n)
                    fc.update()
        act.use_frame_range = True
        act.frame_start = 0
        act.frame_end = n - 1
        try:
            act.use_cyclic = bool(loop)
        except Exception:
            pass
        actions.append((act, slot))
        report[name] = dict(length=length, frames=n, loop=loop, warn=sorted(warn))
    return actions, report
