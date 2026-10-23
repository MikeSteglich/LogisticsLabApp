#!/usr/bin/env python3
# Baut windows/runner/resources/app_icon.ico aus den PNGs von tool/make_icons_test.dart (build/icons/windows/).
# Ein ICO darf PNG-Bilder enthalten (ab Windows Vista) - kein Bildwerkzeug noetig.

import struct
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
SIZES = [16, 24, 32, 48, 64, 128, 256]

images = [(s, (PROJECT / f"build/icons/windows/icon_{s}.png").read_bytes()) for s in SIZES]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, data = b"", b""
for size, png in images:
    dim = 0 if size >= 256 else size            # 0 bedeutet 256
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset + len(data))
    data += png
target = PROJECT / "windows/runner/resources/app_icon.ico"
target.write_bytes(header + entries + data)
print(f"{target} ({len(images)} Groessen)")
