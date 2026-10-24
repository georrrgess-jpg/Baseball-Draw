"""Baseball Draw character generator.

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py [ids...]
        [--no-portraits] [--portraits-only] [--no-glb] [--out ROOT] [--save-blend DIR]

Builds assets/models/characters/<id>.glb (mesh + shared armature + all
animation clips) and assets/textures/portraits/<id>.png for every id given
(default: all 20).  Everything is procedural and deterministic.
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
                Metal=P["metal"])
    if cfg.get("gear"):
        cols["Gear"] = cfg["accent"]
    if cfg.get("sunglasses"):
        cols["Visor"] = cfg["accent"]
    mats = M.material_set(cols)
    if cfg.get("sunglasses"):
        M.make("Visor", cfg["accent"], rough=0.05, metal=0.85)
    if cfg.get("gear"):
        M.make("Gear", cfg["accent"], rough=0.3, metal=0.15)
    return mats


def build_defender(cid):
    cfg = roster.DEFENDERS[cid]
    sk = rig.Skeleton(cfg.get("props", {}))
    arm = sk.build("Armature")
    mats = defender_materials(cfg)
    s = sk.s
    face = dict(cfg.get("face", {}))
    o, h = sk.head_frame()
    neck_base = (0, 0.015 * s, sk.levels["neck"] - 0.05 * s)
    hb = heads.HeadBuilder(o, h, face, neck_r=sk.p["neck_r"] * s, neck_base=neck_base)
    parts = []
    head_obj = hb.build_skin(mats["Skin"], tris=1900)
    parts.append(head_obj)
    parts += hb.build_eyes(mats)
    parts.append(hb.build_brows(mats["Hair"], tris=220))
    parts.append(hb.build_mouth(mats["Pupil"], tris=80))
    if hb.f.get("lashes"):
        parts.append(hb.build_lashes(mats["Pupil"], tris=120))
    hw = cfg.get("headwear", "cap")
    hair_clip = None
    if hw in ("cap", "cap_back", "visor"):
        cb = outfit.CapBuilder(hb, mats, mats["Undershirt"], emblem=cfg.get("emblem"),
                               yaw=180 if hw == "cap_back" else 0,
                               visor_only=(hw == "visor"))
        parts += cb.build(tris_crown=600, tris_brim=240)
        if hw != "visor":
            hair_clip = sdf.offset(outfit._yaw_warp(cb.crown(), hb.P(0, 0.05, 0.1), cb.yaw),
                                   0.004 * h)
    elif hw == "headband":
        parts += outfit.build_headband(hb, mats["Undershirt"])
    elif hw == "catcher":
        parts += build_catcher_helmet(hb, mats)
    parts += outfit.build_hair(hb, cfg.get("hair_style", "short"), mats["Hair"],
                               accent_mat=mats["Undershirt"], tris=800, clip=hair_clip)
    if cfg.get("beard"):
        parts += outfit.build_beard(hb, mats["Hair"], full=False, tris=400)
    if cfg.get("full_beard"):
        parts += outfit.build_beard(hb, mats["Hair"], full=True, tris=700)
    if cfg.get("eyeblack"):
        parts.append(outfit.build_eye_black(hb, mats["Pupil"], hb.skin_sdf()))
    if cfg.get("sunglasses"):
        parts += outfit.build_sunglasses(hb, mats["Visor"], mats["Pupil"])
    bcfg = dict(sleeve_len=0.15, vneck=True)
    bb = body.BodyBuilder(sk, mats, bcfg)
    parts.append(bb.build_torso(mats["Jersey"], tris=1500))
    parts.append(bb.build_collar_trim(mats["JerseyTrim"], tris=200))
    parts.append(bb.build_undershirt_collar(mats["Undershirt"], tris=120))
    parts += bb.build_placket(mats["JerseyTrim"], mats["Number"], tris=200)
    parts += bb.build_sleeve_trim(mats["JerseyTrim"], tris=80)
    if cfg.get("undershirt") == "elbow":
        for sd in "LR":
            parts.append(bb.build_arm(sd, mats["Undershirt"], tris=260, lower=False,
                                      name="ArmUpper." + sd))
            parts.append(bb.build_arm(sd, mats["Skin"], tris=360, upper=False,
                                      name="Forearm." + sd))
    else:
        for sd in "LR":
            parts.append(bb.build_arm(sd, mats["Undershirt"], tris=450))
    if cfg.get("wristbands"):
        for sd in "LR":
            parts.append(bb.build_wrist_band(sd, mats["Undershirt"] if False else mats["Undershirt"],
                                             tris=120))
    parts.append(bb.build_hand("R", mats["Skin"], tris=600))
    parts += outfit.build_mitt(bb, "L", mats["Glove"], mats["Undershirt"],
                               catcher=(cfg.get("mitt") == "catcher"))
    parts.append(bb.build_pants(mats["Pants"], tris=1400))
    parts += bb.build_belt(mats["Belt"], mats["Metal"], mats["Pants"], tris=260)
    parts += bb.build_socks(mats["Socks"], tris=260, stripe_mat=mats["JerseyTrim"])
    parts += bb.build_shoes(mats["Shoes"], tris=420, stripe_mat=mats["Undershirt"])
    if cfg.get("gear"):
        parts += build_catcher_gear(bb, mats)
    parts += outfit.build_numbers(bb, cfg["number"], FONT, mats["Number"], mats["NumberOutline"],
                                  front=not cfg.get("gear"))
    return finish(cid, "defender", sk, arm, parts, style={})


def build_catcher_helmet(hb, mats):
    """Hockey-style catcher's helmet (Gear) with ear guards + steel face cage."""
    h = hb.h
    P = hb.P
    parts = []
    shell = sdf.ellipsoid(P(0, 0.06, 0.06), hb.R(0.40, 0.47, 0.50))
    helm = sdf.intersect(shell, sdf.halfspace(P(0, 0, -0.40), [0, 0.30, -1.0]))
    # face opening (oval from brow to chin)
    helm = sdf.subtract(helm, sdf.ellipsoid(P(0, -0.52, -0.14), hb.R(0.27, 0.34, 0.36)),
                        k=0.03 * h)
    # ridge on top
    ridge = sdf.intersect(sdf.offset(shell, 0.02 * h), sdf.box(P(0, 0.1, 0.4), hb.R(0.05, 0.6, 0.3)))
    helm = sdf.blend(helm, 0.02 * h, ridge)
    helm.bbox = (np.array(hb.o) + np.array([-0.6, -0.8, -0.7]) * h,
                 np.array(hb.o) + np.array([0.6, 0.9, 0.75]) * h)
    ears = [sdf.ellipsoid(P(sx * 0.365, 0.05, -0.08), hb.R(0.06, 0.13, 0.16)) for sx in (1, -1)]
    helm = sdf.blend(helm, 0.04 * h, *ears)
    helm.bbox = (np.array(hb.o) + np.array([-0.6, -0.8, -0.7]) * h,
                 np.array(hb.o) + np.array([0.6, 0.9, 0.75]) * h)
    parts.append(mu.sdf_part("CatcherHelmet", helm, mats["Gear"], 0.008 * h, 1000, rigid="head",
                             sym=True))
    # face cage: bars in front of the face (Metal), frame joins the helmet rim
    bars = []
    face = sdf.ellipsoid(P(0, -0.05, -0.10), hb.R(0.42, 0.57, 0.58))
    for x in (-0.09, 0.09):
        pts = [_on_shell(face, P(x, -0.9, z), hb) for z in np.linspace(0.20, -0.50, 6)]
        bars.append(sdf.polyline_tube(pts, [0.017 * h] * len(pts)))
    for z in (0.20, 0.02, -0.16, -0.34):
        pts = [_on_shell(face, P(x, -0.9, z), hb) for x in np.linspace(-0.36, 0.36, 7)]
        bars.append(sdf.polyline_tube(pts, [0.017 * h] * len(pts)))
    # side struts to the helmet rim
    for sx in (1, -1):
        e1 = _on_shell(face, P(sx * 0.36, -0.9, 0.20), hb)
        bars.append(sdf.capsule(e1, e1 + np.array([sx * 0.01, 0.10, 0.0]) * h, 0.02 * h))
        e2 = _on_shell(face, P(sx * 0.36, -0.9, -0.34), hb)
        bars.append(sdf.capsule(e2, e2 + np.array([sx * 0.01, 0.12, 0.02]) * h, 0.02 * h))
    cage = sdf.union(*bars)
    parts.append(mu.sdf_part("FaceCage", cage, mats["Metal"], 0.006 * h, 900, rigid="head",
                             sym=True))
    return parts


