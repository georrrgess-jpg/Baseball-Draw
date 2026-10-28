"""Baseball Draw character generator.

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py [ids...]
        [--no-portraits] [--portraits-only] [--no-glb] [--out ROOT] [--save-blend DIR]

Builds assets/models/characters/<id>.glb (mesh + shared armature + all
animation clips) and assets/textures/portraits/<id>.png for every id given
(default: all 20).  Everything is procedural and deterministic.

Defenders are stylised mesh-modelled heroes (hero.py + hero_head/body/wear,
geo.py); runners and bosses use the same hero pipeline with their own gear
(enemies.py).
"""
import os
import sys
import time
import json
import math

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np
import bpy
from mathutils import Vector

import meshutil as mu
import materials as M
import rig
import skin
import anim
import roster
import render

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FONT = os.path.join(REPO, "assets", "fonts", "RussoOne-Regular.ttf")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mu.reset_parts()
    sc = bpy.context.scene
    sc.render.fps = anim.FPS
    sc.frame_start = 0


def lighten(hexs, f):
    r, g, b = (int(hexs[i:i + 2], 16) for i in (1, 3, 5))
    r, g, b = (min(255, int(c + (255 - c) * f)) if f > 0 else max(0, int(c * (1 + f)))
               for c in (r, g, b))
    return "#%02X%02X%02X" % (r, g, b)


# ---------------------------------------------------------------------------
# budgets
# ---------------------------------------------------------------------------

def enforce_budget(parts, budget):
    parts = [p for p in parts if p is not None]
    tot = sum(mu.tri_count(p) for p in parts)
    if tot <= budget * 0.98:
        return tot
    big = [p for p in parts if mu.tri_count(p) > 260]
    small_tot = tot - sum(mu.tri_count(p) for p in big)
    big_tot = tot - small_tot
    ratio = (budget * 0.97 - small_tot) / big_tot
    for p in big:
        target = int(mu.tri_count(p) * ratio)
        mu.apply_decimate(p, target, symmetric=False)
        mu.shade(p, True, None)
    return sum(mu.tri_count(p) for p in parts)


def crown_height(props):
    sk = rig.Skeleton(dict(props, scale=1.0))
    o, h = sk.head_frame()
    return o.z + 0.53 * h


# ---------------------------------------------------------------------------
# defenders
# ---------------------------------------------------------------------------

def defender_materials(cfg):
    P = M.PALETTE
    cols = dict(Skin=cfg["skin"], Hair=cfg["hair"], Eyes=P["eyes"], Iris=cfg["iris"],
                Pupil=P["pupil"], Jersey=P["jersey"], JerseyTrim=P["trim"], Number=P["number"],
                NumberOutline=P["gold"], Pants=P["pants"], Socks=P["socks"], Shoes=P["shoes"],
                Belt=P["belt"], Cap=P["cap"], Glove=P["glove"], Undershirt=cfg["accent"],
                Metal=P["metal"], Mouth=P["mouth"], Sole=P["sole"])
    if cfg.get("gear"):
        cols["Gear"] = cfg["accent"]
    if cfg.get("sunglasses"):
        cols["Visor"] = cfg["accent"]
    if cfg.get("brow_col"):
        cols["Brow"] = cfg["brow_col"]
    mats = M.material_set(cols)
    mats["EyeHighlight"] = M.make("EyeHighlight", "#FFFFFF", "#FFFFFF", 1.5, rough=0.2)
    if cfg.get("sunglasses"):
        mats["Visor"] = M.make("Visor", cfg["accent"], rough=0.12, metal=0.45)
    if cfg.get("gear"):
        mats["Gear"] = M.make("Gear", cfg["accent"], rough=0.3, metal=0.15)
    return mats


def build_defender(cid):
    """Stylised hero defender (mesh-modelled, see hero.py)."""
    import hero
    cfg = roster.DEFENDERS[cid]
    sk = hero.make_skeleton(cfg)
    arm = sk.build("Armature")
    mats = defender_materials(cfg)
    hb = hero.Hero(cid, cfg, sk, mats, FONT)
    parts = hb.build()
    tot, rows = hero.report(parts)
    print("TRIS", cid, tot, rows[:12])
    return finish(cid, "defender", sk, arm, parts, style={"idle": cfg.get("idle", "relaxed")},
                  hero_parts=True)


