"""UI icon set: white glyphs on transparent, 64x64 viewBox (the game tints them).

Style rules: solid filled silhouettes with cut-outs (fill-rule evenodd) for most
glyphs; line elements use a 5 px round-capped stroke; content kept inside a
4..60 safe box. Only basic SVG features are used (path/circle/rect/polygon,
evenodd, strokes) so Godot's ThorVG importer renders them exactly.
"""
from __future__ import annotations

import math

from artlib.core import TEX_DIR

OUT = TEX_DIR / "icons"
F = 'fill="#FFFFFF"'
S = 'fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"'
S4 = 'fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"'


def _f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def pts(points):
    return " ".join(f"{_f(x)},{_f(y)}" for x, y in points)


def poly(points, close=True):
    d = "M" + " L".join(f"{_f(x)},{_f(y)}" for x, y in points)
    return d + ("Z" if close else "")


def star_pts(cx, cy, ro, ri, n=5, rot=-90):
    out = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180 / n)
        r = ro if i % 2 == 0 else ri
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


def circle_d(cx, cy, r):
    return (f"M{_f(cx - r)},{_f(cy)} A{_f(r)},{_f(r)} 0 1 0 {_f(cx + r)},{_f(cy)} "
            f"A{_f(r)},{_f(r)} 0 1 0 {_f(cx - r)},{_f(cy)}Z")


def ring_d(cx, cy, r_out, r_in):
    return circle_d(cx, cy, r_out) + circle_d(cx, cy, r_in)


def gear_d(cx, cy, ro, ri, teeth, hole):
    out = []
    n = teeth * 4
    for i in range(n):
        a = 2 * math.pi * i / n
        r = ro if (i % 4) in (1, 2) else ri
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return poly(out) + circle_d(cx, cy, hole)


def rrect(x, y, w, h, r):
    return (f"M{_f(x + r)},{_f(y)} H{_f(x + w - r)} A{_f(r)},{_f(r)} 0 0 1 {_f(x + w)},{_f(y + r)} V{_f(y + h - r)} "
            f"A{_f(r)},{_f(r)} 0 0 1 {_f(x + w - r)},{_f(y + h)} H{_f(x + r)} A{_f(r)},{_f(r)} 0 0 1 {_f(x)},{_f(y + h - r)} "
            f"V{_f(y + r)} A{_f(r)},{_f(r)} 0 0 1 {_f(x + r)},{_f(y)}Z")


def path(d, evenodd=True):
    rule = ' fill-rule="evenodd"' if evenodd else ""
    return f'<path d="{d}" {F}{rule}/>'


def spath(d, attrs=S):
    return f'<path d="{d}" {attrs}/>'


def ball_d(cx, cy, r):
    """Baseball: disc with two seam cut-outs."""
    s = r * 0.62
    return (circle_d(cx, cy, r)
            + f"M{_f(cx - r * 0.62)},{_f(cy - r * 0.78)} C{_f(cx - r * 0.25)},{_f(cy - r * 0.35)} {_f(cx - r * 0.25)},{_f(cy + r * 0.35)} "
              f"{_f(cx - r * 0.62)},{_f(cy + r * 0.78)} L{_f(cx - r * 0.74)},{_f(cy + r * 0.66)} C{_f(cx - r * 0.42)},{_f(cy + r * 0.3)} "
              f"{_f(cx - r * 0.42)},{_f(cy - r * 0.3)} {_f(cx - r * 0.74)},{_f(cy - r * 0.66)}Z"
            + f"M{_f(cx + r * 0.62)},{_f(cy - r * 0.78)} C{_f(cx + r * 0.25)},{_f(cy - r * 0.35)} {_f(cx + r * 0.25)},{_f(cy + r * 0.35)} "
              f"{_f(cx + r * 0.62)},{_f(cy + r * 0.78)} L{_f(cx + r * 0.74)},{_f(cy + r * 0.66)} C{_f(cx + r * 0.42)},{_f(cy + r * 0.3)} "
              f"{_f(cx + r * 0.42)},{_f(cy - r * 0.3)} {_f(cx + r * 0.74)},{_f(cy - r * 0.66)}Z")


