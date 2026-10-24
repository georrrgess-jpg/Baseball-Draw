"""SVG prop generators for illustrations (glove, plates, bases, stopwatch, ...).

Each generator returns SVG markup (and sometimes defs) in its own coordinate
space; place with a transform. Shapes use the shared comic style: ink outline
(drawn as a fat stroke underneath), cel-shaded gradient fills, light rims.
"""
from __future__ import annotations

import math
from itertools import count

import numpy as np

_ids = count()


def uid(prefix="g"):
    return f"{prefix}{next(_ids)}"


# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------
def bezier(p0, p1, p2, p3, n=64):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = (np.array(p, float) for p in (p0, p1, p2, p3))
    return ((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3)


def taper_path(pts, w0, w1, power=1.0):
    """Closed polygon path around a polyline whose width goes from w0 to w1."""
    pts = np.asarray(pts, float)
    n = len(pts)
    d = np.gradient(pts, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    t = np.linspace(0, 1, n) ** power
    w = (w0 + (w1 - w0) * t)[:, None] / 2
    left = pts + nrm * w
    right = pts - nrm * w
    poly = np.vstack([left, right[::-1]])
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in poly) + "Z"


def poly_d(pts, close=True):
    s = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    return s + ("Z" if close else "")


def lin_grad(gid, stops, x1=0, y1=0, x2=0, y2=1, units="objectBoundingBox"):
    st = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>"
                 for o, c, a in [(s + (None,))[:3] for s in stops])
    return (f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="{units}">{st}'
            f'</linearGradient>')


def rad_grad(gid, stops, cx=0.5, cy=0.5, r=0.5, fx=None, fy=None, units="objectBoundingBox"):
    st = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>"
                 for o, c, a in [(s + (None,))[:3] for s in stops])
    f = f' fx="{fx}" fy="{fy}"' if fx is not None else ""
    return f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}"{f} gradientUnits="{units}">{st}</radialGradient>'


def inked(shapes_d, fill, ink="#070D17", ow=8.0, extra=""):
    """Path(s) with an ink outline drawn underneath (outline width = ow)."""
    return (f'<path d="{shapes_d}" fill="{ink}" stroke="{ink}" stroke-width="{ow * 2:.1f}" stroke-linejoin="round"/>'
            f'<path d="{shapes_d}" fill="{fill}" {extra}/>')


def capsule_d(x0, y0, x1, y1, r0, r1=None):
    """Rounded capsule between two points with end radii r0, r1 (as a polygon path)."""
    r1 = r0 if r1 is None else r1
    a = math.atan2(y1 - y0, x1 - x0)
    pts = []
    for k in range(13):
        t = a + math.pi / 2 + k / 12 * math.pi
        pts.append((x0 + math.cos(t) * r0, y0 + math.sin(t) * r0))
    for k in range(13):
        t = a - math.pi / 2 + k / 12 * math.pi
        pts.append((x1 + math.cos(t) * r1, y1 + math.sin(t) * r1))
    return poly_d(pts)


