"""Re-import the exported GLBs and measure animation quality numbers.

Usage:
    /opt/tools/bpyenv/bin/python tools/blender/characters/verify_characters.py [ids...]

For every clip it reports
  * length (s) as imported,
  * foot slide: max horizontal drift of each foot while it is on the ground
    (only for clips where the feet should stay planted),
  * lowest mesh point over the clip (ground penetration check; feet/shoes
    should stay >= about -1 cm),
  * loop seam: max bone-position difference between first and last frame for
    looping clips.
"""
import os
import sys
import json
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy
import numpy as np
import roster

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PLANTED = {"idle", "ready", "stunned", "hit", "victory", "taunt", "slam", "catch"}
LOOPS = {"idle", "run", "stunned", "celebrate", "ready", "victory", "walk", "sprint"}


def check(cid, path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 60
    bpy.ops.import_scene.gltf(filepath=path)
    sc = bpy.context.scene
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    body = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    fps = sc.render.fps / sc.render.fps_base
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
        f0, f1 = act.frame_range
        frames = list(range(int(round(f0)), int(round(f1)) + 1))
        feet = {"toe.L": [], "toe.R": []}
        minz = 1e9
        bones0 = None
        bonesN = None
        step = 2
        for i, f in enumerate(frames):
            sc.frame_set(f)
            if i % step == 0 or i == len(frames) - 1:
                dg = bpy.context.evaluated_depsgraph_get()
                ev = body.evaluated_get(dg)
                me = ev.to_mesh()
                co = np.empty(len(me.vertices) * 3)
                me.vertices.foreach_get("co", co)
                z = co.reshape(-1, 3)[:, 2]
                minz = min(minz, float(z.min()))
                ev.to_mesh_clear()
            for b in feet:
                pb = arm.pose.bones[b]
                feet[b].append(arm.matrix_world @ pb.head)
            pos = np.array([list(arm.matrix_world @ pb.head) for pb in arm.pose.bones])
            if i == 0:
                bones0 = pos
            bonesN = pos
        rec = dict(length=round((f1 - f0) / fps, 3), min_z=round(minz, 4))
        if name in PLANTED:
            slide = 0.0
            for b, ps in feet.items():
                zmin = min(p.z for p in ps)
                grounded = [p for p in ps if p.z < zmin + 0.01]
                if len(grounded) > 1:
                    xs = np.array([[p.x, p.y] for p in grounded])
                    slide = max(slide, float(np.max(np.linalg.norm(xs - xs[0], axis=1))))
            rec["foot_slide"] = round(slide, 4)
        if name in LOOPS:
            rec["loop_seam"] = round(float(np.max(np.linalg.norm(bones0 - bonesN, axis=1))), 5)
        out[name] = rec
    return out


def main(ids, src=None, write=True):
    res = {}
    for cid in ids:
        p = os.path.join(src or os.path.join(REPO, "assets", "models", "characters"), cid + ".glb")
        if not os.path.exists(p):
            print("missing", p)
            continue
        res[cid] = check(cid, p)
        print("VERIFY", cid, json.dumps(res[cid]))
    if not write:
        return res
    rp = os.path.join(REPO, "docs", "asset_reports", "characters_verify.json")
    old = json.load(open(rp)) if os.path.exists(rp) else {}
    old.update(res)
    json.dump(old, open(rp, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    src = None
    for a in list(argv):
        if a.startswith("--dir="):
            src = a.split("=", 1)[1]
            argv.remove(a)
    main(argv or roster.ALL_IDS, src=src, write=src is None)
