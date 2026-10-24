"""Hero stadium props: light tower, gate, scoreboard, walls, bastion,
grandstand, dugout, banner pole.  Blender space: Z up, front (field side)
faces -Y, origin at ground centre, metres."""
import math

from mathutils import Matrix, Vector

from pcommon import empty, finish, load_font, mb_new
from pmesh import RX, RZ, T, mat_at, vec


def _railing(m, pts, h=1.1, post_every=1.0, mat='SteelScarlet', r=0.03, toe='Hazard', closed=False,
             skip_posts=()):
    """Guard rail along a polyline: posts, top + mid rails, optional toe board."""
    P = [vec(p) for p in pts]
    if closed:
        P.append(P[0].copy())
    nseg = len(P) - 1
    for si, (a, b) in enumerate(zip(P[:-1], P[1:])):
        d = b - a
        n = max(1, int(round(d.length / post_every)))
        for i in range(n + 1):
            if i == n and (si < nseg - 1 or closed):
                continue
            p = a + d * (i / n)
            if any((p - vec(s)).length < 0.05 for s in skip_posts):
                continue
            m.strut(p, p + Vector((0, 0, h)), r * 1.2, mat, sides=4)
        for zz in (h, h * 0.5):
            m.cyl(a + Vector((0, 0, zz)), b + Vector((0, 0, zz)), r, mat, seg=6, caps=(False, False))
        if toe:
            nrm = Vector((-d.y, d.x, 0)).normalized() * 0.01
            m.poly([a + nrm, b + nrm, b + nrm + Vector((0, 0, 0.15)), a + nrm + Vector((0, 0, 0.15))], toe)
            m.poly([b - nrm, a - nrm, a - nrm + Vector((0, 0, 0.15)), b - nrm + Vector((0, 0, 0.15))], toe)


def _ladder(m, bottom, top, width=0.45, rung=0.3, mat='SteelGalv', out=Vector((0, 1, 0)), cage_from=None):
    """Ladder between two centre points; `out` = direction away from the wall."""
    b, t = vec(bottom), vec(top)
    d = t - b
    side = d.cross(out).normalized() * (width / 2)
    for s in (-1, 1):
        m.beam(b + side * s, t + side * s, 0.05, 0.03, mat)
    n = int(d.length / rung)
    for i in range(1, n + 1):
        p = b + d * (i / (n + 1))
        m.strut(p - side, p + side, 0.016, mat, sides=4)
    if cage_from is not None:
        zc = cage_from
        rr = width / 2 + 0.2
        hoops = []
        L = d.length
        k = 0
        while True:
            f = (zc - b.z) / d.z if d.z else 0
            if f > 0.97:
                break
            c = b + d * f
            arc = []
            for j in range(7):
                a = math.pi * j / 6
                arc.append(c + side.normalized() * (-math.cos(a) * rr) + out * (0.05 + math.sin(a) * rr * 1.25))
            m.tube(arc, 0.02, mat, seg=3)
            hoops.append(arc)
            zc += 1.0
            k += 1
            if k > 40 or L <= 0:
                break
        if len(hoops) > 1:
            for j in (0, 3, 6):
                m.strut(hoops[0][j], hoops[-1][j], 0.015, mat, sides=3)


def _lamp(m, c, rad=0.3, depth=0.36, lens='LampEmissive', body='SteelCharcoal', visor=True):
    """Stadium lamp at local point c facing local -Y."""
    cx, cy, cz = c
    m.cyl((cx, cy + depth * 0.6, cz), (cx, cy - depth * 0.4, cz), rad * 0.78, body, r1=rad, seg=12,
          caps=(True, False), rot0=15, up_hint=(0, 0, 1))
    # rim ring + lens
    m.cyl((cx, cy - depth * 0.4, cz), (cx, cy - depth * 0.45, cz), rad, body, r1=rad * 0.92, seg=12,
          caps=(False, False), rot0=15, up_hint=(0, 0, 1))
    m.disc((cx, cy - depth * 0.43, cz), (0, -1, 0), rad * 0.9, lens, seg=12, rot0=15)
    if visor:
        m.poly([(cx - rad, cy - depth * 0.42, cz + rad * 1.02), (cx + rad, cy - depth * 0.42, cz + rad * 1.02),
                (cx + rad, cy - depth * 0.95, cz + rad * 0.86), (cx - rad, cy - depth * 0.95, cz + rad * 0.86)], body)
        m.poly([(cx + rad, cy - depth * 0.42, cz + rad * 1.0), (cx - rad, cy - depth * 0.42, cz + rad * 1.0),
                (cx - rad, cy - depth * 0.95, cz + rad * 0.84), (cx + rad, cy - depth * 0.95, cz + rad * 0.84)], body)


