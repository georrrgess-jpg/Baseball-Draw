"""Baseball Draw character generator.

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py [ids...]
        [--no-portraits] [--portraits-only] [--no-glb] [--out ROOT] [--save-blend DIR]

Builds assets/models/characters/<id>.glb (mesh + shared armature + all
animation clips) and assets/textures/portraits/<id>.png for every id given
(default: all 20).  Everything is procedural and deterministic.

Defenders are stylised mesh-modelled heroes (hero.py + hero_head/body/wear,
geo.py); enemies/bosses use the SDF sculpt path (body/heads/outfit/enemies).
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

import sdf
import meshutil as mu
import materials as M
import rig
import heads
import body
import outfit
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
    P = M.PALETTE
    acc = cfg["accent"]
    boss = cfg.get("boss")
    cols = dict(Jersey=P["gunmetal"], JerseyTrim=acc, Pants="#4C525C", Socks=acc,
                Shoes="#121317", Belt="#121317", Gear="#3A3F48", Visor=P["visor"],
                Glow=P["glow"], Glove="#1E2126", Undershirt=P["charcoal"], Cloth=P["charcoal"],
                Metal="#8A939E", Number=acc, Bat="#3A2A1E")
    if cid_is(cfg, "trickster"):
        cols["Cloth"] = "#5B2D8E"
    if cfg.get("gold"):
        cols.update(Jersey="#17171B", Pants="#232328", Gear="#17171B", Metal="#E8B23A",
                    Socks="#E8B23A", Bat="#F2C14E", Cloth="#5A0F14")
    if cfg.get("full_iron"):
        cols.update(Metal="#5E646C", Gear="#4A5058", Jersey="#26292E", Pants="#33373D")
    if cfg.get("ghost"):
        cols.update(Jersey="#3B2A55", Pants="#4A3A66", Cloth="#6E3FB8", Gear="#2A1F3D",
                    Socks="#B45CFF", Glove="#2A1F3D", Undershirt="#2A1F3D")
    if cid_is(cfg, "captain"):
        cols["Cloth"] = "#7A1C14"
        cols["Number"] = P["gold"]
    mats = M.material_set(cols, emissive={"Glow": (P["glow"], 6.0)})
    glow = cfg.get("glow_col") or (acc if boss else P["glow"])
    if boss:
        M.make("Glow", glow, glow, 7.0)
    M.make("Visor", P["visor"], rough=0.08, metal=0.6)
    M.make("Gear", cols["Gear"], rough=0.28, metal=0.25)
    M.make("Metal", cols["Metal"], rough=0.32, metal=0.6 if not cfg.get("gold") else 0.7)
    if cfg.get("ghost"):
        M.make("Cloth", cols["Cloth"], cols["Cloth"], 0.6, alpha=0.72)
        M.make("JerseyTrim", acc, acc, 3.0)
        M.make("Socks", "#B45CFF", "#B45CFF", 1.2)
    if cfg.get("golden_bat"):
        M.make("Bat", cols["Bat"], rough=0.25, metal=0.7)
    return mats


def cid_is(cfg, name):
    return cfg.get("_id") == name


def build_enemy(cid):
    cfg = dict(roster.ENEMIES[cid])
    cfg["_id"] = cid
    props = dict(cfg.get("props", {}))
    target = cfg["height"]
    hcfg = cfg.get("helmet", {})
    extra_top = 0.05 * (hcfg.get("size", 1.0)) if not cfg.get("hood") else 0.04
    ch = crown_height(props)
    props["scale"] = target / (ch + extra_top * props.get("head", 0.28) / 0.28 * 1.0)
    sk = rig.Skeleton(props)
    arm = sk.build("Armature")
    mats = enemy_materials(cfg)
    s = sk.s
    o, h = sk.head_frame()
    neck_base = (0, 0.015 * s, sk.levels["neck"] - 0.05 * s)
    hb = heads.HeadBuilder(o, h, {}, neck_r=sk.p["neck_r"] * s, neck_base=neck_base)
    parts = []
    boss = cfg.get("boss", False)
    parts.append(hb.build_skin(mats["Undershirt"], tris=500 if not boss else 800, face=False,
                               name="Head"))
    if cfg.get("hood"):
        parts += build_hood(hb, mats)
    else:
        parts += outfit.build_batting_helmet(
            hb, mats, mats["JerseyTrim"], size=hcfg.get("size", 1.0), flap=hcfg.get("flap", True),
            riot=hcfg.get("riot", False), crest=hcfg.get("crest", False),
            brim=hcfg.get("brim", True), aero=hcfg.get("aero", False),
            crest_mat=mats["Metal"] if cfg.get("gold") else mats["JerseyTrim"],
            tris=900 if not boss else 1600)
    bcfg = dict(sleeve_len=0.15, vneck=False, pants_loose=0.010)
    bb = body.BodyBuilder(sk, mats, bcfg)
    k = 1.0 if not boss else 1.6
    parts.append(bb.build_torso(mats["Jersey"], tris=int(1300 * k)))
    parts += bb.build_sleeve_trim(mats["JerseyTrim"], tris=80)
    for sd in "LR":
        parts.append(bb.build_arm(sd, mats["Undershirt"], tris=int(380 * k)))
        parts.append(bb.build_hand(sd, mats["Glove"], tris=int(320 * k), mitten=True,
                                   fist=True, curl=1.0))
    parts.append(bb.build_pants(mats["Pants"], tris=int(1200 * k)))
    parts += bb.build_belt(mats["Belt"], mats["Metal"], None, tris=200)
    parts += bb.build_socks(mats["Socks"], tris=200, stripe_mat=None)
    parts += bb.build_shoes(mats["Shoes"], tris=int(380 * k), stripe_mat=mats["JerseyTrim"],
                            chunky=1.1)
    parts.append(outfit.claw_emblem(bb, mats["JerseyTrim"]))
    if cfg.get("number") is not None:
        parts += outfit.build_numbers(bb, cfg["number"], FONT, mats["Number"], None,
                                      front=False, back_h=0.19)
    parts += enemy_extras(cid, cfg, sk, bb, hb, mats)
    style = dict(heavy=cfg.get("heavy", 0.0), bat=cfg.get("bat", False),
                 small=cfg.get("small", False))
    return finish(cid, "boss" if boss else "enemy", sk, arm, parts, style=style)


def build_hood(hb, mats):
    h = hb.h
    P = hb.P
    parts = []
    outer = sdf.ellipsoid(P(0, 0.08, 0.02), hb.R(0.43, 0.52, 0.58))
    hood = sdf.blend(outer, 0.06 * h, sdf.round_cone(P(0, 0.30, 0.30), P(0, 0.62, -0.10),
                                                     0.18 * h, 0.05 * h))
    hood = sdf.subtract(hood, sdf.ellipsoid(P(0, -0.62, -0.08), hb.R(0.30, 0.40, 0.42)), k=0.03 * h)
    hood = sdf.intersect(hood, sdf.halfspace(P(0, 0, -0.55), [0, 0.3, -1]))
    lo = np.array(hb.o) + np.array([-0.6, -0.7, -0.8]) * h
    hi = np.array(hb.o) + np.array([0.6, 0.9, 0.7]) * h
    hood.bbox = (lo, hi)
    parts.append(mu.sdf_part("Hood", hood, mats["Cloth"], 0.009 * h, 900, bones=["head", "neck"]))
    # mask: dark face plate + glowing eyes
    parts += build_visor(hb, mats)
    return parts


def build_visor(hb, mats):
    return outfit.build_visor(hb, mats, 0.92)


def enemy_extras(cid, cfg, sk, bb, hb, mats):
    """Type-specific silhouette pieces (filled in enemies.py)."""
    try:
        import enemies
    except ImportError:
        return []
    return enemies.extras(cid, cfg, sk, bb, hb, mats)


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
