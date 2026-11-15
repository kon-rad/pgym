#!/usr/bin/env python3
"""Writes PGYMTests/Fixtures/proof-test-photo.png: a synthetic 3:4 "gym" scene for the card renderer tests.

No real photo and no person: a warm wall, a dark rubber floor, a rack and a loaded barbell with red,
blue and yellow plates, so each filter visibly changes it. Standard library only (zlib PNG writer).

    python3 ios/Tools/make-proof-test-photo.py
"""
import math
import os
import struct
import zlib

W, H = 768, 1024


def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else int(v)


def pixel(x, y):
    # Wall: warm gradient with a soft light from the top left.
    light = 1.0 - 0.55 * math.hypot(x - 200, y - 120) / 1100
    r, g, b = 196 * light, 160 * light, 128 * light
    # Floor.
    if y > 760:
        t = (y - 760) / 264
        r, g, b = 40 - 12 * t, 42 - 12 * t, 46 - 12 * t
        if (x // 96 + y // 96) % 2 == 0:
            r, g, b = r + 6, g + 6, b + 6
    # Rack uprights.
    for cx in (150, 618):
        if cx - 18 <= x <= cx + 18 and 180 <= y <= 780:
            shade = 70 + 40 * (1 - abs(x - cx) / 18)
            r, g, b = shade, shade, shade + 6
    # Bar.
    if 452 <= y <= 466 and 40 <= x <= 728:
        r, g, b = 210, 210, 214
    # Plates: red, blue, yellow on each side.
    for side in (-1, 1):
        for i, (pr, pg, pb, rad) in enumerate(((220, 40, 40, 150), (40, 80, 210, 120), (240, 200, 40, 90))):
            px = 384 + side * (230 + i * 34)
            if abs(x - px) <= 14 and abs(y - 459) <= rad:
                r, g, b = pr, pg, pb
    # A chalk bowl: bright highlight for the tone curves.
    if (x - 600) ** 2 / 70 ** 2 + (y - 900) ** 2 / 26 ** 2 <= 1:
        r, g, b = 245, 245, 240
    return clamp(r), clamp(g), clamp(b)


def main():
    rows = bytearray()
    for y in range(H):
        rows.append(0)
        for x in range(W):
            rows.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")

    out = os.path.join(os.path.dirname(__file__), "..", "PGYMTests", "Fixtures", "proof-test-photo.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png)
    print(os.path.normpath(out), len(png), "bytes")


if __name__ == "__main__":
    main()
