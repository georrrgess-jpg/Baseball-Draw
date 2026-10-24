"""Field-side props plus the baseball and bat.  Blender space: Z up, front
faces -Y, origin at ground centre (baseball: ball centre; bat: knob end)."""
import math
import random

from mathutils import Matrix, Vector

from pcommon import finish, load_font, mb_new
from pmesh import RX, RY, RZ, T, TAU
from props_hero import _bat_geo, _lamp


def _pillow(m, c, size, mat, rot=0.0, seg=10, rings=6, e=0.35, sag=0.0):
    """Smooth superellipsoid 'bag' centred at c with full size (sx, sy, sz)."""
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2

    def sp(v, ex):
        return math.copysign(abs(v) ** ex, v)
    rows = []
    uvs = []
    for i in range(rings + 1):
        t = -math.pi / 2 + math.pi * i / rings
        row = []
        for j in range(seg):
            a = TAU * j / seg
            x = sx * sp(math.cos(t), e) * sp(math.cos(a), e)
            y = sy * sp(math.cos(t), e) * sp(math.sin(a), e)
            z = sz * sp(math.sin(t), 0.8)
            z -= sag * (1 - (x / sx) ** 2) * 0.0
            row.append((x, y, z))
        rows.append(row)
        uvs.append([(j / seg * 1.5, i / rings) for j in range(seg + 1)])
    with m.xf(T(*c) @ RZ(rot)):
        m.grid(rows, mat, uvs=uvs, wrap=True)


# ================================================================= BARRICADE
def barricade():
    m = mb_new()
    L = 2.0
    prof = [(-0.305, 0.0), (0.305, 0.0), (0.305, 0.075), (0.2, 0.33), (0.075, 0.81), (-0.075, 0.81),
            (-0.2, 0.33), (-0.305, 0.075)]
    # side materials per edge: bottom, back lip, back slope, back face, top, front face, front slope, front lip
    sm = ['Concrete', 'Concrete', 'Concrete', 'Concrete', 'Concrete', 'Hazard', 'Concrete', 'Concrete']
    m.prism_x(prof, -L / 2, L / 2, 'Concrete', side_mats=sm)
    # forklift / drainage slots (dark recesses suggested by boxes)
    for x in (-0.55, 0.55):
        m.box((x, -0.306, 0.06), (0.3, 0.01, 0.1), 'Rubber', skip=('+y',))
        m.box((x, 0.306, 0.06), (0.3, 0.01, 0.1), 'Rubber', skip=('-y',))
    # lifting loops
    for x in (-0.6, 0.6):
        pts = [(x - 0.12, 0, 0.8)] + [(x - 0.12 * math.cos(a), 0, 0.8 + 0.1 * math.sin(a))
                                      for a in [math.pi * k / 6 for k in range(1, 6)]] + [(x + 0.12, 0, 0.8)]
        m.tube(pts, 0.012, 'Rust', seg=4)
    # end connector plates
    for x in (-L / 2, L / 2):
        m.box((x, 0.0, 0.45), (0.02, 0.18, 0.5), 'SteelDark')
    finish(m, 'Barricade')


# ================================================================== SANDBAGS
def sandbags():
    m = mb_new()
    rnd = random.Random(7)
    bag = (0.58, 0.32, 0.16)
    layers = [5, 4, 3]
    for li, n in enumerate(layers):
        z = 0.08 + li * 0.135
        for i in range(n):
            x = (i - (n - 1) / 2) * 0.56
            y = rnd.uniform(-0.03, 0.03) + li * 0.03 - 0.16
            _pillow(m, (x, y, z), (bag[0] * rnd.uniform(0.95, 1.05), bag[1] * rnd.uniform(0.95, 1.08), bag[2]),
                    'Sandbag', rot=rnd.uniform(-6, 6), seg=8, rings=5)
    # a back row so it reads as a wall from both sides
    for i in range(4):
        x = (i - 1.5) * 0.56
        _pillow(m, (x, 0.17, 0.08), bag, 'Sandbag', rot=rnd.uniform(-6, 6), seg=8, rings=5)
    finish(m, 'Sandbags')


