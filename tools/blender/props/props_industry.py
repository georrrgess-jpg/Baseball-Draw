"""Industrial background set (seen from a distance, low detail):
smokestack, crane, warehouse, water tower, shipping container and three
skyline buildings.  Blender space: Z up, front faces -Y, metres."""
import math

from mathutils import Vector

from pcommon import finish, load_font, mb_new
from pmesh import RX, T
from props_hero import _ladder, _octagon


# ================================================================ SMOKESTACK
def smokestack():
    m = mb_new()
    m.prism(_octagon(2.4, 0.7), 0.0, 1.4, 'ConcreteDark', caps=(False, True))
    m.prism(_octagon(2.45, 0.72), 0.0, 0.5, 'Hazard', caps=(False, False))
    z0, z1 = 1.4, 30.0
    r0, r1 = 1.65, 1.05

    def rad(z):
        return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    seg = 16
    # brick shaft with painted aviation bands near the top
    zs = [z0, 24.0, 25.2, 26.4, 27.6, 28.8]
    mats = ['Brick', 'SteelScarlet', 'PaintWhite', 'SteelScarlet', 'PaintWhite']
    for (za, zb), mt in zip(zip(zs[:-1], zs[1:]), mats):
        m.cyl((0, 0, za), (0, 0, zb), rad(za), mt, r1=rad(zb), seg=seg, caps=(False, False),
              uv_scale=1.8 if mt == 'Brick' else None)
    m.cyl((0, 0, 28.8), (0, 0, z1), rad(28.8), 'Brick', r1=r1, seg=seg, caps=(False, False))
    # steel bands
    for z in (5.0, 10.0, 15.0, 20.0):
        m.cyl((0, 0, z), (0, 0, z + 0.3), rad(z) + 0.06, 'SteelCharcoal', r1=rad(z + 0.3) + 0.06, seg=seg,
              caps=(True, True))
    # cap with sooty lip
    m.lathe([(r1 + 0.12, z1), (r1 + 0.12, z1 + 0.5), (r1 - 0.2, z1 + 0.5), (r1 - 0.2, z1 - 0.6)], 'SteelDark',
            seg=seg, sharp=(1, 2))
    m.disc((0, 0, z1 - 0.6), (0, 0, 1), r1 - 0.2, 'Rubber', seg=seg)
    # ladder up the back side
    _ladder(m, (0, rad(1.6) + 0.3, 1.6), (0, r1 + 0.3, z1 + 0.4), width=0.45, rung=0.45, out=Vector((0, 1, 0)))
    m.sphere((0.9, 0, z1 + 0.65), 0.12, 'RedAviation', seg=6, rings=3)
    finish(m, 'Smokestack')