# =============================================================== LIGHT TOWER
def light_tower():
    m = mb_new()
    H = 20.0
    z0 = 0.5
    b0, b1 = 1.6, 0.75

    def hw(z):
        return b0 + (b1 - b0) * (z - z0) / (H - z0)

    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    # footings + base plates
    for sx, sy in corners:
        m.cbox((sx * b0, sy * b0, 0.25), (0.95, 0.95, 0.5), 'Concrete', ch=0.07, skip_down=True)
        m.box((sx * b0, sy * b0, 0.52), (0.55, 0.55, 0.05), 'SteelCharcoal', skip=('-z',))
        for ax, ay in corners:
            m.rivet((sx * b0 + ax * 0.2, sy * b0 + ay * 0.2, 0.545), (0, 0, 1), 'SteelGalv', r=0.04, h=0.05)
        # hazard collar on each leg foot
        m.box((sx * b0, sy * b0, 0.9), (0.34, 0.34, 0.7), 'Hazard', skip=('-z', '+z'))
    # legs
    for sx, sy in corners:
        m.beam((sx * b0, sy * b0, z0), (sx * b1, sy * b1, H), 0.24, 0.24, 'SteelNavy')
    # lattice
    levels = 8
    zs = [z0 + (H - z0) * k / levels for k in range(levels + 1)]
    for k in range(levels + 1):
        z = zs[k]
        w = hw(z)
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            pa = (a[0] * w, a[1] * w, z)
            pb = (b[0] * w, b[1] * w, z)
            if k > 0:
                m.beam(pa, pb, 0.12, 0.12, 'SteelNavy')
            if k < levels:
                z2 = zs[k + 1]
                w2 = hw(z2)
                qa = (a[0] * w2, a[1] * w2, z2)
                qb = (b[0] * w2, b[1] * w2, z2)
                m.strut(pa, qb, 0.045, 'SteelGalv', sides=4)
                m.strut(pb, qa, 0.045, 'SteelGalv', sides=4)
        # gusset plates at leg joints
        if 0 < k < levels:
            for sx, sy in corners:
                m.box((sx * w, sy * w, z), (0.36, 0.36, 0.3), 'SteelScarlet' if k == levels - 1 else 'SteelNavy')
    # electrical cabinet + conduit
    m.cbox((1.0, -1.9, 0.75), (0.9, 0.45, 1.5), 'SteelCharcoal', ch=0.05, skip_down=True)
    m.box((1.0, -2.13, 0.75), (0.7, 0.02, 0.18), 'Hazard', skip=('+y',))
    m.cyl((1.25, -1.75, 1.5), (1.25, -1.75, 2.4), 0.05, 'SteelGalv', seg=6)
    m.cyl((1.25, -1.75, 2.4), (b0 - 0.1, -b0 + 0.12, 2.6), 0.05, 'SteelGalv', seg=6)
    m.cyl((b0 - 0.1, -b0 + 0.12, 2.6), (b1 - 0.02, -b1 + 0.15, H - 0.2), 0.05, 'SteelGalv', seg=6, caps=(False, True))
    # ladder on the back face (+Y)
    lb = Vector((0, hw(0.2) + 0.32, 0.2))
    lt = Vector((0, hw(H) + 0.32, H + 1.15))
    _ladder(m, lb, lt, out=Vector((0, 1, 0)), cage_from=2.6)
    # platform
    m.box_mm((-2.5, -2.0, H - 0.15), (2.5, 0.75, H), 'SteelGalv')
    m.box_mm((-2.5, 0.75, H - 0.15), (-0.42, 1.3, H), 'SteelGalv')
    m.box_mm((0.42, 0.75, H - 0.15), (2.5, 1.3, H), 'SteelGalv')
    for x in (-2.5, 2.5):
        m.box_mm((x - 0.08, -2.0, H - 0.4), (x + 0.08, 1.3, H - 0.15), 'SteelCharcoal', skip=('+z',))
    m.box_mm((-2.5, -2.08, H - 0.4), (2.5, -2.0, H - 0.0), 'SteelScarlet')
    for sx in (-1, 1):
        m.strut((sx * hw(H - 2.6), -hw(H - 2.6), H - 2.6), (sx * 2.3, -1.9, H - 0.3), 0.05, 'SteelNavy')
        m.strut((sx * hw(H - 2.6), hw(H - 2.6), H - 2.6), (sx * 2.3, 1.2, H - 0.3), 0.05, 'SteelNavy')
    gate = [(-0.3, 1.3, H), (0.3, 1.3, H)]
    _railing(m, [(-0.3, 1.3, H), (-2.45, 1.3, H), (-2.45, -1.95, H), (2.45, -1.95, H), (2.45, 1.3, H), (0.3, 1.3, H)],
             post_every=1.1, skip_posts=gate)
    # lamp bank (tilted down towards the field)
    tilt = 24.0
    bank = T(0, -0.55, H + 2.65) @ RX(tilt)
    cols, rows, sp = 6, 4, 0.82
    with m.xf(bank):
        m.cbox((0, 0.3, 0), (cols * sp + 0.3, 0.1, rows * sp + 0.3), 'SteelCharcoal', ch=0.03)
        hx = cols * sp / 2 + 0.1
        hz = rows * sp / 2 + 0.1
        for z in (-hz, hz):
            m.beam((-hx, 0.2, z), (hx, 0.2, z), 0.14, 0.14, 'SteelScarlet', up=(0, 1, 0))
        for x in (-hx, hx):
            m.beam((x, 0.2, -hz), (x, 0.2, hz), 0.14, 0.14, 'SteelScarlet', up=(0, 1, 0))
        for r in range(rows):
            z = (r - (rows - 1) / 2) * sp
            m.cyl((-hx, 0.18, z), (hx, 0.18, z), 0.045, 'SteelGalv', seg=6, caps=(False, False))
            for c in range(cols):
                x = (c - (cols - 1) / 2) * sp
                _lamp(m, (x, 0.0, z), rad=0.3, depth=0.36)
        # aviation light + rod
        m.cyl((0, 0.3, hz + 0.08), (0, 0.3, hz + 0.25), 0.07, 'SteelCharcoal', seg=8)
        m.sphere((0, 0.3, hz + 0.3), 0.09, 'RedAviation', seg=8, rings=4)
        m.strut((1.6, 0.3, hz), (1.6, 0.3, hz + 1.4), 0.02, 'SteelGalv', sides=4)
    # bank supports from the platform deck
    bm = bank
    for sx in (-1, 1):
        lo = bm @ Vector((sx * hx, 0.3, -hz))
        hi = bm @ Vector((sx * hx, 0.3, hz))
        foot = Vector((sx * hx, lo.y + 0.2, H))
        m.beam(foot, lo, 0.16, 0.16, 'SteelNavy')
        foot2 = Vector((sx * hx, hi.y + 0.15, H))
        m.beam(foot2, hi, 0.16, 0.16, 'SteelNavy')
        m.strut(foot, hi, 0.05, 'SteelGalv')
    finish(m, 'LightTower')
    anchor = bank @ Vector((0, -0.16, 0))
    ae = empty('LightAnchor', tuple(anchor), size=0.8)
    return ae


# ====================================================================== GATE
def _door_leaf(m, w, h, t):
    """Door leaf in hinge-local coords: spans x 0..w, y 0..t (front at y=0), z 0..h."""
    rim = 0.2
    # core plate
    m.box_mm((0.02, 0.06, 0.03), (w, t - 0.04, h), 'SteelNavy')
    # perimeter frame (front + back proud)
    for (lo, hi) in (((0.0, 0.0, 0.03), (rim, t, h)), ((w - rim, 0.0, 0.03), (w, t, h)),
                     ((rim, 0.0, h - rim), (w - rim, t, h)), ((rim, 0.0, 0.03), (w - rim, t, 0.03 + rim))):
        m.cbox_mm(lo, hi, 'SteelCharcoal', ch=0.025)
    # horizontal ribs
    for z in (h * 0.36, h * 0.66):
        m.cbox_mm((rim, 0.01, z - 0.09), (w - rim, 0.07, z + 0.09), 'SteelCharcoal', ch=0.02)
    # diagonal brace (front)
    a = Vector((rim + 0.05, 0.03, 0.03 + rim + 0.05))
    b = Vector((w - rim - 0.05, 0.03, h * 0.36 - 0.12))
    m.beam(a, b, 0.2, 0.08, 'SteelScarlet', up=(0, -1, 0))
    a = Vector((rim + 0.05, 0.03, h * 0.66 + 0.12))
    b = Vector((w - rim - 0.05, 0.03, h - rim - 0.05))
    m.beam(a, b, 0.2, 0.08, 'SteelScarlet', up=(0, -1, 0))
    # hazard kick band
    m.box_mm((rim, 0.0, 0.03 + rim), (w - rim, 0.06, 0.03 + rim + 0.45), 'Hazard', skip=('+y',))
    # back side (outside the stadium): ribs + brace
    for z in (h * 0.36, h * 0.66):
        m.box_mm((rim, t - 0.06, z - 0.08), (w - rim, t - 0.01, z + 0.08), 'SteelCharcoal', skip=('-y',))
    m.beam((rim + 0.05, t - 0.03, 0.03 + rim + 0.05), (w - rim - 0.05, t - 0.03, h - rim - 0.05), 0.18, 0.06,
           'SteelCharcoal', up=(0, 1, 0))
    # rivets on the front rim
    n = 10
    for i in range(n):
        z = 0.15 + (h - 0.3) * i / (n - 1)
        m.rivet((rim / 2, -0.0, z), (0, -1, 0), 'SteelGalv', r=0.035, h=0.03)
        m.rivet((w - rim / 2, -0.0, z), (0, -1, 0), 'SteelGalv', r=0.035, h=0.03)
    for i in range(1, 6):
        x = rim + (w - 2 * rim) * i / 6
        m.rivet((x, 0.0, h - rim / 2), (0, -1, 0), 'SteelGalv', r=0.035, h=0.03)
        m.rivet((x, 0.0, 0.03 + rim / 2), (0, -1, 0), 'SteelGalv', r=0.035, h=0.03)
    # hinge knuckles at the outer edge (x=0)
    for z in (0.5, h / 2, h - 0.5):
        m.cyl((0.0, 0.0, z - 0.25), (0.0, 0.0, z + 0.25), 0.075, 'SteelGalv', seg=8)
    # vision slot / lock box on the meeting edge
    m.cbox_mm((w - 0.5, -0.05, h * 0.5 - 0.25), (w - 0.05, 0.02, h * 0.5 + 0.25), 'SteelGalv', ch=0.02)