def shield_d(x0=10, y0=6, x1=54, y1=60):
    cx = (x0 + x1) / 2
    return (f"M{_f(cx)},{_f(y0)} L{_f(x1)},{_f(y0 + 8)} V{_f(y0 + 24)} C{_f(x1)},{_f(y0 + 40)} {_f(cx + 12)},{_f(y1 - 6)} {_f(cx)},{_f(y1)} "
            f"C{_f(cx - 12)},{_f(y1 - 6)} {_f(x0)},{_f(y0 + 40)} {_f(x0)},{_f(y0 + 24)} V{_f(y0 + 8)}Z")


def bolt_d(scale=1.0, dx=0.0, dy=0.0):
    p = [(36, 4), (14, 36), (29, 36), (24, 60), (50, 24), (34, 24), (40, 4)]
    return poly([(x * scale + dx, y * scale + dy) for x, y in p])


def flame_d():
    return ("M33,4 C35,16 48,22 50,38 C52,52 43,60 32,60 C20,60 12,52 12,41 C12,31 18,25 22,19 "
            "C23,27 26,31 30,32 C26,22 29,11 33,4Z"
            "M32,56 C38,56 42,51 42,45 C42,39 37,36 35,30 C33,36 28,38 27,44 C26,47 25,49 24,47 "
            "C22,50 25,56 32,56Z")


def heart_d():
    return ("M32,57 C26,52 6,40 6,23 C6,13 13,7 21,7 C26,7 30,10 32,14 C34,10 38,7 43,7 C51,7 58,13 58,23 "
            "C58,40 38,52 32,57Z")


ICONS: dict[str, str] = {}


def icon(name):
    def deco(fn):
        ICONS[name] = fn()
        return fn
    return deco


# --- categories --------------------------------------------------------------
@icon("offense")
def _():
    out = [path(circle_d(41, 23, 15))]
    d = (-0.7071, 0.7071)
    n = (0.7071, 0.7071)
    for o, L, w in ((-10, 26, 7), (0, 36, 9), (10, 26, 7)):
        sx, sy = 41 + n[0] * o, 23 + n[1] * o
        p = [(sx + n[0] * w / 2, sy + n[1] * w / 2), (sx + d[0] * L, sy + d[1] * L), (sx - n[0] * w / 2, sy - n[1] * w / 2)]
        out.append(path(poly(p)))
    return "".join(out)


@icon("control")
def _():
    # spiral swirl
    pts_ = []
    for i in range(160):
        t = i / 159
        a = t * 2.6 * 2 * math.pi
        r = 3 + 24 * t
        pts_.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    return spath(poly(pts_, False), 'fill="none" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"')


@icon("defense")
def _():
    dia = poly([(32, 18), (44, 31), (32, 44), (20, 31)])
    return path(shield_d() + dia)


@icon("utility")
def _():
    return (path(poly(star_pts(28, 34, 24, 7, 4, -90)))
            + path(poly(star_pts(50, 13, 10, 3, 4, -90))))


# --- resources / stats ---------------------------------------------------------
@icon("coin")
def _():
    dia = poly([(32, 20), (41, 32), (32, 44), (23, 32)])
    return path(circle_d(32, 32, 27) + circle_d(32, 32, 21)) + path(dia)


@icon("star")
def _():
    return path(poly(star_pts(32, 34, 28, 12)))


@icon("energy")
def _():
    hexa = [(32 + math.cos(math.radians(a)) * 28, 32 + math.sin(math.radians(a)) * 28) for a in range(-90, 270, 60)]
    b = [(35, 12), (20, 35), (31, 35), (27, 52), (44, 28), (33, 28), (37, 12)]
    return path(poly(hexa) + poly(b))


@icon("damage")
def _():
    return path(poly(star_pts(32, 32, 29, 13, 8, -90)) + circle_d(32, 32, 6))


@icon("attack_speed")
def _():
    return (path(ball_d(40, 32, 18))
            + spath("M4,22 L16,22 M2,32 L16,32 M4,42 L16,42"))


@icon("range")
def _():
    return (spath("M32,6 A26,26 0 1 1 31.9,6", 'fill="none" stroke="#FFFFFF" stroke-width="5" stroke-dasharray="7 6" stroke-linecap="round"')
            + path(circle_d(32, 32, 6)) + spath("M32,32 H48") + path(poly([(58, 32), (46, 24), (46, 40)])))


