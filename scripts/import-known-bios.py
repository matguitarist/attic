#!/usr/bin/env python3
"""Rebuilds AtticKit/Sources/AtticEmulation/Resources/KnownBIOS.tsv, the
size and MD5 of known good BIOS dumps, from libretro's System.dat:

    curl -LO https://raw.githubusercontent.com/libretro/libretro-database/master/dat/System.dat
    scripts/import-known-bios.py System.dat

Zipped sets are left out: a zip's checksum depends on how it was packed.
The list is CC BY-SA 4.0, like libretro-database (see THIRD_PARTY_NOTICES.md).
"""
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
rows = []
for line in source.splitlines():
    match = re.search(r'rom \( name ("[^"]+"|\S+) size (\d+) crc \w+ md5 (\w+)', line)
    if not match:
        continue
    name = match.group(1).strip('"')
    if name.lower().endswith(".zip"):
        continue
    rows.append(f"{name}\t{match.group(2)}\t{match.group(3).lower()}")
target = pathlib.Path(__file__).resolve().parent.parent / "AtticKit/Sources/AtticEmulation/Resources/KnownBIOS.tsv"
target.write_text("\n".join(rows) + "\n")
print(f"{len(rows)} files")
