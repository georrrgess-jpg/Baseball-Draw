"""Shared PBR material library for the Steel Yard props.

Materials are created lazily by name with `get(name)`.  Textures come from
`ptex` (numpy) or from the PIL text-texture pass (`text_textures.py`, loaded
from TEXT_TEX_DIR) and are packed into the .blend data so the glTF exporter
embeds them (JPEG for opaque colour, PNG where alpha is used).
"""
import os

import bpy
import numpy as np

import ptex

TEXT_TEX_DIR = None      # set by build_props before building
_ARRAY_CACHE = {}        # survives scene resets within one run

# name: spec
#   tex: key into TEX (callable) ; color: flat colour if no tex
#   metal, rough, uv (metres per texture tile)
#   emit: colour hex or 'tex' (use emission texture) ; strength
#   normal: key of normal map ; clip: alpha-clip ; double: double sided
SPECS = {
    'SteelNavy':      dict(tex='steel_navy', metal=0.35, rough=0.48, uv=2.0),
    'SteelCharcoal':  dict(tex='steel_charcoal', metal=0.4, rough=0.52, uv=2.0),
    'SteelScarlet':   dict(tex='steel_scarlet', metal=0.3, rough=0.42, uv=2.0),
    'SteelGalv':      dict(tex='galv', metal=0.85, rough=0.36, uv=1.5),
    'SteelDark':      dict(tex='steel_dark', metal=0.75, rough=0.5, uv=1.5),
    'Rust':           dict(tex='rust', metal=0.25, rough=0.85, uv=1.5),
    'Concrete':       dict(tex='concrete', metal=0.0, rough=0.92, uv=3.0),
    'ConcreteDark':   dict(tex='concrete_dark', metal=0.0, rough=0.9, uv=3.0),
    'Hazard':         dict(tex='hazard', metal=0.15, rough=0.55, uv=1.6),
    'Padding':        dict(tex='padding', metal=0.0, rough=0.62, uv=2.0),
    'SafetyYellow':   dict(tex='yellow_plastic', metal=0.0, rough=0.5, uv=1.0),
    'PaintWhite':     dict(tex='white_paint', metal=0.0, rough=0.6, uv=1.0),
    'Glass':          dict(color='#1B2836', metal=0.1, rough=0.08, uv=2.0),
    'Rubber':         dict(color='#151619', metal=0.0, rough=0.9, uv=1.0),
    'Brick':          dict(tex='brick', metal=0.0, rough=0.9, uv=1.8),
    'Corrugated':     dict(tex='corrugated', normal='corrugated_n', metal=0.2, rough=0.6, uv=2.4),
    'RoofSheet':      dict(tex='roof', normal='roof_n', metal=0.3, rough=0.6, uv=2.0),
    'Container':      dict(tex='container', normal='container_n', metal=0.1, rough=0.55, uv=2.6),
    'Windows':        dict(tex='windows', emit='tex', emit_tex='windows_e', strength=1.6, metal=0.2,
                           rough=0.35, uv=13.0),
    'Wood':           dict(tex='wood', metal=0.0, rough=0.78, uv=1.2),
    'Sandbag':        dict(tex='burlap', metal=0.0, rough=0.95, uv=0.8),
    'Bat':            dict(tex='bat_wood', metal=0.0, rough=0.38, uv=1.0),
    'BatGrip':        dict(tex='grip', metal=0.0, rough=0.8, uv=0.12),
    'Baseball':       dict(tex='baseball', metal=0.0, rough=0.55, uv=1.0),
    'ChainLink':      dict(tex='chainlink', metal=0.8, rough=0.4, uv=0.4, clip=True, double=True),
    'SpeakerGrille':  dict(tex='grille', metal=0.3, rough=0.6, uv=0.6),
    'SeatNavy':       dict(tex='seat_navy', metal=0.0, rough=0.38, uv=1.0),
    'SeatScarlet':    dict(tex='seat_scarlet', metal=0.0, rough=0.38, uv=1.0),
    'CoolerOrange':   dict(tex='cooler', metal=0.0, rough=0.32, uv=1.0),
    'PlasticWhite':   dict(tex='white_plastic', metal=0.0, rough=0.4, uv=1.0),
    'HelmetNavy':     dict(color='#1A2B47', metal=0.2, rough=0.18, uv=1.0),
    # emissive
    'LampEmissive':   dict(tex='lens', emit='tex', emit_tex='lens_e', strength=5.0, metal=0.0, rough=0.2, uv=1.0),
    'BeaconEmissive': dict(color='#FF2414', emit='#FF2414', strength=10.0, metal=0.0, rough=0.25, uv=1.0),
    'AmberEmissive':  dict(color='#FFA51F', emit='#FFA51F', strength=6.0, metal=0.0, rough=0.25, uv=1.0),
    'MarqueeBulb':    dict(color='#FFE0A0', emit='#FFD58A', strength=5.0, metal=0.0, rough=0.3, uv=1.0),
    'WindowGlow':     dict(color='#FFB869', emit='#FFB45E', strength=2.5, metal=0.0, rough=0.2, uv=1.0),
    'GlassLit':       dict(tex='glass_lit', emit='tex', emit_tex='glass_lit_e', strength=1.6, metal=0.1, rough=0.1,
                           uv=2.0),
    'RedAviation':    dict(color='#FF1E1E', emit='#FF1E1E', strength=8.0, metal=0.0, rough=0.3, uv=1.0),
    # game-replaced surfaces
    'Screen':         dict(tex='screen', emit='tex', emit_tex='screen', strength=1.6, metal=0.0, rough=0.25, uv=1.0),
    'Banner':         dict(tex='banner', metal=0.0, rough=0.85, uv=1.0, double=True),
}


