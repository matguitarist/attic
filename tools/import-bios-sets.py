#!/usr/bin/env python3
"""Rebuilds AtticKit/Sources/AtticEmulation/Resources/KnownBIOSSets.tsv, the
chips of the zipped BIOS sets Attic asks for (naomi.zip, hikaru.zip,
model1io.zip, neogeo.zip…), from MAME's game list:

    curl -LO https://github.com/mamedev/mame/releases/download/mame0289/mame0289lx.zip
    unzip mame0289lx.zip
    tools/import-bios-sets.py mame0289.xml

A zip's own checksum depends on how it was packed, so a set is checked by
what's in it: each chip's CRC32, read from the zip's directory. The sets
are those EmulatorCatalog.swift names as `BIOSRequirement("….zip")`.

Columns: set, BIOS revision (empty for a chip every revision needs), chip
name, size, CRC32, and whether the set needs it (0 for a chip MAME only
keeps for its default contents: an EEPROM or NVRAM image).
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

repo = pathlib.Path(__file__).resolve().parent.parent
catalog = (repo / "AtticKit/Sources/AtticEmulation/EmulatorCatalog.swift").read_text()
wanted = {pathlib.PurePosixPath(name).stem.lower()
          for name in re.findall(r'BIOSRequirement\("([^"]+\.zip)"', catalog)}

build = None
rows = []
found = set()
for event, element in ET.iterparse(sys.argv[1], events=("start", "end")):
    if event == "start":
        if element.tag == "mame":
            build = element.get("build", "").split(" ")[0]
        continue
    if element.tag != "machine":
        continue
    name = element.get("name")
    if name in wanted:
        found.add(name)
        seen = set()
        for rom in element.findall("rom"):
            crc = rom.get("crc")
            if rom.get("status") == "nodump" or not crc or (rom.get("name"), crc) in seen:
                continue
            seen.add((rom.get("name"), crc))
            chip = rom.get("name")
            # Default EEPROM/NVRAM contents: emulators make their own.
            needed = not ("eeprom" in chip.lower() or chip.lower().startswith(("93c46", "x76f100")))
            rows.append("\t".join([name, rom.get("bios") or "", chip, rom.get("size"), crc.lower(), "1" if needed else "0"]))
    element.clear()

missing = sorted(wanted - found)
if missing:
    sys.exit(f"Not in MAME's list: {', '.join(missing)}")
target = repo / "AtticKit/Sources/AtticEmulation/Resources/KnownBIOSSets.tsv"
target.write_text(f"# MAME {build}\n" + "\n".join(rows) + "\n")
print(f"{len(found)} sets, {len(rows)} chips, MAME {build}")