@icon("accuracy")
def _():
    return (path(ring_d(32, 32, 22, 17))
            + spath("M32,4 V16 M32,48 V60 M4,32 H16 M48,32 H60")
            + path(circle_d(32, 32, 5)))


@icon("throw_speed")
def _():
    # speedometer gauge with needle
    return (spath("M8,46 A24,24 0 1 1 56,46", 'fill="none" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"')
            + spath("M16,24 L19,27 M32,16 V20 M48,24 L45,27")
            + path(poly([(30, 47), (48, 26), (35, 50)])) + path(circle_d(32, 48, 6)))


@icon("special")
def _():
    return path(ring_d(32, 32, 28, 23)) + path(poly(star_pts(32, 32, 18, 6, 4, -90)))


@icon("cooldown")
def _():
    return (path(rrect(12, 4, 40, 6, 3) + rrect(12, 54, 40, 6, 3))
            + path("M16,10 H48 C48,24 38,28 36,32 C38,36 48,40 48,54 H16 C16,40 26,36 28,32 C26,28 16,24 16,10Z"
                   "M22,16 C23,24 31,27 32,30 C33,27 41,24 42,16Z M32,40 C28,42 22,46 21,50 H43 C42,46 36,42 32,40Z"))


@icon("health")
def _():
    return path(heart_d())


@icon("armor")
def _():
    return path("M14,8 L24,6 C26,12 38,12 40,6 L50,8 L58,18 L52,26 L50,24 V56 C42,60 22,60 14,56 V24 L12,26 L6,18Z"
                "M32,24 C28,26 24,26 21,26 V40 C21,48 27,52 32,54 C37,52 43,48 43,40 V26 C40,26 36,26 32,24Z")


@icon("speed")
def _():
    return (path(poly([(30, 12), (58, 32), (30, 52), (30, 40), (18, 40), (18, 24), (30, 24)]))
            + spath("M4,24 H10 M4,40 H10"))


# --- game state ------------------------------------------------------------------
@icon("runs")
def _():
    return path(poly([(8, 8), (56, 8), (56, 34), (32, 58), (8, 34)]) + poly([(15, 15), (49, 15), (49, 31), (32, 48), (15, 31)]))


@icon("outs")
def _():
    return spath("M14,14 L50,50 M50,14 L14,50", 'fill="none" stroke="#FFFFFF" stroke-width="10" stroke-linecap="round"')


@icon("inning")
def _():
    dia = [(32, 8), (56, 32), (32, 56), (8, 32)]
    inner = [(32, 16), (48, 32), (32, 48), (16, 32)]
    bases = "".join(path(poly([(x, y - 6), (x + 6, y), (x, y + 6), (x - 6, y)])) for x, y in dia)
    return path(poly(dia) + poly(inner)) + bases + path(circle_d(32, 32, 4))


@icon("wave")
def _():
    w1 = "M4,24 C12,14 18,14 25,24 C32,34 38,34 45,24 C52,14 56,16 60,20"
    w2 = "M4,42 C12,32 18,32 25,42 C32,52 38,52 45,42 C52,32 56,34 60,38"
    attrs = 'fill="none" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"'
    return spath(w1, attrs) + spath(w2, attrs)


@icon("enemy")
def _():
    # batting helmet with glowing visor slit (side view)
    return path("M10,40 C10,22 22,10 36,10 C50,10 58,22 58,36 V44 H22 L20,52 H6 V44 C6,42 8,40 10,40Z"
                "M30,30 H54 V36 H30Z")


@icon("boss")
def _():
    return path("M32,6 C46,6 56,16 56,30 C56,38 52,43 48,46 V54 C48,57 46,58 44,58 H20 C18,58 16,57 16,54 V46 "
                "C12,43 8,38 8,30 C8,16 18,6 32,6Z"
                "M22,26 C17,26 15,30 15,33 C15,37 19,39 24,38 C28,37 29,33 28,30 C27,27 25,26 22,26Z"
                "M42,26 C47,26 49,30 49,33 C49,37 45,39 40,38 C36,37 35,33 36,30 C37,27 39,26 42,26Z"
                "M32,40 L36,47 H28Z M24,51 H27 V58 H24Z M30.5,51 H33.5 V58 H30.5Z M37,51 H40 V58 H37Z")