# ---------------------------------------------------------------------------
# Baseball glove (palm view, fingers up). Local box ~ 0..420 x 0..460.
# ---------------------------------------------------------------------------
def glove(leather="#B8682E", dark="#6E3714", light="#E39A5C", lace="#3A1A08", trim=None,
          ink="#070D17", ow=7.0, pocket=None, web=True, catcher=False, lace_hi=None):
    """Return (defs, body) SVG for a fielding glove or catcher's mitt (catcher=True).

    Local coordinates: about 0..420 x 0..460, fingers pointing up (-y), thumb on the left,
    palm (pocket) facing the viewer.
    """
    gid, pid, wid = uid("lg"), uid("pk"), uid("wb")
    pocket = pocket or dark
    lace_hi = lace_hi or light
    defs = (lin_grad(gid, [(0, light), (0.40, leather), (1, dark)], 80, 30, 360, 460, "userSpaceOnUse")
            + rad_grad(pid, [(0, pocket, 0.85), (0.55, pocket, 0.45), (1, pocket, 0)], 0.5, 0.5, 0.5)
            + lin_grad(wid, [(0, leather), (1, dark)], 0, 0, 1, 1))
    fill = f"url(#{gid})"
    trim = trim or dark
    p = []
    if catcher:
        body_d = ("M215,30 C330,25 410,120 405,245 C400,350 330,440 215,448 C105,452 28,372 24,262 "
                  "C20,165 70,95 120,70 C150,45 180,32 215,30Z")
        thumb_d = capsule_d(85, 340, 40, 185, 62, 50)
        p.append(f'<path d="{thumb_d + body_d}" fill="{ink}" stroke="{ink}" stroke-width="{ow * 2:.1f}" stroke-linejoin="round"/>')
        p.append(f'<path d="{thumb_d}" fill="{fill}"/>')
        p.append(f'<path d="{body_d}" fill="{fill}"/>')
        rim_d = ("M215,58 C315,55 380,135 376,245 C372,335 315,415 215,420 C120,424 55,355 52,262 "
                 "C50,175 92,112 135,92 C160,72 185,60 215,58Z")
        p.append(f'<path d="{rim_d}" fill="none" stroke="{trim}" stroke-width="34"/>')
        p.append(f'<path d="{rim_d}" fill="none" stroke="{light}" stroke-width="3" stroke-opacity="0.45" '
                 f'transform="translate(-4,-6)"/>')
        p.append(f'<ellipse cx="220" cy="240" rx="128" ry="130" fill="url(#{pid})"/>')
        for i in range(22):
            a = -2.75 + i * 0.27
            x = 214 + math.cos(a) * 163
            y = 240 + math.sin(a) * 182
            p.append(f'<rect x="{x - 11:.1f}" y="{y - 4.5:.1f}" width="22" height="9" rx="4" fill="{lace_hi}" '
                     f'stroke="{ink}" stroke-width="2" transform="rotate({math.degrees(a) + 90:.1f} {x:.1f} {y:.1f})"/>')
        p.append(f'<path d="M150,330 C200,352 262,352 302,322" fill="none" stroke="{light}" stroke-width="5" '
                 f'stroke-opacity="0.55" stroke-dasharray="10 9"/>')
        p.append(f'<path d="M95,170 C120,130 150,105 190,92" fill="none" stroke="#FFFFFF" stroke-width="9" '
                 f'stroke-opacity="0.25" stroke-linecap="round"/>')
        return defs, "".join(p)

    fingers = [  # (base x, base y, tip x, tip y, r_base, r_tip)
        (165, 250, 150, 62, 40, 37),
        (222, 245, 222, 40, 40, 37),
        (280, 250, 292, 52, 39, 36),
        (334, 265, 360, 92, 37, 34),
    ]
    palm_d = ("M100,260 C96,345 140,440 232,448 C325,452 388,382 386,300 C385,262 380,232 372,212 "
              "C330,175 140,175 112,205 C104,222 101,240 100,260Z")
    thumb_d = capsule_d(128, 335, 46, 168, 46, 38)
    web_d = "M50,150 C58,98 95,58 130,52 L150,72 C152,130 140,190 118,240 L72,232 C60,205 52,178 50,150Z"
    fds = [capsule_d(*f) for f in fingers]
    union = palm_d + "".join(fds) + thumb_d + (web_d if web else "")
    p.append(f'<path d="{union}" fill="{ink}" stroke="{ink}" stroke-width="{ow * 2:.1f}" stroke-linejoin="round"/>')
    if web:
        p.append(f'<path d="{web_d}" fill="url(#{wid})"/>')
        # basket-weave lacing
        for k in range(4):
            y0 = 92 + k * 38
            p.append(f'<path d="M{60 + k * 4},{y0 + 10} L{140 - k * 3},{y0 - 12}" stroke="{lace}" stroke-width="11" stroke-linecap="round"/>')
            p.append(f'<path d="M{60 + k * 4},{y0 + 10} L{140 - k * 3},{y0 - 12}" stroke="{lace_hi}" stroke-width="3" '
                     f'stroke-opacity="0.45" stroke-linecap="round" transform="translate(0,-3)"/>')
        for k in range(3):
            x0 = 78 + k * 24
            p.append(f'<path d="M{x0},{70 + k * 8} L{x0 + 4},{225 - k * 6}" stroke="{lace}" stroke-width="8" stroke-linecap="round"/>')
    p.append(f'<path d="{thumb_d}" fill="{fill}"/>')
    for fd in fds[::-1]:
        p.append(f'<path d="{fd}" fill="{fill}"/>')
    p.append(f'<path d="{palm_d}" fill="{fill}"/>')
    # pocket shading
    p.append(f'<ellipse cx="238" cy="315" rx="125" ry="112" fill="url(#{pid})"/>')
    # finger separations (fused stalls) from the valleys down into the palm
    for (xa, ya, xb, yb) in ((188, 70, 192, 250), (256, 62, 252, 245), (322, 92, 308, 255)):
        p.append(f'<path d="M{xa},{ya} C{xa + 2},{ya + 60} {xb - 2},{yb - 70} {xb},{yb}" fill="none" stroke="{ink}" '
                 f'stroke-width="5" stroke-linecap="round" stroke-opacity="0.85"/>')
        p.append(f'<path d="M{xa - 7},{ya + 6} C{xa - 5},{ya + 60} {xb - 9},{yb - 70} {xb - 7},{yb}" fill="none" '
                 f'stroke="{light}" stroke-width="3" stroke-opacity="0.35" stroke-linecap="round"/>')
        # lace knots binding the finger tips together
        p.append(f'<rect x="{xa - 13}" y="{ya - 6}" width="26" height="12" rx="5" fill="{lace}" stroke="{ink}" stroke-width="2"/>')
        p.append(f'<rect x="{xa - 9}" y="{ya - 4}" width="12" height="4" rx="2" fill="{lace_hi}" fill-opacity="0.6"/>')
    # finger seam stitching
    for (x0, y0, x1, y1, rb, rt) in fingers:
        p.append(f'<path d="M{x0 - 4:.1f},{y0 - 20:.1f} L{x1 - 4:.1f},{y1 + 4:.1f}" stroke="{light}" stroke-width="3" '
                 f'stroke-opacity="0.45" stroke-dasharray="7 6"/>')
        p.append(f'<path d="M{x1 - rt * 0.55:.1f},{y1 + 6:.1f} A{rt * 0.6:.1f},{rt * 0.6:.1f} 0 0 1 {x1 + rt * 0.2:.1f},{y1 - rt * 0.45:.1f}" '
                 f'fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="6" stroke-linecap="round"/>')
    # thumb edge lacing
    for k in range(6):
        t = k / 5
        x, y = 48 + 70 * t, 175 + 150 * t
        p.append(f'<rect x="{x - 15:.1f}" y="{y - 4:.1f}" width="16" height="8" rx="3.5" fill="{lace}" '
                 f'transform="rotate({-62:.1f} {x:.1f} {y:.1f})"/>')
    # heel binding + palm highlight
    p.append(f'<path d="M140,415 C180,452 292,456 338,405" fill="none" stroke="{trim}" stroke-width="24" stroke-linecap="round"/>')
    p.append(f'<path d="M140,415 C180,452 292,456 338,405" fill="none" stroke="{light}" stroke-width="3.5" '
             f'stroke-opacity="0.55" stroke-dasharray="9 8" transform="translate(0,-15)"/>')
    p.append(f'<path d="M126,270 C130,335 165,392 215,412" fill="none" stroke="#FFFFFF" stroke-width="9" '
             f'stroke-opacity="0.18" stroke-linecap="round"/>')
    p.append(f'<path d="M58,190 C70,150 85,120 100,108" fill="none" stroke="#FFFFFF" stroke-width="7" '
             f'stroke-opacity="0.25" stroke-linecap="round"/>')
    return defs, "".join(p)


