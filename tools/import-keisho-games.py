#!/usr/bin/env python3
"""Rebuilds AtticKit/Sources/AtticEmulation/Resources/KeishoGames.xml, the
Model 1, 2 and 3 sets Keisho runs with each chip's CRC32, from Keisho's own
ROM database:

    curl -LO https://raw.githubusercontent.com/Keisho-Emu/Keisho/main/data/games.xml
    tools/import-keisho-games.py games.xml 0.9.63

Only what Verify Games reads is kept (sets, parents, I/O board devices,
titles, chips and whether a region is required), not Keisho's inputs,
outputs or layouts. The chips are MAME's (Keisho transcribes them from
MAME's drivers, BSD-3-Clause); see THIRD_PARTY_NOTICES.md. Attic reads the
games.xml of an installed Keisho instead when there is one, so this copy
only matters until Keisho is installed.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

source, version = sys.argv[1], sys.argv[2]
text = pathlib.Path(source).read_text()
# Its comments hold "--", which XML doesn't allow there.
root = ET.fromstring(re.sub(r"<!--.*?-->", "", text, flags=re.S))

lines = ['<?xml version="1.0" encoding="UTF-8"?>', f"<keisho version={quoteattr(version)}>"]
for game in root.findall("game"):
    attributes = f"name={quoteattr(game.get('name'))}"
    if game.get("parent"):
        attributes += f" parent={quoteattr(game.get('parent'))}"
    lines.append(f"  <game {attributes}>")
    if game.findtext("title"):
        lines.append(f"    <title>{game.findtext('title').strip()}</title>".replace("&", "&amp;"))
    for device in game.iter("device"):
        lines.append(f"    <device name={quoteattr(device.get('name'))}/>")
    for region in game.iter("region"):
        files = [f for f in region.findall("file") if f.get("crc")]
        if not files:
            continue
        required = ' required="false"' if region.get("required") == "false" else ""
        lines.append(f"    <region{required}>")
        for file in files:
            alternate = f" alt_crc={quoteattr(file.get('alt_crc'))}" if file.get("alt_crc") else ""
            lines.append(f"      <file name={quoteattr(file.get('name'))} crc={quoteattr(file.get('crc'))}{alternate}/>")
        lines.append("    </region>")
    lines.append("  </game>")
lines.append("</keisho>")

target = pathlib.Path(__file__).resolve().parent.parent / "AtticKit/Sources/AtticEmulation/Resources/KeishoGames.xml"
target.write_text("\n".join(lines) + "\n")
print(f"{len(root.findall('game'))} sets")
