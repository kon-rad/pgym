#!/usr/bin/env python3
"""Draws the PGYM app icon and the launch-screen mark from the final logo (card D1).

Source of truth: Areas/PGYM/design/logo/pgym-icon.svg and pgym-mark.svg in the design notes. This script
draws the same geometry so the build needs no SVG tool:

- rim: arc radius 300, stroke 72, butt ends; lip: arc radius 228, stroke 22, butt ends
- one cut through both rings from -66 to -18 degrees (SVG angles, y down)
- check: stroke 76, round caps and joins, (-136,12) to (-44,104) to (245,-252.7)
- the whole mark rotated 8 degrees anticlockwise, Plate #FF4D1F

Outputs (standard library only, zlib PNG writer, 4 x 4 supersampling on edges):

- PGYM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png: 1024 x 1024, full-bleed Ink,
  no corner radius and no alpha channel (App Store Connect rejects an icon with alpha)
- PGYM/Resources/Assets.xcassets/LaunchMark.imageset/LaunchMark{,@2x,@3x}.png: the mark on a
  transparent ground in an 88 pt box, the same size as the launch view in AppRootView.swift

    python3 ios/Tools/make-app-icon.py
"""
import math
import os
import struct
import zlib

INK = (0x0B, 0x0B, 0x0C)
PLATE = (0xFF, 0x4D, 0x1F)

TILT = math.radians(-8)  # SVG rotate(-8): anticlockwise on screen
CUT_FROM, CUT_TO = -66.0, -18.0  # degrees, the gap in both rings
RINGS = ((300.0, 36.0), (228.0, 11.0))  # (radius, half stroke)
CHECK = ((-136.0, 12.0), (-44.0, 104.0), (245.0, -252.7))
CHECK_HALF = 38.0


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def ring_sdf(x, y, radius, half):
    """Signed distance to one ring with the butt-ended cut. Negative inside."""
    r = math.hypot(x, y)
    a = math.degrees(math.atan2(y, x))
    if not (CUT_FROM < a < CUT_TO):
        return abs(r - radius) - half
    # In the cut: distance to the nearer butt end (a radial segment).
    best = float("inf")
    for deg in (CUT_FROM, CUT_TO):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        best = min(best, seg_dist(x, y, c * (radius - half), s * (radius - half), c * (radius + half), s * (radius + half)))
    return best


def mark_sdf(x, y):
    """Signed distance in mark units (800-unit box, origin at the ring centre, y down)."""
    # Undo the tilt: rotate the point by +8 degrees.
    c, s = math.cos(-TILT), math.sin(-TILT)
    ux, uy = c * x - s * y, s * x + c * y
    d = min(ring_sdf(ux, uy, r, h) for r, h in RINGS)
    for (ax, ay), (bx, by) in zip(CHECK, CHECK[1:]):
        d = min(d, seg_dist(ux, uy, ax, ay, bx, by) - CHECK_HALF)
    return d


def coverage(px, py, size, units_per_px, origin):
    """Fraction of the pixel (px, py) covered by the mark."""
    cx = (px + 0.5) * units_per_px - origin
    cy = (py + 0.5) * units_per_px - origin
    d = mark_sdf(cx, cy)
    if d > units_per_px:
        return 0.0
    if d < -units_per_px:
        return 1.0
    hit = 0
    for i in range(4):
        for j in range(4):
            sx = (px + (i + 0.5) / 4) * units_per_px - origin
            sy = (py + (j + 0.5) / 4) * units_per_px - origin
            if mark_sdf(sx, sy) <= 0:
                hit += 1
    return hit / 16


def png(width, height, rows, alpha):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    color_type = 6 if alpha else 2
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    out += chunk(b"IEND", b"")
    return out


def icon(size=1024):
    """Full-bleed Ink square; the mark at scale 1 on the 1024 canvas, ring centre at the centre."""
    units_per_px = 1024 / size
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            a = coverage(x, y, size, units_per_px, 512)
            rows.extend(round(INK[k] + (PLATE[k] - INK[k]) * a) for k in range(3))
    return png(size, size, rows, alpha=False)


def launch_mark(px_size):
    """The mark alone on transparent, the 800-unit box filling the image."""
    units_per_px = 800 / px_size
    rows = bytearray()
    for y in range(px_size):
        rows.append(0)
        for x in range(px_size):
            a = coverage(x, y, px_size, units_per_px, 400)
            rows.extend((*PLATE, round(255 * a)))
    return png(px_size, px_size, rows, alpha=True)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print(os.path.normpath(path), len(data), "bytes")


def main():
    assets = os.path.join(os.path.dirname(__file__), "..", "PGYM", "Resources", "Assets.xcassets")
    write(os.path.join(assets, "AppIcon.appiconset", "AppIcon-1024.png"), icon())
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        write(os.path.join(assets, "LaunchMark.imageset", f"LaunchMark{suffix}.png"), launch_mark(88 * scale))


if __name__ == "__main__":
    main()
