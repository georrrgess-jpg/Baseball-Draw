"""Accessories: caps, hair styles, mitts, jersey numbers/emblem decals,
catcher gear, sunglasses, headbands ..."""
import math
import numpy as np
import bpy
from mathutils import Vector

import sdf
import meshutil as mu

FONT_DIR = None


def A(v):
    return np.array(v, dtype=np.float64)


def band_between(surface, lo, hi):
    """Region where lo < surface(P) < hi (a layer hugging a surface)."""
    def f(P):
        d = surface(P)
        return np.maximum(d - hi, lo - d)
    f.bbox = (surface.bbox[0] - hi - 0.01, surface.bbox[1] + hi + 0.01)
    return f


# ---------------------------------------------------------------------------
# glyph outlines from a font
# ---------------------------------------------------------------------------

def glyph_loops(text, font_path, height):
    """2D loops (metres) of the text outline, centred, cap height=height."""
    cu = bpy.data.curves.new("glyph_tmp", 'FONT')
    cu.body = text
    cu.font = bpy.data.fonts.load(font_path, check_existing=True)
    cu.size = 1.0
    cu.resolution_u = 3
    cu.fill_mode = 'BOTH'
    cu.align_x = 'CENTER'
    cu.space_character = 0.95
    ob = bpy.data.objects.new("glyph_tmp", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    # boundary edges
    from collections import defaultdict
    cnt = defaultdict(int)
    for poly in me.polygons:
        vs = list(poly.vertices)
        for i in range(len(vs)):
            e = tuple(sorted((vs[i], vs[(i + 1) % len(vs)])))
            cnt[e] += 1
    bnd = [e for e, c in cnt.items() if c == 1]
    adj = defaultdict(list)
    for a, b in bnd:
        adj[a].append(b)
        adj[b].append(a)
    co = [Vector(v.co) for v in me.vertices]
    seen = set()
    loops = []
    for a, b in bnd:
        if (a, b) in seen:
            continue
        loop = [a]
        prev, cur = a, b
        seen.add((min(a, b), max(a, b)))
        while cur != a:
            loop.append(cur)
            nxts = [x for x in adj[cur] if x != prev]
            if not nxts:
                break
            nxt = nxts[0]
            seen.add((min(cur, nxt), max(cur, nxt)))
            prev, cur = cur, nxt
            if len(loop) > 5000:
                break
        loops.append(np.array([[co[i].x, co[i].y] for i in loop]))
    bpy.data.meshes.remove(me)
    allp = np.concatenate(loops, 0)
    lo, hi = allp.min(0), allp.max(0)
    c = (lo + hi) / 2
    sc = height / (hi[1] - lo[1])
    return [(l - c) * sc for l in loops]


def surface_decal(name, loops, surface, center, u_axis, v_axis, out_dir, mat,
                  lo=0.0, hi=0.005, dilate=0.0, voxel=0.0025, tris=400,
                  bones=None, rigid=None, sym=False, side_offset=0.06):
    prism = sdf.prism2d(loops, center, u_axis, v_axis, dilate=dilate)
    layer = band_between(surface, lo, hi)
    od = A(out_dir) / np.linalg.norm(out_dir)
    side = sdf.halfspace(A(center) - od * side_offset, -od)
    shape = sdf.intersect(sdf.intersect(prism, layer), side)
    ext = max(np.abs(np.concatenate(loops, 0)).max() + abs(dilate), 0.02) + 0.02
    c = A(center)
    shape.bbox = (c - ext, c + ext)
    return mu.sdf_part(name, shape, mat, voxel, tris, bones=bones, rigid=rigid,
                       sym=sym)


def flame_loop(size):
    pts = [(0.0, -0.50), (0.30, -0.42), (0.42, -0.18), (0.36, 0.08), (0.24, 0.20),
           (0.28, 0.42), (0.12, 0.28), (0.06, 0.52), (-0.06, 0.30), (-0.16, 0.40),
           (-0.20, 0.16), (-0.34, 0.24), (-0.40, -0.08), (-0.34, -0.36)]
    return [np.array(pts) * size]


def bolt_loop(size):
    pts = [(0.10, 0.50), (-0.22, 0.02), (-0.02, 0.02), (-0.14, -0.50), (0.24, 0.06),
           (0.04, 0.06), (0.20, 0.50)]
    return [np.array(pts) * size]


def diamond_loops(size):
    o = np.array([(0, 0.5), (0.5, 0), (0, -0.5), (-0.5, 0)]) * size
    i = np.array([(0, 0.28), (0.28, 0), (0, -0.28), (-0.28, 0)]) * size
    return [o, i]


# ---------------------------------------------------------------------------
# head wear
# ---------------------------------------------------------------------------

def cranium(hb, grow=0.0):
    w = hb.f["width"]
    return sdf.ellipsoid(hb.P(0, 0.05, 0.08), hb.R(0.335 * w + grow, 0.40 + grow, 0.44 + grow))


def _yaw_warp(shape, center, deg):
    if not deg:
        return shape
    c = A(center)
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)

    def wf(P):
        Q = P - c
        x = Q[:, 0] * ca + Q[:, 1] * sa
        y = -Q[:, 0] * sa + Q[:, 1] * ca
        return np.stack([x, y, Q[:, 2]], 1) + c
    out = sdf.warp(shape, wf)
    ext = np.abs(np.concatenate([shape.bbox[0] - c, shape.bbox[1] - c])).max()
    out.bbox = (c - ext, c + ext)
    return out


