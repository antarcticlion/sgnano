#!/usr/bin/env python3
"""NEON CIRCUIT - polygon edition: offline scene generator (sgnano / mruby).

The camera choreography, road, city layout and racers are the same as the
wireframe "Open Road" edition. This generator turns the scene into flat-shaded
polygons for Machine::FrameBuffer#fill_triangle:

  * 3D faces are back-face culled, clipped against the near plane, projected,
    clipped to the 640x480 screen and fan-triangulated.
  * Faces are lit (one directional light) and fogged with distance, then
    quantized into a shared palette.
  * A host-side z-buffer (half resolution) removes triangles that are fully
    hidden, so the device only draws what can be seen. The rest is drawn in
    painter's order (far to near), which the device simply follows.
  * Neon edges are drawn on top of the faces; hidden parts are removed with the
    same z-buffer.

Output: NEON_CIRCUIT_POLY.DAT (little-endian)
  "NCP1", u16 frames, u8 fps, u8 reserved, u16 palette_count,
  palette_count * (r, g, b) bytes (0..255), frames * u32 frame offset,
  then per frame: s16 tri_count, s16 line_count, s16 horizon_y, s16 sun_x,
  tri_count * s16 (x0, y0, x1, y1, x2, y2, color),
  line_count * s16 (x0, y0, x1, y1, color).
All coordinates are already inside 0..639 / 0..479 except horizon_y / sun_x.

Requires Python 3 + NumPy (+ Pillow for --preview).
"""
from __future__ import annotations
import argparse, math, struct, time
from pathlib import Path
import numpy as np

W, H = 640, 480
ZW, ZH = W // 2, H // 2               # z-buffer resolution
NEAR = 10.0
DURATION = 50.0
FPS = 4
MAX_TRIS = 170
MAX_LINES = 72
MIN_VISIBLE = 2                       # z-buffer cells a triangle must own to be kept

# Neon base colors (same IDs as the wireframe edition)
BLACK, BLUE, CYAN, VIOLET, HOTPINK, AMBER, LIME, STEEL, SKYBLUE, WHITE = range(10)
RGB = {
    BLACK: (0, 0, 0), BLUE: (20, 35, 255), CYAN: (0, 235, 255),
    VIOLET: (145, 55, 255), HOTPINK: (255, 45, 190), AMBER: (255, 185, 25),
    LIME: (100, 255, 90), STEEL: (45, 65, 120), SKYBLUE: (40, 125, 255),
    WHITE: (255, 255, 255),
}
ASPHALT = (34, 30, 70)
LIGHT = np.array([-0.45, 0.80, -0.40]); LIGHT /= np.linalg.norm(LIGHT)

# Device cost model (measured on the target, mode 2, 2026-10-16): fill_triangle
# about 0.8 ms a call plus 0.22 us a pixel, line about 0.4 ms, background 51 ms.
def est_ms(tris, area, lines):
    return 51 + tris * 0.8 + area * 0.00022 + lines * 0.4


class Obj:
    """One object for painter's sorting: faces, edges and a sort layer."""
    __slots__ = ('layer', 'faces', 'edges', 'center')

    def __init__(s, layer, center):
        s.layer = layer; s.faces = []; s.edges = []; s.center = center


