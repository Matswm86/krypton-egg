import struct
import sys
from pathlib import Path

d = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])
out.mkdir(exist_ok=True)
n = struct.unpack_from("<I", d, 0)[0]
h = struct.unpack_from("<7I", d, 0)
print(h)
names_at, data_at = h[3], h[5]
for i in range(n):
    no, off, sz = struct.unpack_from("<3I", d, 0x1C + 12 * i)
    name = d[names_at + no : d.index(b"\0", names_at + no)].decode()
    blob = d[data_at + off : data_at + off + sz]
    (out / name).write_bytes(blob)
    print(f"{name:14} {off:8x} {sz:8} {blob[:8].hex()}")