class CapBuilder:
    def __init__(self, hb, mats, accent_mat, emblem="diamond", yaw=0.0,
                 visor_only=False, brim_len=1.0):
        self.hb = hb
        self.m = mats
        self.acc = accent_mat
        self.emblem = emblem
        self.yaw = yaw
        self.visor_only = visor_only
        self.brim_len = brim_len

    def crown(self):
        hb = self.hb
        w = hb.f["width"]
        cr = sdf.ellipsoid(hb.P(0, 0.045, 0.095), hb.R(0.375 * w, 0.445, 0.465))
        n = A([0, -0.27, -1.0])
        cut = sdf.halfspace(hb.P(0, -0.40, 0.175), n)
        return sdf.intersect(cr, cut)

    def brim_parts(self):
        hb = self.hb
        h = hb.h
        R = 0.95
        L = self.brim_len
        surf = sdf.sphere(hb.P(0, -0.46, 0.165 - R), R * h)
        brim_shell = sdf.shell(surf, 0.032 * h)
        foot = sdf.ellipsoid(hb.P(0, -0.40, 0.17), hb.R(0.31, 0.30 * L + 0.02, 1.2))
        front = sdf.halfspace(hb.P(0, -0.22, 0), [0, 1, 0])
        brim = sdf.intersect(sdf.intersect(brim_shell, foot), front)
        brim.bbox = (hb.P(-0.4, -0.85, -0.1), hb.P(0.4, -0.1, 0.4))
        pipe = sdf.intersect(sdf.shell(surf, 0.040 * h),
                             sdf.shell(sdf.offset(foot, -0.004 * h), 0.03 * h))
        pipe = sdf.intersect(pipe, sdf.halfspace(hb.P(0, -0.30, 0), [0, 1, 0]))
        pipe.bbox = brim.bbox
        return brim, pipe

    def build(self, tris_crown=900, tris_brim=420):
        hb = self.hb
        h = hb.h
        c0 = hb.P(0, 0.05, 0.1)
        parts = []
        cr = self.crown()
        if self.visor_only:
            band = sdf.intersect(sdf.shell(cr, 0.03 * h),
                                 sdf.halfspace(hb.P(0, 0, 0.32), [0, 0.0, 1]))
            band = sdf.intersect(band, sdf.halfspace(hb.P(0, -0.40, 0.175), [0, -0.27, -1.0]))
            band.bbox = (hb.P(-0.5, -0.6, -0.3), hb.P(0.5, 0.6, 0.6))
            parts.append(mu.sdf_part("CapBand", band, self.m["Cap"], 0.009 * h, 500,
                                     rigid="head", sym=True))
        else:
            btn = sdf.ellipsoid(hb.P(0, 0.045, 0.545), hb.R(0.035, 0.035, 0.02))
            crown = sdf.blend(cr, 0.01 * h, btn)
            if self.yaw:
                # snapback opening above the forehead
                crown = sdf.subtract(crown, sdf.ellipsoid(hb.P(0, -0.40, 0.17),
                                                          hb.R(0.13, 0.2, 0.10)), k=0.01 * h)
            parts.append(mu.sdf_part("CapCrown", crown, self.m["Cap"], 0.0085 * h,
                                     tris_crown, rigid="head", sym=True))
        brim, pipe = self.brim_parts()
        if self.yaw:
            drop = A([0, 0, 0.165 * h])

            def lowered(sh):
                g = sdf.warp(sh, lambda P_: P_ + drop)
                g.bbox = (sh.bbox[0] - drop, sh.bbox[1] - drop)
                return g
            brim = _yaw_warp(lowered(brim), c0, self.yaw)
            pipe = _yaw_warp(lowered(pipe), c0, self.yaw)
        parts.append(mu.sdf_part("CapBrim", brim, self.m["Cap"], 0.007 * h, tris_brim,
                                 rigid="head", sym=True, sharp=50))
        parts.append(mu.sdf_part("CapPiping", pipe, self.m["JerseyTrim"], 0.006 * h, 360,
                                 rigid="head", sym=True))
        if self.emblem and not self.visor_only:
            parts.append(self.build_emblem())
        return parts

    def build_emblem(self):
        hb = self.hb
        h = hb.h
        size = 0.20 * h
        loops = {"flame": flame_loop, "bolt": bolt_loop,
                 "diamond": diamond_loops}[self.emblem](size)
        cr = self.crown()
        yaw = self.yaw
        if yaw:
            # backwards cap: the logo panel faces backwards
            ctr = hb.P(0, 0.47, 0.16)
            u, v, out = A([-1, 0, 0]), A([0, -0.2, 1]), A([0, 1, 0.1])
        else:
            ctr = hb.P(0, -0.40, 0.33)
            u, v, out = A([1, 0, 0]), A([0, 0.25, 1]), A([0, -1, 0.2])
        return surface_decal("CapEmblem", loops, cr, ctr, u, v, out, self.acc,
                             lo=-0.002 * h, hi=0.016 * h, voxel=0.0042 * h, tris=300,
                             rigid="head")


# ---------------------------------------------------------------------------
# hair
# ---------------------------------------------------------------------------

_CAPPED = [False]