# ---------------------------------------------------------------------------
# Small props
# ---------------------------------------------------------------------------
def home_plate_poly(g, X=0.0, Z=4.0, size=0.43):
    """Screen polygon for home plate lying on Ground g (point facing the camera)."""
    s = size
    pts = [(-s / 2, s / 2), (s / 2, s / 2), (s / 2, 0.0), (0.0, -s / 2), (-s / 2, 0.0)]
    return [g.project(X + px, Z + pz) for px, pz in pts]


def base_bag_svg(g, X, Z, size=0.38, height=0.07, ink="#070D17", top="#F4F1EA", side="#B9BCC6"):
    s = size / 2
    corners = [(-s, -s), (s, -s), (s, s), (-s, s)]
    top_pts = [g.project(X + cx, Z + cz) for cx, cz in corners]
    sc = g.scale_at(Z)
    hpx = height * sc
    top_pts = [(x, y - hpx) for x, y in top_pts]
    bot_pts = [g.project(X + cx, Z + cz) for cx, cz in corners]
    side_poly = [bot_pts[3], bot_pts[2], top_pts[2], top_pts[3]]
    side2 = [bot_pts[0], bot_pts[3], top_pts[3], top_pts[0]]
    allp = poly_d(top_pts) + poly_d(side_poly) + poly_d(side2)
    return (f'<path d="{allp}" fill="{ink}" stroke="{ink}" stroke-width="10" stroke-linejoin="round"/>'
            f'<path d="{poly_d(side_poly)}" fill="{side}"/><path d="{poly_d(side2)}" fill="{side}"/>'
            f'<path d="{poly_d(top_pts)}" fill="{top}"/>')