def gate(label='GATE'):
    W, Hd = 8.0, 6.0             # outer width, frame height
    ow, oh = 6.0, 4.9            # opening
    depth = 1.6
    m = mb_new()
    fy0, fy1 = -depth / 2, depth / 2
    for s in (-1, 1):
        x_in, x_out = s * ow / 2, s * W / 2
        lo_x, hi_x = min(x_in, x_out), max(x_in, x_out)
        # plinth
        m.cbox_mm((lo_x - 0.15, fy0 - 0.15, 0.0), (hi_x + 0.15, fy1 + 0.15, 0.45), 'ConcreteDark', ch=0.06,
                  skip_down=True)
        # concrete core
        m.cbox_mm((lo_x + 0.05, fy0 + 0.1, 0.45), (hi_x - 0.05, fy1 - 0.05, Hd), 'Concrete', ch=0.05)
        # steel cladding (front)
        m.cbox_mm((lo_x, fy0, 0.45), (hi_x, fy0 + 0.14, Hd - 1.1), 'SteelCharcoal', ch=0.04)
        # hazard strip along the opening edge
        hx = x_in + (-s) * 0.0
        m.box_mm((min(hx, hx + s * 0.28), fy0 - 0.02, 0.5), (max(hx, hx + s * 0.28), fy0 + 0.02, Hd - 1.15),
                 'Hazard', skip=('+y',))
        # side cladding toward the field + rivet columns
        for i in range(9):
            z = 0.7 + i * (Hd - 1.9) / 8
            m.rivet((x_out - s * 0.12, fy0, z), (0, -1, 0), 'SteelGalv', r=0.04, h=0.035)
            m.rivet((x_in + s * 0.38, fy0, z), (0, -1, 0), 'SteelGalv', r=0.04, h=0.035)
        # rear buttress (outside the stadium, +Y)
        m.prism_x([(fy1 - 0.05, 0.45), (fy1 + 1.4, 0.45), (fy1 + 0.2, 4.2), (fy1 - 0.05, 4.2)],
                  (lo_x + hi_x) / 2 - 0.3, (lo_x + hi_x) / 2 + 0.3, 'SteelNavy')
        # outer side buttress
        m.prism_y([(x_out, 0.45), (x_out + s * 0.9, 0.45), (x_out + s * 0.0, 3.6)] if s > 0 else
                  [(x_out, 0.45), (x_out, 3.6), (x_out + s * 0.9, 0.45)], -0.35, 0.35, 'SteelNavy')
        # cap
        m.cbox_mm((lo_x - 0.1, fy0 - 0.1, Hd), (hi_x + 0.1, fy1 + 0.1, Hd + 0.25), 'SteelScarlet', ch=0.05)
        # amber warning lamp on each pillar cap
        cx = (lo_x + hi_x) / 2
        m.cyl((cx, fy0 + 0.3, Hd + 0.25), (cx, fy0 + 0.3, Hd + 0.35), 0.14, 'SteelCharcoal', seg=8)
        m.dome((cx, fy0 + 0.3, Hd + 0.35), 0.12, 'AmberEmissive', seg=8, rings=3, h=0.16)
        # cap spikes
        for kx in (-0.3, 0.3):
            for ky in (-0.5, 0.5):
                px, py = cx + kx, ky
                m.hull([(px - 0.07, py - 0.07, Hd + 0.25), (px + 0.07, py - 0.07, Hd + 0.25),
                        (px + 0.07, py + 0.07, Hd + 0.25), (px - 0.07, py + 0.07, Hd + 0.25),
                        (px, py, Hd + 0.55)], 'SteelGalv')
    # header beam across the top of the opening
    m.cbox_mm((-W / 2 + 0.95, fy0 - 0.08, oh), (W / 2 - 0.95, fy1 - 0.1, Hd), 'SteelNavy', ch=0.06)
    # header face plate + stencil
    m.box_mm((-3.05, fy0 - 0.16, oh + 0.12), (3.05, fy0 - 0.08, Hd - 0.1), 'SteelCharcoal', skip=('+y',))
    m.box_mm((-3.05, fy0 - 0.12, oh - 0.02), (3.05, fy0 + 0.1, oh + 0.14), 'Hazard', skip=('+y',))
    for i in range(14):
        x = -2.9 + 5.8 * i / 13
        m.rivet((x, fy0 - 0.16, Hd - 0.2), (0, -1, 0), 'SteelGalv', r=0.04, h=0.035)
    # stencil lettering is its own node (`Stencil`) so the game can hide it and
    # put a Label3D there for other gate letters
    font = load_font('RussoOne-Regular.ttf')
    st = mb_new()
    with st.xf(RX(90)):
        st.text(label, font, 0.62, 'PaintWhite', depth=0.03)
    # header top: scarlet coping + a row of spikes along the back edge
    m.box_mm((-3.05, fy0 - 0.18, Hd - 0.12), (3.05, fy1 - 0.1, Hd + 0.06), 'SteelScarlet', skip=('-z',))
    for i in range(9):
        x = -2.8 + 5.6 * i / 8
        if abs(x) < 0.5:
            continue
        py = 0.35
        m.hull([(x - 0.08, py - 0.08, Hd + 0.06), (x + 0.08, py - 0.08, Hd + 0.06), (x + 0.08, py + 0.08, Hd + 0.06),
                (x - 0.08, py + 0.08, Hd + 0.06), (x, py, Hd + 0.4)], 'SteelGalv')
    # two small spotlights on the header aimed down at the field
    for x in (-1.6, 1.6):
        m.box((x, fy0 + 0.1, Hd + 0.12), (0.12, 0.12, 0.12), 'SteelCharcoal')
        with m.xf(T(x, fy0 + 0.05, Hd + 0.35) @ RX(-35)):
            _lamp(m, (0, 0, 0), rad=0.16, depth=0.3, visor=False)
    # rear frame stop + threshold
    m.box_mm((-ow / 2, -0.25, 0.0), (ow / 2, 0.15, 0.06), 'SteelGalv', skip=('-z',))
    m.box_mm((-ow / 2, fy0 - 0.25, 0.0), (ow / 2, -0.25, 0.03), 'Hazard', skip=('-z',))
    finish(m, 'GateFrame')
    finish(st, 'Stencil', loc=(0.0, fy0 - 0.16, oh + 0.62))

    # doors: DoorL at -X (hinge x=-3), DoorR at +X; hinge line at y=-0.55
    hinge_y = -0.55
    w, h, t = ow / 2 - 0.02, oh - 0.03, 0.26
    dl = mb_new()
    _door_leaf(dl, w, h, t)
    finish(dl, 'DoorL', loc=(-ow / 2, hinge_y, 0.0))
    dr = mb_new()
    with dr.mirrored('x'):
        _door_leaf(dr, w, h, t)
    finish(dr, 'DoorR', loc=(ow / 2, hinge_y, 0.0))

    # rotating warning beacon (origin at its base, on top of the header)
    b = mb_new()
    b.cyl((0, 0, 0), (0, 0, 0.14), 0.26, 'SteelCharcoal', r1=0.24, seg=12, caps=(False, True))
    b.lathe([(0.2, 0.14), (0.205, 0.3), (0.17, 0.42), (0.09, 0.49), (0.0, 0.51)], 'BeaconEmissive', seg=12)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        p0 = (0.23 * math.cos(a), 0.23 * math.sin(a), 0.14)
        p1 = (0.2 * math.cos(a), 0.2 * math.sin(a), 0.46)
        b.strut(p0, p1, 0.015, 'SteelCharcoal', sides=4)
        b.strut(p1, (0, 0, 0.55), 0.015, 'SteelCharcoal', sides=4)
    b.tube([(0.23 * math.cos(TAU_ * i / 10), 0.23 * math.sin(TAU_ * i / 10), 0.3) for i in range(10)], 0.012,
           'SteelCharcoal', seg=3, closed=True)
    finish(b, 'Beacon', loc=(0.0, 0.0, Hd))


TAU_ = math.tau


