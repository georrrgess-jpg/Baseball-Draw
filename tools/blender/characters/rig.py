"""Shared humanoid armature (ASSET_SPEC 3.1) + a small FK/IK pose solver.

Conventions (Blender space): Z up, character faces -Y, character left = +X.

Body proportions are a dict (see ``BASE_PROPS``); every character uses the
same bone names/hierarchy, only lengths and thickness change.

Pose model
----------
Every bone gets a *delta* transform ``D_b`` (armature space) mapping rest
positions to posed positions.  ``D_b = D_parent @ T(h_b) @ R_b @ T(-h_b)``
where ``R_b`` is a rotation expressed in rest armature axes.  Arms and legs
can instead be solved with analytic two-bone IK.  The Blender pose-bone basis
is ``B_b = M_b^-1 @ D_parent^-1 @ D_b @ M_b`` (``M_b`` = rest matrix).
"""
import math
from mathutils import Matrix, Quaternion, Vector

BONES = [
    # name, parent, connected
    ("root", None, False),
    ("hips", "root", False),
    ("spine", "hips", True),
    ("chest", "spine", True),
    ("neck", "chest", False),
    ("head", "neck", True),
    ("shoulder.L", "chest", False),
    ("upper_arm.L", "shoulder.L", False),
    ("forearm.L", "upper_arm.L", True),
    ("hand.L", "forearm.L", True),
    ("shoulder.R", "chest", False),
    ("upper_arm.R", "shoulder.R", False),
    ("forearm.R", "upper_arm.R", True),
    ("hand.R", "forearm.R", True),
    ("thigh.L", "hips", False),
    ("shin.L", "thigh.L", True),
    ("foot.L", "shin.L", True),
    ("toe.L", "foot.L", True),
    ("thigh.R", "hips", False),
    ("shin.R", "thigh.R", True),
    ("foot.R", "shin.R", True),
    ("toe.R", "foot.R", True),
]
BONE_NAMES = [b[0] for b in BONES]
PARENT = {b[0]: b[1] for b in BONES}

# Reference proportions for a 1.80 m defender (metres).
BASE_PROPS = dict(
    scale=1.0,           # global scale applied to everything at the end
    head=0.28,           # chin -> crown
    head_w=1.0,          # head width multiplier
    neck_len=0.10, neck_r=0.058,
    spine_len=0.15, chest_len=0.25, lumbar=0.09,
    sh_half=0.205,       # shoulder joint half width
    clav_z=-0.035,       # shoulder joint height relative to neck base
    chest_w=0.175, chest_d=0.125, waist_w=0.148, waist_d=0.108,
    pelvis_w=0.168, pelvis_d=0.118,
    hip_half=0.095,
    upper_arm=0.285, forearm=0.255, hand=0.085,
    arm_r=0.052, forearm_r=0.044, wrist_r=0.030,
    thigh=0.43, shin=0.425, ankle=0.085, foot=0.27,
    thigh_r=0.092, knee_r=0.060, calf_r=0.060, ankle_r=0.034,
    a_pose=40.0,         # arm angle from vertical in rest pose (deg)
    elbow_rest=6.0,      # slight elbow flex in rest (deg)
    hand_scale=1.12, foot_scale=1.0,
    muscle=1.0, belly=0.0,
)


def V(*a):
    if len(a) == 1:
        return Vector(a[0])
    return Vector(a)