def stopwatch(cx, cy, r, ink="#070D17", rim="#C9D3E0", face="#F4F7FB", accent="#E0262F", hand_angle=-40):
    gid, fid = uid("sw"), uid("swf")
    defs = (lin_grad(gid, [(0, "#FFFFFF"), (0.35, rim), (0.7, "#7D8796"), (1, "#3A4352")], 0.2, 0, 0.8, 1)
            + rad_grad(fid, [(0, "#FFFFFF"), (0.75, face), (1, "#B8C4D4")], 0.42, 0.38, 0.65))
    p = []
    # crown + buttons
    p.append(f'<rect x="{cx - r * 0.13:.1f}" y="{cy - r * 1.32:.1f}" width="{r * 0.26:.1f}" height="{r * 0.26:.1f}" rx="{r * 0.04:.1f}" '
             f'fill="url(#{gid})" stroke="{ink}" stroke-width="{r * 0.05:.1f}"/>')
    p.append(f'<rect x="{cx - r * 0.22:.1f}" y="{cy - r * 1.42:.1f}" width="{r * 0.44:.1f}" height="{r * 0.14:.1f}" rx="{r * 0.05:.1f}" '
             f'fill="url(#{gid})" stroke="{ink}" stroke-width="{r * 0.05:.1f}"/>')
    for a in (-45, 45):
        x = cx + math.sin(math.radians(a)) * r * 1.08
        y = cy - math.cos(math.radians(a)) * r * 1.08
        p.append(f'<rect x="{x - r * 0.09:.1f}" y="{y - r * 0.12:.1f}" width="{r * 0.18:.1f}" height="{r * 0.2:.1f}" rx="{r * 0.03:.1f}" '
                 f'fill="url(#{gid})" stroke="{ink}" stroke-width="{r * 0.045:.1f}" transform="rotate({a} {x:.1f} {y:.1f})"/>')
    p.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 1.04:.1f}" fill="{ink}"/>')
    p.append(f'<circle cx="{cx}" cy="{cy}" r="{r:.1f}" fill="url(#{gid})"/>')
    p.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 0.84:.1f}" fill="{ink}"/>')
    p.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 0.80:.1f}" fill="url(#{fid})"/>')
    for i in range(60):
        a = math.radians(i * 6)
        l = 0.12 if i % 5 == 0 else 0.06
        w = r * (0.025 if i % 5 == 0 else 0.012)
        x0, y0 = cx + math.sin(a) * r * 0.74, cy - math.cos(a) * r * 0.74
        x1, y1 = cx + math.sin(a) * r * (0.74 - l), cy - math.cos(a) * r * (0.74 - l)
        p.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{ink}" stroke-width="{w:.1f}"/>')
    # red sweep sector + hand
    a0, a1 = math.radians(0), math.radians(hand_angle)
    p.append(f'<path d="M{cx},{cy} L{cx + math.sin(a0) * r * 0.6:.1f},{cy - math.cos(a0) * r * 0.6:.1f} '
             f'A{r * 0.6:.1f},{r * 0.6:.1f} 0 0 0 {cx + math.sin(a1) * r * 0.6:.1f},{cy - math.cos(a1) * r * 0.6:.1f}Z" '
             f'fill="{accent}" fill-opacity="0.25"/>')
    hx, hy = cx + math.sin(a1) * r * 0.68, cy - math.cos(a1) * r * 0.68
    p.append(f'<line x1="{cx}" y1="{cy}" x2="{hx:.1f}" y2="{hy:.1f}" stroke="{accent}" stroke-width="{r * 0.045:.1f}" stroke-linecap="round"/>')
    p.append(f'<line x1="{cx}" y1="{cy}" x2="{cx + math.sin(a1 + math.pi) * r * 0.15:.1f}" y2="{cy - math.cos(a1 + math.pi) * r * 0.15:.1f}" '
             f'stroke="{accent}" stroke-width="{r * 0.06:.1f}" stroke-linecap="round"/>')
    p.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 0.06:.1f}" fill="{ink}"/>')
    # glass highlight
    p.append(f'<path d="M{cx - r * 0.62:.1f},{cy - r * 0.15:.1f} A{r * 0.66:.1f},{r * 0.66:.1f} 0 0 1 {cx + r * 0.2:.1f},{cy - r * 0.62:.1f}" '
             f'fill="none" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="{r * 0.06:.1f}" stroke-linecap="round"/>')
    return defs, "".join(p)