def _gen(key):
    """Generate (or fetch) the numpy array for a texture key."""
    if key in _ARRAY_CACHE:
        return _ARRAY_CACHE[key]
    T = ptex
    gens = {
        'steel_navy': lambda: T.painted_steel('#1C2E4A', seed=1, wear=0.8, rust=0.7),
        'steel_charcoal': lambda: T.painted_steel('#262A31', seed=2, wear=0.9, rust=0.9),
        'steel_scarlet': lambda: T.painted_steel('#C41F29', seed=3, wear=0.7, rust=0.35, dirt=0.6),
        'steel_dark': lambda: T.bare_metal('#4B5058', seed=4, rust=0.9),
        'galv': lambda: T.bare_metal('#8E979F', seed=5, rust=0.35),
        'rust': lambda: T.rust_metal(seed=6),
        'concrete': lambda: T.concrete(seed=7),
        'concrete_dark': lambda: T.concrete(seed=8, color='#5D5B57'),
        'hazard': lambda: T.hazard(seed=9),
        'padding': lambda: T.padding(seed=10),
        'yellow_plastic': lambda: T.plastic('#F2B227', seed=11, n=256),
        'white_paint': lambda: T.plastic('#E6E1D5', seed=12, n=256),
        'brick': lambda: T.brick(seed=13),
        'wood': lambda: T.wood(seed=14),
        'burlap': lambda: T.burlap(seed=15),
        'bat_wood': lambda: T.bat_wood(),
        'grip': lambda: T.grip_tape(),
        'baseball': lambda: T.baseball(),
        'chainlink': lambda: T.chainlink(),
        'grille': lambda: T.speaker_grille(),
        'seat_navy': lambda: T.plastic('#22395C', seed=16, n=128, scuff=0.5),
        'seat_scarlet': lambda: T.plastic('#C8222B', seed=17, n=128, scuff=0.5),
        'cooler': lambda: T.plastic('#F07A1A', seed=18, n=128),
        'white_plastic': lambda: T.plastic('#E8E6E0', seed=19, n=128),
    }
    if key in gens:
        arr = gens[key]()
    elif key in ('corrugated', 'corrugated_n'):
        c, n = T.corrugated(seed=20, color='#5B6B7A', ribs=16)
        _ARRAY_CACHE['corrugated'], _ARRAY_CACHE['corrugated_n'] = c, n
        arr = _ARRAY_CACHE[key]
    elif key in ('roof', 'roof_n'):
        c, n = T.roof_sheet(seed=21)
        _ARRAY_CACHE['roof'], _ARRAY_CACHE['roof_n'] = c, n
        arr = _ARRAY_CACHE[key]
    elif key in ('container', 'container_n'):
        c, n = T.container_paint(seed=22)
        _ARRAY_CACHE['container'], _ARRAY_CACHE['container_n'] = c, n
        arr = _ARRAY_CACHE[key]
    elif key in ('windows', 'windows_e'):
        c, e = T.windows(seed=23)
        _ARRAY_CACHE['windows'], _ARRAY_CACHE['windows_e'] = c, e
        arr = _ARRAY_CACHE[key]
    elif key in ('glass_lit', 'glass_lit_e'):
        c, e = T.windows(seed=24, bays=6, floors=1, lit_frac=0.7, wall='#22262C', glass='#1E2A36',
                         lit='#FFB45E', lit2='#FFD9A0')
        _ARRAY_CACHE['glass_lit'], _ARRAY_CACHE['glass_lit_e'] = c, e
        arr = _ARRAY_CACHE[key]
    elif key in ('lens', 'lens_e'):
        c, e = T.lamp_lens()
        _ARRAY_CACHE['lens'], _ARRAY_CACHE['lens_e'] = c, e
        arr = _ARRAY_CACHE[key]
    elif key in ('screen', 'banner'):
        arr = _load_text_texture(key)
    else:
        raise KeyError(key)
    _ARRAY_CACHE[key] = arr
    return arr


