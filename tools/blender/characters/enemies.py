"""Type-specific silhouette pieces for The Wreckers (enemies + bosses)."""
import math
import numpy as np
import bpy
import bmesh

import sdf
import meshutil as mu
import outfit


def A(v):
    return np.array(v, dtype=np.float64)


# ---------------------------------------------------------------------------
# generic armour helpers
# ---------------------------------------------------------------------------

def torso_plate(bb, mat, lo=-0.02, hi=0.032, front=True, back=False, z0=None, z1=None,
                grooves=0, name="ChestPlate", tris=700, glow_mat=None):
    s = bb.s
    torso = bb.torso_sdf(with_sleeves=False)
    zp = bb.lv("pelvis")
    zn = bb.lv("neck")
    z0 = zp + 0.04 * s if z0 is None else z0
    z1 = zn - 0.02 * s if z1 is None else z1
    plate = outfit.band_between(torso, lo * s, hi * s)
    region = sdf.box([0, 0, (z0 + z1) / 2], [0.5 * s, 0.5 * s, (z1 - z0) / 2])
    plate = sdf.intersect(plate, region, k=0.006 * s)
    if front and not back:
        plate = sdf.intersect(plate, sdf.halfspace([0, 0.0, 0], [0, 1, 0]))
    if back and not front:
        plate = sdf.intersect(plate, sdf.halfspace([0, 0.0, 0], [0, -1, 0]))
    # neck clearance
    plate = sdf.subtract(plate, sdf.round_cone([0, 0.01 * s, zn - 0.08 * s], [0, 0.02 * s, zn + 0.2 * s],
                                               0.10 * s, 0.12 * s), k=0.01 * s)
    cuts = []
    if grooves:
        for z in np.linspace(z0 + (z1 - z0) / (grooves + 1), z1 - (z1 - z0) / (grooves + 1), grooves):
            cuts.append(sdf.box([0, 0, z], [0.6 * s, 0.6 * s, 0.006 * s]))
        cuts.append(sdf.box([0, -0.3 * s, (z0 + z1) / 2], [0.005 * s, 0.3 * s, (z1 - z0)]))
        plate = sdf.subtract(plate, *cuts, k=0.003 * s)
    plate.bbox = (A([-0.4 * s, -0.4 * s, z0 - 0.02 * s]), A([0.4 * s, 0.4 * s, z1 + 0.02 * s]))
    parts = [mu.sdf_part(name, plate, mat, 0.006 * s, tris, bones=["hips", "spine", "chest"],
                         sym=True, sharp=40)]
    if glow_mat is not None and grooves:
        glow = outfit.band_between(torso, 0.008 * s, 0.018 * s)
        glow = sdf.intersect(glow, sdf.union(*cuts))
        glow = sdf.intersect(glow, region)
        if front and not back:
            glow = sdf.intersect(glow, sdf.halfspace([0, 0.0, 0], [0, 1, 0]))
        glow.bbox = plate.bbox
        parts.append(mu.sdf_part(name + "Glow", glow, glow_mat, 0.005 * s, 400,
                                 bones=["hips", "spine", "chest"], sym=True))
    return parts


def pauldrons(bb, mat, size=1.0, layers=2, tris=500, glow_mat=None, spikes=0, spike_mat=None):
    s = bb.s
    parts = []
    for side, sx in (("L", 1), ("R", -1)):
        S = bb.j("upper_arm." + side)
        c = S + A([sx * 0.015 * s, 0.0, 0.035 * s])
        shapes = []
        for i in range(layers):
            r = (0.105 - 0.018 * i) * s * size
            cc = c + A([sx * 0.03 * i * s, 0, -0.045 * i * s * size])
            sh = sdf.shell(sdf.sphere(cc, r), 0.016 * s)
            sh = sdf.intersect(sh, sdf.halfspace(cc + A([0, 0, -0.25 * r]), [0, 0, -1]))
            sh = sdf.intersect(sh, sdf.halfspace(cc + A([-sx * 0.55 * r, 0, 0]), [-sx, 0, 0]))
            shapes.append(sh)
        if spikes:
            for k in range(spikes):
                a = math.radians(-40 + k * 80 / max(1, spikes - 1))
                base = c + A([sx * 0.07 * s * size, math.sin(a) * 0.06 * s, 0.07 * s * size])
                tip = base + A([sx * 0.06, math.sin(a) * 0.03, 0.08]) * s * size
                shapes.append(sdf.round_cone(base, tip, 0.022 * s * size, 0.004 * s))
        shape = sdf.union(*shapes)
        shape.bbox = (c - 0.25 * s * size, c + 0.25 * s * size)
        parts.append(mu.sdf_part("Pauldron." + side, shape, mat, 0.006 * s, tris,
                                 bones=["shoulder." + side, "upper_arm." + side, "chest"],
                                 sharp=40, extra={"weight_overrides": {"chest": 0.6}}))
    return parts