def hair_cap_region(hb, front_z=0.20, back_z=-0.42, side_z=-0.02, grow=0.025,
                    ear_clear=True):
    """Shell of hair hugging the cranium above a hairline."""
    h = hb.h
    if _CAPPED[0]:
        grow = min(grow, 0.020)
    w = hb.f["width"]
    base = cranium(hb, grow)
    nape = sdf.ellipsoid(hb.P(0, 0.27, -0.10), hb.R(0.31 * w + grow, 0.19 + grow, 0.26))
    base = sdf.blend(base, 0.06 * h, nape)
    # hairline: plane low at the back, high at the front
    n = A([0, -(front_z - back_z) / 0.85, -1.0])
    region = sdf.intersect(base, sdf.halfspace(hb.P(0, -0.40, front_z), n))
    cuts = []
    if ear_clear:
        w = hb.f["width"]
        for sx in (1, -1):
            cuts.append(sdf.ellipsoid(hb.P(sx * 0.36 * w, 0.06, -0.06), hb.R(0.10, 0.11, 0.17)))
    # face clearance (sideburn line)
    cuts.append(sdf.ellipsoid(hb.P(0, -0.42, -0.12), hb.R(0.30, 0.25, 0.30)))
    if cuts:
        region = sdf.subtract(region, *cuts, k=0.02 * h)
    return region


def band_z(y):
    """Cap band height (head units) at head-local y."""
    return 0.175 - 0.27 * (y + 0.40)


