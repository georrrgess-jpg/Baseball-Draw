"""Small geometry helpers shared by the hero_* modelling mixins."""
import math
import numpy as np

import geo
from geo import A, unit

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def rot_about(axis, deg):
    a = unit(axis)
    t = math.radians(deg)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


def superellipsoid(center, radii, rot=None, nu=16, nv=10, e1=2.0, e2=2.0, squash=None):
    """Superellipsoid UV grid (poles on local z).  e1 = profile exponent
    around (x/y), e2 = vertical exponent.  Returns verts, faces."""
    c = A(center)
    r = A(radii)
    R = np.eye(3) if rot is None else A(rot)
    rows = []
    for j in range(1, nv):
        th = -math.pi / 2 + math.pi * j / nv
        cv, sv = geo.superellipse(np.array([th]), e2)
        row = []
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            cu, su = geo.superellipse(np.array([ph]), e1)
            p = np.array([cv[0] * cu[0], cv[0] * su[0], sv[0]]) * r
            if squash is not None:
                p = squash(p)
            row.append(c + R @ p)
        rows.append(row)
    top = c + R @ (np.array([0, 0, 1.0]) * r)
    bot = c + R @ (np.array([0, 0, -1.0]) * r)
    # sphere_mesh_from_rows expects rows from top to bottom
    return geo.sphere_mesh_from_rows(A(rows[::-1]), top, bot)


def orient_outward(verts, faces, inside):
    """Flip all faces if most normals point toward ``inside``."""
    v = A(verts)
    score = 0.0
    for f in faces[:: max(1, len(faces) // 200)]:
        p0, p1, p2 = v[f[0]], v[f[1]], v[f[2]]
        n = np.cross(p1 - p0, p2 - p0)
        score += np.sign(np.dot(n, p0 - A(inside)))
    if score < 0:
        return [tuple(reversed(f)) for f in faces]
    return faces


def ray_poly(p0, d, poly):
    """Distance along ray p0 + t*d to the first crossing of a closed 2D
    polygon (p0 inside)."""
    best = 1e9
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        e = b - a
        den = d[0] * (-e[1]) - d[1] * (-e[0])
        if abs(den) < 1e-12:
            continue
        w = a - p0
        t = (w[0] * (-e[1]) - w[1] * (-e[0])) / den
        u = (d[0] * w[1] - d[1] * w[0]) / den
        if t > 0 and -1e-9 <= u <= 1 + 1e-9:
            best = min(best, t)
    return best


def column_dirs(phi, betas):
    """Unit directions for azimuth phi (0 = front, + toward the character's
    left) and elevations betas (radians)."""
    b = np.asarray(betas, float)
    return np.stack([np.cos(b) * math.sin(phi), -np.cos(b) * math.cos(phi), np.sin(b)], 1)


# ---------------------------------------------------------------------------
# the builder
# ---------------------------------------------------------------------------
