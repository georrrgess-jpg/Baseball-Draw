"""GLB post-processing: move embedded images into a shared texture folder.

Every prop uses the same small library of procedural textures.  Embedded in
each GLB they would be duplicated per file (and Godot would extract a copy of
every image next to every .glb on import).  `externalize()` rewrites a GLB so
its images reference `textures/<name>.<ext>` (a relative URI, resolved by
Godot against the .glb's folder) and drops the image bytes from the binary
chunk.  `write_import_presets()` adds Godot `.import` files for the shared
textures so they import as 3D textures (mipmaps + VRAM compression, normal
maps flagged) without relying on the editor's "detect 3D" pass.
"""
import json
import os
import struct

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def _read(path):
    d = open(path, 'rb').read()
    magic, _ver, _len = struct.unpack('<III', d[:12])
    if magic != GLB_MAGIC:
        raise ValueError('%s is not a GLB' % path)
    jl, _jt = struct.unpack('<II', d[12:20])
    j = json.loads(d[20:20 + jl])
    off = 20 + jl
    binb = b''
    if off < len(d):
        bl, _bt = struct.unpack('<II', d[off:off + 8])
        binb = d[off + 8:off + 8 + bl]
    return j, binb


def _write(path, j, binb):
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + (8 + len(binb) if binb else 0)
    out = struct.pack('<III', GLB_MAGIC, 2, total)
    out += struct.pack('<II', len(js), CHUNK_JSON) + js
    if binb:
        out += struct.pack('<II', len(binb), CHUNK_BIN) + bytes(binb)
    open(path, 'wb').write(out)


def externalize(glb_path, tex_dir, rel='textures'):
    """Move images of `glb_path` into `tex_dir`; returns written texture names."""
    j, binb = _read(glb_path)
    os.makedirs(tex_dir, exist_ok=True)
    img_views = set()
    names = []
    for im in j.get('images', []):
        if 'bufferView' not in im:
            continue
        bv = j['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        data = binb[o:o + bv['byteLength']]
        ext = {'image/jpeg': 'jpg', 'image/png': 'png'}[im['mimeType']]
        fn = '%s.%s' % (im['name'], ext)
        p = os.path.join(tex_dir, fn)
        if not os.path.exists(p) or open(p, 'rb').read() != data:
            open(p, 'wb').write(data)
        names.append(fn)
        img_views.add(im['bufferView'])
        del im['bufferView']
        del im['mimeType']
        im['uri'] = rel + '/' + fn
    if not img_views:
        return names
    remap, views, nb = {}, [], bytearray()
    for i, bv in enumerate(j['bufferViews']):
        if i in img_views:
            continue
        o = bv.get('byteOffset', 0)
        data = binb[o:o + bv['byteLength']]
        while len(nb) % 4:
            nb += b'\0'
        nbv = dict(bv)
        nbv['byteOffset'] = len(nb)
        nb += data
        remap[i] = len(views)
        views.append(nbv)
    while len(nb) % 4:
        nb += b'\0'
    j['bufferViews'] = views
    for acc in j.get('accessors', []):
        if 'bufferView' in acc:
            acc['bufferView'] = remap[acc['bufferView']]
        sp = acc.get('sparse')
        if sp:
            sp['indices']['bufferView'] = remap[sp['indices']['bufferView']]
            sp['values']['bufferView'] = remap[sp['values']['bufferView']]
    j['buffers'][0]['byteLength'] = len(nb)
    _write(glb_path, j, nb)
    return names


IMPORT_PRESET = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/normal_map=%d
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
detect_3d/compress_to=0
"""


def write_import_presets(tex_dir):
    """Create Godot .import presets for textures that do not have one yet."""
    n = 0
    for fn in sorted(os.listdir(tex_dir)):
        if fn.endswith('.import') or not fn.lower().endswith(('.jpg', '.png')):
            continue
        p = os.path.join(tex_dir, fn + '.import')
        if os.path.exists(p):
            continue
        is_normal = os.path.splitext(fn)[0].endswith('_n')
        with open(p, 'w') as f:
            f.write(IMPORT_PRESET % (1 if is_normal else 0))
        n += 1
    return n