def build_hair(hb, style, mat, accent_mat=None, tris=900, clip=None):
    h = hb.h
    P = hb.P
    parts = []
    if style == "none":
        return parts
    _CAPPED[0] = clip is not None
    if clip is not None:
        _mk = mu.sdf_part

        def _clip_part(name, shape, *a, **k):
            return _mk(name, sdf.subtract(shape, clip), *a, **k)
        mu_sdf_part = _clip_part
    else:
        mu_sdf_part = mu.sdf_part
    if style == "spiky":
        base = hair_cap_region(hb, front_z=0.22, back_z=-0.40, grow=0.022)
        spikes = []
        w = hb.f["width"]
        for i in range(13):
            az = math.radians(-72 + i * 144 / 12)       # 0 = back of the head
            y = 0.05 + math.cos(az) * 0.40
            x = math.sin(az) * 0.34 * w
            zr = band_z(y) - 0.035
            zr -= 0.01 * abs(math.degrees(az)) / 72
            root = A(P(x, y, zr))
            outv = A([math.sin(az), math.cos(az), 0.0])
            tip = root + (outv * 0.55 + A([0, 0.25, -1.0]) * 0.55) * 0.12 * h
            spikes.append(sdf.round_cone(root, tip, 0.045 * h, 0.010 * h))
        # temple tufts (above/in front of the ears) + thin sideburns
        for sx in (1, -1):
            spikes.append(sdf.round_cone(P(sx * 0.33 * w, -0.16, 0.13), P(sx * 0.37 * w, -0.08, 0.03),
                                         0.035 * h, 0.010 * h))
            spikes.append(sdf.round_cone(P(sx * 0.33 * w, 0.20, 0.06), P(sx * 0.38 * w, 0.30, -0.06),
                                         0.035 * h, 0.010 * h))
            spikes.append(sdf.round_cone(P(sx * 0.315 * w, -0.13, 0.05), P(sx * 0.318 * w, -0.14, -0.08),
                                         0.022 * h, 0.016 * h))
        shape = sdf.blend(base, *[(0.012 * h, sp) for sp in spikes])
        parts.append(mu_sdf_part("Hair", shape, mat, 0.008 * h, tris, rigid="head", sym=False))
    elif style == "buzz":
        base = hair_cap_region(hb, front_z=0.24, back_z=-0.40, grow=0.012)
        parts.append(mu_sdf_part("Hair", base, mat, 0.008 * h, tris, rigid="head", sym=True))
    elif style == "short":
        base = hair_cap_region(hb, front_z=0.21, back_z=-0.42, grow=0.024)
        side = [sdf.ellipsoid(P(sx * 0.31, -0.10, 0.04), hb.R(0.05, 0.10, 0.12)) for sx in (1, -1)]
        shape = sdf.blend(base, *[(0.03 * h, s_) for s_ in side])
        parts.append(mu_sdf_part("Hair", shape, mat, 0.008 * h, tris, rigid="head", sym=False))
    elif style == "ponytail":
        base = hair_cap_region(hb, front_z=0.21, back_z=-0.45, grow=0.03)
        side = [sdf.polyline_tube([P(sx * 0.28, -0.25, 0.16), P(sx * 0.31, -0.24, 0.0),
                                   P(sx * 0.30, -0.22, -0.16)],
                                  [0.04 * h, 0.03 * h, 0.012 * h]) for sx in (1, -1)]
        pts = [P(0, 0.40, 0.18), P(0, 0.56, 0.12), P(0, 0.62, -0.10), P(0, 0.58, -0.40),
               P(0, 0.50, -0.70), P(0, 0.44, -0.92)]
        rad = A([0.11, 0.12, 0.115, 0.10, 0.075, 0.035]) * h
        tail = sdf.polyline_tube(pts, rad)
        shape = sdf.blend(base, (0.03 * h, side[0]), (0.03 * h, side[1]), (0.05 * h, tail))
        parts.append(mu_sdf_part("Hair", shape, mat, 0.008 * h, tris + 300, sym=True,
                                 bones=["head", "neck"]))
        if accent_mat is not None:
            tie = sdf.torus(P(0, 0.545, 0.14), 0.10 * h, 0.032 * h,
                            sdf.frame_from([1, 0, 0], [0, 0.97, -0.25]))
            parts.append(mu.sdf_part("HairTie", tie, accent_mat, 0.006 * h, 200,
                                     rigid="head", sym=True))
    elif style == "pixie":
        base = hair_cap_region(hb, front_z=0.20, back_z=-0.34, grow=0.02)
        w = hb.f["width"]
        back = sdf.ellipsoid(P(0, 0.28, -0.06), hb.R(0.34 * w, 0.22, 0.20))
        back = sdf.intersect(back, sdf.halfspace(P(0, 0, -0.30), [0, 0.3, -1]))
        locks = [back]
        for sx in (1, -1):
            locks.append(sdf.polyline_tube([P(sx * 0.31, -0.18, 0.13), P(sx * 0.345, -0.22, 0.03),
                                            P(sx * 0.32, -0.25, -0.07)],
                                           [0.05 * h, 0.035 * h, 0.012 * h]))
        # side-swept fringe under the brim, falling across the forehead
        locks.append(sdf.polyline_tube([P(0.28, -0.29, 0.15), P(0.12, -0.38, 0.145),
                                        P(-0.06, -0.40, 0.12), P(-0.22, -0.36, 0.07),
                                        P(-0.31, -0.27, -0.01)],
                                       [0.045 * h, 0.045 * h, 0.038 * h, 0.026 * h, 0.010 * h]))
        for sx in (-0.18, 0.0, 0.18):
            locks.append(sdf.round_cone(P(sx, 0.36, -0.14), P(sx * 1.2, 0.40, -0.30),
                                        0.05 * h, 0.014 * h))
        shape = sdf.blend(base, *[(0.03 * h, l) for l in locks])
        parts.append(mu_sdf_part("Hair", shape, mat, 0.007 * h, tris + 300, rigid="head", sym=False))
    elif style == "curly":
        base = hair_cap_region(hb, front_z=0.22, back_z=-0.40, grow=0.02)
        curls = []
        w = hb.f["width"]
        for row, (dz, rr) in enumerate(((-0.02, 0.060), (-0.10, 0.058), (-0.19, 0.052))):
            n_c = 13 - 2 * row
            span = 120 - 15 * row
            for i in range(n_c):
                az = math.radians(-span + i * 2 * span / (n_c - 1) + (6 if row % 2 else 0))
                y = 0.05 + math.cos(az) * 0.41
                x = math.sin(az) * 0.355 * w
                z = band_z(y) + dz
                if abs(math.degrees(az)) > 100 and row > 0:
                    continue
                outv = A([math.sin(az), math.cos(az), 0.0])
                c = A(P(x, y, z)) + outv * 0.035 * h
                curls.append(sdf.sphere(c, rr * h))
        for sx in (-0.30, -0.18, 0.18, 0.30):
            curls.append(sdf.sphere(P(sx, -0.33 + 0.12 * abs(sx), 0.15), 0.05 * h))
        shape = sdf.blend(base, 0.008 * h, sdf.union(*curls))
        parts.append(mu_sdf_part("Hair", shape, mat, 0.007 * h, tris + 700, rigid="head"))
    elif style == "bob":
        outer = sdf.ellipsoid(P(0, 0.06, 0.06), hb.R(0.40, 0.47, 0.52))
        inner_face = sdf.ellipsoid(P(0, -0.40, -0.12), hb.R(0.30, 0.30, 0.36))
        bottom = sdf.halfspace(P(0, 0, -0.30), [0, -0.25, -1.0])
        shape = sdf.intersect(outer, bottom)
        shape = sdf.subtract(shape, inner_face, k=0.03 * h)
        # bangs
        bangs = sdf.intersect(sdf.ellipsoid(P(0, -0.20, 0.20), hb.R(0.36, 0.25, 0.16)),
                              sdf.halfspace(P(0, 0, 0.115), [0, 0, -1]))
        shape = sdf.blend(shape, 0.03 * h, bangs)
        # face cut so the bangs don't cover eyes
        shape = sdf.subtract(shape, sdf.halfspace(P(0, -0.45, 0.0), [0, 1, 0]), k=0.0)
        parts.append(mu_sdf_part("Hair", shape, mat, 0.008 * h, tris + 300, rigid="head",
                                 sym=True))
    return parts