@icon("shield")
def _():
    return path(shield_d() + "M32,14 L46,19 V31 C46,41 38,48 32,51Z")


# --- menus -------------------------------------------------------------------
@icon("play")
def _():
    return path("M18,8 C18,5 21,4 23,5 L56,29 C58,30.5 58,33.5 56,35 L23,59 C21,60 18,59 18,56Z")


@icon("deck")
def _():
    return (path(rrect(8, 14, 34, 46, 5) + rrect(13, 19, 24, 36, 2))
            + path(rrect(22, 4, 34, 46, 5)) )


@icon("roster")
def _():
    return (path(circle_d(22, 18, 9)) + path("M6,52 C6,40 12,32 22,32 C32,32 38,40 38,52Z")
            + path(circle_d(44, 22, 8)) + path("M40,34 C50,33 58,40 58,52 H42 C42,44 41,38 40,34Z"))


@icon("collection")
def _():
    return "".join(path(rrect(x, y, 23, 23, 4)) for x, y in ((7, 7), (34, 7), (7, 34))) + \
        path(rrect(34, 34, 23, 23, 4) + poly(star_pts(45.5, 46, 8, 3.4)))


@icon("practice")
def _():
    bat = "M6,54 L10,58 L14,54 L44,24 C50,18 56,14 58,8 C54,6 48,12 40,18 L10,50Z"
    return path(bat) + path(ball_d(46, 46, 11))


@icon("progression")
def _():
    return (path(rrect(8, 40, 10, 18, 2)) + path(rrect(23, 30, 10, 28, 2)) + path(rrect(38, 20, 10, 38, 2))
            + spath("M8,28 L24,14 L34,20 L52,6") + path(poly([(56, 4), (54, 16), (44, 8)])))


@icon("settings")
def _():
    return path(gear_d(32, 32, 28, 21, 8, 9))


@icon("exit")
def _():
    return (path("M8,6 H36 V22 H31 V11 H13 V53 H31 V42 H36 V58 H8Z")
            + spath("M24,32 H52") + path(poly([(58, 32), (46, 22), (46, 42)])))


@icon("lock")
def _():
    return (spath("M20,28 V20 C20,12 26,7 32,7 C38,7 44,12 44,20 V28", 'fill="none" stroke="#FFFFFF" stroke-width="6"')
            + path(rrect(10, 27, 44, 32, 6) + "M29,39 A4,4 0 1 1 35,39 L34.5,50 H29.5Z"))


@icon("check")
def _():
    return spath("M10,34 L26,50 L54,14", 'fill="none" stroke="#FFFFFF" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"')


@icon("plus")
def _():
    return spath("M32,10 V54 M10,32 H54", 'fill="none" stroke="#FFFFFF" stroke-width="9" stroke-linecap="round"')


@icon("minus")
def _():
    return spath("M10,32 H54", 'fill="none" stroke="#FFFFFF" stroke-width="9" stroke-linecap="round"')


@icon("trophy")
def _():
    return (path("M16,6 H48 V22 C48,33 41,40 32,40 C23,40 16,33 16,22Z")
            + spath("M16,12 H8 V18 C8,25 12,29 18,30 M48,12 H56 V18 C56,25 52,29 46,30", 'fill="none" stroke="#FFFFFF" stroke-width="4.5" stroke-linejoin="round"')
            + path("M28,39 H36 V48 H28Z") + path(rrect(18, 48, 28, 10, 3)))


@icon("search")
def _():
    return (path(ring_d(26, 26, 20, 14))
            + spath("M41,41 L56,56", 'fill="none" stroke="#FFFFFF" stroke-width="9" stroke-linecap="round"'))


@icon("filter")
def _():
    return path("M6,8 H58 L38,32 V52 L26,58 V32Z")


@icon("sort")
def _():
    return (path(poly([(18, 4), (30, 18), (22, 18), (22, 58), (14, 58), (14, 18), (6, 18)]))
            + path(poly([(46, 60), (58, 46), (50, 46), (50, 6), (42, 6), (42, 46), (34, 46)])))


@icon("swap")
def _():
    return (spath("M10,22 H48") + path(poly([(58, 22), (44, 11), (44, 33)]))
            + spath("M54,44 H16") + path(poly([(6, 44), (20, 33), (20, 55)])))