# ---------------------------------------------------------------------------
# enemies / bosses
# ---------------------------------------------------------------------------

def enemy_materials(cfg):
    """Hero material set for a Wrecker: shared kit + accent + per-type colours."""
    P = M.PALETTE
    acc = cfg["accent"]
    cols = dict(roster.WRECKERS)
    cols.update(Skin=cfg["skin"], Hair=cfg["hair"], Eyes=P["eyes"], Iris=cfg["iris"],
                Pupil=P["pupil"], JerseyTrim=acc, Number=acc, Socks=acc, Cap=acc,
                Mouth=P["mouth"])
    cols.update(cfg.get("colors", {}))
    if cfg.get("brow_col"):
        cols["Brow"] = cfg["brow_col"]
    glow = cols["Glow"]
    mats = M.material_set(cols, emissive={"Glow": (glow, 6.0)})
    mats["EyeHighlight"] = M.make("EyeHighlight", "#FFFFFF", "#FFFFFF", 1.5, rough=0.2)
    mats["Visor"] = M.make("Visor", cols["Visor"], rough=0.10, metal=0.6)
    mats["Gear"] = M.make("Gear", cols["Gear"], rough=0.3, metal=0.2)
    gold = cfg.get("gold")
    mats["Metal"] = M.make("Metal", cols["Metal"], rough=0.28 if gold else 0.32,
                           metal=0.75 if gold else 0.6)
    if cfg.get("cap_metal"):
        mats["Cap"] = M.make("Cap", cols["Cap"], rough=0.3, metal=0.6 if not gold else 0.75)
    else:
        mats["Cap"] = M.make("Cap", cols["Cap"], rough=0.35, metal=0.05)   # glossy helmet
    if cfg.get("bat", {}).get("metal"):
        mats["Bat"] = M.make("Bat", cols["Bat"], rough=0.25, metal=0.7)
    if cfg.get("glow_iris"):
        mats["Iris"] = M.make("Iris", cfg["iris"], cfg["iris"], 3.0)
    if cfg.get("ghost"):
        mats["Cloth"] = M.make("Cloth", cols["Cloth"], cols["Cloth"], 0.6, alpha=0.72)
        mats["JerseyTrim"] = M.make("JerseyTrim", acc, acc, 3.0)
        mats["Socks"] = M.make("Socks", cols["Socks"], cols["Socks"], 1.2)
    return mats


def build_enemy(cid):
    """Runner / boss in the stylised hero style (enemies.py)."""
    import hero
    import enemies
    cfg = dict(roster.ENEMIES[cid])
    cfg["_id"] = cid
    boss = cfg.get("boss", False)
    hcfg = dict(cfg)
    hcfg["top_extra"] = cfg.get("top_extra", 0.0) + {"helmet": 0.03, "aero": 0.0,
                                                     "beanie": 0.10}.get(cfg["headwear"], 0.0)
    sk = hero.make_skeleton(hcfg)
    arm = sk.build("Armature")
    mats = enemy_materials(cfg)
    eb = enemies.EnemyHero(cid, cfg, sk, mats, FONT)
    parts = eb.build()
    tot, rows = hero.report(parts)
    print("TRIS", cid, tot, rows[:12])
    style = dict(heavy=cfg.get("heavy", 0.0), bat=bool(cfg.get("bat")),
                 small=cfg.get("small", False), hero=True, gait=cfg.get("gait", "runner"))
    return finish(cid, "boss" if boss else "enemy", sk, arm, parts, style=style,
                  hero_parts=True)


# ---------------------------------------------------------------------------
# finish: weights, join, animation, export
# ---------------------------------------------------------------------------

LAST = {}