def build_beard(hb, mat, full=False, tris=600):
    h = hb.h
    P = hb.P
    lower = sdf.ellipsoid(P(0, -0.07, -0.19), hb.R(0.30 * hb.f["jaw_w"], 0.31, 0.31))
    jaw = sdf.blend(lower, 0.08 * h, sdf.ellipsoid(P(0, -0.26, -0.42), hb.R(0.13, 0.09, 0.085)))
    grow = 0.05 if full else 0.022
    shell = sdf.offset(jaw, grow * h)
    if full:
        shell = sdf.blend(shell, 0.06 * h, sdf.ellipsoid(P(0, -0.30, -0.52), hb.R(0.18, 0.11, 0.13)))
    region = sdf.intersect(shell, sdf.halfspace(P(0, 0, -0.10), [0, -0.3, 1.0]))
    # keep only the front/side (not behind the ears)
    region = sdf.intersect(region, sdf.halfspace(P(0, 0.04, 0), [0, 1, 0]))
    # mouth opening
    mouth = sdf.ellipsoid(P(0, -0.40, -0.285), hb.R(0.12, 0.12, 0.045 if not full else 0.04))
    region = sdf.subtract(region, mouth, k=0.02 * h)
    # cheeks above the jaw stay bare: cut under the cheekbone line
    cheek = sdf.ellipsoid(P(0, -0.33, -0.05), hb.R(0.26, 0.20, 0.13))
    region = sdf.subtract(region, cheek, k=0.03 * h)
    parts = [mu.sdf_part("Beard", region, mat, 0.008 * h, tris, rigid="head", sym=True)]
    if full:
        mst = sdf.round_cone(P(-0.12, -0.42, -0.26), P(0.0, -0.46, -0.235), 0.03 * h, 0.035 * h)
        mst2 = sdf.round_cone(P(0.12, -0.42, -0.26), P(0.0, -0.46, -0.235), 0.03 * h, 0.035 * h)
        parts.append(mu.sdf_part("Moustache", sdf.union(mst, mst2), mat, 0.006 * h, 260,
                                 rigid="head", sym=True))
    return parts


def build_eye_black(hb, mat, skin_shape):
    h = hb.h
    loops = []
    for sx in (1, -1):
        cx = sx * 0.14
        loops.append(np.array([(cx - 0.07, -0.075), (cx + 0.07, -0.075),
                               (cx + 0.065, -0.115), (cx - 0.065, -0.115)]) * h)
    ctr = hb.P(0, -0.40, 0)
    return surface_decal("EyeBlack", loops, skin_shape, ctr, [1, 0, 0], [0, 0, 1],
                         [0, -1, 0], mat, lo=-0.001 * h, hi=0.006 * h,
                         voxel=0.004 * h, tris=200, rigid="head", sym=True)


def build_sunglasses(hb, lens_mat, frame_mat):
    h = hb.h
    P = hb.P
    w = hb.f["width"]
    band = sdf.ellipsoid(P(0, -0.02, 0.0), hb.R(0.37 * w, 0.43, 0.40))
    lens = sdf.intersect(sdf.shell(band, 0.03 * h),
                         sdf.box(P(0, -0.3, 0.012), hb.R(0.36, 0.3, 0.075), rnd=0.03 * h))
    lens = sdf.intersect(lens, sdf.halfspace(P(0, -0.18, 0), [0, 1, 0]))
    # nose notch
    lens = sdf.subtract(lens, sdf.ellipsoid(P(0, -0.42, -0.07), hb.R(0.05, 0.1, 0.06)), k=0.01 * h)
    lens.bbox = (P(-0.5, -0.6, -0.15), P(0.5, 0.0, 0.15))
    parts = [mu.sdf_part("Sunglasses", lens, lens_mat, 0.006 * h, 500, rigid="head",
                         sym=True, sharp=60)]
    top = sdf.intersect(sdf.shell(sdf.offset(band, 0.006 * h), 0.03 * h),
                        sdf.box(P(0, -0.3, 0.085), hb.R(0.37, 0.3, 0.014), rnd=0.008 * h))
    top = sdf.intersect(top, sdf.halfspace(P(0, -0.18, 0), [0, 1, 0]))
    arms = [sdf.capsule(P(sx * 0.33 * w, -0.17, 0.07), P(sx * 0.345 * w, 0.12, 0.03), 0.012 * h)
            for sx in (1, -1)]
    fr = sdf.union(top, *arms)
    fr.bbox = (P(-0.5, -0.6, -0.15), P(0.5, 0.3, 0.2))
    parts.append(mu.sdf_part("GlassesFrame", fr, frame_mat, 0.005 * h, 300, rigid="head",
                             sym=True))
    return parts


def build_headband(hb, mat):
    h = hb.h
    cr = cranium(hb, 0.012)
    band = sdf.intersect(cr, sdf.box(hb.P(0, 0, 0.28), hb.R(1, 1, 0.055), rot=sdf.rot_matrix(-12, 0, 0)))
    band = sdf.subtract(band, cranium(hb, -0.03))
    band.bbox = (hb.P(-0.5, -0.6, 0.0), hb.P(0.5, 0.6, 0.5))
    return [mu.sdf_part("Headband", band, mat, 0.007 * h, 500, rigid="head", sym=True)]


# ---------------------------------------------------------------------------
# baseball mitt (left hand)
# ---------------------------------------------------------------------------

