"""Baseball Draw - "Steel Yard" stadium & industrial prop generator.

Usage (from the repo root):
    /opt/tools/bpyenv/bin/python tools/blender/props/build_props.py            # all props
    /opt/tools/bpyenv/bin/python tools/blender/props/build_props.py gate wall_segment
    ... build_props.py --list
    ... build_props.py --out /some/dir --stats stats.json gate
    ... build_props.py --embed            # self-contained GLBs (textures packed)

Writes binary glTF files to assets/models/props/<name>.glb (Blender Z-up /
front -Y, exported Y-up so the prop front faces +Z in Godot, origin at the
ground centre, metres).  Textures are generated procedurally (numpy, plus a
small Pillow pass for the text placeholders run with the system `python3`).
By default the GLBs reference one shared texture library in
assets/models/props/textures/ (relative URIs + Godot .import presets) so the
materials' textures are stored and loaded once; `--embed` packs them instead.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True      # keep __pycache__ out of the repo
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402

import glb_tools  # noqa: E402
import pmat  # noqa: E402
import pmesh  # noqa: E402
import props_hero  # noqa: E402
import props_industry  # noqa: E402
import props_small  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
DEFAULT_OUT = os.path.join(REPO, 'assets', 'models', 'props')

REGISTRY = {}
for _mod in (props_hero, props_industry, props_small):
    REGISTRY.update(_mod.PROPS)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_text_textures(tmp):
    """Run the Pillow text-texture script with the system python3."""
    script = os.path.join(HERE, 'text_textures.py')
    for exe in (os.environ.get('PROPS_PYTHON'), shutil.which('python3'), '/usr/bin/python3'):
        if not exe:
            continue
        try:
            subprocess.run([exe, script, tmp], check=True, capture_output=True, text=True)
            return True
        except (OSError, subprocess.CalledProcessError) as exc:
            print('text textures via %s failed: %s' % (exe, getattr(exc, 'stderr', exc)))
    return False


def scene_stats():
    bpy.context.view_layer.update()
    stats = {'objects': [], 'tris': 0, 'materials': set()}
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for ob in bpy.context.scene.objects:
        entry = {'name': ob.name, 'type': ob.type,
                 'location': [round(c, 4) for c in ob.matrix_world.translation]}
        if ob.type == 'MESH':
            me = ob.data
            tris = sum(len(p.vertices) - 2 for p in me.polygons)
            entry['tris'] = tris
            entry['materials'] = [m.name for m in me.materials]
            stats['tris'] += tris
            stats['materials'].update(entry['materials'])
            for v in me.vertices:
                w = ob.matrix_world @ v.co
                for i in range(3):
                    lo[i] = min(lo[i], w[i])
                    hi[i] = max(hi[i], w[i])
        stats['objects'].append(entry)
    stats['materials'] = sorted(stats['materials'])
    # report bounds in Godot axes (x, y=up, z=front)
    stats['bounds_godot'] = {
        'x': [round(lo[0], 3), round(hi[0], 3)],
        'y': [round(lo[2], 3), round(hi[2], 3)],
        'z': [round(-hi[1], 3), round(-lo[1], 3)],
    }
    stats['size_godot'] = [round(hi[0] - lo[0], 3), round(hi[2] - lo[2], 3), round(hi[1] - lo[1], 3)]
    return stats


def export_glb(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='JPEG',
        export_jpeg_quality=88,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
    )


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('names', nargs='*', help='props to build (default: all)')
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--stats', default=None, help='write build statistics JSON here')
    ap.add_argument('--blend', default=None, help='also save a .blend per prop into this dir (debug)')
    ap.add_argument('--embed', action='store_true', help='pack textures into each GLB instead of textures/')
    ap.add_argument('--list', action='store_true')
    args = ap.parse_args(argv)
    if args.list:
        print('\n'.join(REGISTRY))
        return 0
    names = args.names or list(REGISTRY)
    bad = [n for n in names if n not in REGISTRY]
    if bad:
        print('unknown props: %s' % ', '.join(bad))
        return 2
    os.makedirs(args.out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='props_tex_')
    if make_text_textures(tmp):
        pmat.TEXT_TEX_DIR = tmp
    all_stats = {}
    t_all = time.time()
    for name in names:
        t0 = time.time()
        reset_scene()
        REGISTRY[name]()
        st = scene_stats()
        path = os.path.join(args.out, name + '.glb')
        export_glb(path)
        if not args.embed:
            st['textures'] = glb_tools.externalize(path, os.path.join(args.out, 'textures'))
        if args.blend:
            os.makedirs(args.blend, exist_ok=True)
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.blend, name + '.blend'), compress=True)
        st['file_kb'] = round(os.path.getsize(path) / 1024, 1)
        all_stats[name] = st
        print('%-18s %6d tris  size(x,y,z)=%-24s %7.1f KB  %.1fs  mats=%s' % (
            name, st['tris'], st['size_godot'], st['file_kb'], time.time() - t0, ','.join(st['materials'])))
    shutil.rmtree(tmp, ignore_errors=True)
    if not args.embed:
        glb_tools.write_import_presets(os.path.join(args.out, 'textures'))
    if args.stats:
        with open(args.stats, 'w') as f:
            json.dump(all_stats, f, indent=1)
    print('built %d props in %.1fs -> %s' % (len(names), time.time() - t_all, args.out))
    return 0


if __name__ == '__main__':
    argv = sys.argv[1:]
    if '--' in argv:
        argv = argv[argv.index('--') + 1:]
    sys.exit(main(argv))