def _on_shell(shape, start, hb):
    """March from ``start`` toward the head centre until hitting shape."""
    c = np.array(hb.o)
    st = np.array(start)
    d = c - st
    ts = np.linspace(0, 1, 300)
    pts = st + ts[:, None] * d
    v = shape(pts)
    k = int(np.argmax(v < 0))
    return pts[k]


def build_catcher_gear(bb, mats):
    s = bb.s
    parts = []
    torso = bb.torso_sdf(with_sleeves=False)
    zc = bb.lv("chest")
    zp = bb.lv("pelvis")
    # chest protector: thick shell over the front of the torso
    prot = sdf.intersect(sdf.offset(torso, 0.022 * s),
                         sdf.halfspace([0, -0.02 * s, 0], [0, 1, 0]))
    prot = sdf.intersect(prot, sdf.halfspace([0, 0, zp + 0.02 * s], [0, 0, -1]))
    prot = sdf.intersect(prot, sdf.halfspace([0, 0, bb.lv("neck") - 0.03 * s], [0, 0, 1]))
    prot = sdf.subtract(prot, sdf.offset(torso, 0.002 * s))
    # segment grooves
    grooves = [sdf.box([0, -0.3 * s, z], [0.3 * s, 0.2 * s, 0.006 * s])
               for z in np.linspace(zp + 0.12 * s, zc + 0.15 * s, 4)]
    prot = sdf.subtract(prot, *grooves, k=0.004 * s)
    prot.bbox = (np.array([-0.3, -0.35, zp - 0.05]) * 1.0 * s / s * np.array([s, s, 1]),
                 np.array([0.3 * s, 0.1 * s, bb.lv("neck") + 0.02 * s]))
    prot.bbox = (np.array([-0.3 * s, -0.35 * s, zp - 0.05 * s]),
                 np.array([0.3 * s, 0.1 * s, bb.lv("neck") + 0.02 * s]))
    parts.append(mu.sdf_part("ChestProtector", prot, mats["Gear"], 0.0065 * s, 700,
                             bones=["hips", "spine", "chest"], sym=True, sharp=50))
    # straps over the back (thin)
    for sd in ("L", "R"):
        sh = bb.sock_sdf(sd, extra=0.0)
        K = bb.j("shin." + sd)
        Ak = bb.j("foot." + sd)
        guard = sdf.intersect(sdf.offset(sh, 0.018 * s),
                              sdf.halfspace(K + np.array([0, 0.005 * s, 0]), [0, 1, 0]))
        knee = sdf.ellipsoid(K + np.array([0, -0.06 * s, 0.02 * s]), [0.07 * s, 0.05 * s, 0.075 * s])
        guard = sdf.blend(guard, 0.03 * s, knee)
        guard = sdf.intersect(guard, sdf.halfspace(Ak + np.array([0, 0, 0.035 * s]), [0, 0, -1]))
        guard = sdf.subtract(guard, sdf.offset(sh, 0.003 * s))
        ribs = [sdf.box(K + np.array([x, -0.1 * s, -0.17 * s]), [0.005 * s, 0.1 * s, 0.17 * s])
                for x in (-0.025 * s, 0.025 * s)]
        guard = sdf.subtract(guard, *ribs, k=0.003 * s)
        guard.bbox = (K - np.array([0.15, 0.2, 0.0]) * s - np.array([0, 0, K[2]]),
                      K + np.array([0.15, 0.15, 0.15]) * s)
        parts.append(mu.sdf_part("ShinGuard." + sd, guard, mats["Gear"], 0.006 * s, 500,
                                 bones=["thigh." + sd, "shin." + sd, "foot." + sd], sharp=50))
    return parts


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
    M.make("Metal", cols["Metal"], rough=0.32, metal=1.0)
    if cfg.get("ghost"):
        M.make("Cloth", cols["Cloth"], cols["Cloth"], 0.6, alpha=0.72)
    if cfg.get("golden_bat"):
        M.make("Bat", cols["Bat"], rough=0.25, metal=1.0)
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


def finish(cid, kind, sk, arm, parts, style):
    parts = [p for p in parts if p is not None]
    budget = roster.BUDGET[kind]
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