def padlock(cx, cy, s, ink="#070D17", body="#F5B82E", dark="#A86A12", light="#FFE7A0", shackle="#C9D3E0"):
    gid, sid = uid("pl"), uid("sh")
    defs = (lin_grad(gid, [(0, light), (0.45, body), (1, dark)], 0, 0, 0.3, 1)
            + lin_grad(sid, [(0, "#FFFFFF"), (0.5, shackle), (1, "#5A6576")], 0, 0, 1, 0))
    w, h = s, s * 0.8
    p = []
    sh_d = (f"M{cx - w * 0.30:.1f},{cy - h * 0.15:.1f} L{cx - w * 0.30:.1f},{cy - h * 0.62:.1f} "
            f"A{w * 0.30:.1f},{w * 0.30:.1f} 0 0 1 {cx + w * 0.30:.1f},{cy - h * 0.62:.1f} L{cx + w * 0.30:.1f},{cy - h * 0.15:.1f}")
    p.append(f'<path d="{sh_d}" fill="none" stroke="{ink}" stroke-width="{w * 0.17:.1f}"/>')
    p.append(f'<path d="{sh_d}" fill="none" stroke="url(#{sid})" stroke-width="{w * 0.10:.1f}"/>')
    rect = f'x="{cx - w / 2:.1f}" y="{cy - h * 0.2:.1f}" width="{w:.1f}" height="{h * 0.8:.1f}" rx="{w * 0.12:.1f}"'
    p.append(f'<rect {rect} fill="{ink}" stroke="{ink}" stroke-width="{w * 0.08:.1f}"/>')
    p.append(f'<rect {rect} fill="url(#{gid})"/>')
    p.append(f'<rect x="{cx - w * 0.42:.1f}" y="{cy - h * 0.13:.1f}" width="{w * 0.84:.1f}" height="{h * 0.08:.1f}" rx="{w * 0.03:.1f}" '
             f'fill="#FFFFFF" fill-opacity="0.45"/>')
    p.append(f'<circle cx="{cx}" cy="{cy + h * 0.15:.1f}" r="{w * 0.09:.1f}" fill="{ink}"/>')
    p.append(f'<path d="M{cx - w * 0.04:.1f},{cy + h * 0.17:.1f} L{cx - w * 0.06:.1f},{cy + h * 0.42:.1f} '
             f'L{cx + w * 0.06:.1f},{cy + h * 0.42:.1f} L{cx + w * 0.04:.1f},{cy + h * 0.17:.1f}Z" fill="{ink}"/>')
    return defs, "".join(p)