def gauntlets(bb, mat, tris=300, extra=0.016):
    s = bb.s
    parts = []
    for side in ("L", "R"):
        arm = bb.arm_sdf(side, upper=False, lower=True)
        E = bb.j("forearm." + side)
        W = bb.j("hand." + side)
        d = (W - E) / np.linalg.norm(W - E)
        g = outfit.band_between(arm, -0.015 * s, extra * s)
        g = sdf.intersect(g, sdf.halfspace(E + d * 0.35 * np.linalg.norm(W - E), -d))
        g = sdf.intersect(g, sdf.halfspace(W + d * 0.01 * s, d))
        g.bbox = (np.minimum(E, W) - 0.12 * s, np.maximum(E, W) + 0.12 * s)
        parts.append(mu.sdf_part("Gauntlet." + side, g, mat, 0.005 * s, tris,
                                 bones=["forearm." + side, "hand." + side], sharp=45))
    return parts


def greaves(bb, mat, tris=300, knee=True, glow_mat=None):
    s = bb.s
    parts = []
    for side in ("L", "R"):
        sock = bb.sock_sdf(side)
        K = bb.j("shin." + side)
        Ak = bb.j("foot." + side)
        g = outfit.band_between(sock, -0.02 * s, 0.022 * s)
        g = sdf.intersect(g, sdf.halfspace(K + A([0, 0.01 * s, 0]), [0, 1, 0]))
        g = sdf.intersect(g, sdf.halfspace(Ak + A([0, 0, 0.05 * s]), [0, 0, -1]))
        g = sdf.intersect(g, sdf.halfspace(K - A([0, 0, 0.05 * s]), [0, 0, 1]))
        if knee:
            kc = sdf.ellipsoid(K + A([0, -0.065 * s, 0.0]), [0.065 * s, 0.04 * s, 0.07 * s])
            kc = sdf.subtract(kc, sdf.sphere(K, 0.07 * s))
            g = sdf.union(g, kc)
        g.bbox = (np.minimum(K, Ak) - 0.15 * s, np.maximum(K, Ak) + 0.15 * s)
        parts.append(mu.sdf_part("Greave." + side, g, mat, 0.006 * s, tris,
                                 bones=["thigh." + side, "shin." + side], sharp=45))
    return parts


def thigh_plates(bb, mat, tris=300):
    s = bb.s
    pants = bb.pants_sdf()
    parts = []
    zb = bb.belt_z()
    for side, sx in (("L", 1), ("R", -1)):
        H = bb.j("thigh." + side)
        K = bb.j("shin." + side)
        g = outfit.band_between(pants, -0.02 * s, 0.022 * s)
        g = sdf.intersect(g, sdf.halfspace(H + A([0, 0.0, 0]), [0, 1, 0]))
        g = sdf.intersect(g, sdf.halfspace(A([0, 0, zb - 0.03 * s]), [0, 0, 1]))
        g = sdf.intersect(g, sdf.halfspace(A([0, 0, (H[2] + K[2]) / 2]), [0, 0, -1]))
        g = sdf.intersect(g, sdf.halfspace(A([sx * 0.02 * s, 0, 0]), [-sx, 0, 0]))
        g.bbox = (A([min(0, sx * 0.4) * s, -0.4 * s, K[2]]), A([max(0, sx * 0.4) * s, 0.2 * s, zb]))
        parts.append(mu.sdf_part("Tasset." + side, g, mat, 0.006 * s, tris,
                                 bones=["hips", "thigh." + side], sharp=45))
    return parts