# ================================================================ SCOREBOARD
def scoreboard():
    m = mb_new()
    W, Hb = 16.0, 8.0
    zb = 6.0
    d0, d1 = -0.6, 0.6
    # legs: I-beam columns
    def ibeam(x, y, z0, z1, mat='SteelNavy'):
        f, wb, tf, tw = 0.5, 0.5, 0.06, 0.05
        prof = [(-f / 2, -wb / 2), (f / 2, -wb / 2), (f / 2, -wb / 2 + tf), (tw / 2, -wb / 2 + tf),
                (tw / 2, wb / 2 - tf), (f / 2, wb / 2 - tf), (f / 2, wb / 2), (-f / 2, wb / 2),
                (-f / 2, wb / 2 - tf), (-tw / 2, wb / 2 - tf), (-tw / 2, -wb / 2 + tf), (-f / 2, -wb / 2 + tf)]
        prof = [(px + x, py + y) for px, py in prof]
        m.prism(prof, z0, z1, mat)
    for x in (-5.0, 5.0):
        m.cbox((x, 0.9, 0.3), (1.6, 1.6, 0.6), 'Concrete', ch=0.08, skip_down=True)
        m.box((x, 0.9, 0.95), (0.62, 0.62, 0.7), 'Hazard', skip=('-z', '+z'))
        ibeam(x, 0.9, 0.6, zb + Hb - 0.6)
        # knee braces into the board
        m.beam((x, 0.9, zb - 1.8), (x - 1.6, 0.75, zb), 0.16, 0.16, 'SteelNavy')
        m.beam((x, 0.9, zb - 1.8), (x + 1.6, 0.75, zb), 0.16, 0.16, 'SteelNavy')
    # X bracing between the legs
    for (a, b) in (((-5.0, 1.2), (5.0, zb - 2.4)), ((5.0, 1.2), (-5.0, zb - 2.4))):
        m.strut((a[0], 0.9, a[1]), (b[0], 0.9, b[1]), 0.06, 'SteelGalv', sides=4)
    m.beam((-5.0, 0.9, zb - 2.4), (5.0, 0.9, zb - 2.4), 0.2, 0.3, 'SteelNavy')
    # ladder up the right leg
    _ladder(m, (5.6, 0.9, 0.6), (5.6, 0.9, zb - 0.1), out=Vector((1, 0, 0)), cage_from=2.6)
    # board body
    fw = 0.8
    m.box_mm((-W / 2 + 0.1, -0.28, zb + 0.1), (W / 2 - 0.1, d1, zb + Hb - 0.1), 'SteelCharcoal', skip=('-y',))
    for lo, hi in (((-W / 2, d0, zb), (W / 2, d1, zb + fw)), ((-W / 2, d0, zb + Hb - fw), (W / 2, d1, zb + Hb)),
                   ((-W / 2, d0, zb + fw), (-W / 2 + fw, d1, zb + Hb - fw)),
                   ((W / 2 - fw, d0, zb + fw), (W / 2, d1, zb + Hb - fw))):
        m.cbox_mm(lo, hi, 'SteelNavy', ch=0.08)
    # inner bevel trim (scarlet) around the display
    t = 0.08
    for lo, hi in (((-W / 2 + fw, d0 + 0.05, zb + fw - t), (W / 2 - fw, -0.28, zb + fw)),
                   ((-W / 2 + fw, d0 + 0.05, zb + Hb - fw), (W / 2 - fw, -0.28, zb + Hb - fw + t)),
                   ((-W / 2 + fw - t, d0 + 0.05, zb + fw - t), (-W / 2 + fw, -0.28, zb + Hb - fw + t)),
                   ((W / 2 - fw, d0 + 0.05, zb + fw - t), (W / 2 - fw + t, -0.28, zb + Hb - fw + t))):
        m.box_mm(lo, hi, 'SteelScarlet')
    # marquee bulbs on the frame front
    def bulb(x, z):
        m.dome((x, d0 - 0.0, z), 0.07, 'MarqueeBulb', seg=6, rings=2, normal=(0, -1, 0))
    n = 30
    for i in range(n + 1):
        x = -W / 2 + 0.4 + (W - 0.8) * i / n
        bulb(x, zb + 0.4)
        bulb(x, zb + Hb - 0.4)
    nz = 13
    for i in range(1, nz):
        z = zb + 0.4 + (Hb - 0.8) * i / nz
        bulb(-W / 2 + 0.4, z)
        bulb(W / 2 - 0.4, z)
    # back stiffeners + rivets
    for x in (-6.0, -2.0, 2.0, 6.0):
        m.box_mm((x - 0.12, d1, zb + 0.2), (x + 0.12, d1 + 0.25, zb + Hb - 0.2), 'SteelNavy', skip=('-y',))
    for z in (zb + 2.2, zb + 5.6):
        m.box_mm((-W / 2 + 0.3, d1, z - 0.1), (W / 2 - 0.3, d1 + 0.2, z + 0.1), 'SteelNavy', skip=('-y',))
    # catwalk under the board front
    m.box_mm((-W / 2 + 0.2, d0 - 1.1, zb - 0.12), (W / 2 - 0.2, d0, zb), 'SteelGalv')
    for x in (-6.0, 0.0, 6.0):
        m.strut((x, d0 - 1.0, zb - 0.1), (x, 0.0, zb - 1.0), 0.05, 'SteelNavy')
    _railing(m, [(-W / 2 + 0.25, d0, zb), (-W / 2 + 0.25, d0 - 1.05, zb), (W / 2 - 0.25, d0 - 1.05, zb),
                 (W / 2 - 0.25, d0, zb)], h=1.0, post_every=1.6, mat='SteelScarlet')
    # header sign
    m.cbox_mm((-4.8, -0.35, zb + Hb), (4.8, 0.35, zb + Hb + 1.5), 'SteelScarlet', ch=0.08)
    m.box_mm((-4.6, -0.39, zb + Hb + 0.12), (4.6, -0.35, zb + Hb + 0.2), 'SteelCharcoal', skip=('+y',))
    m.box_mm((-4.6, -0.39, zb + Hb + 1.3), (4.6, -0.35, zb + Hb + 1.38), 'SteelCharcoal', skip=('+y',))
    font = load_font('RussoOne-Regular.ttf')
    with m.xf(T(0, -0.39, zb + Hb + 0.75) @ RX(90)):
        m.text('STEEL YARD', font, 0.95, 'PaintWhite', depth=0.04)
    for x in (-3.5, 3.5):
        m.strut((x, 0.0, zb + Hb + 1.5), (x, 0.0, zb + Hb + 2.3), 0.04, 'SteelGalv')
    # flood lamps lighting the board
    for x in (-5.5, 0.0, 5.5):
        m.beam((x, 0.0, zb + Hb), (x, -1.2, zb + Hb + 0.35), 0.1, 0.1, 'SteelCharcoal')
        with m.xf(T(x, -1.25, zb + Hb + 0.35) @ RX(-130)):
            _lamp(m, (0, 0, 0), rad=0.2, depth=0.3, visor=False)
    finish(m, 'ScoreboardFrame')

    # Screen: 14.4 x 6.4 m (9:4), facing -Y (Godot +Z), UV 0..1, origin at its centre
    s = mb_new()
    sw, sh = W - 2 * fw, Hb - 2 * fw
    s.quad_grid((-sw / 2, 0, -sh / 2), (sw, 0, 0), (0, 0, sh), 1, 1, 'Screen')
    finish(s, 'Screen', loc=(0.0, -0.3, zb + Hb / 2))


