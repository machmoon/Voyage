#!/usr/bin/env python3
"""Generates the placeholder Voyage app icon (1024x1024 PNG) with no dependencies."""
import struct, zlib, math, sys

S = 1024

def lerp(a, b, t):
    return a + (b - a) * t

def px(x, y):
    # Vertical night-sky gradient: deep indigo top -> warm horizon bottom.
    t = y / S
    r = lerp(10, 46, t)
    g = lerp(16, 58, t)
    b = lerp(42, 110, t)

    # Great-circle route arc (quadratic-ish curve across the icon).
    # Parametrize: for each x, arc y = 640 - 340 * sin(pi * x/S)
    ay = 640 - 340 * math.sin(math.pi * x / S)
    d = abs(y - ay)
    if d < 7:
        a = max(0.0, 1.0 - d / 7) * 0.9
        # dashed contrail: fade behind the plane (plane sits at x=700)
        if x < 700:
            dash = 1.0 if (x // 34) % 2 == 0 else 0.25
            a *= dash * min(1.0, (x - 60) / 200) if x > 60 else 0
            r, g, b = lerp(r, 255, a), lerp(g, 255, a), lerp(b, 255, a)

    # Plane: solid rounded diamond at arc position x=700
    px0, py0 = 700, 640 - 340 * math.sin(math.pi * 700 / S)
    dx, dy = x - px0, y - py0
    # rotate ~ -35 degrees (direction of travel)
    ang = -0.62
    rx = dx * math.cos(ang) - dy * math.sin(ang)
    ry = dx * math.sin(ang) + dy * math.cos(ang)
    # simple plane silhouette: fuselage + swept wings
    body = (abs(rx) / 95 + abs(ry) / 26) < 1
    wing = (abs(rx + 8) / 22 + abs(ry) / 78) < 1
    tail = (abs(rx + 70) / 16 + abs(ry) / 34) < 1
    if body or wing or tail:
        r, g, b = 255, 255, 255

    # A few stars in the upper region
    stars = [(140, 150), (330, 90), (520, 200), (830, 120), (900, 320), (240, 300), (700, 60)]
    for sx, sy in stars:
        if (x - sx) ** 2 + (y - sy) ** 2 < 14:
            r, g, b = 235, 240, 255
    return int(r), int(g), int(b)

rows = []
for y in range(S):
    row = bytearray([0])
    for x in range(S):
        row += bytes(px(x, y))
    rows.append(bytes(row))

raw = b"".join(rows)
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")

with open(sys.argv[1], "wb") as f:
    f.write(png)
print("wrote", sys.argv[1])