class Skeleton:
    """Computes rest joint positions from proportions."""

    def __init__(self, props):
        p = dict(BASE_PROPS)
        p.update(props or {})
        self.p = p
        s = p["scale"]
        self.s = s
        a = math.radians(p["a_pose"])
        heads, tails, rolls = {}, {}, {}
        ankle_z = p["ankle"]
        knee_z = ankle_z + p["shin"]
        hip_z = knee_z + p["thigh"]
        pelvis_z = hip_z + 0.03
        spine_z = pelvis_z + p["lumbar"]
        chest_z = spine_z + p["spine_len"]
        neck_z = chest_z + p["chest_len"]
        head_z = neck_z + p["neck_len"]
        self.levels = dict(ankle=ankle_z, knee=knee_z, hip=hip_z,
                           pelvis=pelvis_z, spine=spine_z, chest=chest_z,
                           neck=neck_z, head=head_z)
        front = V(0, -1, 0)
        back = V(0, 1, 0)
        up = V(0, 0, 1)
        heads["root"] = V(0, 0, 0)
        tails["root"] = V(0, 0, 0.18)
        rolls["root"] = front
        heads["hips"] = V(0, 0.0, pelvis_z)
        tails["hips"] = V(0, 0.0, spine_z)
        rolls["hips"] = front
        heads["spine"] = tails["hips"]
        tails["spine"] = V(0, 0.005, chest_z)
        rolls["spine"] = front
        heads["chest"] = tails["spine"]
        tails["chest"] = V(0, 0.01, neck_z - 0.01)
        rolls["chest"] = front
        heads["neck"] = V(0, 0.012, neck_z)
        tails["neck"] = V(0, 0.004, head_z)
        rolls["neck"] = front
        heads["head"] = tails["neck"]
        tails["head"] = V(0, 0.004, head_z + 0.20 * p["head"] / 0.275)
        rolls["head"] = front
        sh_z = neck_z + p["clav_z"]
        for side, sx in (("L", 1.0), ("R", -1.0)):
            heads["shoulder." + side] = V(0.025 * sx, 0.01, sh_z + 0.01)
            tails["shoulder." + side] = V((p["sh_half"] - 0.025) * sx, 0.02, sh_z + 0.005)
            rolls["shoulder." + side] = front
            S = V(p["sh_half"] * sx, 0.02, sh_z)
            d = V(math.sin(a) * sx, 0, -math.cos(a))
            E = S + d * p["upper_arm"]
            # forearm slightly flexed forward in rest
            fl = math.radians(p["elbow_rest"])
            d2 = (d * math.cos(fl) + front * math.sin(fl)).normalized()
            W = E + d2 * p["forearm"]
            Hn = W + d2 * p["hand"]
            heads["upper_arm." + side] = S
            tails["upper_arm." + side] = E
            heads["forearm." + side] = E
            tails["forearm." + side] = W
            heads["hand." + side] = W
            tails["hand." + side] = Hn
            for b in ("upper_arm.", "forearm.", "hand."):
                rolls[b + side] = front
            Hj = V(p["hip_half"] * sx, 0.0, hip_z)
            K = V(p["hip_half"] * 1.03 * sx, -0.012, knee_z)
            A = V(p["hip_half"] * 1.05 * sx, 0.012, ankle_z)
            fl_ = p["foot"] * p["foot_scale"]
            ball = V(A.x, A.y - fl_ * 0.52, 0.028)
            tip = V(A.x, A.y - fl_ * 0.80, 0.024)
            heads["thigh." + side] = Hj
            tails["thigh." + side] = K
            heads["shin." + side] = K
            tails["shin." + side] = A
            heads["foot." + side] = A
            tails["foot." + side] = ball
            heads["toe." + side] = ball
            tails["toe." + side] = tip
            rolls["thigh." + side] = back
            rolls["shin." + side] = back
            rolls["foot." + side] = up
            rolls["toe." + side] = up
        # global scale
        for k in heads:
            heads[k] = heads[k] * s
            tails[k] = tails[k] * s
        for k in self.levels:
            self.levels[k] *= s
        self.heads, self.tails, self.rolls = heads, tails, rolls
        # rest frames (3x3, columns = bone x, y, z) computed like Blender's
        # align_roll: y along bone, z = roll vector made perpendicular.
        self.rest = {}
        for name in BONE_NAMES:
            y = (tails[name] - heads[name]).normalized()
            z = rolls[name] - y * rolls[name].dot(y)
            z.normalize()
            x = y.cross(z)
            m = Matrix((x, y, z)).transposed()
            M = m.to_4x4()
            M.translation = heads[name]
            self.rest[name] = M
        self.length = {n: (tails[n] - heads[n]).length for n in BONE_NAMES}
        # palm normals in rest (hand faces the body)
        self.palm_rest = {}
        for side in ("L", "R"):
            hx = self.rest["hand." + side].to_3x3().col[0]
            self.palm_rest[side] = hx.copy() if side == "L" else -hx

    # convenient derived points -------------------------------------------
    def head_frame(self):
        """Return (origin, h) of the head modelling frame: origin at the
        eye line centre, h = head height."""
        p = self.p
        h = p["head"] * self.s
        pivot = self.heads["head"]
        chin_z = pivot.z - 0.035 * h / 0.275
        eye_z = chin_z + 0.47 * h
        return V(0, pivot.y - 0.005 * self.s, eye_z), h

    def build(self, name="Armature"):
        import bpy
        arm = bpy.data.armatures.new(name)
        arm.display_type = 'STICK'
        obj = bpy.data.objects.new(name, arm)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        ebs = {}
        for bname, parent, conn in BONES:
            eb = arm.edit_bones.new(bname)
            eb.head = self.heads[bname]
            eb.tail = self.tails[bname]
            eb.align_roll(self.rolls[bname])
            ebs[bname] = eb
        for bname, parent, conn in BONES:
            if parent:
                ebs[bname].parent = ebs[parent]
                ebs[bname].use_connect = conn
        bpy.ops.object.mode_set(mode='OBJECT')
        for pb in obj.pose.bones:
            pb.rotation_mode = 'QUATERNION'
        # use Blender's own rest matrices (identical up to float noise)
        for b in arm.bones:
            self.rest[b.name] = b.matrix_local.copy()
        self.obj = obj
        return obj