# ============================================================== WALL SEGMENT
def wall_segment():
    m = mb_new()
    L = 6.0
    x0, x1 = -L / 2, L / 2
    # footing
    m.box_mm((x0, -0.6, 0.0), (x1, 0.7, 0.35), 'ConcreteDark', skip=('-z', '-x', '+x'))
    # core
    m.box_mm((x0, -0.25, 0.35), (x1, 0.25, 3.13), 'ConcreteDark', skip=('-x', '+x'))
    # padding panels (field side)
    for i in range(3):
        cx = x0 + 1.0 + i * 2.0
        m.cbox_mm((cx - 0.985, -0.43, 0.38), (cx + 0.985, -0.25, 3.05), 'Padding', ch=0.06)
    m.box_mm((x0, -0.42, 0.35), (x1, -0.25, 0.38), 'Padding', skip=('-x', '+x', '-z', '+z', '+y'))
    m.box_mm((x0, -0.42, 3.05), (x1, -0.25, 3.12), 'Padding', skip=('-x', '+x', '-z', '+y'))
    # home-run line + cap beam
    m.box_mm((x0, -0.45, 3.12), (x1, -0.24, 3.2), 'SafetyYellow', skip=('-x', '+x', '+y'))
    m.prism_x([(-0.47, 3.2), (0.42, 3.2), (0.42, 3.5), (0.36, 3.58), (-0.41, 3.58), (-0.47, 3.52)], x0, x1,
              'SteelCharcoal', caps=(False, False))
    m.box_mm((x0, 0.25, 3.13), (x1, 0.42, 3.2), 'SteelCharcoal', skip=('-x', '+x', '-y', '+z'))
    for i in range(12):
        x = x0 + 0.25 + i * 0.5
        m.rivet((x, -0.47, 3.36), (0, -1, 0), 'SteelGalv', r=0.035, h=0.03)
    # outside plating
    for i in range(3):
        cx = x0 + 1.0 + i * 2.0
        m.box_mm((cx - 0.98, 0.25, 0.35), (cx + 0.98, 0.33, 3.13), 'SteelNavy', skip=('-y',))
        for z in (0.55, 2.9):
            for k in range(4):
                m.rivet((cx - 0.75 + k * 0.5, 0.33, z), (0, 1, 0), 'SteelGalv', r=0.035, h=0.03)
    m.box_mm((x0, 0.33, 1.6), (x1, 0.45, 1.8), 'SteelScarlet', skip=('-x', '+x', '-y'))
    # buttresses (interior positions only, so modules tile cleanly)
    for x in (-1.5, 1.5):
        m.prism_x([(0.33, 0.35), (1.45, 0.35), (0.33, 3.0)], x - 0.16, x + 0.16, 'SteelCharcoal')
        m.box_mm((x - 0.3, 0.33, 0.35), (x + 0.3, 1.55, 0.42), 'SteelCharcoal', skip=('-z',))
    # railing on the cap
    for x in (-2.25, -0.75, 0.75, 2.25):
        m.strut((x, -0.05, 3.58), (x, -0.05, 4.6), 0.035, 'SteelGalv', sides=4)
        # barbed-wire outrigger leaning outwards (+Y)
        m.strut((x, -0.05, 4.6), (x, 0.45, 5.0), 0.025, 'SteelGalv', sides=4)
    for z in (4.1, 4.58):
        m.cyl((x0, -0.05, z), (x1, -0.05, z), 0.03, 'SteelGalv', seg=6, caps=(False, False))
    for f in (0.35, 0.7, 1.0):
        p = Vector((0, -0.05 + 0.5 * f, 4.6 + 0.4 * f))
        m.strut((x0, p.y, p.z), (x1, p.y, p.z), 0.008, 'SteelDark', sides=3)
    # concertina coil along the cap (integer loops so it tiles)
    loops, segs, rc = 12, 8, 0.24
    pts = []
    for i in range(loops * segs + 1):
        t = i / (loops * segs)
        a = t * loops * math.tau
        pts.append((x0 + L * t, 0.2 + rc * math.cos(a), 3.58 + rc + rc * math.sin(a)))
    m.tube(pts, 0.012, 'SteelDark', seg=3)
    finish(m, 'WallSegment')


def wall_post():
    m = mb_new()
    h = 4.7
    m.cbox((0, 0, 0.3), (1.6, 1.6, 0.6), 'ConcreteDark', ch=0.08, skip_down=True)
    m.cbox((0, 0, 0.6 + (h - 0.6) / 2), (1.3, 1.3, h - 0.6), 'SteelNavy', ch=0.08)
    m.box((0, 0, 1.05), (1.34, 1.34, 0.7), 'Hazard', skip=('-z', '+z'))
    m.box((0, 0, 3.6), (1.36, 1.36, 0.3), 'SteelScarlet', skip=('-z',))
    # corner angle strips with rivets
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * 0.62, sy * 0.62, 2.4), (0.16, 0.16, 3.4), 'SteelCharcoal', skip=('-z',))
            for k in range(6):
                z = 1.6 + k * 0.38
                m.rivet((sx * 0.62, sy * 0.71, z), (0, sy, 0), 'SteelGalv', r=0.03, h=0.025)
                m.rivet((sx * 0.71, sy * 0.62, z), (sx, 0, 0), 'SteelGalv', r=0.03, h=0.025)
    # bastion cap
    m.hull([(sx * 0.78, sy * 0.78, z) for sx in (-1, 1) for sy in (-1, 1) for z in (h, h + 0.25)] +
           [(sx * 0.6, sy * 0.6, h + 0.45) for sx in (-1, 1) for sy in (-1, 1)], 'SteelCharcoal')
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = sx * 0.62, sy * 0.62
            m.hull([(px - 0.08, py - 0.08, h + 0.3), (px + 0.08, py - 0.08, h + 0.3),
                    (px + 0.08, py + 0.08, h + 0.3), (px - 0.08, py + 0.08, h + 0.3),
                    (px, py, h + 0.75)], 'SteelGalv')
    m.cyl((0, 0, h + 0.45), (0, 0, h + 0.55), 0.13, 'SteelCharcoal', seg=8)
    m.dome((0, 0, h + 0.55), 0.11, 'AmberEmissive', seg=8, rings=3, h=0.14)
    finish(m, 'WallPost')


# ============================================================ FORTRESS TOWER
def _octagon(half, cut):
    """Octagon (square with chamfered corners) as CCW 2D points."""
    h, c = half, cut
    return [(-h + c, -h), (h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c)]