class Scene:
    def __init__(s):
        s.objs = []

    # face: (vertices [(x,y,z)...] convex, base rgb, mode) mode: 'lit' | 'emit' | 'flat2' (double sided, lit)
    def box(s, x, y, z, w, h, d, base, edge_col, layer=2, edges=True, roof_mul=1.25, extra_edges=()):
        c = (x + w / 2, y + h / 2, z + d / 2)
        o = Obj(layer, c)
        p = [(x, y, z), (x + w, y, z), (x + w, y + h, z), (x, y + h, z),
             (x, y, z + d), (x + w, y, z + d), (x + w, y + h, z + d), (x, y + h, z + d)]
        quads = [(0, 1, 2, 3), (5, 4, 7, 6), (4, 0, 3, 7), (1, 5, 6, 2), (3, 2, 6, 7), (4, 5, 1, 0)]
        for qi, q in enumerate(quads):
            col = tuple(min(255, int(v * roof_mul)) for v in base) if qi == 4 else base
            o.faces.append(([p[i] for i in q], col, 'lit', c))
        if edges:
            for a, b in [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]:
                o.edges.append((p[a], p[b], edge_col, 4))
        for e in extra_edges:
            o.edges.append(e)
        s.objs.append(o)
        return o

    @staticmethod
    def curve_delta(z, scroll):
        return math.sin((scroll + z) * 0.00165) * 34.0 - math.sin(scroll * 0.00165) * 34.0

    @staticmethod
    def wrap_depth(z, near, span):
        while z < near: z += span
        lim = near + span
        while z >= lim: z -= span
        return z

    def add_road(self, scroll, frame):
        zs = [-360, -270, -205, -155, -115, -82, -55, -32, -14, 0, 12, 18, 25, 34, 46, 61, 80, 104, 134, 172, 220, 280, 356, 450, 566, 710, 890, 1100, 1340, 1600, 1880]
        for i in range(len(zs) - 1):
            z0, z1 = zs[i], zs[i + 1]
            c0, c1 = self.curve_delta(z0, scroll), self.curve_delta(z1, scroll)
            o = Obj(0, (c0, -4, (z0 + z1) / 2))
            # two lanes, slightly different tone (reads as a road at a glance)
            for k, (a, b) in enumerate(((-52, 0), (0, 52))):
                col = ASPHALT if k == 0 else (40, 34, 80)
                o.faces.append(([(c0 + a, -4, z0), (c0 + b, -4, z0), (c1 + b, -4, z1), (c1 + a, -4, z1)], col, 'up', None))
            o.edges.append(((c0 - 52, -4, z0), (c1 - 52, -4, z1), SKYBLUE, 3))
            o.edges.append(((c0 + 52, -4, z0), (c1 + 52, -4, z1), SKYBLUE, 3))
            self.objs.append(o)
        # lane dashes: thin emissive quads lying on the road. 2026-11-15: they move with the road
        # (shifted by scroll, a 30-unit dash every 58); before, they stood still and blinked every
        # third frame, which did not read as motion.
        z = -360. - (scroll % 58.0)
        while z < 1500:
            z2 = z + 30
            ca, cb = self.curve_delta(z, scroll), self.curve_delta(z2, scroll)
            o = Obj(1, (ca, -3.7, z + 15))
            for side in (-17, 17):
                o.faces.append(([(ca + side - 1.2, -3.7, z), (ca + side + 1.2, -3.7, z), (cb + side + 1.2, -3.7, z2), (cb + side - 1.2, -3.7, z2)], RGB[CYAN], 'emit', None))
            self.objs.append(o)
            z += 58
        # side rails: low walls along both edges
        z = -360.
        while z < 1450:
            z2 = z + 75
            ca, cb = self.curve_delta(z, scroll), self.curve_delta(z2, scroll)
            for side in (-1, 1):
                x1 = ca + side * 56; x2 = cb + side * 56
                o = Obj(2, (x1, 0, z + 37))
                o.faces.append(([(x1, -1.8, z), (x2, -1.8, z2), (x2, 2.5, z2), (x1, 2.5, z)], (20, 60, 150), 'rail', None))
                o.edges.append(((x1, 2.5, z), (x2, 2.5, z2), CYAN, 2))
                self.objs.append(o)
            z += 75

    def add_city(self, scroll):
        for i in range(20):
            side = -1 if i % 2 == 0 else 1; distance = 92 + ((i * 47) % 155); w = 22 + ((i * 13) % 34)
            h = 85 + ((i * 67) % 205); d = 35 + ((i * 19) % 56); base_z = 80 + ((i * 173) % 1660)
            col = [BLUE, CYAN, VIOLET, HOTPINK, SKYBLUE][i % 5]; accent = [STEEL, SKYBLUE, VIOLET, CYAN][i % 4]
            # Keep the building until it is behind the camera (near = -120) so it does not
            # vanish while still visible at the side of the screen. The span keeps the far
            # end at about the same distance as before.
            z = self.wrap_depth(base_z - scroll, -120, 1950); curve = self.curve_delta(z, scroll)
            x = (-distance - w + curve) if side < 0 else (distance + curve)
            y = -24
            base = tuple(int(v * 0.30) + 12 for v in RGB[col])
            extra = []
            # window bands on the face toward the road and on the near face
            levels = min(5, int(h) // 26)
            fx = x + w if side < 0 else x
            for level in range(1, levels + 1):
                yy = y + h * level / (levels + 1)
                extra.append(((x, yy, z), (x + w, yy, z), accent, 5))
                extra.append(((fx, yy, z), (fx, yy, z + d), accent, 5))
            self.box(x, y, z, w, h, d, base, col, extra_edges=extra)
        # the piers under the elevated road, every 210. 2026-11-15: they move with the road like the
        # buildings (wrapped behind the camera); before, they stood at fixed distances from the
        # camera and seemed to follow the cars.
        for i in range(9):
            z = self.wrap_depth(95 + i * 210 - scroll, -120, 1890)
            c = self.curve_delta(z, scroll)
            self.box(c - 59, -74, z, 4, 70, 5, (70, 30, 120), VIOLET, edges=False)
            self.box(c + 55, -74, z, 4, 70, 5, (70, 30, 120), VIOLET, edges=False)

    def add_gantry(self, scroll):
        for i in range(4):
            base_z = 210 + i * 420; z = self.wrap_depth(base_z - scroll, -120, 1950); c = self.curve_delta(z, scroll)
            self.box(c - 59, -4, z, 4, 49, 4, (0, 110, 130), CYAN, edges=False)
            self.box(c + 55, -4, z, 4, 49, 4, (0, 110, 130), CYAN, edges=False)
            beam = self.box(c - 59, 41, z, 118, 5, 5, (20, 70, 150), SKYBLUE, edges=False)
            beam.edges.append(((c - 59, 46, z), (c + 59, 46, z), CYAN, 2))
            beam.edges.append(((c - 55, 35, z - .5), (c + 55, 35, z - .5), HOTPINK, 2))

    def add_car(self, cx, z, color, accent, variant):
        rear_z = z - 14.0; front_z = z + 12.0; rear_w = 19.0; front_w = 11.0
        bot_y = -1.6; rear_y = 3.6; front_y = 2.0
        v = [(cx - rear_w, bot_y, rear_z), (cx + rear_w, bot_y, rear_z), (cx + front_w, bot_y, front_z), (cx - front_w, bot_y, front_z),
             (cx - rear_w, rear_y, rear_z + 1.5), (cx + rear_w, rear_y, rear_z + 1.5), (cx + front_w, front_y, front_z - 1), (cx - front_w, front_y, front_z - 1)]
        c = (cx, 1.0, z)
        o = Obj(2, c)
        body = tuple(int(x * 0.75) for x in RGB[color])
        for q in [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]:
            o.faces.append(([v[i] for i in q], body, 'lit', c))
        # cockpit canopy, sitting slightly above the deck
        cp = [(cx - 6, 3.4, z - 6.5), (cx + 6, 3.4, z - 6.5), (cx + 4.2, 6.6, z + 2.8), (cx - 4.2, 6.6, z + 2.8)]
        o.faces.append((cp, RGB[accent], 'emit', None))
        for a, b, col in [(0, 1, color), (4, 5, color), (0, 4, accent), (1, 5, accent), (4, 7, color), (5, 6, color), (6, 7, color), (1, 2, color), (0, 3, color)]:
            o.edges.append((v[a], v[b], col, 0))
        for i in range(4):
            o.edges.append((cp[i], cp[(i + 1) % 4], WHITE, 0))
        # thrusters
        o.edges.append(((cx - 8, -.2, rear_z - .5), (cx - 2, -.2, rear_z - .5), AMBER, 0))
        o.edges.append(((cx + 2, -.2, rear_z - .5), (cx + 8, -.2, rear_z - .5), AMBER, 0))
        if variant == 1:
            f = [(cx - 15, -1.8, z - 1), (cx - 21, -1.2, z + 3), (cx - 15, -.8, z + 5)]
        else:
            f = [(cx + 15, -1.8, z - 1), (cx + 21, -1.2, z + 3), (cx + 15, -.8, z + 5)]
        o.faces.append((f, RGB[accent], 'emit2', None))
        self.objs.append(o)

    def add_racers(self, race_t, scroll):
        # 2026-11-02: the old piecewise choreography jumped at 10 s / 25 s / 36 s
        # (the cars teleported to the other lane). Use key frames and a smoothstep
        # between them; the first two keys keep the cars in their lanes, then the
        # lane change from 10..14 s and the swap back from 25..29 s glide across.
        def keyed(t, keys):
            if t <= keys[0][0]: return keys[0][1], keys[0][2]
            for i in range(1, len(keys)):
                if t <= keys[i][0]:
                    u = (t - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])
                    u = u * u * (3.0 - 2.0 * u)
                    return (keys[i - 1][1] + (keys[i][1] - keys[i - 1][1]) * u,
                            keys[i - 1][2] + (keys[i][2] - keys[i - 1][2]) * u)
            return keys[-1][1], keys[-1][2]
        # (t, z, x): z is the distance ahead of the camera, x the lane offset.
        A = [(0.0, 80.0, -22.0), (6.0, 112.0, -22.0), (10.0, 150.0, -22.0),
             (14.0, 145.0, 20.0), (20.0, 155.0, 20.0), (25.0, 145.0, 20.0),
             (29.0, 150.0, -22.0), (36.0, 150.0, -21.0), (46.0, 174.0, -21.0)]
        B = [(0.0, 128.0, 22.0), (6.0, 128.0, 22.0), (10.0, 128.0, 22.0),
             (14.0, 112.0, -20.0), (20.0, 104.0, -20.0), (25.0, 98.0, -20.0),
             (29.0, 108.0, 22.0), (36.0, 108.0, 21.0), (46.0, 108.0, 21.0)]
        za, xa = keyed(race_t, A); zb, xb = keyed(race_t, B)
        # A little continuous weave; it never crosses lanes on its own.
        za += math.sin(race_t * .34) * 3.0; xa += math.sin(race_t * .45) * 2.5
        zb += math.cos(race_t * .29) * 2.5; xb += math.sin(race_t * .39 + 1.0) * 2.5
        ca = self.curve_delta(za, scroll); cb = self.curve_delta(zb, scroll)
        self.add_car(ca + xa, za, CYAN, LIME, 1); self.add_car(cb + xb, zb, HOTPINK, AMBER, 2)

    def add_finish_line(self, race_t, scroll):
        if race_t < 37 or race_t > 43.8: return
        z = max(18, 340 - (race_t - 37) * 76); c = self.curve_delta(z, scroll)
        o = Obj(1, (c, -3.55, z))
        div = 16
        for row in range(2):
            for i in range(div):
                x1 = c - 50 + 100 * i / div; x2 = c - 50 + 100 * (i + 1) / div
                z0 = z + row * 6.25; z1 = z0 + 6.25
                col = RGB[WHITE] if (i + row) % 2 == 0 else (60, 10, 50)
                o.faces.append(([(x1, -3.55, z0), (x2, -3.55, z0), (x2, -3.55, z1), (x1, -3.55, z1)], col, 'emit', None))
        self.objs.append(o)
        self.box(c - 57, -4, z, 4, 52, 4, (0, 120, 140), CYAN, edges=False)
        self.box(c + 53, -4, z, 4, 52, 4, (0, 120, 140), CYAN, edges=False)
        top = self.box(c - 57, 48, z, 114, 7, 4, (130, 20, 100), HOTPINK, edges=False)
        top.edges.append(((c - 57, 55, z), (c + 57, 55, z), WHITE, 1))

    @staticmethod
    def smoothstep(u):
        u = max(0.0, min(1.0, u)); return u * u * (3.0 - 2.0 * u)

    @classmethod
    def mix(cls, a, b, u): return a + (b - a) * cls.smoothstep(u)

    @classmethod
    def camera_state(cls, race_t):
        # identical to the wireframe edition
        if race_t < 6.0:
            u = race_t / 6.0
            cy = cls.mix(8.0, 55.0, u); pitch = cls.mix(0.035, 0.28, u); yaw = cls.mix(0.0, -0.08, u); cx = cls.mix(0.0, -10.0, u)
            focal = cls.mix(405.0, 430.0, u); center_y = cls.mix(207.0, 214.0, u)
        elif race_t < 14.0:
            u = (race_t - 6.0) / 8.0
            cy = cls.mix(55.0, 155.0, u); pitch = cls.mix(0.28, 0.75, u); yaw = cls.mix(-0.08, 0.18, u); cx = cls.mix(-10.0, 24.0, u)
            focal = cls.mix(430.0, 490.0, u); center_y = cls.mix(214.0, 230.0, u)
        elif race_t < 22.0:
            u = (race_t - 14.0) / 8.0
            cy = cls.mix(155.0, 250.0, u); pitch = cls.mix(0.75, 1.10, u); yaw = cls.mix(0.18, -0.30, u); cx = cls.mix(24.0, -30.0, u)
            focal = cls.mix(490.0, 500.0, u); center_y = cls.mix(230.0, 244.0, u)
        elif race_t < 32.0:
            u = (race_t - 22.0) / 10.0
            cy = cls.mix(250.0, 335.0, u); pitch = cls.mix(1.10, 1.36, u); yaw = cls.mix(-0.30, 0.30, u); cx = cls.mix(-30.0, 34.0, u)
            focal = cls.mix(500.0, 460.0, u); center_y = cls.mix(244.0, 240.0, u)
        elif race_t < 38.0:
            u = (race_t - 32.0) / 6.0
            cy = cls.mix(335.0, 390.0, u); pitch = cls.mix(1.36, 1.48, u); yaw = cls.mix(0.30, -0.05, u); cx = cls.mix(34.0, 0.0, u)
            focal = cls.mix(460.0, 440.0, u); center_y = 240.0
        else:
            u = min(1.0, (race_t - 38.0) / 5.0)
            cy = 390.0 + math.sin(race_t * 0.22) * 2.0; pitch = 1.48
            yaw = -0.05 + 0.10 * cls.smoothstep(u) + math.sin(race_t * 0.16) * 0.025
            cx = math.sin(race_t * 0.28) * 4.0; focal = 440.0; center_y = 240.0
        cy += math.sin(race_t * 0.72) * 1.8
        yaw += math.sin(race_t * 0.39) * 0.018
        cx += math.sin(race_t * 0.52) * 2.5
        return cx, cy, 0.0, yaw, pitch, focal, center_y