# ===================================================================== CRATE
def crate():
    m = mb_new()
    s = 1.2
    h = s / 2
    # inner box + plank panels
    m.box((0, 0, h), (s - 0.08, s - 0.08, s - 0.04), 'Wood', skip=('-z',))
    t = 0.12
    # frame edges
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.cbox((sx * (h - t / 2), sy * (h - t / 2), h), (t, t, s), 'Wood', ch=0.012)
    for z in (t / 2, s - t / 2):
        for sy in (-1, 1):
            m.cbox((0, sy * (h - t / 2), z), (s - 2 * t, t, t), 'Wood', ch=0.012)
        for sx in (-1, 1):
            m.cbox((sx * (h - t / 2), 0, z), (t, s - 2 * t, t), 'Wood', ch=0.012)
    # diagonal braces on the four sides
    for ang in (0, 90, 180, 270):
        with m.xf(RZ(ang)):
            m.beam((-h + t, -h + 0.02, t), (h - t, -h + 0.02, s - t), 0.1, 0.04, 'Wood', up=(0, -1, 0))
    # steel corner brackets
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.0, s - 0.16):
                xa, xb = sorted((sx * (h + 0.01), sx * (h - 0.17)))
                ya, yb = sorted((sy * (h + 0.01), sy * (h - 0.17)))
                m.box_mm((xa, ya, z), (xb, yb, z + 0.16), 'SteelDark', skip=('-z',))
    # stencil
    font = load_font('RussoOne-Regular.ttf')
    with m.xf(T(0, -h - 0.003, h + 0.05) @ RX(90)):
        m.text('SY-07', font, 0.2, 'PaintWhite', depth=0.006, resolution=1)
    with m.xf(T(0, -h - 0.003, h - 0.17) @ RX(90)):
        m.box((0, 0, 0.003), (0.5, 0.05, 0.006), 'SteelScarlet')
    finish(m, 'Crate')


# ==================================================================== BARREL
def barrel():
    m = mb_new()
    r = 0.29
    H = 0.88
    prof = [(r - 0.01, 0.0), (r, 0.02), (r, 0.11), (r + 0.012, 0.12), (r + 0.012, 0.14), (r, 0.15),
            (r, 0.29), (r + 0.01, 0.3), (r, 0.31), (r, 0.57), (r + 0.01, 0.58), (r, 0.59),
            (r, 0.73), (r + 0.012, 0.74), (r + 0.012, 0.76), (r, 0.77), (r, H - 0.02), (r - 0.01, H)]
    # body split into material bands: scarlet / hazard band in the middle
    def band(i0, i1, mat):
        m.lathe(prof[i0:i1 + 1], mat, seg=16, uv_scale=1.2)
    band(0, 9, 'SteelScarlet')
    band(9, 11, 'SteelDark')
    band(11, len(prof) - 1, 'SteelScarlet')
    m.cyl((0, 0, 0.36), (0, 0, 0.5), r + 0.003, 'Hazard', seg=16, caps=(False, False), uv_scale=0.8)
    # lid: rim + recessed top + bungs
    m.lathe([(r - 0.01, H), (r - 0.025, H + 0.012), (r - 0.04, H - 0.01), (0.0, H - 0.01)], 'SteelDark', seg=16,
            sharp=(1, 2))
    for (x, y, rr) in ((0.15, 0.05, 0.035), (-0.17, -0.02, 0.025)):
        m.cyl((x, y, H - 0.01), (x, y, H + 0.012), rr, 'SteelGalv', seg=6)
    m.disc((0, 0, 0.0), (0, 0, -1), r - 0.01, 'SteelDark', seg=16)
    finish(m, 'Barrel')


# =============================================================== BALL BUCKET
def _baseball_geo(m, c, r, seg=8, rings=4, rot=0.0):
    with m.xf(T(*c) @ RZ(rot) @ RX(rot * 0.7)):
        m.sphere((0, 0, 0), r, 'Baseball', seg=seg, rings=rings, uv01=True)


