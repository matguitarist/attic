#!/usr/bin/env python3
"""Builds Attic/Resources/SystemLogos.xcassets from Dan Patrick's console logos.

    python3 scripts/import-system-logos.py <extracted folder>

<extracted folder> holds the "Light - Color" and "Dark - Color" folders of
"v2.1 Recommended Versions (Normal) (1 Per Platform)" from
https://archive.org/details/console-logos-professionally-redrawn-plus-official-versions

"Dark - Color" logos are drawn for light backgrounds and "Light - Color" for
dark ones, so each system gets one image set with both appearances. Logos are
scaled down to 600 px on their longer side, plenty for Cabinet Mode.
"""
import json
import os
import shutil
import subprocess
import sys

# Attic system → logo file (category folder / name, without .png).
LOGOS = {
    "nes": "Consoles/Nintendo Entertainment System",
    "snes": "Consoles/Super Nintendo Entertainment System",
    "genesis": "Consoles/Sega Genesis",
    "psx": "Consoles/Sony Playstation",
    "gba": "Handhelds/Nintendo Game Boy Advance",
    "mastersystem": "Consoles/Sega Master System",
    "gamegear": "Handhelds/Sega Game Gear",
    "segacd": "Consoles/Sega CD",
    "saturn": "Consoles/Sega Saturn",
    "dreamcast": "Consoles/Sega Dreamcast",
    "sega32x": "Consoles/Sega 32X",
    "atari2600": "Consoles/Atari 2600",
    "atari5200": "Consoles/Atari 5200",
    "atari7800": "Consoles/Atari 7800",
    "atarilynx": "Handhelds/Atari Lynx",
    "atarijaguar": "Consoles/Atari Jaguar",
    "pcengine": "Consoles/NEC TurboGrafx-16",
    "pcenginecd": "Consoles/NEC TurboGrafx-CD",
    "pcfx": "Consoles/NEC PC-FX",
    "supergrafx": "Consoles/NEC PC Engine SuperGrafx",
    "virtualboy": "Consoles/Nintendo Virtual Boy",
    "neogeo": "Consoles/SNK Neo Geo",
    "cps1": "Arcade/Capcom Play System",
    "cps2": "Arcade/Capcom Play System II",
    "cps3": "Arcade/Capcom Play System III",
    "triforce": "Arcade/Sega Triforce",
    "gb": "Handhelds/Nintendo Game Boy",
    "gbc": "Handhelds/Nintendo Game Boy Color",
    "n64": "Consoles/Nintendo 64",
    "nds": "Handhelds/Nintendo DS",
    "n3ds": "Handhelds/Nintendo 3DS",
    "gamecube": "Consoles/Nintendo GameCube",
    "wii": "Consoles/Nintendo Wii",
    "wiiu": "Consoles/Nintendo Wii U",
    "fds": "Consoles/Nintendo Famicom Disk System",
    "pokemini": "Handhelds/Nintendo Pokémon Mini",
    "gameandwatch": "Handhelds/Nintendo Game & Watch",
    "sg1000": "Consoles/Sega SG-1000",
    "naomi": "Arcade/Sega Naomi",
    "atomiswave": "Arcade/Sammy Atomiswave",
    "model3": "Arcade/Sega Model 3",
    "naomi2": "Arcade/Sega Naomi 2",
    # No GD-ROM logo in the set: NAOMI's.
    "naomigd": "Arcade/Sega Naomi",
    "model2": "Arcade/Sega Model 2",
    "stv": "Arcade/SEGA ST-V",
    "gaelco": "Arcade/Gaelco",
    "n64dd": "Consoles/Nintendo 64DD",
    "satellaview": "Consoles/Nintendo Satellaview",
    "sufami": "Consoles/Nintendo Sufami Turbo",
    "psp": "Handhelds/Sony PSP",
    "ps2": "Consoles/Sony Playstation 2",
    "ps3": "Consoles/Sony Playstation 3",
    "ps4": "Consoles/Sony Playstation 4",
    "psvita": "Handhelds/Sony PS Vita",
    "scummvm": "Computers/ScummVM",
    "x68000": "Computers/Sharp X68000",
    "pc88": "Computers/NEC PC-8801",
    "pc98": "Computers/NEC PC-9801",
    "pico8": "Consoles/Pico-8",
    "tic80": "Computers/TIC-80",
    "vic20": "Computers/Commodore VIC-20",
    "plus4": "Computers/Commodore Plus 4",
    "c128": "Computers/Commodore 128",
    "zx81": "Computers/Sinclair ZX81",
    "macintosh": "Computers/Apple Mac OS",
    "xbox": "Consoles/Microsoft Xbox",
    "msx": "Computers/Microsoft MSX",
    "dos": "Computers/MS-DOS",
    "wonderswan": "Handhelds/WonderSwan",
    "wonderswancolor": "Handhelds/Wonderswan Color",
    "ngp": "Handhelds/SNK Neo Geo Pocket",
    "ngpc": "Handhelds/SNK Neo Geo Pocket Color",
    "neogeocd": "Consoles/SNK Neo Geo CD",
    "atarist": "Computers/Atari ST",
    "atari800": "Computers/Atari 800",
    "colecovision": "Consoles/ColecoVision",
    "intellivision": "Consoles/Mattel Intellivision",
    "vectrex": "Consoles/GCE Vectrex",
    "odyssey2": "Consoles/Magnavox Odyssey 2",
    "channelf": "Consoles/Fairchild Channel F",
    "c64": "Computers/Commodore 64",
    "amiga": "Computers/Commodore Amiga",
    "zxspectrum": "Computers/Sinclair ZX Spectrum",
    "amstradcpc": "Computers/Amstrad CPC",
    "mame": "Arcade/MAME",
    "fbneo": "Arcade/Final Burn Neo",
    "3do": "Consoles/3DO Interactive Multiplayer",
    "cdi": "Consoles/Philips CD-i",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Attic", "Resources", "SystemLogos.xcassets")
INFO = {"author": "xcode", "version": 1}


def main(source):
    if os.path.exists(CATALOG):
        shutil.rmtree(CATALOG)
    os.makedirs(CATALOG)
    write_json(os.path.join(CATALOG, "Contents.json"), {"info": INFO})
    # Images are named "SystemLogo/<system>".
    folder = os.path.join(CATALOG, "SystemLogo")
    os.makedirs(folder)
    write_json(os.path.join(folder, "Contents.json"), {"info": INFO, "properties": {"provides-namespace": True}})

    missing = []
    for system, logo in sorted(LOGOS.items()):
        on_light = find(source, "Dark - Color", logo)
        on_dark = find(source, "Light - Color", logo)
        if not (on_light and on_dark):
            missing.append(logo)
            continue
        imageset = os.path.join(folder, system + ".imageset")
        os.makedirs(imageset)
        for src, name in ((on_light, "light.png"), (on_dark, "dark.png")):
            dest = os.path.join(imageset, name)
            subprocess.run(["sips", "-Z", "600", src, "--out", dest], check=True, capture_output=True)
        write_json(os.path.join(imageset, "Contents.json"), {
            "images": [
                {"filename": "light.png", "idiom": "universal"},
                {"filename": "dark.png", "idiom": "universal",
                 "appearances": [{"appearance": "luminosity", "value": "dark"}]},
            ],
            "info": INFO,
        })
    if missing:
        sys.exit("Missing logos: " + ", ".join(missing))
    print(f"{len(LOGOS)} logos written to {os.path.relpath(CATALOG, ROOT)}")


def find(source, variant, logo):
    """The two variants don't always spell a file the same way
    ("Sega Model 3 " vs "Sega Model 3", "…Disk System-02", "Pico-8-10"),
    and one is misspelled ("Sharp X6800")."""
    for name in (logo, logo + " ", logo + "-02", logo + "-10", logo.replace("X68000", "X6800")):
        path = os.path.join(source, variant, name + ".png")
        if os.path.exists(path):
            return path
    return None


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