# ---------------------------------------------------------------------------
# rotations helpers
# ---------------------------------------------------------------------------

def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'X')


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Y')


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z')


def body_rot(fwd=0.0, left=0.0, yaw=0.0):
    """Rotation in armature axes: ``fwd`` = lean forward (deg), ``left`` =
    lean to the character's left, ``yaw`` = turn to the character's left.
    Twist is applied first, then side lean, then forward lean."""
    return rx(fwd) @ ry(left) @ rz(yaw)


def T(v):
    return Matrix.Translation(v)


def frame3(x, y):
    """3x3 frame with columns x, y, z = x cross y (x re-orthogonalised)."""
    y = y.normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


def two_bone_ik(S, W, l1, l2, pole):
    """Return (E, W', hinge_axis).  pole = direction the middle joint
    should point to (need not be perpendicular)."""
    d = W - S
    D = d.length
    D = max(min(D, (l1 + l2) * 0.9995), abs(l1 - l2) + 1e-4)
    u = d.normalized() if d.length > 1e-9 else Vector((0, 0, -1))
    W2 = S + u * D
    v = pole - u * pole.dot(u)
    if v.length < 1e-6:
        v = Vector((0, 1, 0)) - u * u.y
    v.normalize()
    ca = (l1 * l1 + D * D - l2 * l2) / (2 * l1 * D)
    ca = max(-1.0, min(1.0, ca))
    sa = math.sqrt(max(0.0, 1 - ca * ca))
    E = S + (u * ca + v * sa) * l1
    hinge = v.cross(u).normalized()
    return E, W2, hinge


