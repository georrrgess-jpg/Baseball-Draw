"""Uniform layering check on the exported defender GLBs.

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/characters/check_layers.py [ids...] [--dir=DIR]
        [--json=OUT.json]

For every pair (inner layer, outer layer) - jersey hem under the pants waist,
undershirt/skin arm under the jersey sleeve, sock under the pant cuff (and
under Rico's shin guards), neck under the collar - each inner vertex that is covered in the rest
pose is anchored to the outermost covering triangle (ray along its normal).
In every frame of every clip the vertex's signed distance to its posed
anchor triangle is measured; a positive value means the inner layer pokes
through the outer one.  Reported per pair and clip: the worst poke-out (m),
the time it happens and the number of vertices poking out by more than 3 mm.
"""
import os
import sys
import json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import roster

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# label: (inner materials, outer materials, max cover distance (m), z filter)
PAIRS = {
    "waist": (("Jersey",), ("Pants", "Belt"), 0.07, "waist"),
    "sleeve": (("Undershirt", "Skin"), ("Jersey", "JerseyTrim"), 0.05, "arm"),
    "cuff": (("Socks", "JerseyTrim"), ("Pants", "Gear"), 0.06, "shin"),
    "collar": (("Skin",), ("Jersey", "JerseyTrim"), 0.05, "neck"),
}
POKE = 0.003
DEBUG = False


def base(name):
    return name.split(".")[0]


def vert_mats(me):
    n = len(me.vertices)
    vm = np.full(n, -1, np.int64)
    for p in me.polygons:
        for vi in p.vertices:
            vm[vi] = p.material_index
    return vm


def tri_arrays(me, mat_ids):
    me.calc_loop_triangles()
    tris = np.array([t.vertices[:] for t in me.loop_triangles], np.int64)
    mats = np.array([t.material_index for t in me.loop_triangles], np.int64)
    keep = np.isin(mats, list(mat_ids))
    return tris[keep]


def anchors(me, co, inner_idx, tris, dmax):
    bvh = BVHTree.FromPolygons([tuple(map(float, c)) for c in co], tris.tolist(), all_triangles=True)
    res = []
    for vi in inner_idx:
        p = Vector(co[vi])
        nrm = me.vertices[vi].normal
        if nrm.length < 0.5:
            continue
        last = None
        o = p + nrm * 0.0005
        travelled = 0.0
        for _ in range(6):
            hit = bvh.ray_cast(o, nrm, dmax - travelled)
            if hit[0] is None:
                break
            last = hit
            travelled += (hit[0] - o).length + 0.0005
            o = hit[0] + nrm * 0.0005
        if last is None:
            continue
        ti = last[2]
        a, b, c = (co[k] for k in tris[ti])
        n = np.cross(b - a, c - a)
        n /= max(np.linalg.norm(n), 1e-12)
        d0 = float((co[vi] - a) @ n)
        sgn = -1.0 if d0 > 0 else 1.0      # inner side -> negative distance
        res.append((vi, ti, sgn))
    return res


def bary(P, A, B, C):
    v0, v1, v2 = B - A, C - A, P - A
    d00 = (v0 * v0).sum(1)
    d01 = (v0 * v1).sum(1)
    d11 = (v1 * v1).sum(1)
    d20 = (v2 * v0).sum(1)
    d21 = (v2 * v1).sum(1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-14)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    return 1 - v - w, v, w


