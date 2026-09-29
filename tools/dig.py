"""Read the DIG_ sample chunk of a GAF bank: 8-bit unsigned mono PCM."""

import struct
from pathlib import Path

import gaf


def sounds(path):
    """Return [(name, rate, loop_flag, pcm bytes)].

    Each sample has a 20-byte header (u32 unused, u32 size, u16 rate, u8 loop,
    9-byte name). The shareware packs all headers first and all data after;
    the CD release puts each header directly before its own data, 4-byte aligned.
    """
    d = Path(path).read_bytes()
    c = gaf.chunks(d)["DIG_"]
    base, n = c["off"], c["count"]

    def head(p):
        size, rate, flag = struct.unpack_from("<IHB", d, p + 4)
        return size, rate, flag, d[p + 11 : p + 20].split(b"\0")[0].decode("latin1")

    out = []
    if c["ver"] == 0x10:
        start = base + 20 * n
        for i in range(n):
            size, rate, flag, name = head(base + 20 * i)
            out.append((name, rate, flag, d[start : start + size]))
            start += size
    else:
        p = base
        for _ in range(n):
            size, rate, flag, name = head(p)
            out.append((name, rate, flag, d[p + 20 : p + 20 + size]))
            p = (p + 20 + size + 3) & ~3
    return out