# ===================================================================== CRANE
def crane():
    m = mb_new()
    Y = 'SafetyYellow'
    # concrete base + ballast
    m.cbox((0, 0, 0.5), (6.0, 6.0, 1.0), 'Concrete', ch=0.08, skip_down=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * 1.6, sy * 1.6, 1.5), (1.4, 1.4, 1.0), 'ConcreteDark', skip=('-z',))
    # mast lattice
    hw = 1.0
    z0, zt = 1.0, 30.0
    n = 12
    zs = [z0 + (zt - z0) * k / n for k in range(n + 1)]
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in cs:
        m.strut((sx * hw, sy * hw, z0), (sx * hw, sy * hw, zt), 0.11, Y, sides=4)
    for k in range(n):
        for i in range(4):
            a, b = cs[i], cs[(i + 1) % 4]
            pa = (a[0] * hw, a[1] * hw, zs[k])
            pb = (b[0] * hw, b[1] * hw, zs[k + 1])
            if (k + i) % 2:
                pa, pb = (a[0] * hw, a[1] * hw, zs[k + 1]), (b[0] * hw, b[1] * hw, zs[k])
            m.strut(pa, pb, 0.05, Y, sides=3)
            m.strut((a[0] * hw, a[1] * hw, zs[k]), (b[0] * hw, b[1] * hw, zs[k]), 0.05, Y, sides=3)
    # slewing unit, cab
    m.box((0, 0, zt + 0.5), (2.6, 2.6, 1.0), 'SteelCharcoal')
    m.cbox((1.2, -1.9, zt + 1.6), (1.6, 1.4, 2.0), Y, ch=0.06)
    m.box((1.2, -2.61, zt + 1.85), (1.4, 0.04, 1.1), 'Glass', skip=('+y',))
    m.box((2.01, -1.9, zt + 1.85), (0.04, 1.2, 1.0), 'Glass', skip=('-x',))
    # tower head (apex)
    apex = Vector((0, 0, zt + 7.0))
    for sx, sy in cs:
        m.strut((sx * 0.9, sy * 0.9, zt + 1.0), apex, 0.08, Y, sides=4)
    # jib toward +X (triangular lattice)
    L = 30.0
    jz = zt + 1.0
    jw = 0.7
    jh = 1.6
    bays = 10
    m.strut((0.0, -jw, jz), (L, -jw, jz), 0.07, Y, sides=4)
    m.strut((0.0, jw, jz), (L, jw, jz), 0.07, Y, sides=4)
    m.strut((0.0, 0.0, jz + jh), (L - 1.0, 0.0, jz + 0.25), 0.07, Y, sides=4)
    for k in range(bays):
        xa = 1.3 + (L - 1.3) * k / bays
        xb = 1.3 + (L - 1.3) * (k + 1) / bays
        ztop = lambda x: jz + jh + (0.25 - jh) * x / (L - 1.0)
        for sy in (-jw, jw):
            m.strut((xa, sy, jz), ((xa + xb) / 2, 0.0, ztop((xa + xb) / 2)), 0.04, Y, sides=3)
            m.strut((xb, sy, jz), ((xa + xb) / 2, 0.0, ztop((xa + xb) / 2)), 0.04, Y, sides=3)
        m.strut((xa, -jw, jz), (xa, jw, jz), 0.035, Y, sides=3)
    # counter-jib toward -X with counterweights
    cl = 11.0
    m.box_mm((-cl, -1.0, jz - 0.1), (-1.3, 1.0, jz + 0.2), 'SteelCharcoal')
    for sy in (-1.0, 1.0):
        m.strut((-cl, sy, jz + 0.2), (-1.3, sy, jz + 0.2), 0.07, Y, sides=4)
        m.strut((-1.3, sy, jz + 0.2), (-cl + 4, sy, jz + 1.2), 0.05, Y, sides=3)
        m.strut((-cl, sy, jz + 0.2), (-cl + 4, sy, jz + 1.2), 0.05, Y, sides=3)
    for k in range(3):
        m.cbox((-cl + 0.8 + k * 1.1, 0, jz - 1.0), (1.0, 2.0, 1.8), 'ConcreteDark', ch=0.05)
    # tie bars from the apex
    m.strut(apex, (L * 0.55, 0.0, jz + jh * 0.45 + 0.1), 0.04, 'SteelDark', sides=3)
    m.strut(apex, (-cl + 1.0, 0.0, jz + 0.2), 0.04, 'SteelDark', sides=3)
    # trolley, hook and hanging hook block
    tx = 19.0
    m.box((tx, 0, jz - 0.25), (1.2, 1.6, 0.4), 'SteelCharcoal')
    for dy in (-0.15, 0.15):
        m.strut((tx, dy, jz - 0.45), (tx, dy, 14.0), 0.02, 'SteelDark', sides=3)
    m.cbox((tx, 0, 13.6), (0.7, 0.4, 0.9), 'SteelScarlet', ch=0.05)
    m.tube([(tx, 0, 13.1), (tx, 0, 12.7), (tx + 0.25, 0, 12.5), (tx + 0.3, 0, 12.8)], 0.06, 'SteelDark', seg=4)
    m.sphere((0, 0, zt + 7.15), 0.15, 'RedAviation', seg=6, rings=3)
    m.sphere((L, 0, jz + 0.4), 0.15, 'RedAviation', seg=6, rings=3)
    finish(m, 'Crane')


