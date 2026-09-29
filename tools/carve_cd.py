"""Carve the resources out of KE.RSC from the C2V Games Suite CD (1996, full version).

Usage: python3 tools/carve_cd.py <KRYPTON/COM/CDROM/KE.RSC> <out dir>

KE.RSC has a scrambled directory, so this carves by content instead:
  * most banks are stored bit-inverted (every byte XOR 0xFF); the music banks
    and the FLI cutscenes are stored plain;
  * a GAF bank carries its own length at offset 14, a FLI at offset 0;
  * the 100 levels are 586-byte records (u16 speed, 8 monster bytes, 18x16 cells).
The offset-to-name table below is specific to the COM (registered) KE.RSC.
"""

import io
import re
import struct
import sys
from pathlib import Path

from PIL import Image

BANK_NAMES = {
    0x130FF: "KE_LOGO",
    0x2CE79: "KE_TIT",
    0x499DD: "KE_MENU",
    0x50CD3: "KE_MENU2",
    0x66F6F: "KE_MNCYC",
    0x678CF: "KE_FONT",
    0x70635: "KE_SCORE",
    0x8681D: "KE_INFO2",
    0x96FA5: "KE_INFOS",
    0x9A7A3: "KE_RED",
    0x9AAD3: "KE_FILL",
    0xA0041: "KE_BRICK",
    0xA9805: "KE_BORD",
    0xAB233: "KE_DIGIT",
    0xAC18D: "KE_NMY",
    0xB1377: "KE_RACK",
    0xB5105: "KE_SPELL",
    0xB8D43: "KE_LVL",
    0xBE3A7: "KE_MAIN",
    0xF90DF: "KE_GO",
    0x115287: "KE_PAUSE",
    0x11ECCB: "KE_END",
    0x134043: "KE_MONST",
}
PIC_NAMES = {
    0xB6B2: "presents",
    0x136CA1: "title",
    0x14E4D2: "menu",
    0x15107F: "score",
    0x15277C: "monst",
}
LEVEL_SIZE = 586


def level_ok(buf, q):
    h = buf[q : q + 10]
    return len(h) == 10 and h[1] < 3 and all(b < 8 for b in h[2:])


def main():
    raw = Path(sys.argv[1]).read_bytes()
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    inv = bytes(255 - b for b in raw)
    for buf in (inv, raw):
        for m in re.finditer(b"GAF_", buf):
            p = m.start()
            size = struct.unpack_from("<I", buf, p + 14)[0]
            name = BANK_NAMES.get(p, f"MUS_{p:08x}")
            (out / f"{name}.GAF").write_bytes(buf[p : p + size])
    for p, name in PIC_NAMES.items():
        Image.open(io.BytesIO(inv[p : p + 400_000])).convert("RGB").save(out / f"PIC_{name}.png")
    first = inv.find(bytes.fromhex("f4010105010505010105"))
    start = first
    while level_ok(inv, start - LEVEL_SIZE):
        start -= LEVEL_SIZE
    end = start
    while level_ok(inv, end):
        end += LEVEL_SIZE
    (out / "KE.LVL").write_bytes(inv[start:end])
    print("levels:", (end - start) // LEVEL_SIZE)
    p = raw.find(b"\x11\xaf\x3c\x00\x40\x01\xc8\x00") - 4
    n = 0
    while struct.unpack_from("<H", raw, p + 4)[0] == 0xAF11:
        size = struct.unpack_from("<I", raw, p)[0]
        (out / f"{n:02d}.fli").write_bytes(raw[p : p + size])
        p += size
        n += 1
    print("cutscenes:", n)


if __name__ == "__main__":
    main()