def chain_links(pts, link_len, link_w, color="#8FD3FF", ink="#070D17", core="#FFFFFF"):
    """Chain of interlocking links placed along a polyline."""
    pts = np.asarray(pts, float)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    L = np.concatenate([[0], np.cumsum(seg)])
    out = []
    n = int(L[-1] / (link_len * 0.78))
    for i in range(n):
        s = (i + 0.5) * link_len * 0.78
        x = np.interp(s, L, pts[:, 0])
        y = np.interp(s, L, pts[:, 1])
        s2 = min(L[-1], s + 1)
        x2, y2 = np.interp(s2, L, pts[:, 0]), np.interp(s2, L, pts[:, 1])
        ang = math.degrees(math.atan2(y2 - y, x2 - x))
        flat = i % 2 == 1
        ry = link_w * (0.18 if flat else 0.5)
        sw = link_w * 0.22
        out.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{link_len / 2:.1f}" ry="{ry:.1f}" fill="none" stroke="{ink}" '
                   f'stroke-width="{sw * 1.9:.1f}" transform="rotate({ang:.1f} {x:.1f} {y:.1f})"/>')
        out.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{link_len / 2:.1f}" ry="{ry:.1f}" fill="none" stroke="{color}" '
                   f'stroke-width="{sw:.1f}" transform="rotate({ang:.1f} {x:.1f} {y:.1f})"/>')
        out.append(f'<ellipse cx="{x:.1f}" cy="{y - ry * 0.3:.1f}" rx="{link_len / 2 * 0.8:.1f}" ry="{max(1, ry * 0.6):.1f}" fill="none" '
                   f'stroke="{core}" stroke-opacity="0.6" stroke-width="{sw * 0.35:.1f}" stroke-dasharray="{link_len * 0.5:.1f} {link_len * 2:.1f}" '
                   f'transform="rotate({ang:.1f} {x:.1f} {y:.1f})"/>')
    return "".join(out)


# ---------------------------------------------------------------------------
# Hands, whistle, cleat, text glyphs
# ---------------------------------------------------------------------------
def glyph_d(ch, family="Bangers", size=100.0):
    from .core import text_outline, cmds_to_d
    cmds, e = text_outline(ch, family, size)
    return cmds_to_d(cmds), e


def ghost_hand_d(curl=0.5):
    """Clawed open hand, wrist at (0, 0) pointing up (-y). Roughly 160 wide, 300 tall."""
    pts = []
    # wrist left -> palm left
    pts += [(-38, 0), (-46, -70), (-62, -110)]
    # thumb
    pts += [(-98, -128), (-122, -160), (-118, -176), (-100, -168), (-70, -140), (-52, -150)]
    fingers = [(-46, -150, -60, -250), (-16, -160, -20, -290), (16, -158, 22, -282), (46, -146, 60, -238)]
    for i, (bx, by, tx, ty) in enumerate(fingers):
        cx = tx + curl * 22 * (1 if tx > 0 else -1) * 0.3
        pts += [(bx - 10, by), (tx - 12, ty + 30), (tx - 4, ty), (cx + 8, ty + 18 * curl), (tx + 10, ty + 34), (bx + 12, by + 4)]
    pts += [(62, -120), (48, -70), (38, 0)]
    return poly_d(pts)