# ---------------------------------------------------------------------------
# cloth: cape, scarf tails
# ---------------------------------------------------------------------------

def cape(bb, mat, length=0.55, flare=1.0, tattered=False, spread=0.80, rows=14, cols=18,
         thickness=0.012, name="Cape", seed=1):
    """Cape hanging from the shoulders down the back (bmesh grid + solidify)."""
    s = bb.s
    p = bb.p
    zs = bb.j("upper_arm.L")[2] + 0.035 * s
    zk = bb.lv("knee")
    z_bot = zs - (zs - zk) * length / 0.55 * 0.92
    ax0 = p["sh_half"] * s + 0.045 * s
    ay0 = p["chest_d"] * s + 0.035 * s
    ax1 = ax0 + 0.08 * s * flare
    ay1 = ay0 + 0.10 * s * flare
    rng = np.random.RandomState(seed)
    jag = rng.uniform(0, 1, cols + 1)
    verts = []
    for i in range(rows + 1):
        v = i / rows
        row = []
        for j in range(cols + 1):
            u = j / cols
            th = math.pi * (u - 0.5) * spread
            vv = v
            ax = ax0 + (ax1 - ax0) * vv ** 1.3
            ay = ay0 + (ay1 - ay0) * vv ** 1.1
            # folds
            fold = 0.012 * s * math.sin(u * math.pi * 6) * vv
            zb = z_bot
            if tattered:
                zb = z_bot + (0.10 * s if j % 2 else 0.0) * (0.5 + 0.5 * jag[j]) + 0.02 * s * jag[j]
            z = zs + (zb - zs) * v
            x = (ax + fold) * math.sin(th)
            y = (ay + fold) * math.cos(th) + 0.01 * s
            # the top edge rolls over the shoulders a little
            if i == 0:
                z += 0.01 * s
            row.append((x, y, z))
        verts.append(row)
    bm = bmesh.new()
    vv = [[bm.verts.new(c) for c in row] for row in verts]
    for i in range(rows):
        for j in range(cols):
            bm.faces.new((vv[i][j], vv[i][j + 1], vv[i + 1][j + 1], vv[i + 1][j]))
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    sol = obj.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = thickness * s
    sol.offset = 0.0
    mu.apply_modifiers(obj)
    mu.set_material(obj, mat)
    mu.shade(obj, True)
    obj["rigid"] = ""
    obj["bones"] = "spine,chest,hips"
    obj["weight_overrides"] = {"hips": 1.6, "spine": 1.4}
    mu.PARTS.append(obj)
    return [obj]


def scarf_tails(bb, mat, name="Scarf"):
    s = bb.s
    zn = bb.lv("neck")
    parts = []
    # wrap around the neck
    nr = bb.p["neck_r"] * s
    ring = sdf.torus([0, 0.012 * s, zn - 0.01 * s], nr * 1.35, 0.03 * s)
    shapes = [ring]
    for sx in (1, -1):
        pts = [A([sx * 0.03 * s, 0.07 * s, zn - 0.01 * s]),
               A([sx * 0.06 * s, 0.17 * s, zn - 0.10 * s]),
               A([sx * 0.10 * s, 0.24 * s, zn - 0.26 * s]),
               A([sx * 0.13 * s, 0.30 * s, zn - 0.44 * s])]
        tail = sdf.polyline_tube(pts, [0.03 * s, 0.028 * s, 0.024 * s, 0.012 * s])
        # flatten: intersect with a slab
        tail = sdf.intersect(tail, sdf.box(A([sx * 0.08 * s, 0.2 * s, zn - 0.25 * s]),
                                           [0.012 * s, 0.4 * s, 0.4 * s],
                                           rot=sdf.rot_matrix(0, 0, sx * 18), rnd=0.004 * s))
        shapes.append(tail)
    sh = sdf.union(*shapes)
    sh.bbox = (A([-0.3 * s, -0.2 * s, zn - 0.55 * s]), A([0.3 * s, 0.45 * s, zn + 0.08 * s]))
    parts.append(mu.sdf_part(name, sh, mat, 0.006 * s, 700, bones=["neck", "chest", "spine"]))
    return parts