def fortress_tower():
    m = mb_new()
    # battered concrete bastion
    o0 = _octagon(3.0, 0.9)
    o1 = _octagon(2.55, 0.75)
    zt = 5.0
    m.hull([(x, y, 0.0) for x, y in o0] + [(x, y, zt) for x, y in o1], 'Concrete', skip_down=True)
    # hazard skirt + steel bands
    def oct_band(z0, z1, half0, half1, cut0, cut1, mat, grow=0.04):
        a = _octagon(half0 + grow, cut0 + grow * 0.4)
        b = _octagon(half1 + grow, cut1 + grow * 0.4)
        for i in range(8):
            j = (i + 1) % 8
            m.poly([(a[i][0], a[i][1], z0), (a[j][0], a[j][1], z0), (b[j][0], b[j][1], z1), (b[i][0], b[i][1], z1)], mat)

    def half_at(z):
        return 3.0 + (2.55 - 3.0) * z / zt

    def cut_at(z):
        return 0.9 + (0.75 - 0.9) * z / zt
    oct_band(0.0, 0.7, half_at(0), half_at(0.7), cut_at(0), cut_at(0.7), 'Hazard')
    for z in (2.4,):
        oct_band(z, z + 0.3, half_at(z), half_at(z + 0.3), cut_at(z), cut_at(z + 0.3), 'SteelCharcoal', grow=0.06)
    # slit windows (glowing) on the faces
    for ang in (0, 90, 180, 270):
        with m.xf(RZ(ang)):
            y = -half_at(3.6) - 0.02
            m.box((0.0, y + 0.06, 3.6), (0.22, 0.12, 0.8), 'WindowGlow', skip=('+y',))
            m.box((0.0, y + 0.0, 4.1), (0.5, 0.2, 0.12), 'SteelCharcoal')
    # steel door at the back
    m.cbox_mm((-0.7, half_at(1.0) - 0.1, 0.0), (0.7, half_at(1.0) + 0.12, 2.3), 'SteelNavy', ch=0.04)
    m.box_mm((-0.55, half_at(1.0) + 0.12, 0.15), (0.55, half_at(1.0) + 0.16, 2.1), 'SteelCharcoal', skip=('-y',))
    m.box_mm((-0.55, half_at(1.0) + 0.16, 0.15), (0.55, half_at(1.0) + 0.18, 0.55), 'Hazard', skip=('-y',))
    # rim beam at top of concrete
    m.prism(_octagon(2.75, 0.82), zt, zt + 0.35, 'SteelCharcoal')
    # steel turret / cabin
    zc0, zc1 = zt + 0.35, zt + 2.7
    m.prism(_octagon(2.2, 0.65), zc0, zc0 + 0.8, 'SteelNavy', caps=(False, False))
    m.prism(_octagon(2.15, 0.63), zc0 + 0.8, zc0 + 1.6, 'GlassLit', caps=(False, False))
    m.prism(_octagon(2.2, 0.65), zc0 + 1.6, zc1, 'SteelNavy', caps=(False, False))
    # window mullions + glow behind glass
    oc = _octagon(2.2, 0.65)
    for x, y in oc:
        m.box((x * 0.985, y * 0.985, zc0 + 1.2), (0.12, 0.12, 0.85), 'SteelCharcoal')
    # rivets on the cabin lower plate
    for i in range(8):
        a, b = oc[i], oc[(i + 1) % 8]
        for k in (0.25, 0.5, 0.75):
            px = a[0] + (b[0] - a[0]) * k
            py = a[1] + (b[1] - a[1]) * k
            nrm = Vector((b[1] - a[1], -(b[0] - a[0]), 0)).normalized()
            m.rivet((px, py, zc0 + 0.5), nrm, 'SteelGalv', r=0.04, h=0.03)
    # platform + crenellated parapet
    zp = zc1
    m.prism(_octagon(3.0, 0.9), zp, zp + 0.25, 'SteelCharcoal')
    m.prism(_octagon(3.0, 0.9), zp - 0.12, zp, 'SteelScarlet', caps=(True, False))
    po = _octagon(2.95, 0.88)
    for i in range(8):
        a, b = Vector((*po[i], 0)), Vector((*po[(i + 1) % 8], 0))
        d = b - a
        n = max(1, int(round(d.length / 1.0)))
        nrm = Vector((d.y, -d.x, 0)).normalized()
        for k in range(n):
            if k % 2:
                continue
            p0 = a + d * (k / n)
            p1 = a + d * ((k + 1) / n)
            pts = []
            for p in (p0, p1):
                for off in (0.0, -0.22):
                    for z in (zp + 0.25, zp + 1.15):
                        q = p + nrm * off
                        pts.append((q.x, q.y, z))
            m.hull(pts, 'SteelNavy')
        # low wall between merlons
        pts = []
        for p in (a, b):
            for off in (0.0, -0.18):
                for z in (zp + 0.25, zp + 0.7):
                    q = p + nrm * off
                    pts.append((q.x, q.y, z))
        m.hull(pts, 'SteelCharcoal')
    # roof canopy on four posts
    zr = zp + 2.5
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.beam((sx * 1.6, sy * 1.6, zp + 0.25), (sx * 1.6, sy * 1.6, zr), 0.18, 0.18, 'SteelCharcoal')
    m.hull([(x * 1.04, y * 1.04, zr) for x, y in _octagon(2.6, 0.78)] +
           [(x * 1.04, y * 1.04, zr + 0.2) for x, y in _octagon(2.6, 0.78)] +
           [(x, y, zr + 0.9) for x, y in _octagon(0.9, 0.25)], 'SteelScarlet')
    m.cyl((0, 0, zr + 0.9), (0, 0, zr + 1.6), 0.05, 'SteelGalv', seg=6)
    m.sphere((0, 0, zr + 1.65), 0.1, 'RedAviation', seg=8, rings=4)
    # spotlights on the parapet corners, aimed outward/down
    for ang in (45, 135, 225, 315):
        with m.xf(RZ(ang - 90) @ T(0, -2.55, zp + 1.15)):
            m.cyl((0, 0.1, 0), (0, 0.1, 0.35), 0.05, 'SteelCharcoal', seg=6)
            with m.xf(T(0, 0.0, 0.55) @ RX(15)):
                _lamp(m, (0, 0, 0), rad=0.25, depth=0.45)
    # front searchlight (big)
    with m.xf(T(0, -2.6, zp + 1.2)):
        m.cyl((0, 0.2, -0.05), (0, 0.2, 0.35), 0.07, 'SteelCharcoal', seg=6)
        with m.xf(T(0, 0.0, 0.7) @ RX(10)):
            _lamp(m, (0, 0, 0), rad=0.42, depth=0.7)
    # ladder up the back face to the platform
    _ladder(m, (1.6, half_at(0.2) + 0.25, 0.2), (1.6, half_at(zt) + 0.45, zp + 1.0), out=Vector((0, 1, 0)),
            cage_from=2.5)
    finish(m, 'FortressTower')


# ================================================================ GRANDSTAND
ROWS = 10
ROW_DEPTH = 0.9
ROW_RISE = 0.45
ROW0_FLOOR = 1.0
SEAT_PITCH = 0.6
GS_WIDTH = 12.0
GS_FRONT_Y = -4.5     # Blender y of the first row's front edge (Godot z = +4.5)


def grandstand():
    m = mb_new()
    x0, x1 = -GS_WIDTH / 2, GS_WIDTH / 2
    fy = GS_FRONT_Y
    by = fy + ROWS * ROW_DEPTH            # back edge of the last row
    top = ROW0_FLOOR + (ROWS - 1) * ROW_RISE
    # stepped concrete body (profile in (y, z), extruded along X)
    prof = [(fy, 0.0)]
    side = ['ConcreteDark']
    for k in range(ROWS):
        h = ROW0_FLOOR + k * ROW_RISE
        yf = fy + k * ROW_DEPTH
        prof.append((yf, h))
        side.append('Concrete')            # tread
        prof.append((yf + ROW_DEPTH, h))
        side.append('ConcreteDark')        # riser (or back for the last row)
    prof.append((by, 0.0))
    side.append('ConcreteDark')             # bottom
    side = side[1:] + side[:1]
    # side_mats[i] is for edge prof[i] -> prof[i+1]
    sm = []
    for i in range(len(prof)):
        a, b = prof[i], prof[(i + 1) % len(prof)]
        sm.append('Concrete' if abs(a[1] - b[1]) < 1e-6 and a[1] > 0 else 'ConcreteDark')
    m.prism_x(prof, x0, x1, 'ConcreteDark', side_mats=sm)
    # tread nosing strips (hazard-yellow edge on each step)
    for k in range(ROWS):
        h = ROW0_FLOOR + k * ROW_RISE
        yf = fy + k * ROW_DEPTH
        m.box_mm((x0, yf - 0.005, h - 0.04), (x1, yf + 0.06, h + 0.005), 'SafetyYellow', skip=('-x', '+x', '-z', '+y'))
    # front podium: padding panels + scarlet cap
    for i in range(4):
        cx = x0 + 1.5 + i * 3.0
        m.cbox_mm((cx - 1.48, fy - 0.14, 0.08), (cx + 1.48, fy, 0.86), 'Padding', ch=0.05)
    m.box_mm((x0, fy - 0.16, 0.86), (x1, fy + 0.1, ROW0_FLOOR + 0.02), 'SteelScarlet', skip=('-x', '+x', '-z'))
    # front railing (posts on a 1.5 m pitch, offset so stands tile)
    ry = fy + 0.12
    for i in range(8):
        x = x0 + 0.75 + i * 1.5
        m.strut((x, ry, ROW0_FLOOR), (x, ry, ROW0_FLOOR + 1.0), 0.03, 'SteelGalv', sides=4)
    for z in (ROW0_FLOOR + 1.0, ROW0_FLOOR + 0.55):
        m.cyl((x0, ry, z), (x1, ry, z), 0.035, 'SteelGalv', seg=6, caps=(False, False))
    # seats
    for k in range(ROWS):
        h = ROW0_FLOOR + k * ROW_RISE
        yf = fy + k * ROW_DEPTH
        for i in range(int(GS_WIDTH / SEAT_PITCH)):
            x = x0 + SEAT_PITCH / 2 + i * SEAT_PITCH
            mat = 'SeatScarlet' if (k in (3, 7)) else 'SeatNavy'
            # pedestal
            m.box((x, yf + 0.6, h + 0.2), (0.08, 0.16, 0.4), 'SteelDark', skip=('-z', '+z', '+y'))
            # pan
            m.box((x, yf + 0.55, h + 0.43), (0.48, 0.44, 0.06), mat, skip=('-z',))
            # back (reclined 12 deg)
            with m.xf(T(x, yf + 0.79, h + 0.44) @ RX(-12)):
                m.box((0, 0, 0.23), (0.48, 0.05, 0.42), mat, skip=('-z',))
    # back wall
    bw0, bw1 = by, by + 0.3
    wall_top = top + 3.6
    m.box_mm((x0, bw0, top), (x1, bw1, wall_top), 'SteelNavy', skip=('-x', '+x', '-z'))
    m.box_mm((x0, bw0 - 0.04, top + 1.2), (x1, bw0, top + 1.45), 'SteelScarlet', skip=('-x', '+x', '+y'))
    m.box_mm((x0, bw0, 0.0), (x1, bw1, top), 'ConcreteDark', skip=('-x', '+x', '-z', '-y'))
    for x in (-3.0, 3.0):
        m.box_mm((x - 0.15, bw0 - 0.15, top), (x + 0.15, bw0, wall_top), 'SteelCharcoal', skip=('-z', '+y'))
        for k in range(5):
            m.rivet((x, bw0 - 0.15, top + 0.4 + k * 0.7), (0, -1, 0), 'SteelGalv', r=0.03, h=0.025)
    # back-wall lamps
    for x in (-4.5, -1.5, 1.5, 4.5):
        m.box((x, bw0 - 0.08, top + 2.3), (0.5, 0.16, 0.12), 'SteelCharcoal')
        m.box((x, bw0 - 0.08, top + 2.22), (0.42, 0.12, 0.04), 'WindowGlow', skip=('+z',))
    finish(m, 'Grandstand')

    # roof canopy as its own node so the game can hide it
    c = mb_new()
    cz_back, cz_front = wall_top, wall_top + 0.55
    cy_back, cy_front = bw1, fy + 4.7
    for x in (-4.5, -1.5, 1.5, 4.5):
        c.beam((x, cy_back + 0.25, cz_back - 1.6), (x, cy_back + 0.25, cz_back + 0.2), 0.22, 0.22, 'SteelNavy')
        c.beam((x, cy_back + 0.25, cz_back + 0.2), (x, cy_front, cz_front), 0.18, 0.3, 'SteelNavy',
               up=(0, 0, 1))
        c.strut((x, cy_back + 0.25, cz_back - 1.4), (x, cy_back - 2.5, cz_back + 0.42), 0.05, 'SteelGalv')
    # roof deck (sloped plane with thickness)
    ny = Vector((0, cy_front - cy_back, cz_front - cz_back)).normalized()
    up = Vector((0, -ny.z, ny.y)) * 0.12
    p0 = Vector((0, cy_back + 0.3, cz_back + 0.36))
    p1 = Vector((0, cy_front - 0.05, cz_front + 0.16))
    c.hull([(x, p.y + du.y, p.z + du.z) for x in (x0, x1) for p in (p0, p1) for du in (Vector((0, 0, 0)), up)],
           'RoofSheet')
    # fascia
    c.box_mm((x0, cy_front - 0.12, cz_front - 0.25), (x1, cy_front + 0.02, cz_front + 0.35), 'SteelScarlet',
             skip=('-x', '+x'))
    for i in range(8):
        x = x0 + 0.75 + i * 1.5
        c.box((x, cy_front + 0.25, cz_front - 0.27), (0.34, 0.2, 0.06), 'SteelCharcoal')
        c.box((x, cy_front + 0.25, cz_front - 0.31), (0.28, 0.14, 0.02), 'LampEmissive', skip=('+z',))
    finish(c, 'Canopy')