def whistle(cx, cy, s, ink="#070D17", metal="#C9D3E0", dark="#5A6576", light="#FFFFFF", cord="#E0262F"):
    gid = uid("wh")
    defs = lin_grad(gid, [(0, light), (0.4, metal), (1, dark)], 0, 0, 0.3, 1)
    p = []
    body = (f"M{cx - s * 1.3:.1f},{cy - s * 0.42:.1f} L{cx + s * 0.1:.1f},{cy - s * 0.42:.1f} "
            f"A{s * 0.62:.1f},{s * 0.62:.1f} 0 1 1 {cx + s * 0.1:.1f},{cy + s * 0.52:.1f} "
            f"L{cx - s * 1.3:.1f},{cy + s * 0.1:.1f}Z")
    p.append(f'<path d="{body}" fill="{ink}" stroke="{ink}" stroke-width="{s * 0.16:.1f}" stroke-linejoin="round"/>')
    p.append(f'<path d="{body}" fill="url(#{gid})"/>')
    p.append(f'<rect x="{cx - s * 1.3:.1f}" y="{cy - s * 0.42:.1f}" width="{s * 0.35:.1f}" height="{s * 0.52:.1f}" fill="{dark}" fill-opacity="0.5"/>')
    p.append(f'<path d="M{cx - s * 0.6:.1f},{cy - s * 0.42:.1f} L{cx - s * 0.6:.1f},{cy - s * 0.2:.1f} L{cx - s * 0.3:.1f},{cy - s * 0.2:.1f} '
             f'L{cx - s * 0.3:.1f},{cy - s * 0.42:.1f}" fill="{ink}"/>')
    p.append(f'<circle cx="{cx + s * 0.25:.1f}" cy="{cy - s * 0.95:.1f}" r="{s * 0.2:.1f}" fill="none" stroke="{ink}" stroke-width="{s * 0.16:.1f}"/>')
    p.append(f'<circle cx="{cx + s * 0.25:.1f}" cy="{cy - s * 0.95:.1f}" r="{s * 0.2:.1f}" fill="none" stroke="{metal}" stroke-width="{s * 0.08:.1f}"/>')
    p.append(f'<path d="M{cx - s * 0.9:.1f},{cy - s * 0.3:.1f} L{cx - s * 0.0:.1f},{cy - s * 0.3:.1f}" stroke="#FFFFFF" '
             f'stroke-opacity="0.8" stroke-width="{s * 0.07:.1f}" stroke-linecap="round"/>')
    return defs, "".join(p)


def flat_hand_svg(length=230.0, width=76.0, skin="#F4F1EA", shade="#B9C2D0", ink="#070D17", sleeve=True):
    """Flat hand (fingers together) pointing +x with the wrist at x=0, thumb on top; optional
    black/white striped referee sleeve extending to negative x. Returns SVG markup."""
    L, Wd = length, width
    palm = (f"M0,{-Wd * 0.45:.1f} L{L * 0.42:.1f},{-Wd * 0.50:.1f} L{L * 0.95:.1f},{-Wd * 0.46:.1f} "
            f"C{L * 1.03:.1f},{-Wd * 0.44:.1f} {L * 1.03:.1f},{Wd * 0.44:.1f} {L * 0.95:.1f},{Wd * 0.46:.1f} "
            f"L{L * 0.40:.1f},{Wd * 0.50:.1f} L0,{Wd * 0.45:.1f}Z")
    thumb = (f"M{L * 0.10:.1f},{-Wd * 0.40:.1f} C{L * 0.22:.1f},{-Wd * 0.95:.1f} {L * 0.45:.1f},{-Wd * 0.95:.1f} "
             f"{L * 0.52:.1f},{-Wd * 0.72:.1f} C{L * 0.56:.1f},{-Wd * 0.58:.1f} {L * 0.45:.1f},{-Wd * 0.48:.1f} {L * 0.35:.1f},{-Wd * 0.45:.1f}Z")
    p = []
    if sleeve:
        sl = f"M{-L * 0.55:.1f},{-Wd * 0.62:.1f} L{L * 0.02:.1f},{-Wd * 0.58:.1f} L{L * 0.02:.1f},{Wd * 0.58:.1f} L{-L * 0.55:.1f},{Wd * 0.62:.1f}Z"
        p.append(f'<path d="{sl}" fill="{ink}" stroke="{ink}" stroke-width="14" stroke-linejoin="round"/>')
        p.append(f'<path d="{sl}" fill="#F4F1EA"/>')
        for k in range(3):
            x0 = -L * 0.50 + k * L * 0.18
            p.append(f'<rect x="{x0:.1f}" y="{-Wd * 0.62:.1f}" width="{L * 0.085:.1f}" height="{Wd * 1.24:.1f}" fill="{ink}"/>')
    p.append(f'<path d="{palm}{thumb}" fill="{ink}" stroke="{ink}" stroke-width="14" stroke-linejoin="round"/>')
    p.append(f'<path d="{palm}" fill="{skin}"/><path d="{thumb}" fill="{skin}"/>')
    for k in (-0.18, 0.05, 0.27):
        p.append(f'<path d="M{L * 0.55:.1f},{Wd * k:.1f} L{L * 0.97:.1f},{Wd * k:.1f}" stroke="{shade}" stroke-width="4" stroke-linecap="round"/>')
    p.append(f'<path d="M{L * 0.30:.1f},{-Wd * 0.40:.1f} C{L * 0.38:.1f},{-Wd * 0.3:.1f} {L * 0.45:.1f},{-Wd * 0.3:.1f} {L * 0.52:.1f},{-Wd * 0.42:.1f}" '
             f'fill="none" stroke="{shade}" stroke-width="4" stroke-linecap="round"/>')
    p.append(f'<path d="M{L * 0.1:.1f},{Wd * 0.40:.1f} L{L * 0.85:.1f},{Wd * 0.40:.1f}" stroke="{shade}" stroke-width="8" stroke-opacity="0.7" stroke-linecap="round"/>')
    return "".join(p)