def check(cid, path, step=2):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 60
    bpy.ops.import_scene.gltf(filepath=path)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    body = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    me = body.data
    mat_names = [base(m.name) for m in me.materials]
    vm = vert_mats(me)
    co0 = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co0)
    co0 = co0.reshape(-1, 3)
    mw = np.array(body.matrix_world)
    # mesh space -> world (glTF import: y-up converted, armature parent)
    co0w = co0 @ mw[:3, :3].T + mw[:3, 3]
    zs = co0w[:, 2]
    H = zs.max()
    sets = {}
    tmat = {}
    for label, (inner, outer, dmax, zf) in PAIRS.items():
        ii = [i for i, m in enumerate(mat_names) if m in inner]
        oo = [i for i, m in enumerate(mat_names) if m in outer]
        if not oo:
            continue
        idx = np.nonzero(np.isin(vm, ii))[0]
        if zf == "waist":
            idx = idx[(zs[idx] < 0.62 * H) & (zs[idx] > 0.38 * H)]
        elif zf == "arm":
            idx = idx[(zs[idx] > 0.55 * H) & (np.abs(co0w[idx, 0]) > 0.08 * H)]
        elif zf == "neck":
            idx = idx[(zs[idx] > 0.70 * H) & (np.abs(co0w[idx, 0]) < 0.06 * H)]
        elif zf == "shin":
            idx = idx[zs[idx] < 0.40 * H]
        tris = tri_arrays(me, oo)
        an = anchors(me, co0, idx, tris, dmax)
        if not an:
            continue
        vi = np.array([a[0] for a in an])
        tr = tris[np.array([a[1] for a in an])]
        sg = np.array([a[2] for a in an])
        sets[label] = (vi, tr, sg)
        tmat[label] = vm[tr[:, 0]]
    out = {}
    if arm.animation_data is None:
        arm.animation_data_create()
    for act in bpy.data.actions:
        name = act.name.split("_Armature")[0].split("|")[0]
        arm.animation_data.action = act
        try:
            arm.animation_data.action_slot = act.slots[0]
        except Exception:
            pass
        f0, f1 = (int(round(x)) for x in act.frame_range)
        best = {k: [0.0, 0.0, 0] for k in sets}
        for f in list(range(f0, f1 + 1, step)) + [f1]:
            sc.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            ev = body.evaluated_get(dg)
            m2 = ev.to_mesh()
            co = np.empty(len(m2.vertices) * 3)
            m2.vertices.foreach_get("co", co)
            ev.to_mesh_clear()
            co = co.reshape(-1, 3)
            for k, (vi, tr, sg) in sets.items():
                P = co[vi]
                A, B, C = co[tr[:, 0]], co[tr[:, 1]], co[tr[:, 2]]
                n = np.cross(B - A, C - A)
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
                d = ((P - A) * n).sum(1) * sg
                u, v, w = bary(P - n * d[:, None] * sg[:, None], A, B, C)
                inside = (u > -0.6) & (v > -0.6) & (w > -0.6)
                d = np.where(inside, d, 0.0)
                mx = float(d.max())
                if DEBUG and mx > best[k][0] and mx > POKE:
                    j = int(d.argmax())
                    best[k].append((round((f - f0) / 60.0, 3), mat_names[vm[vi[j]]],
                                    mat_names[tmat[k][j]], [round(x, 3) for x in co0w[vi[j]]]))
                cnt = int((d > POKE).sum())
                if mx > best[k][0]:
                    best[k][0] = mx
                    best[k][1] = round((f - f0) / 60.0, 3)
                best[k][2] = max(best[k][2], cnt)
        if DEBUG:
            for k, v in best.items():
                if len(v) > 3:
                    print("DBG", name, k, v[-1])
        out[name] = {k: dict(poke=round(v[0], 4), at=v[1], verts=v[2]) for k, v in best.items()}
    return out


def main(ids, src, js):
    res = {}
    for cid in ids:
        p = os.path.join(src, cid + ".glb")
        res[cid] = check(cid, p)
        worst = {}
        for clip, d in res[cid].items():
            for k, v in d.items():
                if v["poke"] > worst.get(k, (0, ""))[0]:
                    worst[k] = (v["poke"], "%s@%.2f n=%d" % (clip, v["at"], v["verts"]))
        print("LAYERS", cid, json.dumps({k: "%.1fcm %s" % (v[0] * 100, v[1]) for k, v in worst.items()}))
        for clip, d in sorted(res[cid].items()):
            bad = {k: v for k, v in d.items() if v["poke"] > POKE}
            if bad:
                print("   ", clip, json.dumps(bad))
    if js:
        json.dump(res, open(js, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    src = os.path.join(REPO, "assets", "models", "characters")
    js = None
    for a in list(argv):
        if a.startswith("--dir="):
            src = a.split("=", 1)[1]
            argv.remove(a)
        elif a == "--debug":
            DEBUG = True
            argv.remove(a)
        elif a.startswith("--json="):
            js = a.split("=", 1)[1]
            argv.remove(a)
    main(argv or list(roster.DEFENDERS), src, js)
