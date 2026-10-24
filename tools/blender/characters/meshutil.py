"""Blender mesh helpers: SDF parts -> decimated mesh objects, lofts, etc."""
import math
import numpy as np
import bpy
import bmesh
from mathutils import Vector, Matrix

import sdf

PARTS = []  # collected part objects for the current character


def reset_parts():
    PARTS.clear()


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_from_arrays(name, verts, faces):
    me = bpy.data.meshes.new(name)
    verts = np.asarray(verts, dtype=np.float64)
    faces = np.asarray(faces, dtype=np.int64)
    nv = len(verts)
    nf = len(faces)
    corners = faces.shape[1] if nf else 3
    me.vertices.add(nv)
    me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    me.loops.add(nf * corners)
    me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
    me.polygons.add(nf)
    me.polygons.foreach_set("loop_start", (np.arange(nf) * corners).astype(np.int32))
    me.polygons.foreach_set("loop_total", np.full(nf, corners, np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    obj = bpy.data.objects.new(name, me)
    link(obj)
    return obj


def tri_count(obj):
    me = obj.data
    return sum(len(p.vertices) - 2 for p in me.polygons)


def apply_decimate(obj, target_tris, symmetric=False, axis='X'):
    cur = tri_count(obj)
    if target_tris is None or cur <= target_tris:
        return obj
    mod = obj.modifiers.new("dec", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = max(0.0005, target_tris / cur)
    mod.use_symmetry = symmetric
    mod.symmetry_axis = axis
    mod.use_collapse_triangulate = True
    apply_modifiers(obj)
    cleanup(obj)
    return obj


def cleanup(obj, merge=1e-6):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    # delete duplicate faces (same vertex set)
    seen = set()
    dup = []
    for f in bm.faces:
        key = tuple(sorted(v.index for v in f.verts))
        if key in seen or len(set(key)) < 3:
            dup.append(f)
        seen.add(key)
    if dup:
        bmesh.ops.delete(bm, geom=dup, context='FACES_ONLY')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(me)
    bm.free()
    me.validate(clean_customdata=False)
    me.update()
    return obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True,
                                         depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    bpy.data.meshes.remove(old)
    return obj


def shade(obj, smooth=True, sharp_angle=None):
    me = obj.data
    if smooth:
        me.shade_smooth()
        if sharp_angle is not None:
            try:
                me.set_sharp_from_angle(angle=math.radians(sharp_angle))
            except Exception:
                pass
    else:
        me.shade_flat()


def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def make_part(name, verts, faces, mat, bones=None, rigid=None, smooth=True,
              sharp=None, tris=None, sym=False, kind="deform", extra=None):
    obj = mesh_from_arrays(name, verts, faces)
    if tris:
        apply_decimate(obj, tris, symmetric=sym)
    set_material(obj, mat)
    shade(obj, smooth, sharp)
    obj["rigid"] = rigid or ""
    obj["bones"] = ",".join(bones) if bones else ""
    if extra:
        for k, v in extra.items():
            obj[k] = v
    PARTS.append(obj)
    return obj


def sdf_part(name, shape, mat, voxel, tris, bones=None, rigid=None, sym=False,
             smooth=True, sharp=None, bbox=None, extra=None):
    verts, quads = sdf.polygonize(shape, voxel, bbox=bbox)
    if len(quads) == 0:
        print("WARNING: empty SDF part", name)
        return None
    return make_part(name, verts, quads, mat, bones=bones, rigid=rigid,
                     smooth=smooth, sharp=sharp, tris=tris, sym=sym,
                     extra=extra)


# ---------------------------------------------------------------------------
# simple bmesh primitives (for crisp low-poly bits)
# ---------------------------------------------------------------------------

def uv_sphere(name, center, radius, mat, seg=12, rings=8, scale=(1, 1, 1),
              rot=None, rigid=None, bones=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings,
                              radius=1.0)
    M = Matrix.Diagonal(Vector(scale) * radius).to_4x4()
    if rot is not None:
        M = rot.to_4x4() @ M
    M = Matrix.Translation(Vector(center)) @ M
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    link(obj)
    set_material(obj, mat)
    shade(obj, True)
    obj["rigid"] = rigid or ""
    obj["bones"] = ",".join(bones) if bones else ""
    PARTS.append(obj)
    return obj


def loft(name, rings, mat, cap_start=True, cap_end=True, rigid=None,
         bones=None, smooth=True, sharp=None):
    """rings: list of (K,3) arrays with equal K; builds a quad tube."""
    rings = [np.asarray(r, float) for r in rings]
    K = len(rings[0])
    verts = np.concatenate(rings, 0)
    faces = []
    for i in range(len(rings) - 1):
        for k in range(K):
            a = i * K + k
            b = i * K + (k + 1) % K
            c = (i + 1) * K + (k + 1) % K
            d = (i + 1) * K + k
            faces.append((a, b, c, d))
    verts = list(map(tuple, verts))
    extra_faces = []
    if cap_start:
        verts.append(tuple(rings[0].mean(0)))
        ci = len(verts) - 1
        for k in range(K):
            extra_faces.append((ci, (k + 1) % K, k))
    if cap_end:
        verts.append(tuple(rings[-1].mean(0)))
        ci = len(verts) - 1
        base = (len(rings) - 1) * K
        for k in range(K):
            extra_faces.append((ci, base + k, base + (k + 1) % K))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], [tuple(f) for f in faces] + extra_faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    link(obj)
    set_material(obj, mat)
    shade(obj, smooth, sharp)
    obj["rigid"] = rigid or ""
    obj["bones"] = ",".join(bones) if bones else ""
    PARTS.append(obj)
    return obj


def text_mesh(name, text, font_path, size, extrude, offset=0.0, resolution=2):
    """Create a mesh object from text (flat filled, extruded)."""
    cu = bpy.data.curves.new(name + "_c", 'FONT')
    cu.body = text
    try:
        cu.font = bpy.data.fonts.load(font_path, check_existing=True)
    except Exception as e:
        print("font load failed", e)
    cu.size = size
    cu.extrude = extrude
    cu.offset = offset
    cu.resolution_u = resolution
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.fill_mode = 'BOTH'
    ob = bpy.data.objects.new(name + "_t", cu)
    link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    obj = bpy.data.objects.new(name, me)
    link(obj)
    return obj


def mesh_arrays(obj):
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", co)
    return co.reshape(n, 3).astype(np.float64)


def set_mesh_coords(obj, co):
    me = obj.data
    me.vertices.foreach_set("co", np.asarray(co, np.float32).ravel())
    me.update()
