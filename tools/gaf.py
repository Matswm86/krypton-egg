"""Decoder for Krypton Egg (C2V, Windows 1995/1996) GAF resource banks.

A GAF file is a chunk directory: GOB_ (sprites), RGB_ (palette), DIG_ (samples),
FNT_, ANM_, NAM_. Two revisions exist: the 1995 shareware (chunk version 0x10)
and the 1996 CD release (0x9606), which differ in sprite header size, palette
header size and one extra run-length token.
"""

import struct
from pathlib import Path

from PIL import Image


def chunks(d):
    _, _, n = struct.unpack_from("<HHH", d, 4)
    pos, out = 0x12, {}
    for _ in range(n):
        tag = d[pos:pos + 4].decode()
        elen, ver, cnt, off, size = struct.unpack_from("<HHHII", d, pos + 4)
        out[tag] = dict(count=cnt, off=off, size=size, ver=ver, extra=d[pos + 18:pos + elen])
        pos += elen
    return out


def palette(d, c):
    head = 8 if c["ver"] == 0x10 else 10
    raw = d[c["off"] + head:c["off"] + head + 768]
    return [tuple(raw[i * 3:i * 3 + 3]) for i in range(256)]


def sprite(d, p, new):
    """Decode one run-length sprite; return (sprite dict, offset of the next one).

    Each row starts with a run count. A run byte >= 0x80 skips 256-b transparent
    pixels, 1..0x7f copies that many literal pixels, and (CD release only) 0
    repeats the following value byte `count` times.
    """
    w, h, x, y = struct.unpack_from("<4h", d, p)
    if new:
        data_off, size = struct.unpack_from("<II", d, p + 12)
        q = p + data_off
    else:
        size = struct.unpack_from("<I", d, p + 16)[0]
        q = p + 20
    px = {}
    for row in range(h):
        n = d[q]
        q += 1
        col = 0
        for _ in range(n):
            r = d[q]
            q += 1
            if r >= 0x80:
                col += 256 - r
            elif r == 0 and new:
                cnt, val = d[q], d[q + 1]
                q += 2
                for k in range(cnt):
                    px[(col + k, row)] = val
                col += cnt
            else:
                for k in range(r):
                    px[(col + k, row)] = d[q + k]
                col += r
                q += r
    return dict(w=w, h=h, x=x, y=y, px=px), p + size


def load(path):
    d = Path(path).read_bytes()
    ch = chunks(d)
    pal = palette(d, ch["RGB_"]) if "RGB_" in ch else None
    sprites = []
    if "GOB_" in ch:
        g = ch["GOB_"]
        new = g["ver"] != 0x10
        p = g["off"]
        while len(sprites) < g["count"]:
            s, p = sprite(d, p, new)
            sprites.append(s)
    return d, ch, pal, sprites


def to_image(s, pal):
    im = Image.new("RGBA", (max(s["w"], 1), max(s["h"], 1)), (0, 0, 0, 0))
    for (x, y), v in s["px"].items():
        if 0 <= x < s["w"]:
            im.putpixel((x, y), pal[v] + (255,))
    return im