def ball_bucket():
    m = mb_new()
    r0, r1, h = 0.145, 0.165, 0.37
    m.lathe([(0.0, 0.0), (r0, 0.0), (r0 + 0.004, 0.015), (r1, h - 0.02), (r1 + 0.012, h - 0.015),
             (r1 + 0.012, h), (r1 - 0.006, h), (r0 - 0.01, 0.03), (0.0, 0.03)], 'SeatNavy', seg=16,
            sharp=(1, 2, 3, 4, 5, 6, 7))
    rr = r0 + (r1 - r0) * (h - 0.06) / h + 0.004
    m.cyl((0, 0, h - 0.06), (0, 0, h - 0.048), rr, 'SeatNavy', seg=16, caps=(False, False))
    m.cyl((0, 0, 0.13), (0, 0, 0.19), r0 + (r1 - r0) * 0.16 / h + 0.003, 'SteelScarlet', seg=16,
          caps=(False, False), uv_scale=0.5)
    # wire handle
    pts = []
    for k in range(13):
        a = math.pi * k / 12
        pts.append(((r1 + 0.01) * math.cos(a), 0.0, h - 0.04 + 0.16 * math.sin(a)))
    m.tube(pts, 0.004, 'SteelGalv', seg=4)
    # heap of balls
    br = 0.0375
    rnd = random.Random(3)
    spots = [(0, 0)] + [(0.075 * math.cos(TAU * k / 6), 0.075 * math.sin(TAU * k / 6)) for k in range(6)] + \
            [(0.135 * math.cos(TAU * (k + 0.5) / 11), 0.135 * math.sin(TAU * (k + 0.5) / 11)) for k in range(11)]
    for (x, y) in spots:
        d = math.hypot(x, y)
        z = h - 0.03 + 0.03 * (1 - d / 0.15)
        _baseball_geo(m, (x, y, z), br, rot=rnd.uniform(0, 360))
    for (x, y) in [(0.03, 0.02), (-0.045, 0.03), (0.0, -0.05), (0.06, -0.04)]:
        _baseball_geo(m, (x, y, h + 0.035), br, rot=rnd.uniform(0, 360))
    finish(m, 'BallBucket')


# ================================================================== BAT RACK
def bat_rack():
    m = mb_new()
    W = 1.4
    for x in (-W / 2, W / 2):
        # side A-frame
        m.beam((x, -0.3, 0.03), (x, 0.0, 1.0), 0.06, 0.06, 'Wood', up=(1, 0, 0))
        m.beam((x, 0.3, 0.03), (x, 0.0, 1.0), 0.06, 0.06, 'Wood', up=(1, 0, 0))
        m.box((x, 0.0, 0.03), (0.08, 0.7, 0.06), 'SteelCharcoal')
    # slotted top bar, lower tray
    m.cbox((0, -0.02, 0.92), (W + 0.12, 0.16, 0.06), 'Wood', ch=0.01)
    m.cbox((0, -0.12, 0.12), (W, 0.24, 0.04), 'Wood', ch=0.008)
    m.box((0, -0.24, 0.17), (W, 0.02, 0.1), 'SteelScarlet')
    m.box((0, -0.105, 0.95), (W + 0.12, 0.012, 0.03), 'SteelScarlet', skip=('+y',))
    n = 8
    for k in range(n):
        x = -W / 2 + 0.12 + k * (W - 0.24) / (n - 1)
        lean = ((k * 7) % 5 - 2) * 1.2
        with m.xf(T(x, -0.12, 0.14) @ RX(-8) @ RY(lean) @ RY(180) @ T(0, 0, -0.86)):
            _bat_geo(m, seg=6, length=0.86, simple=False, grip=k % 2 == 0)
    finish(m, 'BatRack')