def _load_text_texture(key):
    """PNG made by text_textures.py (PIL).  Fallback: plain procedural."""
    path = os.path.join(TEXT_TEX_DIR or '', key + '.png')
    if TEXT_TEX_DIR and os.path.exists(path):
        img = bpy.data.images.load(path)
        w, h = img.size
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
        bpy.data.images.remove(img)
        arr = np.flipud(px.reshape(h, w, 4))[..., :3].copy()
        return arr
    print('WARNING: text texture %s missing, using fallback' % key)
    if key == 'screen':
        return ptex.flat('#101418', 64)
    return ptex.flat('#C41F29', 64)


def _image(key, non_color=False):
    name = 'tex_' + key
    img = bpy.data.images.get(name)
    if img is not None:
        return img
    arr = _gen(key)
    h, w, c = arr.shape
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :c] = arr
    img = bpy.data.images.new(name, w, h, alpha=(c == 4))
    img.pixels.foreach_set(np.flipud(rgba).ravel())
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pack()
    return img


def _hex_lin(hexs):
    rgb = ptex.hex_rgb(hexs)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return (float(lin[0]), float(lin[1]), float(lin[2]), 1.0)


def uv_scale(name):
    return SPECS.get(name, {}).get('uv', 2.0)


def get(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    spec = SPECS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not spec.get('double', False)
    nt = mat.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    bsdf.inputs['Metallic'].default_value = spec.get('metal', 0.0)
    bsdf.inputs['Roughness'].default_value = spec.get('rough', 0.5)
    x = -400
    if 'tex' in spec:
        tn = nt.nodes.new('ShaderNodeTexImage')
        tn.image = _image(spec['tex'])
        tn.location = (x, 200)
        nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
        if spec.get('clip'):
            rn = nt.nodes.new('ShaderNodeMath')
            rn.operation = 'ROUND'
            rn.location = (x + 200, 0)
            nt.links.new(tn.outputs['Alpha'], rn.inputs[0])
            nt.links.new(rn.outputs[0], bsdf.inputs['Alpha'])
    else:
        bsdf.inputs['Base Color'].default_value = _hex_lin(spec['color'])
    if 'normal' in spec:
        nn = nt.nodes.new('ShaderNodeTexImage')
        nn.image = _image(spec['normal'], non_color=True)
        nn.location = (x, -300)
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nm.location = (x + 250, -300)
        nt.links.new(nn.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    emit = spec.get('emit')
    if emit:
        if emit == 'tex':
            en = nt.nodes.new('ShaderNodeTexImage')
            en.image = _image(spec['emit_tex'])
            en.location = (x, -600)
            nt.links.new(en.outputs['Color'], bsdf.inputs['Emission Color'])
        else:
            bsdf.inputs['Emission Color'].default_value = _hex_lin(emit)
        bsdf.inputs['Emission Strength'].default_value = spec.get('strength', 1.0)
    return mat