# ================================================================= WAREHOUSE
def warehouse():
    m = mb_new()
    W, D, He, Hr = 30.0, 15.0, 8.0, 12.0
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    # concrete skirt
    m.box_mm((x0 - 0.05, y0 - 0.05, 0.0), (x1 + 0.05, y1 + 0.05, 0.9), 'ConcreteDark', skip=('-z', '+z'))
    # corrugated walls
    m.box_mm((x0, y0, 0.9), (x1, y1, He), 'Corrugated', skip=('-z', '+z'))
    # gable ends
    for x, sgn in ((x0, -1), (x1, 1)):
        pts = [(x, y0, He), (x, y1, He), (x, 0.0, Hr)]
        if sgn > 0:
            m.poly(pts, 'Corrugated')
        else:
            m.poly(list(reversed(pts)), 'Corrugated')
    # roof (two slopes with overhang + thickness)
    ov = 0.5
    for sgn in (-1, 1):
        ye = sgn * (D / 2 + ov)
        ze = He - ov * (Hr - He) / (D / 2)
        m.hull([(x, y, z) for x in (x0 - ov, x1 + ov)
                for (y, z) in ((ye, ze), (0.0, Hr), (ye, ze + 0.2), (0.0, Hr + 0.2))], 'RoofSheet')
    # ridge cap
    m.box_mm((x0 - ov, -0.25, Hr + 0.12), (x1 + ov, 0.25, Hr + 0.32), 'SteelCharcoal')
    # roof turbine vents along the ridge
    for i in range(5):
        x = x0 + 3.0 + i * 6.0
        m.cyl((x, 0, Hr + 0.2), (x, 0, Hr + 1.0), 0.35, 'SteelGalv', seg=8, caps=(False, False))
        m.lathe([(0.45, Hr + 1.0), (0.48, Hr + 1.35), (0.3, Hr + 1.6), (0.0, Hr + 1.7)], 'SteelGalv', seg=8)
    # front: two roller shutters + man door + strip windows + sign
    for cx in (-7.0, 5.0):
        m.box_mm((cx - 2.6, y0 - 0.25, 0.0), (cx + 2.6, y0, 5.6), 'SteelCharcoal', skip=('-z', '+y'))
        m.box_mm((cx - 2.3, y0 - 0.12, 0.05), (cx + 2.3, y0 - 0.02, 5.2), 'Container', skip=('+y', '-z'))
        m.box_mm((cx - 2.6, y0 - 0.3, 5.6), (cx + 2.6, y0, 6.1), 'SteelNavy', skip=('+y',))
        for dx in (-3.0, 3.0):
            m.cyl((cx + dx, y0 - 0.6, 0.0), (cx + dx, y0 - 0.6, 1.1), 0.12, 'Hazard', seg=8, caps=(False, True))
    m.box_mm((11.0, y0 - 0.08, 0.0), (12.2, y0, 2.3), 'SteelScarlet', skip=('+y', '-z'))
    m.box_mm((x0 + 0.5, y0 - 0.06, 6.35), (x1 - 0.5, y0, 6.85), 'WindowGlow', skip=('+y',))
    for k in range(15):
        x = x0 + 0.5 + k * (W - 1.0) / 14
        m.box((x, y0 - 0.08, 6.6), (0.15, 0.06, 0.6), 'SteelCharcoal', skip=('+y',))
    m.box_mm((-6.2, y0 - 0.05, 6.95), (4.2, y0, 7.9), 'SteelNavy', skip=('+y',))
    font = load_font('RussoOne-Regular.ttf')
    with m.xf(T(-1.0, y0 - 0.05, 7.42) @ RX(90)):
        m.text('WORKS 07', font, 0.8, 'PaintWhite', depth=0.04, resolution=1)
    # gutters + downpipes
    for sgn in (-1, 1):
        y = sgn * (D / 2 + ov)
        m.box_mm((x0 - ov, y - 0.12, He - ov * (Hr - He) / (D / 2) - 0.2), (x1 + ov, y + 0.12,
                 He - ov * (Hr - He) / (D / 2)), 'SteelDark')
    for x in (x0 + 0.3, x1 - 0.3):
        m.cyl((x, y0 - 0.4, 0.0), (x, y0 - 0.4, He - 0.4), 0.08, 'SteelDark', seg=6, caps=(False, False))
    finish(m, 'Warehouse')


