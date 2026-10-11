#!/usr/bin/env python3
"""Package native-rendered PNG representations in an ICNS container."""
from pathlib import Path
import struct
import sys

root, destination = map(Path, sys.argv[1:])
chunks = []
for code, filename in [('icp4','icon_16x16.png'), ('icp5','icon_32x32.png'),
                       ('icp6','icon_32x32@2x.png'), ('ic07','icon_128x128.png'),
                       ('ic08','icon_256x256.png'), ('ic09','icon_512x512.png'),
                       ('ic10','icon_512x512@2x.png')]:
    data = (root/filename).read_bytes()
    chunks.append(code.encode('ascii') + struct.pack('>I', len(data)+8) + data)
payload = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(payload)+8) + payload)
