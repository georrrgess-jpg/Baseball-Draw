"""Procedural skin weights: inverse distance to per-bone influence segments
(normalised by a per-bone thickness), restricted to the bones a part allows,
then Laplacian-smoothed over the part's own mesh.  Rigid parts get 100 % to
one bone."""
import numpy as np
import bpy

import meshutil as mu

# thickness (reference metres) used to normalise distances
BONE_R = {
    "hips": 0.15, "spine": 0.14, "chest": 0.16, "neck": 0.06, "head": 0.10,
    "shoulder.L": 0.065, "shoulder.R": 0.065,
    "upper_arm.L": 0.055, "upper_arm.R": 0.055,
    "forearm.L": 0.045, "forearm.R": 0.045,
    "hand.L": 0.045, "hand.R": 0.045,
    "thigh.L": 0.09, "thigh.R": 0.09,
    "shin.L": 0.06, "shin.R": 0.06,
    "foot.L": 0.05, "foot.R": 0.05,
    "toe.L": 0.035, "toe.R": 0.035,
}


def influence_segments(sk):
    s = sk.s
    H, T = sk.heads, sk.tails
    L = sk.levels
    seg = {}

    def v(x):
        return np.array(x, dtype=np.float64)
    seg["hips"] = (v((0, 0.0, L["pelvis"] - 0.04 * s)), v((0, 0.0, L["spine"])))
    seg["spine"] = (v((0, 0.0, L["spine"])), v((0, 0.0, L["chest"])))
    seg["chest"] = (v((0, 0.0, L["chest"])), v((0, 0.0, L["neck"] - 0.02 * s)))
    seg["neck"] = (v(H["neck"]), v(T["neck"]))
    seg["head"] = (v(H["head"]) + v((0, 0, 0.02 * s)), v(T["head"]))
    for sd in ("L", "R"):
        seg["shoulder." + sd] = (v(H["shoulder." + sd]), v(T["shoulder." + sd]))
        S = v(H["upper_arm." + sd])
        E = v(T["upper_arm." + sd])
        seg["upper_arm." + sd] = (S + (E - S) * 0.08, E)
        seg["forearm." + sd] = (v(H["forearm." + sd]), v(T["forearm." + sd]))
        W = v(H["hand." + sd])
        seg["hand." + sd] = (W, W + (v(T["hand." + sd]) - W) * 1.4)
        Hh = v(H["thigh." + sd])
        K = v(T["thigh." + sd])
        seg["thigh." + sd] = (Hh + (K - Hh) * 0.10, K)
        seg["shin." + sd] = (v(H["shin." + sd]), v(T["shin." + sd]))
        seg["foot." + sd] = (v(H["foot." + sd]), v(T["foot." + sd]))
        seg["toe." + sd] = (v(H["toe." + sd]), v(T["toe." + sd]))
    return seg


def seg_dist(P, a, b):
    ab = b - a
    l2 = max(float(ab @ ab), 1e-12)
    t = np.clip((P - a) @ ab / l2, 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def mesh_edges(obj):
    me = obj.data
    e = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def compute_weights(obj, sk, bones, power=5.0, smooth_iters=6, overrides=None):
    P = mu.mesh_arrays(obj)
    segs = influence_segments(sk)
    s = sk.s
    W = np.zeros((len(P), len(bones)))
    for j, b in enumerate(bones):
        a, c = segs[b]
        r = BONE_R[b] * s
        if overrides and b in overrides:
            r *= overrides[b]
        d = seg_dist(P, a, c) / r
        W[:, j] = np.maximum(d, 0.2) ** (-power)
    W /= W.sum(1, keepdims=True)
    if smooth_iters and len(P) > 3:
        E = mesh_edges(obj)
        deg = np.zeros(len(P))
        np.add.at(deg, E[:, 0], 1)
        np.add.at(deg, E[:, 1], 1)
        deg = np.maximum(deg, 1)
        for _ in range(smooth_iters):
            acc = np.zeros_like(W)
            np.add.at(acc, E[:, 0], W[E[:, 1]])
            np.add.at(acc, E[:, 1], W[E[:, 0]])
            W = 0.5 * W + 0.5 * acc / deg[:, None]
    # keep top 4
    if W.shape[1] > 4:
        idx = np.argsort(-W, axis=1)[:, 4:]
        np.put_along_axis(W, idx, 0.0, axis=1)
    W[W < 0.01] = 0.0
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    return W


def apply_weights(obj, sk):
    rigid = obj.get("rigid", "")
    n = len(obj.data.vertices)
    if rigid:
        vg = obj.vertex_groups.get(rigid) or obj.vertex_groups.new(name=rigid)
        vg.add(list(range(n)), 1.0, 'REPLACE')
        return
    bones = [b for b in obj.get("bones", "").split(",") if b]
    if not bones:
        raise RuntimeError("part %s has no bones" % obj.name)
    ov = obj.get("weight_overrides")
    overrides = (ov.to_dict() if hasattr(ov, 'to_dict') else dict(ov)) if ov else None
    W = compute_weights(obj, sk, bones, overrides=overrides)
    for j, b in enumerate(bones):
        col = W[:, j]
        nz = np.nonzero(col > 0)[0]
        if len(nz) == 0:
            continue
        vg = obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)
        # group by identical weights is not worth it; add per vertex
        for i in nz:
            vg.add([int(i)], float(col[i]), 'REPLACE')


def join_parts(parts, name, armature):
    parts = [p for p in parts if p is not None]
    base = parts[0]
    with bpy.context.temp_override(active_object=base, selected_editable_objects=parts,
                                   selected_objects=parts):
        bpy.ops.object.join()
    base.name = name
    base.data.name = name
    base.parent = armature
    mod = base.modifiers.new("Armature", 'ARMATURE')
    mod.object = armature
    return base