def cleat(x, y, s, ink="#070D17", body="#2B2F36", accent="#FF7A1A", sole="#14171C", flip=False):
    """Side view of a cleat (toe pointing +x unless flip). Origin = heel bottom. s ~ length."""
    k = -1 if flip else 1
    def P(px, py):
        return f"{x + k * px * s:.1f},{y + py * s:.1f}"
    upper = (f"M{P(0.02, -0.02)} L{P(0.0, -0.42)} C{P(0.02, -0.52)} {P(0.18, -0.55)} {P(0.30, -0.50)} "
             f"L{P(0.52, -0.36)} C{P(0.75, -0.32)} {P(0.97, -0.25)} {P(1.0, -0.10)} L{P(0.98, -0.02)}Z")
    sole_d = f"M{P(0.0, -0.05)} L{P(1.0, -0.06)} L{P(0.99, 0.03)} L{P(0.01, 0.03)}Z"
    spikes = "".join(f'<path d="M{P(t - 0.03, 0.03)} L{P(t, 0.12)} L{P(t + 0.03, 0.03)}Z" fill="#9AA3AE" stroke="{ink}" stroke-width="{s * 0.012:.1f}"/>'
                     for t in (0.1, 0.32, 0.6, 0.8, 0.93))
    p = [f'<path d="{upper}" fill="{ink}" stroke="{ink}" stroke-width="{s * 0.05:.1f}" stroke-linejoin="round"/>',
         f'<path d="{sole_d}" fill="{ink}" stroke="{ink}" stroke-width="{s * 0.05:.1f}" stroke-linejoin="round"/>', spikes,
         f'<path d="{upper}" fill="{body}"/>', f'<path d="{sole_d}" fill="{sole}"/>']
    # swoosh stripe + laces + highlight
    p.append(f'<path d="M{P(0.12, -0.12)} C{P(0.4, -0.12)} {P(0.6, -0.2)} {P(0.85, -0.18)}" fill="none" stroke="{accent}" '
             f'stroke-width="{s * 0.05:.1f}" stroke-linecap="round"/>')
    for t in (0.36, 0.44, 0.52, 0.60):
        p.append(f'<path d="M{P(t, -0.47 + (t - 0.36) * 0.5)} L{P(t + 0.05, -0.36 + (t - 0.36) * 0.4)}" stroke="#D9DEE6" '
                 f'stroke-width="{s * 0.02:.1f}" stroke-linecap="round"/>')
    p.append(f'<path d="M{P(0.05, -0.4)} C{P(0.08, -0.48)} {P(0.18, -0.5)} {P(0.28, -0.46)}" fill="none" stroke="#FFFFFF" '
             f'stroke-opacity="0.35" stroke-width="{s * 0.02:.1f}" stroke-linecap="round"/>')
    return "".join(p)
