"""Material creation (Principled BSDF) with the names required by
ASSET_SPEC 3.3 (+ a few documented extras: Pupil, NumberOutline, Visor)."""
import bpy


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(srgb_to_linear(int(h[i:i + 2], 16)) for i in (0, 2, 4))


PALETTE = dict(
    jersey="#1C2E4A",
    trim="#D7262E",
    pants="#EDEBE6",
    navy="#1C2E4A",
    belt="#17233A",
    socks="#1C2E4A",
    shoes="#17191E",
    cap="#1C2E4A",
    number="#F4F1EA",
    gold="#F5B82E",
    glove="#9A5B2C",
    eyes="#F2F0EA",
    pupil="#0B0B0E",
    metal="#B7BDC6",
    bat="#C9A169",
    # enemies
    gunmetal="#2B2F36",
    hazard="#FF7A1A",
    glow="#FF3D00",
    charcoal="#1B1F27",
    visor="#101216",
)

# name -> (roughness, metallic)
SURFACE = {
    "Skin": (0.52, 0.0),
    "Hair": (0.45, 0.0),
    "Eyes": (0.18, 0.0),
    "Iris": (0.15, 0.0),
    "Pupil": (0.15, 0.0),
    "Jersey": (0.72, 0.0),
    "JerseyTrim": (0.6, 0.0),
    "Number": (0.55, 0.0),
    "NumberOutline": (0.4, 0.35),
    "Pants": (0.8, 0.0),
    "Socks": (0.85, 0.0),
    "Shoes": (0.35, 0.0),
    "Belt": (0.45, 0.0),
    "Cap": (0.7, 0.0),
    "Glove": (0.55, 0.0),
    "Undershirt": (0.7, 0.0),
    "Gear": (0.35, 0.1),
    "Metal": (0.3, 1.0),
    "Glow": (0.4, 0.0),
    "Bat": (0.45, 0.0),
    "Cloth": (0.8, 0.0),
    "Visor": (0.08, 0.6),
}


def make(name, color, emission=None, strength=0.0, rough=None, metal=None,
         alpha=1.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            bsdf = n
    if bsdf is None:
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    r, mt = SURFACE.get(name, (0.6, 0.0))
    if rough is not None:
        r = rough
    if metal is not None:
        mt = metal
    rgb = hex_rgb(color) if isinstance(color, str) else color
    bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
    bsdf.inputs['Roughness'].default_value = r
    bsdf.inputs['Metallic'].default_value = mt
    if emission:
        e = hex_rgb(emission) if isinstance(emission, str) else emission
        bsdf.inputs['Emission Color'].default_value = (*e, 1.0)
        bsdf.inputs['Emission Strength'].default_value = strength
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
        try:
            m.blend_method = 'BLEND'
        except Exception:
            pass
    m.diffuse_color = (*rgb, alpha)
    return m


def material_set(colors, emissive=None, alpha=None):
    """colors: dict name -> hex.  Returns dict name -> material."""
    emissive = emissive or {}
    alpha = alpha or {}
    mats = {}
    for name, col in colors.items():
        if name in emissive:
            ecol, stren = emissive[name]
            mats[name] = make(name, col, ecol, stren, alpha=alpha.get(name, 1.0))
        else:
            mats[name] = make(name, col, alpha=alpha.get(name, 1.0))
    return mats
