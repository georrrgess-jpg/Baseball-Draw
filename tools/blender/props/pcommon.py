"""Small shared helpers for the prop builder modules."""
import os

import bpy

import pmat
from pmesh import MB

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
FONT_DIR = os.path.join(REPO, 'assets', 'fonts')


def mb_new():
    return MB(uv_scale_fn=pmat.uv_scale)


def finish(m, name, loc=(0.0, 0.0, 0.0), parent=None):
    """Turn a builder into a mesh object named `name` (mesh data gets the same name)."""
    ob = m.build(name, pmat.get, parent=parent)
    ob.location = loc
    return ob


def empty(name, loc, size=0.5, parent=None):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    ob.empty_display_type = 'PLAIN_AXES'
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    if parent is not None:
        ob.parent = parent
    return ob


def load_font(name='RussoOne-Regular.ttf'):
    path = os.path.join(FONT_DIR, name)
    if os.path.exists(path):
        return bpy.data.fonts.load(path, check_existing=True)
    print('WARNING: font %s missing, using Blender default' % path)
    return bpy.data.fonts.load('<builtin>') if '<builtin>' in [f.filepath for f in bpy.data.fonts] else None
