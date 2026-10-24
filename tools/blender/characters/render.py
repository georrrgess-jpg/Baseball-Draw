"""Cycles render helpers (portraits + preview sheets)."""
import math
import bpy
from mathutils import Vector


def setup_cycles(res=512, samples=48, transparent=True):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        pass
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.compression = 90
    try:
        sc.view_settings.view_transform = 'Standard'
        sc.view_settings.look = 'None'
    except Exception:
        pass
    world = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.42, 0.45, 0.52, 1.0)
        bg.inputs[1].default_value = 0.35


def _light(name, kind, loc, target, energy, size=1.0, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == 'AREA':
        ld.size = size
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return ob


def clear_cams_lights():
    for ob in list(bpy.data.objects):
        if ob.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(ob)


def camera(loc, target, lens=50.0, ortho=None, name="Cam"):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_start = 0.01
    cd.clip_end = 200
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = ob
    return ob


def key_rim_lights(center, radius, key_energy=1.0):
    """Consistent key + fill + rim setup around ``center`` (scaled by
    ``radius`` = rough subject size)."""
    c = Vector(center)
    r = radius
    e = r * r
    # key: front-left-high (character's right side seen from 3/4 front)
    _light("Key", 'AREA', c + Vector((-1.6, -2.4, 1.5)) * r * 2, c,
           900 * e * key_energy, size=2.5 * r, color=(1.0, 0.96, 0.9))
    _light("Fill", 'AREA', c + Vector((2.2, -1.8, 0.2)) * r * 2, c,
           260 * e * key_energy, size=3.0 * r, color=(0.85, 0.9, 1.0))
    _light("RimL", 'AREA', c + Vector((1.8, 2.2, 1.2)) * r * 2, c,
           1100 * e * key_energy, size=1.2 * r, color=(0.85, 0.92, 1.0))
    _light("RimR", 'AREA', c + Vector((-1.9, 2.0, 0.8)) * r * 2, c,
           700 * e * key_energy, size=1.2 * r, color=(1.0, 0.85, 0.75))


def render_to(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
