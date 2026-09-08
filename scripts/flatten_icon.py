#!/usr/bin/env python3
"""Strips the alpha channel from a PNG in place, no dependencies.

App Store Connect rejects a marketing icon that carries an alpha channel
(ITMS-90717), even when every pixel is fully opaque — it is the presence of
the channel that fails validation, not any actual transparency. That failure
happens at upload, after the archive is already built.

    python3 scripts/flatten_icon.py Voyage/Assets.xcassets/AppIcon.appiconset/AppIcon.png

Rewrites an RGBA (color type 6) or grey+alpha (type 4) PNG as RGB (type 2),
compositing over opaque black. Exits 0 and touches nothing if the file is
already alpha-free, so it is safe to re-run.
"""
import os
import struct
import sys
import zlib


def read_chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG file")
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        tag = data[i + 4:i + 8]
        yield tag, data[i + 8:i + 8 + length]
        i += 12 + length


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def unfilter(raw, width, height, bpp):
    """Reverse the per-scanline PNG filters, returning flat sample bytes."""
    stride = width * bpp
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                if ftype == 1:
                    line[x] = (line[x] + a) & 0xFF
                elif ftype == 2:
                    line[x] = (line[x] + b) & 0xFF
                elif ftype == 3:
                    line[x] = (line[x] + (a + b) // 2) & 0xFF
                elif ftype == 4:
                    line[x] = (line[x] + paeth(a, b, c)) & 0xFF
                else:
                    raise SystemExit("unsupported PNG filter type %d" % ftype)
        out += line
        prev = line
    return out


def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload)))


def main(path):
    data = open(path, "rb").read()
    header = None
    idat = b""
    for tag, payload in read_chunks(data):
        if tag == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif tag == b"IDAT":
            idat += payload

    if header is None:
        raise SystemExit("%s: no IHDR chunk" % path)
    width, height, depth, color, comp, filt, interlace = header

    if color not in (4, 6):
        print("%s: color type %d already has no alpha channel; unchanged" % (path, color))
        return
    if depth != 8 or interlace != 0 or comp != 0 or filt != 0:
        raise SystemExit(
            "%s: only 8-bit non-interlaced PNGs are supported "
            "(got depth %d, interlace %d)" % (path, depth, interlace))

    bpp = 4 if color == 6 else 2
    samples = unfilter(zlib.decompress(idat), width, height, bpp)

    # Composite over opaque black and drop the alpha channel.
    rows = []
    for y in range(height):
        row = bytearray([0])  # filter type None
        base = y * width * bpp
        for x in range(width):
            o = base + x * bpp
            alpha = samples[o + bpp - 1]
            if color == 6:
                r, g, b = samples[o], samples[o + 1], samples[o + 2]
            else:
                r = g = b = samples[o]
            if alpha != 255:
                r = r * alpha // 255
                g = g * alpha // 255
                b = b * alpha // 255
            row += bytes((r, g, b))
        rows.append(bytes(row))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"sRGB", b"\x00")
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")

    tmp = path + ".flatten.tmp"
    with open(tmp, "wb") as f:
        f.write(png)
    os.replace(tmp, path)
    print("%s: flattened RGBA -> RGB (%d x %d, %d bytes)" % (path, width, height, len(png)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: flatten_icon.py <path-to-png>")
    main(sys.argv[1])