class Camera:
    def __init__(s, race_t):
        s.x, s.y, s.z, yaw, pitch, s.f, s.cy = Scene.camera_state(race_t)
        s.cx = 320 + math.sin(race_t * .62) * 5
        s.cyaw, s.syaw = math.cos(yaw), math.sin(yaw)
        s.cp, s.sp = math.cos(pitch), math.sin(pitch)
        s.pos = np.array([s.x, s.y, s.z])

    def to_cam(s, p):
        dx = p[0] - s.x; dy = p[1] - s.y; dz = p[2] - s.z
        r = dx * s.cyaw - dz * s.syaw
        u = dx * s.sp * s.syaw + dy * s.cp + dz * s.sp * s.cyaw
        d = dx * s.syaw * s.cp - dy * s.sp + dz * s.cyaw * s.cp
        return (r, u, d)

    def proj(s, c):
        return (s.cx + c[0] * s.f / c[2], s.cy - c[1] * s.f / c[2], 1.0 / c[2])

    def horizon(s):
        hy = s.cy - s.f * s.sp / max(1e-6, s.cp)
        sx = s.cx - s.syaw * s.f / max(1e-6, s.cyaw * s.cp)
        return int(max(-30000, min(30000, hy))), int(max(-30000, min(30000, sx)))