def build_mitt(bb, side, mat, lace_mat, catcher=False):
    """Fielder's glove (or round catcher's mitt) rigid to hand.<side>.
    Hand frame: a = along fingers, b = palm normal (pocket side), c = thumb side."""
    s = bb.s * bb.p["hand_scale"] / 1.12 * 1.08
    W, f, n, t = bb.hand_frame(side)
    Rm = np.stack([t, n, f], 1)  # local x->thumb dir, y->palm normal, z->fingers

    def H(a, b, c):
        return W + f * a * s + n * b * s + t * c * s
    parts = []
    laces = []
    if catcher:
        body = sdf.ellipsoid(H(0.115, -0.005, 0.005), [0.125 * s, 0.062 * s, 0.135 * s], Rm)
        rim = sdf.torus(H(0.115, 0.012, 0.005), 0.112 * s, 0.032 * s, np.stack([t, f, n], 1))
        shape = sdf.blend(body, 0.025 * s, rim)
        pocket = sdf.ellipsoid(H(0.115, 0.072, 0.005), [0.088 * s, 0.045 * s, 0.095 * s], Rm)
        shape = sdf.subtract(shape, pocket, k=0.02 * s)
        thumb = sdf.round_cone(H(0.03, 0.0, 0.075), H(0.13, 0.025, 0.14), 0.036 * s, 0.03 * s)
        shape = sdf.blend(shape, 0.02 * s, thumb)
        heel = sdf.ellipsoid(H(0.0, -0.004, 0.0), [0.08 * s, 0.04 * s, 0.055 * s], Rm)
        shape = sdf.blend(shape, 0.03 * s, heel)
        # finger ridges on the back
        ridges = [sdf.round_cone(H(0.06, -0.045, cc), H(0.21, -0.03, cc * 1.3), 0.018 * s,
                                 0.016 * s) for cc in (0.05, 0.015, -0.02, -0.055)]
        shape = sdf.blend(shape, 0.015 * s, *ridges)
        pts = []
        for k in range(17):
            a_ = -math.pi * 0.95 + k * (1.9 * math.pi / 16)
            pts.append(H(0.115 + math.cos(a_) * 0.124, 0.03, 0.005 + math.sin(a_) * 0.124))
        laces.append(sdf.polyline_tube(pts, [0.0072 * s] * len(pts)))
        for i in range(4):
            a_ = -0.6 + i * 0.4
            laces.append(sdf.capsule(H(0.115 + math.cos(a_) * 0.105, 0.04, 0.005 + math.sin(a_) * 0.105),
                                     H(0.115 + math.cos(a_) * 0.140, 0.0, 0.005 + math.sin(a_) * 0.140),
                                     0.0065 * s))
        tris = 1000
    else:
        palm = sdf.box(H(0.085, -0.014, -0.004), [0.066 * s, 0.020 * s, 0.075 * s], Rm,
                       rnd=0.018 * s)
        heel = sdf.ellipsoid(H(0.008, -0.004, -0.004), [0.068 * s, 0.036 * s, 0.050 * s], Rm)
        shape = sdf.blend(palm, 0.03 * s, heel)
        stalls = []
        tips = []
        for cb, ln in ((0.042, 0.272), (0.014, 0.288), (-0.014, 0.281), (-0.042, 0.258)):
            base = H(0.10, -0.010, cb)
            mid = H(0.10 + (ln - 0.10) * 0.55, 0.002, cb * 1.25)
            tip = H(ln, 0.030, cb * 1.45)
            stalls.append(sdf.polyline_tube([base, mid, tip],
                                            [0.0215 * s, 0.022 * s, 0.020 * s]))
            tips.append((ln, cb * 1.45))
        fingers = sdf.smooth_union(0.004 * s, *stalls)
        shape = sdf.blend(shape, 0.012 * s, fingers)
        thumb = sdf.polyline_tube([H(0.03, -0.008, 0.058), H(0.12, 0.006, 0.098),
                                   H(0.195, 0.034, 0.112)],
                                  [0.024 * s, 0.022 * s, 0.019 * s])
        shape = sdf.blend(shape, 0.012 * s, thumb)
        # pocket rim: padded heel roll on the pocket side
        roll = sdf.round_cone(H(0.035, 0.012, 0.05), H(0.03, 0.012, -0.055), 0.020 * s, 0.018 * s)
        shape = sdf.blend(shape, 0.015 * s, roll)
        # I-web between thumb and index stall
        web_c = H(0.20, 0.016, 0.086)
        web = sdf.box(web_c, [0.020 * s, 0.007 * s, 0.055 * s], Rm, rnd=0.005 * s)
        holes = [sdf.box(H(0.168 + 0.032 * i, 0.016, 0.086), [0.012 * s, 0.03 * s, 0.009 * s],
                         Rm, rnd=0.003 * s) for i in range(3)]
        web = sdf.subtract(web, *holes)
        shape = sdf.union(shape, web)
        # pocket (palm side)
        pocket = sdf.ellipsoid(H(0.145, 0.052, 0.006), [0.060 * s, 0.040 * s, 0.11 * s], Rm)
        shape = sdf.subtract(shape, pocket, k=0.02 * s)
        # wrist opening on the back + strap
        strap = sdf.box(H(0.018, -0.036, -0.004), [0.07 * s, 0.009 * s, 0.022 * s], Rm,
                        rnd=0.008 * s)
        shape = sdf.blend(shape, 0.004 * s, strap)
        # laces: over the finger tips, through the web, thumb tip
        tip_pts = [H(ln + 0.004, 0.026, cc) for ln, cc in tips]
        tip_pts = [H(0.205, 0.038, 0.112)] + tip_pts
        laces.append(sdf.polyline_tube(tip_pts, [0.0065 * s] * len(tip_pts)))
        for i in range(4):
            a_ = 0.155 + i * 0.03
            laces.append(sdf.capsule(H(a_, 0.024, 0.062), H(a_ + 0.012, 0.024, 0.108), 0.0055 * s))
        laces.append(sdf.capsule(H(0.15, 0.024, 0.086), H(0.255, 0.024, 0.086), 0.0055 * s))
        # heel lacing
        laces.append(sdf.polyline_tube([H(-0.03, 0.0, 0.055), H(-0.045, 0.0, 0.0),
                                        H(-0.03, 0.0, -0.06)], [0.0055 * s] * 3))
        # logo patch on the back strap
        laces.append(sdf.box(H(0.018, -0.046, -0.004), [0.03 * s, 0.004 * s, 0.012 * s], Rm,
                             rnd=0.003 * s))
        tris = 1100
    parts.append(mu.sdf_part("Mitt", shape, mat, 0.0032 * s, tris, rigid="hand." + side))
    parts.append(mu.sdf_part("MittLace", sdf.union(*laces), lace_mat, 0.0026 * s, 300,
                             rigid="hand." + side))
    return parts