@icon("save")
def _():
    return path("M6,10 C6,7 8,6 10,6 H46 L58,18 V54 C58,57 56,58 54,58 H10 C8,58 6,57 6,54Z"
                "M16,6 H42 V22 H16Z M14,34 H50 V52 H14Z") + path("M33,10 H38 V18 H33Z")


@icon("load")
def _():
    return path("M4,14 C4,11 6,10 8,10 H24 L30,16 H56 C58,16 60,18 60,20 V52 C60,55 58,56 56,56 H8 C6,56 4,55 4,52Z"
                "M32,24 L44,36 H36 V48 H28 V36 H20Z")


@icon("camera")
def _():
    return path("M6,22 C6,19 8,17 11,17 H20 L25,10 H39 L44,17 H53 C56,17 58,19 58,22 V50 C58,53 56,55 53,55 H11 C8,55 6,53 6,50Z"
                + ring_d(32, 35, 14, 9) + circle_d(49, 25, 3))


@icon("map")
def _():
    return path("M4,14 L22,8 L42,14 L60,8 V50 L42,56 L22,50 L4,56Z M25,13 V46 L39,51 V18Z")


@icon("fast_forward")
def _():
    return path("M4,12 L30,32 L4,52Z") + path("M32,12 L58,32 L32,52Z")


@icon("pause")
def _():
    return path(rrect(12, 8, 14, 48, 4)) + path(rrect(38, 8, 14, 48, 4))


@icon("back")
def _():
    return path("M6,32 L30,10 V22 H50 C55,22 58,25 58,30 V34 C58,39 55,42 50,42 H30 V54Z")


@icon("info")
def _():
    return path(circle_d(32, 32, 28) + circle_d(32, 18, 4.5) + rrect(28, 26, 8, 22, 3))


@icon("upgrade")
def _():
    return (path(poly([(32, 4), (56, 28), (44, 28), (32, 16), (20, 28), (8, 28)]))
            + path(poly([(32, 22), (56, 46), (44, 46), (32, 34), (20, 46), (8, 46)]))
            + path(rrect(24, 48, 16, 10, 2)))


@icon("gift")
def _():
    return (path(rrect(6, 22, 52, 12, 3) + "M30,22 H34 V34 H30Z")
            + path("M10,36 H54 V56 C54,58 52,59 50,59 H14 C12,59 10,58 10,56Z M30,36 H34 V59 H30Z")
            + spath("M32,22 C26,8 12,10 16,18 C18,22 26,22 32,22 C38,22 46,22 48,18 C52,10 38,8 32,22", S4))


@icon("crown")
def _():
    return path("M6,18 L20,32 L32,10 L44,32 L58,18 L52,48 H12Z") + path(rrect(12, 51, 40, 7, 2)) \
        + path(circle_d(6, 16, 4)) + path(circle_d(32, 8, 4)) + path(circle_d(58, 16, 4))


# --- elements ------------------------------------------------------------------
@icon("fire")
def _():
    return path(flame_d())


@icon("frost")
def _():
    arms = []
    for k in range(6):
        a = math.radians(k * 60 - 90)
        ex, ey = 32 + math.cos(a) * 27, 32 + math.sin(a) * 27
        arms.append(f"M32,32 L{_f(ex)},{_f(ey)}")
        for t, L in ((0.55, 8), (0.8, 6)):
            bx, by = 32 + math.cos(a) * 27 * t, 32 + math.sin(a) * 27 * t
            for s_ in (-1, 1):
                aa = a + s_ * math.radians(45)
                arms.append(f"M{_f(bx)},{_f(by)} L{_f(bx + math.cos(aa) * L)},{_f(by + math.sin(aa) * L)}")
    return spath(" ".join(arms), 'fill="none" stroke="#FFFFFF" stroke-width="4.5" stroke-linecap="round"') + path(circle_d(32, 32, 5))


@icon("shadow")
def _():
    return path("M40,6 C28,10 20,20 20,32 C20,44 28,54 40,58 C24,60 6,48 6,32 C6,16 24,4 40,6Z") + \
        path("M40,18 C48,18 56,24 56,32 C56,40 48,46 40,46 C46,42 48,37 48,32 C48,27 46,22 40,18Z")