# ============================================================= SPEAKER STACK
def speaker_stack():
    m = mb_new()
    # road-case cart
    m.cbox((0, 0, 0.18), (1.3, 0.85, 0.16), 'SteelCharcoal', ch=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.cyl((sx * 0.5, sy * 0.3, 0.1), (sx * 0.5, sy * 0.3, 0.0), 0.06, 'Rubber', seg=8)
            m.box((sx * 0.5, sy * 0.3, 0.07), (0.06, 0.1, 0.06), 'SteelDark')

    def cab(cx, cz, w, d, hh, woofers):
        m.cbox((cx, 0, cz + hh / 2), (w, d, hh), 'SteelNavy', ch=0.03)
        m.box((cx, -d / 2 - 0.005, cz + hh / 2), (w - 0.08, 0.01, hh - 0.08), 'SpeakerGrille', skip=('+y',))
        for (wx, wz, wr) in woofers:
            m.cyl((cx + wx, -d / 2 - 0.0, cz + wz), (cx + wx, -d / 2 - 0.03, cz + wz), wr, 'SteelCharcoal',
                  r1=wr * 0.92, seg=14, caps=(False, False))
            m.cyl((cx + wx, -d / 2 + 0.02, cz + wz), (cx + wx, -d / 2 - 0.012, cz + wz), wr * 0.92, 'Rubber',
                  r1=wr * 0.2, seg=14, caps=(False, False))
        # scarlet corner protectors
        for sx in (-1, 1):
            for sz in (0, 1):
                m.box((cx + sx * (w / 2 - 0.03), -d / 2 + 0.03, cz + 0.03 + sz * (hh - 0.06)), (0.08, 0.08, 0.08),
                      'SteelScarlet')
        # handles
        for sx in (-1, 1):
            m.box((cx + sx * (w / 2 + 0.01), 0, cz + hh * 0.7), (0.02, 0.2, 0.05), 'SteelDark')
    cab(0.0, 0.26, 1.2, 0.75, 0.7, [(-0.28, 0.35, 0.24), (0.28, 0.35, 0.24)])
    cab(-0.3, 0.96, 0.58, 0.55, 0.85, [(0.0, 0.25, 0.16)])
    cab(0.3, 0.96, 0.58, 0.55, 0.85, [(0.0, 0.25, 0.16)])
    # horns
    for x in (-0.3, 0.3):
        m.hull([(x - 0.2, -0.28, 1.6), (x + 0.2, -0.28, 1.6), (x + 0.2, -0.28, 1.74), (x - 0.2, -0.28, 1.74),
                (x - 0.05, -0.2, 1.65), (x + 0.05, -0.2, 1.65), (x + 0.05, -0.2, 1.69), (x - 0.05, -0.2, 1.69)],
               'Rubber')
    # cables
    m.tube([(0.45, 0.3, 1.0), (0.6, 0.45, 0.7), (0.62, 0.5, 0.3), (0.7, 0.6, 0.02), (1.1, 0.7, 0.02)], 0.015,
           'Rubber', seg=4)
    finish(m, 'SpeakerStack')


# ========================================================== SMALL FLOODLIGHT
def floodlight_small():
    m = mb_new()
    H = 3.0
    # tripod
    for k in range(3):
        a = TAU * k / 3 + math.pi / 2
        m.strut((0, 0, 1.0), (0.8 * math.cos(a), 0.8 * math.sin(a), 0.03), 0.022, 'SteelGalv', sides=4)
        m.box((0.8 * math.cos(a), 0.8 * math.sin(a), 0.015), (0.1, 0.1, 0.03), 'Rubber')
    m.cyl((0, 0, 0.6), (0, 0, 1.2), 0.045, 'Hazard', seg=8, caps=(True, False), uv_scale=0.5)
    m.cyl((0, 0, 1.2), (0, 0, H), 0.032, 'SteelGalv', seg=8)
    # T-bar with two heads aimed forward and down
    m.cyl((-0.55, 0, H), (0.55, 0, H), 0.03, 'SteelCharcoal', seg=6)
    for x in (-0.4, 0.4):
        m.box((x, 0, H + 0.08), (0.04, 0.04, 0.16), 'SteelCharcoal')
        with m.xf(T(x, -0.05, H + 0.25) @ RX(20)):
            m.cbox((0, 0.04, 0), (0.42, 0.18, 0.32), 'SteelCharcoal', ch=0.02)
            m.box((0, -0.06, 0), (0.36, 0.02, 0.26), 'LampEmissive', skip=('+y',),
                  uvs={'-y': [(0, 0), (1, 0), (1, 1), (0, 1)]})
            m.poly([(-0.21, -0.06, 0.16), (0.21, -0.06, 0.16), (0.21, -0.2, 0.13), (-0.21, -0.2, 0.13)],
                   'SteelCharcoal')
            m.poly([(0.21, -0.06, 0.16), (-0.21, -0.06, 0.16), (-0.21, -0.2, 0.13), (0.21, -0.2, 0.13)],
                   'SteelCharcoal')
    # ballast box / generator + cable
    m.cbox((0.9, 0.6, 0.25), (0.6, 0.4, 0.5), 'SteelScarlet', ch=0.03, skip_down=True)
    m.box((0.9, 0.39, 0.25), (0.5, 0.02, 0.12), 'Hazard', skip=('+y',))
    m.tube([(0.03, 0.03, 1.2), (0.15, 0.2, 0.5), (0.3, 0.4, 0.05), (0.6, 0.55, 0.03), (0.75, 0.55, 0.2)], 0.012,
           'Rubber', seg=4)
    finish(m, 'FloodlightSmall')


# ============================================================== CHAIN FENCE
def fence_chain():
    m = mb_new()
    L, H = 4.0, 2.4
    for x in (-L / 2, L / 2):
        m.cyl((x, 0, 0.0), (x, 0, H + 0.05), 0.045, 'SteelGalv', seg=8, caps=(False, True))
        m.cbox((x, 0, 0.1), (0.25, 0.25, 0.2), 'Concrete', ch=0.03, skip_down=True)
        # barbed-wire arm leaning outward (+Y)
        m.strut((x, 0, H), (x, 0.4, H + 0.4), 0.018, 'SteelGalv', sides=4)
    m.cyl((-L / 2, 0, H - 0.02), (L / 2, 0, H - 0.02), 0.025, 'SteelGalv', seg=6, caps=(False, False))
    m.cyl((-L / 2, 0, 1.2), (L / 2, 0, 1.2), 0.016, 'SteelGalv', seg=4, caps=(False, False))
    m.strut((-L / 2, 0, 0.06), (L / 2, 0, 0.06), 0.006, 'SteelGalv', sides=3)
    for f in (0.33, 0.66, 1.0):
        m.strut((-L / 2, 0.4 * f, H + 0.4 * f), (L / 2, 0.4 * f, H + 0.4 * f), 0.005, 'SteelDark', sides=3)
    # chain-link mesh: one double-sided alpha-masked quad
    m.poly([(-L / 2 + 0.04, 0.0, 0.05), (L / 2 - 0.04, 0.0, 0.05), (L / 2 - 0.04, 0.0, H - 0.03),
            (-L / 2 + 0.04, 0.0, H - 0.03)], 'ChainLink')
    finish(m, 'FenceChain')


# ================================================================== BASEBALL
def baseball():
    m = mb_new()
    # 0.075 m diameter, origin at the ball centre (projectile pivot)
    with m.xf(RX(90)):
        m.sphere((0, 0, 0), 0.0375, 'Baseball', seg=24, rings=16, uv01=True)
    finish(m, 'Baseball')


def bat():
    m = mb_new()
    _bat_geo(m, seg=16, length=0.85)
    finish(m, 'Bat')


PROPS = {
    'barricade': barricade,
    'sandbags': sandbags,
    'crate': crate,
    'barrel': barrel,
    'ball_bucket': ball_bucket,
    'bat_rack': bat_rack,
    'speaker_stack': speaker_stack,
    'floodlight_small': floodlight_small,
    'fence_chain': fence_chain,
    'baseball': baseball,
    'bat': bat,
}