# ---------------------------------------------------------------------------
# jersey numbers
# ---------------------------------------------------------------------------

def build_numbers(bb, number, font_path, mat_num, mat_outline, back_h=0.20, front_h=0.075,
                  front=True):
    s = bb.s
    torso = bb.shapes.get("torso_ns") or bb.torso_sdf(with_sleeves=False)
    zc = bb.lv("chest")
    parts = []
    loops_b = glyph_loops(str(number), font_path, back_h * s)
    yb = bb._surface_y(torso, 0.0, zc + 0.08 * s, front=False)
    cb = A([0, yb, zc + 0.06 * s])
    u, v, out = A([-1, 0, 0]), A([0, 0, 1]), A([0, 1, 0])
    parts.append(surface_decal("NumberBack", loops_b, torso, cb, u, v, out, mat_num,
                               lo=-0.002 * s, hi=0.0065 * s, voxel=0.0028 * s, tris=700,
                               bones=["chest", "spine"]))
    if mat_outline is not None:
        parts.append(surface_decal("NumberBackOutline", loops_b, torso, cb, u, v, out,
                                   mat_outline, lo=-0.002 * s, hi=0.0042 * s,
                                   dilate=0.009 * s, voxel=0.0028 * s, tris=700,
                                   bones=["chest", "spine"]))
    if front:
        loops_f = glyph_loops(str(number), font_path, front_h * s)
        xf = 0.085 * s
        zf = zc + 0.06 * s
        yf = bb._surface_y(torso, xf, zf, front=True)
        cf = A([xf, yf, zf])
        u, v, out = A([1, 0, 0]), A([0, 0, 1]), A([0.25, -1, 0])
        parts.append(surface_decal("NumberFront", loops_f, torso, cf, u, v, out, mat_num,
                                   lo=-0.002 * s, hi=0.005 * s, voxel=0.0018 * s, tris=360,
                                   bones=["chest", "spine"]))
        parts.append(surface_decal("NumberFrontOutline", loops_f, torso, cf, u, v, out,
                                   mat_outline, lo=-0.002 * s, hi=0.0033 * s,
                                   dilate=0.0045 * s, voxel=0.0018 * s, tris=300,
                                   bones=["chest", "spine"]))
    return parts


# ---------------------------------------------------------------------------
# enemy head gear
# ---------------------------------------------------------------------------

def helmet_shell(hb, grow=0.0, size=1.0):
    return sdf.ellipsoid(hb.P(0, 0.07, 0.07), hb.R(0.40 * size + grow, 0.47 * size + grow,
                                                     0.50 * size + grow))