@icon("lightning")
def _():
    return path(poly([(38, 3), (12, 36), (28, 36), (20, 61), (52, 24), (35, 24), (44, 3)]))


@icon("target")
def _():
    return path(ring_d(32, 32, 28, 22) + ring_d(32, 32, 16, 10) + circle_d(32, 32, 5))


# --- team / tactics ------------------------------------------------------------------
@icon("captain")
def _():
    # ball cap with a star on the crown
    cap = ("M8,40 C8,22 18,10 32,10 C46,10 54,22 54,36 L54,40 C62,42 62,48 56,50 C46,53 30,52 18,50 C12,49 8,46 8,40Z")
    return path(cap + poly(star_pts(30, 28, 10, 4.2)))


@icon("formation")
def _():
    nodes = [(32, 8), (54, 30), (32, 52), (10, 30), (32, 30)]
    return (spath("M32,8 L54,30 L32,52 L10,30Z M32,8 L32,52", S4)
            + "".join(path(circle_d(x, y, 6.5)) for x, y in nodes))


@icon("synergy")
def _():
    a = 'fill="none" stroke="#FFFFFF" stroke-width="6"'
    return f'<circle cx="23" cy="32" r="15" {a}/><circle cx="41" cy="32" r="15" {a}/>' + path(poly(star_pts(32, 32, 7, 3, 4, -90)))


# --- system ---------------------------------------------------------------------
@icon("calendar")
def _():
    return (path(rrect(6, 10, 52, 48, 6) + rrect(11, 24, 42, 29, 2))
            + path(rrect(16, 4, 7, 12, 3)) + path(rrect(41, 4, 7, 12, 3))
            + "".join(path(rrect(x, y, 8, 7, 1.5)) for x in (16, 28, 40) for y in (29, 41)))


@icon("music")
def _():
    return (path("M24,12 L56,6 V46 H51 V16 L29,20 V52 H24Z")
            + path("M14,52 C14,46 20,43 26,44 V52 C26,57 21,60 17,59 C15,58 14,55 14,52Z")
            + path("M41,46 C41,40 47,37 53,38 V46 C53,51 48,54 44,53 C42,52 41,49 41,46Z"))


@icon("volume")
def _():
    return (path("M6,24 H18 L34,10 V54 L18,40 H6Z")
            + spath("M42,22 C46,26 46,38 42,42") + spath("M50,14 C58,22 58,42 50,50"))


@icon("keyboard")
def _():
    keys = "".join(rrect(x, y, 7, 6, 1.5) for x in (12, 21, 30, 39, 48) for y in (22, 31)) + rrect(18, 40, 28, 6, 1.5)
    return path(rrect(4, 14, 56, 38, 6) + keys)


@icon("display")
def _():
    return path(rrect(4, 8, 56, 38, 5) + rrect(9, 13, 46, 28, 2)) + path("M26,46 H38 L40,54 H24Z") + path(rrect(16, 54, 32, 5, 2.5))


NAMES = ["offense", "control", "defense", "utility", "coin", "star", "energy", "damage", "attack_speed", "range",
         "accuracy", "throw_speed", "special", "cooldown", "health", "armor", "speed", "runs", "outs", "inning", "wave",
         "enemy", "boss", "shield", "play", "deck", "roster", "collection", "practice", "progression", "settings", "exit",
         "lock", "check", "plus", "minus", "trophy", "search", "filter", "sort", "swap", "save", "load", "camera", "map",
         "fast_forward", "pause", "back", "info", "upgrade", "gift", "crown", "fire", "frost", "shadow", "lightning",
         "target", "captain", "formation", "synergy", "calendar", "music", "volume", "keyboard", "display"]


def svg_text(name: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'{ICONS[name]}</svg>\n')


def build(out_dir=OUT):
    out_dir.mkdir(parents=True, exist_ok=True)
    missing = [n for n in NAMES if n not in ICONS]
    if missing:
        raise SystemExit(f"missing icons: {missing}")
    paths = []
    for n in NAMES:
        p = out_dir / f"{n}.svg"
        p.write_text(svg_text(n))
        paths.append(p)
    print(f"  {len(paths)} icons")
    return paths


if __name__ == "__main__":
    build()