# ==================================================================== DUGOUT
def dugout():
    m = mb_new()
    W = 10.0
    x0, x1 = -W / 2, W / 2
    fl = -0.75                 # pit floor
    yf, yb = -1.2, 1.6         # front wall outer face, back wall outer face
    roof = 2.3
    # pit floor + surrounding apron
    m.box_mm((x0 + 0.2, yf + 0.2, fl - 0.1), (x1 - 0.2, yb - 0.2, fl), 'ConcreteDark', skip=('-z',))
    # front wall (field side) with an opening for the steps at the left end
    m.cbox_mm((-3.6, yf, fl), (x1, yf + 0.2, 0.35), 'Concrete', ch=0.03)
    m.cbox_mm((-3.6, yf - 0.06, 0.35), (x1, yf + 0.26, 0.5), 'Padding', ch=0.04)
    # dugout rail + posts
    for x in (-3.3, -1.0, 1.3, 3.6, 4.7):
        m.strut((x, yf + 0.1, 0.5), (x, yf + 0.1, 1.15), 0.03, 'SteelGalv', sides=4)
    m.cyl((-3.4, yf + 0.1, 1.15), (4.8, yf + 0.1, 1.15), 0.04, 'SteelGalv', seg=8)
    # steps down at the left end
    for i, z in enumerate((-0.25, -0.5)):
        m.box_mm((x0 + 0.2, yf + 0.2 + i * 0.35, fl), (-3.6, yf + 0.55 + i * 0.35, z), 'Concrete', skip=('-z',))
    m.box_mm((x0 + 0.2, yf, fl), (-3.6, yf + 0.2, 0.0), 'Concrete', skip=('-z',))
    # side + back walls
    for sx in (-1, 1):
        lo = (min(sx * (W / 2 - 0.2), sx * W / 2), yf, fl)
        hi = (max(sx * (W / 2 - 0.2), sx * W / 2), yb, roof)
        m.box_mm(lo, hi, 'Concrete', skip=('-z',))
        m.box_mm((lo[0] - 0.02, yf - 0.02, 0.0), (hi[0] + 0.02, yf + 0.25, 0.5), 'Hazard', skip=('-z',))
    m.box_mm((x0, yb - 0.2, fl), (x1, yb, roof), 'ConcreteDark', skip=('-z', '-x', '+x'))
    # painted upper back wall + stripe
    m.box_mm((x0 + 0.2, yb - 0.24, 0.3), (x1 - 0.2, yb - 0.2, roof - 0.1), 'SteelNavy', skip=('+y', '-z'))
    m.box_mm((x0 + 0.2, yb - 0.26, 0.85), (x1 - 0.2, yb - 0.24, 1.0), 'SteelScarlet', skip=('+y',))
    # roof slab + fascia
    m.cbox_mm((x0 - 0.2, yf - 0.3, roof), (x1 + 0.2, yb + 0.1, roof + 0.25), 'ConcreteDark', ch=0.04)
    m.box_mm((x0 - 0.2, yf - 0.36, roof - 0.15), (x1 + 0.2, yf - 0.3, roof + 0.3), 'SteelNavy', skip=('+y',))
    m.box_mm((x0 - 0.2, yf - 0.38, roof + 0.22), (x1 + 0.2, yf - 0.36, roof + 0.3), 'SteelScarlet', skip=('+y',))
    m.box_mm((x0 - 0.2, yf - 0.38, roof - 0.15), (x1 + 0.2, yf - 0.36, roof - 0.07), 'SteelScarlet', skip=('+y',))
    font = load_font('RussoOne-Regular.ttf')
    with m.xf(T(0, yf - 0.38, roof + 0.075) @ RX(90)):
        m.text('DIAMOND DEFENDERS', font, 0.2, 'PaintWhite', depth=0.015)
    # roof padding along the front edge (top)
    m.cbox_mm((x0 - 0.2, yf - 0.3, roof + 0.25), (x1 + 0.2, yf + 0.3, roof + 0.4), 'Padding', ch=0.04)
    # light strip under the roof
    m.box_mm((-3.5, 0.3, roof - 0.06), (3.5, 0.45, roof), 'SteelCharcoal', skip=('+z',))
    m.box_mm((-3.4, 0.33, roof - 0.08), (3.4, 0.42, roof - 0.06), 'WindowGlow', skip=('+z',))
    # bench along the back wall
    by = yb - 0.2
    for i in range(6):
        x = -2.5 + i * 1.0
        m.box((x, by - 0.3, fl + 0.21), (0.06, 0.32, 0.42), 'SteelDark', skip=('-z',))
    for k in range(2):
        m.cbox_mm((-2.7, by - 0.52 + k * 0.21, fl + 0.42), (2.7, by - 0.33 + k * 0.21, fl + 0.48), 'Wood', ch=0.015)
    m.cbox_mm((-2.7, by - 0.08, fl + 0.6), (2.7, by - 0.02, fl + 0.9), 'Wood', ch=0.012)
    # helmet rack (cubbies) on the back wall, left
    hx0, hx1 = -4.65, -2.95
    hz0 = fl + 0.75
    m.box_mm((hx0, by - 0.42, hz0), (hx1, by, hz0 + 0.04), 'SteelCharcoal')
    m.box_mm((hx0, by - 0.42, hz0 + 0.45), (hx1, by, hz0 + 0.49), 'SteelCharcoal')
    m.box_mm((hx0, by - 0.42, hz0 + 0.9), (hx1, by, hz0 + 0.94), 'SteelCharcoal')
    for k in range(5):
        x = hx0 + k * (hx1 - hx0) / 4
        m.box_mm((x - 0.02, by - 0.42, hz0), (x + 0.02, by, hz0 + 0.94), 'SteelCharcoal')
    for row in range(2):
        for k in range(4):
            x = hx0 + (k + 0.5) * (hx1 - hx0) / 4
            z = hz0 + 0.04 + row * 0.45
            with m.xf(T(x, by - 0.22, z) @ RZ(180 + (k * 37 + row * 11) % 30 - 15)):
                m.dome((0, 0, 0), 0.15, 'HelmetNavy', seg=10, rings=3, h=0.17)
                m.poly([(-0.1, -0.12, 0.012), (0.1, -0.12, 0.012), (0.12, -0.26, 0.0), (-0.12, -0.26, 0.0)],
                       'HelmetNavy')
                m.poly([(0.1, -0.12, 0.004), (-0.1, -0.12, 0.004), (-0.12, -0.26, -0.008),
                        (0.12, -0.26, -0.008)], 'HelmetNavy')
                m.box((0, 0.13, 0.06), (0.03, 0.03, 0.08), 'SteelScarlet', skip=('-z',))
    # water cooler on a stand
    cx, cy = 3.05, by - 0.3
    m.box((cx, cy, fl + 0.3), (0.55, 0.45, 0.6), 'SteelGalv', skip=('-z',))
    m.cyl((cx, cy, fl + 0.6), (cx, cy, fl + 1.12), 0.24, 'CoolerOrange', seg=14, caps=(False, False))
    m.cyl((cx, cy, fl + 1.12), (cx, cy, fl + 1.2), 0.25, 'PlasticWhite', r1=0.22, seg=14, caps=(False, True))
    m.cyl((cx, cy, fl + 0.72), (cx, cy, fl + 0.76), 0.245, 'PlasticWhite', seg=14, caps=(False, False))
    m.cyl((cx, cy, fl + 1.0), (cx, cy, fl + 1.04), 0.245, 'PlasticWhite', seg=14, caps=(False, False))
    m.cyl((cx, cy - 0.24, fl + 0.7), (cx, cy - 0.3, fl + 0.7), 0.025, 'PlasticWhite', seg=6)
    m.cyl((cx + 0.33, cy, fl + 0.65), (cx + 0.33, cy, fl + 1.1), 0.04, 'PlasticWhite', seg=8)
    # bat rack (floor standing) with bats
    rx0, rx1 = 3.6, 4.7
    for x in (rx0, rx1):
        m.box((x, by - 0.2, fl + 0.5), (0.06, 0.06, 1.0), 'Wood', skip=('-z',))
    m.cbox_mm((rx0, by - 0.3, fl + 0.85), (rx1, by - 0.1, fl + 0.92), 'Wood', ch=0.01)
    m.cbox_mm((rx0, by - 0.3, fl + 0.02), (rx1, by - 0.1, fl + 0.12), 'Wood', ch=0.01)
    for k in range(7):
        x = rx0 + 0.1 + k * (rx1 - rx0 - 0.2) / 6
        lean = (k % 3 - 1) * 0.03
        with m.xf(T(x, by - 0.2, fl + 0.12) @ Matrix.Rotation(math.radians(180) + lean, 4, 'Y')
                  @ T(0, 0, -0.86)):
            _bat_geo(m, seg=6, length=0.86, simple=True)
    finish(m, 'Dugout')