def clip_near(poly):
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]; b = poly[(i + 1) % n]
        ia = a[2] > NEAR; ib = b[2] > NEAR
        if ia: out.append(a)
        if ia != ib:
            t = (NEAR - a[2]) / (b[2] - a[2])
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    return out


def clip_screen(poly):
    # poly: [(x, y, iz)], Sutherland-Hodgman against 0..W-1, 0..H-1 (iz is linear in screen space)
    def clip(pts, k, v, keep_less):
        out = []
        n = len(pts)
        for i in range(n):
            a = pts[i]; b = pts[(i + 1) % n]
            ia = (a[k] <= v) if keep_less else (a[k] >= v)
            ib = (b[k] <= v) if keep_less else (b[k] >= v)
            if ia: out.append(a)
            if ia != ib:
                t = (v - a[k]) / (b[k] - a[k])
                out.append(tuple(a[j] + (b[j] - a[j]) * t for j in range(3)))
        return out
    for k, v, less in ((0, 0.0, False), (0, W - 1.0, True), (1, 0.0, False), (1, H - 1.0, True)):
        poly = clip(poly, k, v, less)
        if len(poly) < 3: return []
    return poly


def clip_line_screen(a, b):
    x1, y1, z1 = a; x2, y2, z2 = b
    dx = x2 - x1; dy = y2 - y1; t0 = 0.0; t1 = 1.0
    for p, q in [(-dx, x1), (dx, W - 1.0 - x1), (-dy, y1), (dy, H - 1.0 - y1)]:
        if abs(p) < 1e-12:
            if q < 0: return None
        else:
            r = q / p
            if p < 0:
                if r > t1: return None
                if r > t0: t0 = r
            else:
                if r < t0: return None
                if r < t1: t1 = r
    return ((x1 + dx * t0, y1 + dy * t0, z1 + (z2 - z1) * t0), (x1 + dx * t1, y1 + dy * t1, z1 + (z2 - z1) * t1))


