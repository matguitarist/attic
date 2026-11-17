#!/usr/bin/env python3
"""Rebuilds AtticKit/Sources/AtticEmulation/Resources/KnownBIOS.tsv, the
size and MD5 of known good BIOS dumps, from libretro's System.dat, plus the
other good dumps of the same files Batocera's BIOS check accepts:

    curl -LO https://raw.githubusercontent.com/libretro/libretro-database/master/dat/System.dat
    curl -LO https://raw.githubusercontent.com/batocera-linux/batocera.linux/master/package/batocera/core/batocera-scripts/scripts/batocera-systems
    tools/import-known-bios.py System.dat batocera-systems

Zipped sets are left out: a zip's checksum depends on how it was packed
(their contents are in KnownBIOSSets.tsv, from tools/import-bios-sets.py).
Batocera lists no sizes, so only its dumps of files System.dat has are
taken, with that file's size.
The list is CC BY-SA 4.0, like libretro-database (see THIRD_PARTY_NOTICES.md).
"""
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
rows = []
sizes = {}
seen = set()
for line in source.splitlines():
    match = re.search(r'rom \( name ("[^"]+"|\S+) size (\d+) crc \w+ md5 (\w+)', line)
    if not match:
        continue
    name = match.group(1).strip('"')
    if name.lower().endswith(".zip"):
        continue
    md5 = match.group(3).lower()
    rows.append(f"{name}\t{match.group(2)}\t{md5}")
    sizes.setdefault(name.lower(), (name, match.group(2)))
    seen.add((name.lower(), md5))

added = 0
if len(sys.argv) > 2:
    batocera = pathlib.Path(sys.argv[2]).read_text()
    # Loose files only: a "zippedFile" is a chip inside a set.
    for md5, file in re.findall(r'\{\s*"md5":\s*"(\w+)"\s*,\s*"file":\s*"bios/([^"]+)"', batocera):
        key = (file.lower(), md5.lower())
        if file.lower().endswith(".zip") or file.lower() not in sizes or key in seen:
            continue
        name, size = sizes[file.lower()]
        rows.append(f"{name}\t{size}\t{md5.lower()}")
        seen.add(key)
        added += 1

target = pathlib.Path(__file__).resolve().parent.parent / "AtticKit/Sources/AtticEmulation/Resources/KnownBIOS.tsv"
target.write_text("\n".join(rows) + "\n")
print(f"{len(rows)} files ({added} from Batocera)")