# =============================================================== WATER TOWER
def water_tower():
    m = mb_new()
    zt = 18.0
    b0, b1 = 3.6, 2.6
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in cs:
        m.cbox((sx * b0, sy * b0, 0.3), (1.1, 1.1, 0.6), 'Concrete', ch=0.06, skip_down=True)
        m.cyl((sx * b0, sy * b0, 0.6), (sx * b1, sy * b1, zt), 0.22, 'SteelNavy', r1=0.2, seg=8)
    for za, zb in ((0.8, 6.5), (6.5, 12.2), (12.2, zt - 0.3)):
        fa = (za) / zt
        fb = (zb) / zt
        wa = b0 + (b1 - b0) * fa
        wb = b0 + (b1 - b0) * fb
        for i in range(4):
            a, b = cs[i], cs[(i + 1) % 4]
            m.strut((a[0] * wa, a[1] * wa, za), (b[0] * wb, b[1] * wb, zb), 0.035, 'SteelGalv', sides=3)
            m.strut((b[0] * wa, b[1] * wa, za), (a[0] * wb, a[1] * wb, zb), 0.035, 'SteelGalv', sides=3)
            m.strut((a[0] * wb, a[1] * wb, zb), (b[0] * wb, b[1] * wb, zb), 0.06, 'SteelNavy', sides=4)
    # riser pipe
    m.cyl((0, 0, 0.0), (0, 0, zt), 0.45, 'SteelGalv', seg=10, caps=(False, False))
    # tank (lathe) with balcony
    R = 4.2
    seg = 20
    m.lathe([(0.0, zt - 1.0), (R * 0.75, zt - 0.6), (R, zt + 0.2)], 'SteelNavy', seg=seg, sharp=())
    m.cyl((0, 0, zt + 0.2), (0, 0, zt + 2.2), R, 'PaintWhite', seg=seg, caps=(False, False), uv_scale=4.0)
    m.cyl((0, 0, zt + 2.2), (0, 0, zt + 3.4), R, 'SteelScarlet', seg=seg, caps=(False, False), uv_scale=4.0)
    m.cyl((0, 0, zt + 3.4), (0, 0, zt + 5.2), R, 'PaintWhite', seg=seg, caps=(False, False), uv_scale=4.0)
    m.lathe([(R + 0.1, zt + 5.2), (R * 0.5, zt + 6.6), (0.0, zt + 7.0)], 'SteelNavy', seg=seg, sharp=(1,))
    m.lathe([(R + 0.12, zt + 5.15), (R + 0.12, zt + 5.3)], 'SteelNavy', seg=seg)
    m.cyl((0, 0, zt + 6.9), (0, 0, zt + 7.6), 0.06, 'SteelGalv', seg=6)
    m.sphere((0, 0, zt + 7.7), 0.13, 'RedAviation', seg=6, rings=3)
    # balcony ring
    m.cyl((0, 0, zt + 0.15), (0, 0, zt + 0.3), R + 0.9, 'SteelGalv', seg=seg, caps=(True, True))
    ring = []
    for i in range(seg):
        a = math.tau * i / seg
        ring.append(((R + 0.85) * math.cos(a), (R + 0.85) * math.sin(a), zt + 1.3))
    m.tube(ring, 0.04, 'SteelGalv', seg=4, closed=True)
    for i in range(0, seg, 2):
        x, y, _ = ring[i]
        m.strut((x, y, zt + 0.3), (x, y, zt + 1.3), 0.025, 'SteelGalv', sides=3)
    _ladder(m, (0, b0 + 0.5, 0.3), (0, R + 0.9, zt + 0.3), width=0.45, rung=0.5, out=Vector((0, 1, 0)))
    finish(m, 'WaterTower')


# ================================================================= CONTAINER
def container():
    m = mb_new()
    L, Wd, H = 6.06, 2.44, 2.59
    x0, x1 = -L / 2, L / 2
    y0, y1 = -Wd / 2, Wd / 2
    C = 'Container'
    # skin (inset between the frame)
    m.box_mm((x0 + 0.06, y0 + 0.02, 0.15), (x1 - 0.06, y1 - 0.02, H - 0.1), C, skip=('-z',))
    # bottom + top rails, corner posts
    for y in (y0, y1):
        m.box_mm((x0, y - 0.02 if y < 0 else y - 0.1, 0.0), (x1, y + 0.1 if y < 0 else y + 0.02, 0.17), C)
        m.box_mm((x0, y - 0.02 if y < 0 else y - 0.1, H - 0.12), (x1, y + 0.1 if y < 0 else y + 0.02, H), C)
    for x in (x0, x1):
        for y in (y0, y1):
            lo = (x if x < 0 else x - 0.16, y if y < 0 else y - 0.16, 0.0)
            hi = (x + 0.16 if x < 0 else x, y + 0.16 if y < 0 else y, H)
            m.box_mm(lo, hi, C, skip=('-z',))
            for z in (0.0, H - 0.12):
                m.box_mm((lo[0] - 0.005, lo[1] - 0.005, z), (hi[0] + 0.005, hi[1] + 0.005, z + 0.12), 'SteelDark',
                         skip=('-z',))
    # door end (+X): seams, locking bars, handles
    m.box_mm((x1 - 0.07, -0.01, 0.17), (x1 - 0.04, 0.01, H - 0.12), 'SteelDark', skip=('-x',))
    for y in (-0.95, -0.55, 0.55, 0.95):
        m.cyl((x1 - 0.02, y, 0.12), (x1 - 0.02, y, H - 0.08), 0.025, 'SteelDark', seg=6)
        m.box((x1 + 0.02, y + 0.1, 1.1), (0.04, 0.22, 0.05), 'SteelDark')
        for z in (0.35, H - 0.4):
            m.box((x1 - 0.01, y, z), (0.05, 0.1, 0.1), 'SteelDark')
    finish(m, 'Container')