def shade(face, cam, depth):
    pts, base, mode, center = face
    p = np.array(pts, dtype=float)
    if mode in ('emit', 'emit2'):
        k = 1.0
    else:
        n = np.cross(p[1] - p[0], p[2] - p[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9: return None
        n /= nn
        if mode == 'up':
            n = np.array([0.0, 1.0, 0.0])
        elif mode in ('two', 'rail'):
            if np.dot(n, cam.pos - p[0]) < 0: n = -n
        elif center is not None and np.dot(n, p.mean(axis=0) - np.array(center)) < 0:
            n = -n
        k = 0.42 + 0.58 * max(0.0, float(np.dot(n, LIGHT)))
    fog = max(0.18, min(1.0, 1.0 - (depth - 260.0) / 1700.0))
    if mode in ('emit', 'emit2'): fog = max(0.35, fog)
    return tuple(int(max(0, min(255, c * k * fog))) for c in base)


def p_mean(pts):
    return tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))


def facing(face, cam):
    pts, base, mode, center = face
    if mode == 'rail':
        # a rail right in front of the camera fills the bottom of the screen with one dark wall: edges only there
        return cam.to_cam(p_mean(pts))[2] > 90.0
    if mode in ('two', 'emit2'): return True
    p = np.array(pts, dtype=float)
    if mode in ('up', 'emit'):
        return cam.y > pts[0][1]
    n = np.cross(p[1] - p[0], p[2] - p[0])
    if center is not None and np.dot(n, p.mean(axis=0) - np.array(center)) < 0: n = -n
    return float(np.dot(n, cam.pos - p[0])) > 0


