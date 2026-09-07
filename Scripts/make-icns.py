#!/usr/bin/env python3
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "Resources"
iconset = root / "AppIcon.iconset"
mapping = {
    b"icp4": "icon_16x16.png",
    b"ic11": "icon_16x16@2x.png",
    b"icp5": "icon_32x32.png",
    b"ic12": "icon_32x32@2x.png",
    b"ic07": "icon_128x128.png",
    b"ic13": "icon_128x128@2x.png",
    b"ic08": "icon_256x256.png",
    b"ic14": "icon_256x256@2x.png",
    b"ic09": "icon_512x512.png",
    b"ic10": "icon_512x512@2x.png",
}
chunks = []
for ostype, name in mapping.items():
    data = (iconset / name).read_bytes()
    chunks.append(ostype + struct.pack(">I", 8 + len(data)) + data)
body = b"".join(chunks)
output = root / "AppIcon.icns"
output.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)
print(f"Wrote {output} ({output.stat().st_size} bytes)")
