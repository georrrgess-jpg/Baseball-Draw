"""Head-and-shoulders portraits (512x512, transparent, 3/4 view, key + rim)."""
import math
import bpy
from mathutils import Vector

import anim
import render


def _set_action(arm, name, frame=0):
    act = bpy.data.actions.get(name)
    ad = arm.animation_data
    if ad is None:
        ad = arm.animation_data_create()
    for tr in list(ad.nla_tracks):
        tr.mute = True
    ad.action = act
    try:
        ad.action_slot = act.slots[0]
    except Exception:
        pass
    bpy.context.scene.frame_set(frame)


def render_portrait(cid, info, path, res=512, samples=96):
    sc = bpy.context.scene
    arm = info["arm"]
    c = info["ctx"]
    sk = info["sk"]
    kind = info["kind"]
    enemy = kind != "defender"
    # pose: idle frame 0 (solve it in Python to know where the head is)
    P = anim.clip_idle(c, 0.0)
    P.solve()
    _set_action(arm, "idle", 0)
    o, h = sk.head_frame()
    eye = P.D["head"] @ Vector(o)
    render.clear_cams_lights()
    render.setup_cycles(res=res, samples=samples, transparent=True)
    sc.render.film_transparent = True
    if enemy and c.hero:
        # hero-style runners / bosses: head-and-shoulders like the defenders,
        # a little looser for helmets, horns and the trickster's cap
        frame_h = (1.90 if info["id"] in ("grand_slammer", "trickster") else 1.74) * h
        target = eye + Vector((0, 0, (-0.04 if info["id"] in ("grand_slammer", "trickster")
                                      else -0.10) * h))
        yaw = 24.0
        if info["id"] == "swarmer":
            # show the tiny body under the huge helmet (tells it from the Runner)
            frame_h = 2.6 * h
            target = eye + Vector((0, 0, -0.62 * h))
    elif enemy:
        frame_h = 1.95 * h
        target = eye + Vector((0, 0, -0.22 * h))
        yaw = 24.0
    else:
        # stylised defenders: tight head-and-shoulders, slightly low camera
        frame_h = 1.62 * h
        target = eye + Vector((0, 0, -0.13 * h))
        yaw = 27.0
    lens = 85.0
    fov = 2 * math.atan(18.0 / lens)
    dist = (frame_h / 2) / math.tan(fov / 2)
    a = math.radians(yaw)
    el = math.radians(6 if enemy else 2)
    cam_pos = target + Vector((-math.sin(a) * math.cos(el), -math.cos(a) * math.cos(el),
                               math.sin(el))) * dist
    render.camera(cam_pos, target, lens=lens)
    _portrait_lights(target, h, a, enemy)
    render.render_to(path)
    return path


def _light(name, loc, target, energy, size, color):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.color = color
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def _portrait_lights(c, h, cam_yaw, enemy):
    """Key from camera-left/high, soft fill from camera-right, two strong rims
    from behind (consistent across all portraits)."""
    def at(yaw_deg, el_deg, dist):
        a = cam_yaw + math.radians(yaw_deg)
        e = math.radians(el_deg)
        return c + Vector((-math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e),
                           math.sin(e))) * dist
    d = 9.0 * h
    k = (h / 0.28) ** 2
    if not enemy:
        # defenders: warmer, punchier key + soft cool fill + bounce from below
        _light("Key", at(-38, 26, d), c, 210 * k, 3.0 * h * 4, (1.0, 0.94, 0.86))
        _light("Fill", at(60, 6, d), c, 38 * k, 4.0 * h * 4, (0.80, 0.87, 1.0))
        _light("Bounce", at(10, -35, d), c, 14 * k, 4.0 * h * 4, (1.0, 0.92, 0.85))
        _light("RimL", at(150, 22, d), c, 360 * k, 1.4 * h * 4, (0.80, 0.90, 1.0))
        _light("RimR", at(-150, 18, d), c, 300 * k, 1.4 * h * 4, (1.0, 0.86, 0.72))
        _light("Top", at(0, 80, d), c, 30 * k, 3.0 * h * 4, (1.0, 1.0, 1.0))
        return
    _light("Key", at(-40, 30, d), c, 170 * k, 3.0 * h * 4, (1.0, 0.95, 0.88))
    _light("Fill", at(55, 8, d), c, 45 * k, 4.0 * h * 4, (0.82, 0.88, 1.0))
    rim_e = 330 if not enemy else 480
    _light("RimL", at(150, 22, d), c, rim_e * k, 1.4 * h * 4, (0.80, 0.90, 1.0))
    _light("RimR", at(-150, 18, d), c, rim_e * 0.75 * k, 1.4 * h * 4, (1.0, 0.86, 0.72))
    _light("Top", at(0, 80, d), c, 40 * k, 3.0 * h * 4, (1.0, 1.0, 1.0))