def raster(zbuf, ibuf, tid, tri):
    # tri: 3 x (x, y, iz) in screen pixels; rasterize at half resolution, keep the largest iz (nearest)
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = [(x / 2, y / 2, z) for x, y, z in tri]
    area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
    if abs(area) < 1e-6: return
    minx = max(0, int(math.floor(min(x0, x1, x2)))); maxx = min(ZW - 1, int(math.ceil(max(x0, x1, x2))))
    miny = max(0, int(math.floor(min(y0, y1, y2)))); maxy = min(ZH - 1, int(math.ceil(max(y0, y1, y2))))
    if minx > maxx or miny > maxy: return
    gx = np.arange(minx, maxx + 1, dtype=np.float64) + 0.5
    gy = np.arange(miny, maxy + 1, dtype=np.float64) + 0.5
    xx, yy = np.meshgrid(gx, gy)
    w0 = ((x1 - xx) * (y2 - yy) - (y1 - yy) * (x2 - xx)) / area
    w1 = ((x2 - xx) * (y0 - yy) - (y2 - yy) * (x0 - xx)) / area
    w2 = 1.0 - w0 - w1
    eps = -1e-3
    mask = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    if not mask.any(): return
    d = w0 * z0 + w1 * z1 + w2 * z2
    zt = zbuf[miny:maxy + 1, minx:maxx + 1]; it = ibuf[miny:maxy + 1, minx:maxx + 1]
    it[mask] = tid                          # painter's order: what the device shows (later wins)
    np.maximum(zt, np.where(mask, d, 0.0), out=zt)   # true z-buffer: for the edges