def _bat_geo(m, seg=12, length=0.85, simple=False, grip=True):
    """Baseball bat along local +Z from the knob (z=0)."""
    s = length / 0.85
    prof = [(0.0, 0.0), (0.028, 0.0), (0.03, 0.008), (0.022, 0.02), (0.0125, 0.03), (0.0125, 0.25),
            (0.0145, 0.36), (0.02, 0.45), (0.028, 0.54), (0.032, 0.62), (0.033, 0.8), (0.031, 0.84),
            (0.022, 0.85), (0.0, 0.85)]
    if simple:
        prof = [(0.0, 0.0), (0.026, 0.0), (0.013, 0.03), (0.0125, 0.3), (0.025, 0.52), (0.033, 0.62),
                (0.033, 0.83), (0.0, 0.85)]
    prof = [(r * 1.0, z * s) for r, z in prof]
    m.lathe(prof, 'Bat', seg=seg, sharp=(1, 2), vmode='01')
    if grip and not simple:
        m.cyl((0, 0, 0.03 * s), (0, 0, 0.26 * s), 0.0135, 'BatGrip', seg=seg, caps=(False, False),
              uv_scale=0.12)


# =============================================================== BANNER POLE
def banner_pole():
    m = mb_new()
    m.cbox((0, 0, 0.2), (0.8, 0.8, 0.4), 'Concrete', ch=0.05, skip_down=True)
    m.cyl((0, 0, 0.4), (0, 0, 0.45), 0.24, 'SteelCharcoal', seg=8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        m.cyl((0.18 * math.cos(a), 0.18 * math.sin(a), 0.45), (0.18 * math.cos(a), 0.18 * math.sin(a), 0.52),
              0.025, 'SteelGalv', seg=6)
    m.cyl((0, 0, 0.45), (0, 0, 1.3), 0.125, 'Hazard', r1=0.122, seg=10, caps=(False, False))
    m.cyl((0, 0, 1.3), (0, 0, 9.0), 0.122, 'SteelNavy', r1=0.08, seg=10, caps=(False, True))
    m.cyl((0, 0, 2.6), (0, 0, 2.8), 0.125, 'SteelScarlet', r1=0.123, seg=10, caps=(False, False))
    m.sphere((0, 0, 9.12), 0.14, 'SteelScarlet', seg=10, rings=6)
    # top arm + diagonal brace
    za = 8.55
    m.cyl((0.0, 0, za), (1.9, 0, za), 0.035, 'SteelCharcoal', seg=6)
    m.strut((0.08, 0, za - 0.7), (1.0, 0, za - 0.02), 0.022, 'SteelCharcoal', sides=4)
    m.sphere((1.92, 0, za), 0.05, 'SteelScarlet', seg=6, rings=4)
    # banner clips on the arm
    for k in range(5):
        x = 0.2 + k * 0.38
        m.cyl((x, 0, za - 0.05), (x, 0, za - 0.12), 0.02, 'SteelGalv', seg=6)
    finish(m, 'BannerPole')
    # Banner: 1.6 x 4.2 m, 16 x 24 quads, faces -Y (Godot +Z).  Origin at the
    # top pole-side corner; UV (0,0) top-left in Godot = attached corner.
    b = mb_new()
    bw, bh = 1.6, 4.2
    b.quad_grid((0.0, 0.0, -bh), (bw, 0, 0), (0, 0, bh), 16, 24, 'Banner')
    finish(b, 'Banner', loc=(0.18, 0.0, za - 0.12))


PROPS = {
    'light_tower': light_tower,
    'gate': lambda: gate('GATE'),          # generic stencil
    'gate_a': lambda: gate('GATE A'),
    'gate_b': lambda: gate('GATE B'),
    'gate_c': lambda: gate('GATE C'),
    'gate_d': lambda: gate('GATE D'),
    'scoreboard': scoreboard,
    'wall_segment': wall_segment,
    'wall_post': wall_post,
    'fortress_tower': fortress_tower,
    'grandstand': grandstand,
    'dugout': dugout,
    'banner_pole': banner_pole,
}