def finish(cid, kind, sk, arm, parts, style, hero_parts=False):
    parts = [p for p in parts if p is not None]
    budget = roster.BUDGET[kind]
    if hero_parts:
        # clean quad meshes built to budget: no decimation, decals copy the
        # weights of the surface under them
        import hero
        hero.apply_weights(parts, sk)
        if kind != "defender":
            import enemies
            enemies.apply_fixed_weights(parts)
        tot = sum(mu.tri_count(p) for p in parts)
        if tot > budget:
            print("WARNING: %s over budget: %d > %d" % (cid, tot, budget))
    else:
        tot = enforce_budget(parts, budget)
        for p in parts:
            mu.cleanup(p)
            skin.apply_weights(p, sk)
    body_obj = skin.join_parts(parts, "Body", arm)
    arm["props"] = json.dumps(sk.p)
    arm["kind"] = kind
    arm["style"] = json.dumps(style)
    c = anim.Ctx(sk, "defender" if kind == "defender" else "enemy", style)
    actions, rep = anim.bake(arm, c, "defender" if kind == "defender" else "enemy")
    LAST.clear()
    LAST.update(dict(id=cid, kind=kind, tris=mu.tri_count(body_obj), anims=rep, sk=sk,
                     arm=arm, body=body_obj, actions=actions, ctx=c))
    return LAST


def export_glb(path, arm, actions):
    # leave the armature with no active action, push all actions to NLA so
    # the exporter (ACTIONS mode) sees every one of them
    ad = arm.animation_data
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for act, slot in actions:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, 0, act)
        try:
            st.action_slot = slot
        except Exception:
            pass
        tr.mute = True
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=False, export_yup=True,
        export_apply=False, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_optimize_animation_size=False,
        export_anim_single_armature=True, export_def_bones=False, export_skins=True,
        export_morph=False, export_materials='EXPORT', export_cameras=False,
        export_lights=False, export_extras=False, export_rest_position_armature=True,
        export_reset_pose_bones=True, export_frame_range=False, export_texcoords=False,
        export_normals=True, export_tangents=False, export_attributes=False)


def build(cid, out_root, glb=True, portrait=True, save_blend=None):
    t0 = time.time()
    reset_scene()
    if cid in roster.DEFENDERS:
        info = build_defender(cid)
    else:
        info = build_enemy(cid)
    path = os.path.join(out_root, "assets", "models", "characters", cid + ".glb")
    if save_blend:
        os.makedirs(save_blend, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(save_blend, cid + ".blend"))
    if glb:
        export_glb(path, info["arm"], info["actions"])
    if portrait:
        import portrait as PT
        PT.render_portrait(cid, info, os.path.join(out_root, "assets", "textures", "portraits",
                                                   cid + ".png"))
    dt = time.time() - t0
    rep = dict(id=cid, kind=info["kind"], tris=info["tris"], seconds=round(dt, 1),
               height=round(max((info["body"].matrix_world @ v.co).z
                                for v in info["body"].data.vertices), 3),
               anims={k: dict(length=v["length"], frames=v["frames"], loop=v["loop"],
                              warn=v["warn"]) for k, v in info["anims"].items()})
    print("BUILT", json.dumps(rep))
    return rep


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = [a for a in argv if a.startswith("--")]
    out_root = REPO
    save_blend = None
    for f in flags:
        if f.startswith("--out="):
            out_root = f.split("=", 1)[1]
        if f.startswith("--save-blend="):
            save_blend = f.split("=", 1)[1]
    ids = args or roster.ALL_IDS
    portraits = "--no-portraits" not in flags
    glb = "--no-glb" not in flags
    reports = []
    for cid in ids:
        if cid not in roster.ALL_IDS:
            print("unknown id", cid)
            continue
        reports.append(build(cid, out_root, glb=glb, portrait=portraits, save_blend=save_blend))
    rp = os.path.join(out_root, "docs", "asset_reports", "characters_build.json")
    try:
        old = json.load(open(rp)) if os.path.exists(rp) else {}
    except Exception:
        old = {}
    for r in reports:
        old[r["id"]] = r
    os.makedirs(os.path.dirname(rp), exist_ok=True)
    json.dump(old, open(rp, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    main(argv)