class Pose:
    """Pose description.  Fill attributes then call ``solve()``.

    hips_off : Vector offset of the hips (armature space)
    rot[b]   : 3x3 rotation (rest armature axes) for FK bones
    arm[side]: dict(target=Vector (chest space), pole=Vector (chest space),
               fingers=Vector, palm=Vector (chest space, optional),
               space='chest'|'world', wrist=3x3 extra rotation)
    leg[side]: dict(ankle=Vector world, pole=Vector world,
               foot=3x3 absolute foot rotation, toe=3x3 absolute toe rot)
    """

    def __init__(self, skel):
        self.sk = skel
        self.hips_off = Vector((0, 0, 0))
        self.root_rot = Matrix.Identity(3)
        self.rot = {}
        self.arm = {}
        self.leg = {}
        self.D = {}
        self.clamped = []

    # ------------------------------------------------------------------
    def _fk(self, name, parent_D):
        h = self.sk.heads[name]
        R = self.rot.get(name, Matrix.Identity(3)).to_4x4()
        return parent_D @ T(h) @ R @ T(-h)

    def _abs(self, name, head_pos, R_abs):
        """Delta transform placing bone ``name`` with absolute rotation
        R_abs (3x3, delta) and posed head at head_pos."""
        h = self.sk.heads[name]
        return T(head_pos) @ R_abs.to_4x4() @ T(-h)

    def solve(self):
        sk = self.sk
        D = {}
        D["root"] = T(Vector((0, 0, 0))) @ self.root_rot.to_4x4()
        hD = T(self.hips_off) @ D["root"]
        D["hips"] = self._fk("hips", hD)
        D["spine"] = self._fk("spine", D["hips"])
        D["chest"] = self._fk("chest", D["spine"])
        D["neck"] = self._fk("neck", D["chest"])
        D["head"] = self._fk("head", D["neck"])
        for side in ("L", "R"):
            sh = "shoulder." + side
            D[sh] = self._fk(sh, D["chest"])
            ua, fa, hd = "upper_arm." + side, "forearm." + side, "hand." + side
            spec = self.arm.get(side)
            if spec is None:
                D[ua] = self._fk(ua, D[sh])
                D[fa] = self._fk(fa, D[ua])
                D[hd] = self._fk(hd, D[fa])
                continue
            space = spec.get("space", "chest")
            if space == "chest":
                Ms = D["chest"]
            elif space == "head":
                Ms = D["head"]
            elif space == "hips":
                Ms = D["hips"]
            else:
                Ms = Matrix.Identity(4)
            R_s = Ms.to_3x3()
            S = D[sh] @ sk.heads[ua]
            W = Ms @ spec["target"]
            pole = R_s @ spec.get("pole", Vector((0, 1, -0.3)))
            l1, l2 = sk.length[ua], sk.length[fa]
            E, W2, hinge = two_bone_ik(S, W, l1, l2, pole)
            if (W - W2).length > 0.001:
                self.clamped.append((side + "arm", (W - W2).length))
            F0u = sk.rest[ua].to_3x3()
            F0f = sk.rest[fa].to_3x3()
            Fu = frame3(hinge, E - S)
            Ff = frame3(hinge, W2 - E)
            Ru = Fu @ F0u.transposed()
            Rf = Ff @ F0f.transposed()
            D[ua] = self._abs(ua, S, Ru)
            D[fa] = self._abs(fa, E, Rf)
            F0h = sk.rest[hd].to_3x3()
            if spec.get("fingers") is not None:
                fdir = R_s @ spec["fingers"]
                palm = R_s @ spec["palm"]
                # rest frame of the hand expressed as (palm, fingers)
                Fh0 = frame3(sk.palm_rest[side], F0h.col[1])
                Fh = frame3(palm, fdir)
                Rh = Fh @ Fh0.transposed()
            else:
                Rh = Rf @ spec.get("wrist", Matrix.Identity(3))
            D[hd] = self._abs(hd, W2, Rh)
        for side in ("L", "R"):
            th, sh_, ft, to = ("thigh." + side, "shin." + side,
                               "foot." + side, "toe." + side)
            spec = self.leg.get(side)
            if spec is None:
                D[th] = self._fk(th, D["hips"])
                D[sh_] = self._fk(sh_, D[th])
                D[ft] = self._fk(ft, D[sh_])
                D[to] = self._fk(to, D[ft])
                continue
            Hj = D["hips"] @ sk.heads[th]
            A = spec["ankle"]
            l1, l2 = sk.length[th], sk.length[sh_]
            E, A2, hinge = two_bone_ik(Hj, A, l1, l2, spec["pole"])
            if (A - A2).length > 0.0005:
                self.clamped.append((side + "leg", (A - A2).length))
            F0t = sk.rest[th].to_3x3()
            F0s = sk.rest[sh_].to_3x3()
            # legs: rest hinge (x axis) = +X; flexion = knee forward.
            Ft = frame3(hinge, E - Hj)
            Fs = frame3(hinge, A2 - E)
            D[th] = self._abs(th, Hj, Ft @ F0t.transposed())
            D[sh_] = self._abs(sh_, E, Fs @ F0s.transposed())
            Rfoot = spec.get("foot", Matrix.Identity(3))
            D[ft] = self._abs(ft, A2, Rfoot)
            ball = D[ft] @ sk.heads[to]
            Rtoe = spec.get("toe", Rfoot)
            D[to] = self._abs(to, ball, Rtoe)
        self.D = D
        return D

    # ------------------------------------------------------------------
    def basis(self):
        """Blender pose-bone (location, quaternion) per bone."""
        sk = self.sk
        out = {}
        for name in BONE_NAMES:
            M = sk.rest[name]
            par = PARENT[name]
            Dp = self.D[par] if par else Matrix.Identity(4)
            B = M.inverted() @ Dp.inverted() @ self.D[name] @ M
            loc, q, _ = B.decompose()
            out[name] = (loc, q)
        return out

    def world(self, name, local_point=None):
        """Posed position of a rest-space point (default: bone head)."""
        p = self.sk.heads[name] if local_point is None else local_point
        return self.D[name] @ p