# ============================================================= CITY SKYLINE
FL = 3.25           # window texture tile = 13 m = 4 floors x 4 bays of 3.25 m


def _rooftop(m, x, y, z, s=(4.0, 3.0, 2.0)):
    m.box((x, y, z + s[2] / 2), s, 'ConcreteDark', skip=('-z',))


def building_a():
    m = mb_new()
    # podium + slab tower (45.5 m)
    m.box((0, 0, 3.25), (26.0, 19.5, 6.5), 'Windows', skip=('-z', '+z'))
    m.box((0, 0, 6.6), (26.4, 19.9, 0.2), 'ConcreteDark', skip=('-z',))
    m.box((0, 0, 6.5 + 19.5), (19.5, 13.0, 39.0), 'Windows', skip=('-z', '+z'))
    m.box((0, 0, 45.6), (19.9, 13.4, 0.3), 'ConcreteDark', skip=('-z',))
    m.box((0, 0, 45.75 + 0.6), (19.5, 13.0, 1.2), 'ConcreteDark', skip=('-z', '+z'))
    _rooftop(m, -4.0, 1.5, 45.75, (6.0, 5.0, 3.0))
    m.cyl((5.0, -2.0, 45.75), (5.0, -2.0, 49.0), 1.6, 'SteelDark', seg=8)
    m.lathe([(1.7, 49.0), (0.0, 49.8)], 'SteelDark', seg=8)
    m.cyl((-6.0, 3.0, 48.75), (-6.0, 3.0, 52.0), 0.12, 'SteelGalv', seg=4)
    m.sphere((-6.0, 3.0, 52.1), 0.3, 'RedAviation', seg=6, rings=3)
    finish(m, 'BuildingA')


def building_b():
    m = mb_new()
    m.box((0, 0, 26.0), (19.5, 19.5, 52.0), 'Windows', skip=('-z', '+z'))
    m.box((0, 0, 52.1), (20.1, 20.1, 0.3), 'ConcreteDark', skip=('-z',))
    m.box((0, 0, 52.0 + 9.75), (13.0, 13.0, 19.5), 'Windows', skip=('-z', '+z'))
    # lit crown
    m.box((0, 0, 71.5 + 1.0), (13.6, 13.6, 2.0), 'WindowGlow', skip=('-z',))
    m.hull([(sx * 6.8, sy * 6.8, 73.5) for sx in (-1, 1) for sy in (-1, 1)] + [(0, 0, 78.0)], 'SteelCharcoal')
    m.cyl((0, 0, 78.0), (0, 0, 86.0), 0.18, 'SteelGalv', r1=0.08, seg=4)
    m.sphere((0, 0, 86.1), 0.35, 'RedAviation', seg=6, rings=3)
    _rooftop(m, 6.0, 6.0, 52.25, (4.0, 4.0, 2.5))
    _rooftop(m, -6.5, 6.0, 52.25, (3.0, 4.0, 2.0))
    finish(m, 'BuildingB')


def building_c():
    m = mb_new()
    oc = _octagon(6.5, 1.9)
    m.prism(oc, 0.0, 78.0, 'Windows', caps=(False, True), cap_mat='ConcreteDark')
    m.prism(_octagon(6.9, 2.0), 26.0, 26.6, 'ConcreteDark', caps=(True, True))
    m.prism(_octagon(6.9, 2.0), 58.5, 59.1, 'ConcreteDark', caps=(True, True))
    m.prism(_octagon(6.9, 2.0), 78.0, 78.9, 'SteelScarlet', caps=(True, True))
    m.hull([(x * 0.7, y * 0.7, 78.9) for x, y in oc] + [(x * 0.25, y * 0.25, 83.0) for x, y in oc], 'SteelCharcoal')
    m.cyl((0, 0, 83.0), (0, 0, 89.5), 0.15, 'SteelGalv', r1=0.06, seg=4)
    m.sphere((0, 0, 89.6), 0.3, 'RedAviation', seg=6, rings=3)
    finish(m, 'BuildingC')


PROPS = {
    'smokestack': smokestack,
    'crane': crane,
    'warehouse': warehouse,
    'water_tower': water_tower,
    'container': container,
    'building_a': building_a,
    'building_b': building_b,
    'building_c': building_c,
}
