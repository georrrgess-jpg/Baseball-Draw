"""Animation review strips: render key frames of every defender clip from the
battle camera angle and from close 3/4 front / back views (Cycles, CPU).

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/characters/review_frames.py OUT_DIR [ids...]
        [--views=battle,front,back] [--clips=throw,catch] [--res=300] [--glb-dir=DIR]
        [--focus=ZC,FH] (close-up: centre and frame height as fractions of the height)
        [--times=t1,t2] (override the key times of the selected clips)

Writes OUT_DIR/<id>_<view>.png contact sheets (one tile per clip/time, labelled)
using ImageMagick ``montage``; the single frames stay in OUT_DIR/frames/.
"""
import os
import sys
import math
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy
from mathutils import Vector

import roster

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# clip -> key times (s); event frames included (throw 0.30, catch 0.25, ...)
FRAMES = [
    ("idle", [0.0, 0.5, 1.0, 1.5]),
    ("ready", [0.0, 0.4]),
    ("run", [0.0, 0.175, 0.35, 0.525]),
    ("throw", [0.05, 0.12, 0.19, 0.25, 0.30, 0.36, 0.45, 0.60]),
    ("catch", [0.10, 0.18, 0.25, 0.33, 0.45]),
    ("celebrate", [0.0, 0.18, 0.30, 0.42, 0.55, 0.75]),
    ("hit", [0.05, 0.10, 0.18, 0.28]),
    ("pitch", [0.50, 0.72, 0.85, 1.0]),
    ("special", [0.40, 0.58, 0.70, 0.90]),
    ("victory", [0.0, 0.5]),
]
# view -> (azimuth deg from the front, elevation deg, ortho scale in heights)
VIEWS = {
    "battle": (25.0, 52.0, 1.30),
    "front": (35.0, 10.0, 1.25),
    "back": (150.0, 12.0, 1.25),
    "rside": (90.0, 8.0, 1.25),
    "lside": (-90.0, 8.0, 1.25),
    "backleft": (-150.0, 12.0, 1.25),
}


def setup(res, samples=10):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 2
    sc.render.resolution_x = res
    sc.render.resolution_y = int(res * 1.25)
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    try:
        sc.view_settings.view_transform = 'Standard'
    except Exception:
        pass
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.36, 0.50, 0.32, 1.0)   # grass-ish backdrop
    bg.inputs[1].default_value = 0.9
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = 3.2
    ld.angle = math.radians(8)
    ob = bpy.data.objects.new("Sun", ld)
    sc.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(40), math.radians(10), math.radians(-30))
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, az, el, scale, height, focus=None):
    a, e = math.radians(az), math.radians(el)
    target = Vector((0, 0, height * 0.50))
    if focus:
        # (z centre, frame height) in fractions of the character height
        target = Vector((0, 0, height * focus[0]))
        scale = focus[1]
    d = Vector((-math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = target + d * 8.0
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = scale * height
    cam.data.clip_end = 50


def set_action(arm, name):
    act = None
    for a in bpy.data.actions:
        if a.name.split("_Armature")[0].split("|")[0] == name:
            act = a
    if act is None:
        return None
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        ad.action_slot = act.slots[0]
    except Exception:
        pass
    return act


def run(cid, out, views, clips, res, glb_dir, focus=None, times=None, tag=""):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 60
    bpy.ops.import_scene.gltf(filepath=os.path.join(glb_dir, cid + ".glb"))
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    body = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    height = max((body.matrix_world @ v.co).z for v in body.data.vertices)
    cam = setup(res)
    fdir = os.path.join(out, "frames")
    os.makedirs(fdir, exist_ok=True)
    for vname in views:
        az, el, scl = VIEWS[vname]
        aim(cam, az, el, scl, height, focus)
        tiles = []
        for clip, tlist in FRAMES:
            if clips and clip not in clips:
                continue
            if times:
                tlist = times
            if set_action(arm, clip) is None:
                continue
            for t in tlist:
                sc.frame_set(int(round(t * 60)))
                p = os.path.join(fdir, "%s%s_%s_%s_%03d.png" % (cid, tag, vname, clip, int(round(t * 100))))
                sc.render.filepath = p
                bpy.ops.render.render(write_still=True)
                tiles.append((p, "%s %.2f" % (clip, t)))
        sheet = os.path.join(out, "%s%s_%s.png" % (cid, tag, vname))
        cmd = ["montage"]
        for p, lab in tiles:
            cmd += ["-label", lab, p]
        cmd += ["-tile", "8x", "-geometry", "+2+2", "-pointsize", "14", "-background", "#202020",
                "-fill", "white", sheet]
        subprocess.run(cmd, check=False)
        print("SHEET", sheet)


def main(argv):
    out = argv[0]
    rest = argv[1:]
    ids = [a for a in rest if not a.startswith("--")] or list(roster.DEFENDERS)
    views = ["battle", "front", "back"]
    clips = None
    res = 300
    glb_dir = os.path.join(REPO, "assets", "models", "characters")
    focus = None
    times = None
    tag = ""
    for a in rest:
        if a.startswith("--focus="):
            focus = [float(x) for x in a.split("=", 1)[1].split(",")]
            tag = "_z%d" % int(focus[0] * 100)
        elif a.startswith("--times="):
            times = [float(x) for x in a.split("=", 1)[1].split(",")]
        if a.startswith("--views="):
            views = a.split("=", 1)[1].split(",")
        elif a.startswith("--clips="):
            clips = set(a.split("=", 1)[1].split(","))
        elif a.startswith("--res="):
            res = int(a.split("=", 1)[1])
        elif a.startswith("--glb-dir="):
            glb_dir = a.split("=", 1)[1]
    os.makedirs(out, exist_ok=True)
    for cid in ids:
        run(cid, out, views, clips, res, glb_dir, focus, times, tag)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    main(argv)