def build_batting_helmet(hb, mats, accent_mat, size=1.0, flap=True, stripe=True,
                         brim=True, riot=False, crest=False, crest_mat=None, tris=1100,
                         aero=False):
    """Batting helmet (Gear) + full-face dark visor (Visor) + glowing slit (Glow)."""
    h = hb.h
    P = hb.P
    parts = []
    shell = helmet_shell(hb, 0, size)
    if aero:
        tail = sdf.round_cone(P(0, 0.30, 0.25), P(0, 0.75 * size, 0.05), 0.22 * h * size, 0.04 * h)
        shell = sdf.blend(shell, 0.10 * h, tail)
    cut = sdf.halfspace(P(0, -0.42, 0.14), [0, -0.12, -1.0])
    helm = sdf.intersect(shell, cut)
    # open the face area at the front (visor goes there)
    helm = sdf.subtract(helm, sdf.ellipsoid(P(0, -0.55, -0.05), hb.R(0.30, 0.30, 0.22)), k=0.02 * h)
    if flap:
        fl = sdf.intersect(sdf.offset(helmet_shell(hb, 0, size), 0.0),
                           sdf.ellipsoid(P(0.36 * size, -0.02, -0.22), hb.R(0.2, 0.26, 0.24)))
        helm = sdf.blend(helm, 0.03 * h, fl)
        if riot:
            fl2 = sdf.intersect(helmet_shell(hb, 0, size),
                                sdf.ellipsoid(P(-0.36 * size, -0.02, -0.22), hb.R(0.2, 0.26, 0.24)))
            helm = sdf.blend(helm, 0.03 * h, fl2)
    if brim:
        b = sdf.intersect(sdf.shell(sdf.sphere(P(0, -0.40, 0.17 - 0.9), 0.9 * h), 0.03 * h),
                          sdf.ellipsoid(P(0, -0.42 * size, 0.17), hb.R(0.30 * size, 0.22 * size, 1.0)))
        b = sdf.intersect(b, sdf.halfspace(P(0, -0.30, 0), [0, 1, 0]))
        helm = sdf.union(helm, b)
    # vent holes on top
    vents = [sdf.capsule(P(sx, 0.05, 0.6 * size), P(sx, 0.25, 0.55 * size), 0.035 * h)
             for sx in (-0.12, 0.12)]
    helm = sdf.subtract(helm, *vents, k=0.01 * h)
    helm.bbox = (P(-0.6, -0.8, -0.6) * 1, P(0.6, 0.9, 0.8))
    lo = A(hb.o) + A([-0.6, -0.8, -0.6]) * h * size
    hi = A(hb.o) + A([0.6, 0.9, 0.75]) * h * size
    helm.bbox = (lo, hi)
    parts.append(mu.sdf_part("Helmet", helm, mats["Gear"], 0.009 * h, tris, rigid="head",
                             sym=not flap or riot, sharp=None))
    if stripe:
        st = sdf.intersect(sdf.shell(sdf.offset(shell, 0.004 * h), 0.012 * h),
                           sdf.box(P(0, 0.05, 0.3), hb.R(0.045, 1.0, 1.0)))
        st = sdf.intersect(st, cut)
        st = sdf.intersect(st, sdf.halfspace(P(0, 0, 0.12), [0, 0, -1]))
        st.bbox = (lo, hi)
        parts.append(mu.sdf_part("HelmetStripe", st, accent_mat, 0.006 * h, 300, rigid="head",
                                 sym=True))
    if crest:
        cpts = [P(0, -0.30, 0.50 * size), P(0, 0.0, 0.66 * size), P(0, 0.35, 0.62 * size),
                P(0, 0.60, 0.40 * size)]
        crest_sh = sdf.polyline_tube(cpts, A([0.03, 0.06, 0.06, 0.03]) * h)
        crest_sh = sdf.intersect(crest_sh, sdf.box(P(0, 0.1, 0.5), hb.R(0.035, 1, 1)))
        crest_sh = sdf.blend(crest_sh, 0.02 * h, sdf.intersect(
            sdf.offset(shell, 0.12 * h), sdf.box(P(0, 0.1, 0.45), hb.R(0.03, 0.55, 0.3))))
        crest_sh = sdf.intersect(crest_sh, sdf.halfspace(P(0, 0, 0.25), [0, 0, -1]))
        crest_sh.bbox = (lo, hi + A([0, 0, 0.3 * h]))
        parts.append(mu.sdf_part("Crest", crest_sh, crest_mat or accent_mat, 0.007 * h, 500,
                                 rigid="head", sym=True))
    parts += build_visor(hb, mats, size)
    return parts


def build_visor(hb, mats, size=1.0, slit="angry"):
    h = hb.h
    P = hb.P
    face = sdf.ellipsoid(P(0, -0.02, -0.06), hb.R(0.36 * size, 0.46 * size, 0.52 * size))
    vis = sdf.intersect(sdf.shell(face, 0.03 * h),
                        sdf.halfspace(P(0, -0.12, 0), [0, 1, 0]))
    vis = sdf.intersect(vis, sdf.halfspace(P(0, 0, 0.17), [0, 0.15, 1.0]))
    vis = sdf.intersect(vis, sdf.halfspace(P(0, 0, -0.50), [0, 0.5, -1.0]))
    lo = A(hb.o) + A([-0.5, -0.7, -0.7]) * h * size
    hi = A(hb.o) + A([0.5, 0.1, 0.4]) * h * size
    vis.bbox = (lo, hi)
    parts = [mu.sdf_part("Visor", vis, mats["Visor"], 0.007 * h, 700, rigid="head", sym=True,
                         sharp=70)]
    # glowing eye slit (V shaped, menacing)
    if slit == "angry":
        loops = []
        for sx in (1, -1):
            pts = np.array([(0.03, -0.035), (0.27, 0.035), (0.26, 0.075), (0.03, 0.015)])
            pts[:, 0] *= sx
            if sx < 0:
                pts = pts[::-1]
            loops.append(pts * h * size)
    else:
        loops = [np.array([(-0.26, -0.02), (0.26, -0.02), (0.26, 0.04), (-0.26, 0.04)]) * h * size]
    ctr = hb.P(0, -0.46, 0.02)
    parts.append(surface_decal("EyeSlit", loops, face, ctr, [1, 0, 0], [0, 0, 1], [0, -1, 0],
                               mats["Glow"], lo=0.008 * h, hi=0.024 * h, voxel=0.004 * h,
                               tris=260, rigid="head", sym=True))
    return parts


def claw_emblem(bb, mat, size=0.13):
    s = bb.s
    torso = bb.torso_sdf(with_sleeves=False)
    zc = bb.lv("chest")
    loops = []
    for i in range(3):
        o = (i - 1) * 0.30
        loops.append(np.array([(o - 0.10, 0.48), (o + 0.02, 0.48), (o + 0.12, -0.48),
                               (o + 0.0, -0.48)]) * size * s)
    xf = 0.0
    zf = zc + 0.07 * s
    yf = bb._surface_y(torso, xf, zf, front=True)
    return surface_decal("ChestEmblem", loops, torso, [xf, yf, zf], [1, 0, 0], [0, 0, 1],
                         [0, -1, 0], mat, lo=-0.002 * s, hi=0.005 * s, voxel=0.0028 * s,
                         tris=300, bones=["chest", "spine"])