def precompute_frame(t, frame):
    race_t = max(0, t - 4.2); scroll = race_t * 80
    s = Scene()
    s.add_road(scroll, frame); s.add_city(scroll); s.add_gantry(scroll); s.add_racers(race_t, scroll); s.add_finish_line(race_t, scroll)
    cam = Camera(race_t)
    tris = []          # (layer, objdepth, order, [(x,y,iz)*3], rgb)
    for oi, o in enumerate(s.objs):
        od = cam.to_cam(o.center)[2]
        for face in o.faces:
            if not facing(face, cam): continue
            cpts = clip_near([cam.to_cam(p) for p in face[0]])
            if len(cpts) < 3: continue
            fd = sum(c[2] for c in cpts) / len(cpts)
            col = shade(face, cam, fd)
            if col is None: continue
            sp = clip_screen([cam.proj(c) for c in cpts])
            if len(sp) < 3: continue
            # decals and the road: sort by the face's own depth; objects: by the object's depth
            key = fd if o.layer < 2 else od
            for i in range(1, len(sp) - 1):
                tri = [sp[0], sp[i], sp[i + 1]]
                a = (tri[1][0] - tri[0][0]) * (tri[2][1] - tri[0][1]) - (tri[1][1] - tri[0][1]) * (tri[2][0] - tri[0][0])
                if abs(a) < 0.5: continue
                tris.append((o.layer, key, len(tris), tri, col, abs(a) / 2))
    # painter's order: layer, then far to near
    tris.sort(key=lambda q: (q[0], -q[1], q[2]))
    # visibility: rasterize in painter's order (later wins) to see what the device would show,
    # and keep a true z-buffer to test the edges
    zbuf = np.zeros((ZH, ZW)); ibuf = np.full((ZH, ZW), -1, dtype=np.int32)
    for i, q in enumerate(tris):
        raster(zbuf, ibuf, i, q[3])
    counts = np.bincount(ibuf[ibuf >= 0].ravel(), minlength=len(tris))
    keep = [i for i in range(len(tris)) if counts[i] >= MIN_VISIBLE]
    if len(keep) > MAX_TRIS:
        keep = sorted(sorted(keep, key=lambda i: -counts[i])[:MAX_TRIS])
    out_tris = [(tris[i][3], tris[i][4]) for i in keep]
    area = sum(tris[i][5] for i in keep)
    # neon edges, hidden parts removed with the z-buffer
    lines = []
    for o in s.objs:
        for a, b, col, pri in o.edges:
            ca = cam.to_cam(a); cb = cam.to_cam(b)
            if ca[2] <= NEAR and cb[2] <= NEAR: continue
            if ca[2] <= NEAR or cb[2] <= NEAR:
                tt = (NEAR + 0.01 - ca[2]) / (cb[2] - ca[2])
                m = tuple(ca[k] + (cb[k] - ca[k]) * tt for k in range(3))
                if ca[2] <= NEAR: ca = m
                else: cb = m
            cl = clip_line_screen(cam.proj(ca), cam.proj(cb))
            if cl is None: continue
            (x1, y1, z1), (x2, y2, z2) = cl
            steps = max(1, int(max(abs(x2 - x1), abs(y2 - y1)) / 2))
            run = None; last = None
            for k in range(steps + 1):
                u = k / steps
                px = x1 + (x2 - x1) * u; py = y1 + (y2 - y1) * u; iz = z1 + (z2 - z1) * u
                zx = min(ZW - 1, int(px / 2)); zy = min(ZH - 1, int(py / 2))
                hidden = zbuf[zy, zx] > iz * 1.03 + 2e-5
                if pri == 0: hidden = False     # racers: always on top
                if not hidden:
                    if run is None: run = (px, py)
                    last = (px, py)
                elif run is not None:
                    lines.append((run, last, col, pri)); run = None
            if run is not None:
                lines.append((run, last, col, pri))
    lines = [l for l in lines if max(abs(l[0][0] - l[1][0]), abs(l[0][1] - l[1][1])) >= 2]
    lines.sort(key=lambda l: (l[3], -max(abs(l[0][0] - l[1][0]), abs(l[0][1] - l[1][1]))))
    lines = lines[:MAX_LINES]
    lines.sort(key=lambda l: (1 if l[3] == 0 else 0, -l[3]))   # details first, racers last
    hy, sx = cam.horizon()
    return out_tris, lines, hy, sx, area


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", default="NEON_CIRCUIT_POLY.DAT")
    ap.add_argument("--fps", type=int, default=FPS)
    ap.add_argument("--duration", type=float, default=DURATION)
    ap.add_argument("--preview", default=None, help="write a contact sheet PNG of a few frames")
    ap.add_argument("--frames", default="", help="only these frame indexes (comma separated, for the preview)")
    args = ap.parse_args()
    count = int(round(args.duration * args.fps))
    only = [int(x) for x in args.frames.split(",") if x] if args.frames else None
    palette = {}; pal_list = []

    def pal(rgb):
        q = tuple((c >> 3) << 3 for c in rgb)
        if q not in palette:
            palette[q] = len(pal_list); pal_list.append(q)
        return palette[q]

    frames = []; stats = []
    t0 = time.time()
    for i in (only if only else range(count)):
        tris, lines, hy, sx, area = precompute_frame(i / args.fps, i)
        rec = [len(tris), len(lines), hy, sx]
        for tri, col in tris:
            for x, y, _ in tri:
                rec += [int(round(x)), int(round(y))]
            rec.append(pal(col))
        for a, b, col, _ in lines:
            rec += [int(round(a[0])), int(round(a[1])), int(round(b[0])), int(round(b[1])), pal(RGB[col])]
        frames.append((i, rec, tris, lines, hy, sx))
        ms = est_ms(len(tris), area, len(lines))
        stats.append(ms)
        if (len(frames)) % 20 == 0 or only:
            print(f"{i + 1:3d}/{count} tris={len(tris)} lines={len(lines)} area={int(area)} est={ms:.0f}ms palette={len(pal_list)} time={time.time() - t0:.0f}s", flush=True)
    if len(pal_list) > 65535: raise SystemExit("palette too large")
    if args.preview:
        from PIL import Image, ImageDraw
        sel = frames if only else [frames[k] for k in (0, 30, 60, 100, 140, 180)]
        sheet = Image.new("RGB", (W, (H // 2) * ((len(sel) + 1) // 2)))
        for n, (i, rec, tris, lines, hy, sx) in enumerate(sel):
            im = Image.new("RGB", (W, H), (6, 0, 14)); d = ImageDraw.Draw(im)
            if hy > 0:
                for b in range(6):
                    y0 = hy * b // 6; y1 = hy * (b + 1) // 6
                    d.rectangle([0, y0, W, y1], fill=(20 + b * 18, 4 + b * 3, 60 + b * 8))
            for tri, col in tris:
                d.polygon([(round(x), round(y)) for x, y, _ in tri], fill=tuple(pal_list[pal(col)]), outline=tuple(pal_list[pal(col)]))
            for a, b, col, _ in lines:
                d.line([(round(a[0]), round(a[1])), (round(b[0]), round(b[1]))], fill=RGB[col])
            d.text((4, 4), f"#{i} t={i / args.fps:.2f}s tris={len(tris)} lines={len(lines)}", fill=(255, 255, 255))
            sheet.paste(im.resize((W // 2, H // 2)), ((n % 2) * W // 2, (n // 2) * H // 2))
        sheet.save(args.preview)
        print("preview", args.preview)
    if only: return
    head = bytearray(b"NCP1") + struct.pack("<HBBH", count, args.fps, 0, len(pal_list))
    for r, g, b in pal_list: head += bytes((r, g, b))
    body = bytearray(); offs = []
    base = len(head) + 4 * count
    for i, rec, *_ in frames:
        offs.append(base + len(body))
        body += struct.pack("<%dh" % len(rec), *rec)
    out = head + struct.pack("<%dI" % count, *offs) + body
    Path(args.output).write_bytes(out)
    print(f"WROTE {args.output} bytes={len(out)} frames={count} palette={len(pal_list)} est_ms avg={sum(stats) / len(stats):.0f} max={max(stats):.0f}")


if __name__ == "__main__":
    main()