# ---------------------------------------------------------------------------
# bats
# ---------------------------------------------------------------------------

def bat(bb, mat, band_mat=None, length=1.0, barrel=0.05, spikes=0, spike_mat=None,
        name="Bat", tris=900):
    """Bat rigid to hand.R along the hand's thumb axis (t)."""
    s = bb.s
    W, f, n, t = bb.hand_frame("R")
    hs = bb.p["hand_scale"]
    grip = W + f * 0.058 * s * hs + n * 0.028 * s * hs
    knob_c = grip - t * 0.15 * s * hs
    L = length * s
    handle_r = 0.016 * s * hs
    p0 = knob_c
    p1 = grip + t * 0.10 * s
    p2 = grip + t * (0.38 * L)
    p3 = grip + t * (L - 0.15 * s * hs)
    knob = sdf.ellipsoid(knob_c, [0.026 * s * hs] * 3)
    body = sdf.round_cone(p0, p1, handle_r, handle_r * 1.05)
    taper = sdf.round_cone(p1, p2, handle_r * 1.05, barrel * s * 0.9)
    barr = sdf.round_cone(p2, p3, barrel * s * 0.9, barrel * s)
    shape = sdf.blend(knob, 0.01 * s, body, taper, barr)
    shape.bbox = (np.minimum(knob_c, p3) - 0.2 * s, np.maximum(knob_c, p3) + 0.2 * s)
    parts = [mu.sdf_part(name, shape, mat, 0.006 * s * max(1.0, barrel / 0.05), tris,
                         rigid="hand.R", sharp=None)]
    if band_mat is not None:
        bands = []
        for k in (0.45, 0.62, 0.80, 0.93):
            c = grip + t * (k * (L - 0.15 * s * hs))
            M = np.stack([n, f, t], 1)
            bands.append(sdf.torus(c, barrel * s * 0.98, 0.012 * s, M))
        if spikes:
            for k in range(spikes):
                kk = 0.55 + 0.38 * (k // 4) / max(1, (spikes - 1) // 4)
                ang = (k % 4) * math.pi / 2 + (k // 4) * math.pi / 4
                c = grip + t * (kk * (L - 0.15 * s * hs))
                d = n * math.cos(ang) + f * math.sin(ang)
                bands.append(sdf.round_cone(c + d * barrel * s * 0.9, c + d * (barrel * s + 0.07 * s),
                                            0.018 * s, 0.003 * s))
        bs = sdf.union(*bands)
        parts.append(mu.sdf_part(name + "Bands", bs, band_mat, 0.005 * s, 600, rigid="hand.R",
                                 sharp=45))
    return parts


# ---------------------------------------------------------------------------
# decals
# ---------------------------------------------------------------------------

def lightning_stripes(bb, mat):
    s = bb.s
    parts = []
    torso = bb.torso_sdf(with_sleeves=False)
    zc = bb.lv("chest")
    bolt = np.array([(0.0, 0.22), (0.05, 0.22), (0.01, 0.04), (0.06, 0.04), (-0.04, -0.24),
                     (-0.01, -0.03), (-0.06, -0.03)]) * s
    for sx in (1, -1):
        b = bolt.copy()
        b[:, 0] *= sx
        if sx < 0:
            b = b[::-1]
        x = sx * (bb.p["chest_w"] * s * 0.95)
        ctr = A([x, 0.0, zc - 0.02 * s])
        parts.append(outfit.surface_decal("Bolt." + ("L" if sx > 0 else "R"), [b], torso, ctr,
                                          [0, -1, 0] if sx > 0 else [0, 1, 0], [0, 0, 1],
                                          [sx, 0, 0], mat, lo=-0.002 * s, hi=0.005 * s,
                                          voxel=0.003 * s, tris=200, bones=["spine", "chest", "hips"],
                                          side_offset=0.035 * s))
    pants = bb.pants_sdf()
    for side, sx in (("L", 1), ("R", -1)):
        H = bb.j("thigh." + side)
        K = bb.j("shin." + side)
        b = (bolt * 0.9).copy()
        b[:, 0] *= sx
        if sx < 0:
            b = b[::-1]
        ctr = A([H[0] + sx * (bb.p["thigh_r"] * s + 0.01 * s), 0.0, (H[2] + K[2]) / 2])
        parts.append(outfit.surface_decal("LegBolt." + side, [b], pants, ctr,
                                          [0, -1, 0] if sx > 0 else [0, 1, 0], [0, 0, 1],
                                          [sx, 0, 0], mat, lo=-0.002 * s, hi=0.005 * s,
                                          voxel=0.003 * s, tris=200,
                                          bones=["thigh." + side, "hips"]))
    return parts


def springs(bb, coil_mat, plate_mat):
    """Spring-like shin guards + knee braces (jumper)."""
    s = bb.s
    parts = []
    for side in ("L", "R"):
        K = bb.j("shin." + side)
        Ak = bb.j("foot." + side)
        d = (Ak - K) / np.linalg.norm(Ak - K)
        L = np.linalg.norm(Ak - K)
        cr = bb.p["calf_r"] * s
        # helix around the shin from below the knee to above the ankle
        u = np.cross(d, [1, 0, 0])
        u /= np.linalg.norm(u)
        v = np.cross(d, u)
        pts = []
        turns = 5.5
        N = 80
        for i in range(N + 1):
            k = i / N
            ang = 2 * math.pi * turns * k
            r = cr * (1.25 - 0.45 * k) + 0.012 * s
            c = K + d * (0.16 * L + 0.66 * L * k)
            pts.append(c + (u * math.cos(ang) + v * math.sin(ang)) * r)
        coil = sdf.polyline_tube(pts, [0.009 * s] * len(pts))
        coil.bbox = (np.minimum(K, Ak) - 0.15 * s, np.maximum(K, Ak) + 0.15 * s)
        parts.append(mu.sdf_part("Spring." + side, coil, coil_mat, 0.004 * s, 900,
                                 bones=["shin." + side]))
        # knee brace: ring + side hinges
        M = np.stack([A([1, 0, 0]), A([0, 1, 0]), d], 1)
        brace = sdf.torus(K + A([0, 0, 0.0]), bb.p["knee_r"] * s * 1.18, 0.016 * s,
                          sdf.frame_from([1, 0, 0], d))
        hinge = [sdf.sphere(K + A([sx * bb.p["knee_r"] * s * 1.18, 0, 0]), 0.022 * s)
                 for sx in (1, -1)]
        bsh = sdf.union(brace, *hinge)
        bsh.bbox = (K - 0.15 * s, K + 0.15 * s)
        parts.append(mu.sdf_part("KneeBrace." + side, bsh, plate_mat, 0.004 * s, 400,
                                 bones=["thigh." + side, "shin." + side], sharp=45))
    return parts


def armband(bb, mat, side="L"):
    s = bb.s
    S = bb.j("upper_arm." + side)
    E = bb.j("forearm." + side)
    d = (E - S) / np.linalg.norm(E - S)
    arm = bb.arm_sdf(side, upper=True, lower=False)
    c = S + d * 0.17 * s
    slab = sdf.intersect(sdf.halfspace(c - d * 0.025 * s, -d), sdf.halfspace(c + d * 0.025 * s, d))
    band = sdf.intersect(sdf.offset(arm, 0.008 * s), slab, k=0.003 * s)
    band.bbox = (c - 0.12 * s, c + 0.12 * s)
    return [mu.sdf_part("Armband." + side, band, mat, 0.004 * s, 250,
                        bones=["upper_arm." + side])]


# ---------------------------------------------------------------------------
# dispatcher
# ---------------------------------------------------------------------------

def extras(cid, cfg, sk, bb, hb, mats):
    parts = []
    M = mats
    if cfg.get("lightning"):
        parts += lightning_stripes(bb, M["JerseyTrim"])
    if cfg.get("springs"):
        parts += springs(bb, M["JerseyTrim"], M["Metal"])
    if cid == "armored":
        parts += torso_plate(bb, M["Metal"], grooves=2, tris=800)
        parts += pauldrons(bb, M["Metal"], size=1.1, layers=2)
        parts += greaves(bb, M["Metal"], tris=300)
    if cid == "captain":
        parts += cape(bb, M["Cloth"], length=0.55, flare=1.0)
        parts += armband(bb, M["Number"], "L")
        parts += pauldrons(bb, M["JerseyTrim"], size=0.85, layers=1, tris=300)
    if cid == "trickster":
        parts += scarf_tails(bb, M["Cloth"])
    if cid == "slugger":
        parts += pauldrons(bb, M["Metal"], size=1.15, layers=2, tris=400, spikes=3)
        parts += torso_plate(bb, M["Metal"], grooves=1, tris=500, z0=bb.lv("chest") - 0.02 * bb.s)
        parts += gauntlets(bb, M["Metal"], tris=260)
        parts += bat(bb, M["Bat"], M["Metal"], length=1.05, barrel=0.062, spikes=8, tris=700)
    if cid == "iron_slugger":
        g = M["Glow"]
        parts += torso_plate(bb, M["Metal"], grooves=3, tris=1400, glow_mat=g, front=True, back=True)
        parts += pauldrons(bb, M["Metal"], size=1.25, layers=3, tris=700, spikes=4)
        parts += gauntlets(bb, M["Metal"], tris=500)
        parts += greaves(bb, M["Metal"], tris=600)
        parts += thigh_plates(bb, M["Metal"], tris=500)
        parts += bat(bb, M["Bat"], M["Metal"], length=1.05, barrel=0.068, spikes=12, tris=1000)
    if cid == "phantom_captain":
        parts += cape(bb, M["Cloth"], length=0.68, flare=1.4, tattered=True, rows=16, cols=24)
        parts += pauldrons(bb, M["Gear"], size=0.95, layers=2, tris=500)
        parts += armband(bb, M["Glow"], "L")
    if cid == "grand_slammer":
        h = hb.h
        P = hb.P
        horns = []
        for sx in (1, -1):
            pts = [P(sx * 0.33, 0.02, 0.22), P(sx * 0.52, 0.0, 0.30), P(sx * 0.62, -0.04, 0.48),
                   P(sx * 0.60, -0.10, 0.66)]
            horns.append(sdf.polyline_tube(pts, [0.075 * h, 0.06 * h, 0.04 * h, 0.008 * h]))
        hs = sdf.union(*horns)
        parts.append(mu.sdf_part("Horns", hs, M["Metal"], 0.008 * h, 500, rigid="head", sym=True,
                                 sharp=50))
        parts += torso_plate(bb, M["Gear"], grooves=2, tris=1200, front=True, back=True)
        parts += torso_plate(bb, M["Metal"], lo=0.020, hi=0.042, grooves=0, tris=500,
                             z0=bb.lv("chest") + 0.02 * bb.s, z1=bb.lv("chest") + 0.20 * bb.s,
                             name="ChestCrest")
        parts += pauldrons(bb, M["Metal"], size=1.3, layers=3, tris=800, spikes=3)
        parts += gauntlets(bb, M["Metal"], tris=500)
        parts += greaves(bb, M["Gear"], tris=600)
        parts += thigh_plates(bb, M["Metal"], tris=500)
        parts += cape(bb, M["Cloth"], length=0.60, flare=1.2, rows=14, cols=20)
        parts += bat(bb, M["Bat"], M["Metal"], length=1.0, barrel=0.07, spikes=0, tris=900)
    return parts
