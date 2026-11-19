#!/usr/bin/env python3
"""Builds Attic/Resources/SystemLogos.xcassets from Dan Patrick's console logos.

    python3 tools/import-system-logos.py <extracted folder> <extracted SVG folder>

<extracted folder> holds the "Light - Color" and "Dark - Color" folders of
"v2.1 Recommended Versions (Normal) (1 Per Platform)", and <extracted SVG
folder> the "Matching Word Options (Ports, All Games etc)" folder of
"v2.1 SVGs (vector) (Full Set)", both from
https://archive.org/details/console-logos-professionally-redrawn-plus-official-versions
Unzip them with `ditto -x -k`: unzip trips on "SAM Coupé" and "Pokémon".

Systems' logos are named "SystemLogo/<system>"; arcade companies' (Cave,
Data East, Toaplan…) "ArcadeLogo/<maker>", for `ArcadeMaker` in AtticModels.
The set also has arcade boards Attic has no system for yet (Daphne, PGM,
Sega System 16 and 32, Taito Type X, TeknoParrot): add the system to LOGOS
when Attic gets it.

"Dark - Color" logos are drawn for light backgrounds and "Light - Color" for
dark ones, so each system gets one image set with both appearances. Logos are
scaled down to 600 px on their longer side, plenty for Cabinet Mode.
"""
import json
import os
import shutil
import subprocess
import sys
import unicodedata

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
    "model1": "Arcade/Sega Model 1",
    "model2": "Arcade/Sega Model 2",
    "hikaru": "Arcade/Sega Hikaru",
    "amigacd32": "Consoles/Commodore Amiga CD32",
    "cdtv": "Consoles/Commodore CDTV",
    "gx4000": "Consoles/Amstrad GX4000",
    "megaduck": "Handhelds/Mega Duck",
    "moto": "Computers/Thomson MO5",
    "spectravideo": "Computers/SpectraVideo",
    "supervision": "Handhelds/Watara Supervision",
    "x1": "Computers/Sharp X1",
    "segapico": "Computers/Sega Pico",
    "pet": "Computers/Commodore PET",
    "steam": "Computers/Steam",
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
    "switch": "Consoles/Nintendo Switch",
    "sgb": "Consoles/Nintendo Super Game Boy",
    "arcadia": "Consoles/Emerson Arcadia 2001",
    "astrocade": "Consoles/Bally Astrocade",
    "crvision": "Consoles/VTech CreatiVision",
    "cassettevision": "Consoles/Epoch Cassette Vision",
    "scv": "Consoles/Epoch Super Cassette Vision",
    "pv1000": "Consoles/Casio PV-1000",
    "supracan": "Consoles/Funtech Super Acan",
    "loopy": "Consoles/Casio Loopy",
    "advision": "Handhelds/Entex Adventure Vision",
    "gamate": "Handhelds/Gamate",
    "gamecom": "Handhelds/Tiger Game.com",
    "gmaster": "Handhelds/Hartung Game Master",
    # Mostly Tiger's handhelds.
    "lcdgames": "Handhelds/Tiger LCD Handhelds",
    "apple2": "Computers/Apple II",
    "apple2gs": "Computers/Apple IIGS",
    "bbcmicro": "Computers/BBC Microcomputer System",
    "electron": "Computers/Acorn Electron",
    "archimedes": "Computers/Acorn Archimedes",
    "dragon32": "Computers/Dragon 32 64",
    "ti99": "Computers/Texas Instruments TI 99 4A",
    "oricatmos": "Computers/Oric Atmos",
    "samcoupe": "Computers/SAM Coupé",
    "fm7": "Computers/Fujitsu FM-7",
    "fmtowns": "Computers/Fujitsu FM Towns",
    "camplynx": "Computers/Camputers Lynx",
    "adam": "Computers/Coleco ADAM",
    "namco22": "Arcade/Namco System 22",
    "neogeo64": "Arcade/Hyper Neo Geo 64",
    "pspminis": "Handhelds/Sony PSP Minis",
    "wiiware": "Consoles/Nintendo WiiWare",
    "dsiware": "Handhelds/Nintendo DSi Ware",
}

# Systems whose logo is one of the set's word logos, from the SVG set:
# (black, for light backgrounds; white, for dark ones).
WORDS = {
    "ports": "Ports",
}

# Arcade companies, by the names in AtticModels' ArcadeMaker. The set
# calls most of them "<Maker> Classics"; Data East is that in one variant only.
ARCADE = {
    "americanlasergames": "Arcade/American Laser Games",
    "atari": "Arcade/Atari Classics",
    "banpresto": "Arcade/Banpresto",
    "capcom": "Arcade/Capcom Classics",
    "cave": "Arcade/Cave",
    "dataeast": "Arcade/Data East",
    "eighting": "Arcade/Eighting",
    "gaelco": "Arcade/Gaelco",
    "irem": "Arcade/Irem Classics",
    "jaleco": "Arcade/Jaleco Classics",
    "kaneko": "Arcade/Kaneko",
    "konami": "Arcade/Konami Classics",
    "midway": "Arcade/Midway Classics",
    "namco": "Arcade/Namco Classics",
    "nichibutsu": "Arcade/Nichibutsu",
    "nintendo": "Arcade/Nintendo Classics",
    "psikyo": "Arcade/Psikyo",
    "raizing": "Arcade/Raizing",
    "romstar": "Arcade/Romstar",
    "sega": "Arcade/Sega Classics",
    "seibukaihatsu": "Arcade/Seibu Kaihatsu",
    "snk": "Arcade/SNK Classics",
    "stern": "Arcade/Stern",
    "taito": "Arcade/Taito Classics",
    "technos": "Arcade/Technos",
    "tecmo": "Arcade/Tecmo",
    "toaplan": "Arcade/Toaplan",
    "universal": "Arcade/Universal",
    "videosystem": "Arcade/Video System Co",
    "visco": "Arcade/Visco",
    "williams": "Arcade/Williams Classics",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Attic", "Resources", "SystemLogos.xcassets")
INFO = {"author": "xcode", "version": 1}


def main(source, svg_source):
    if os.path.exists(CATALOG):
        shutil.rmtree(CATALOG)
    os.makedirs(CATALOG)
    write_json(os.path.join(CATALOG, "Contents.json"), {"info": INFO})

    missing = []
    systems = namespace("SystemLogo")
    for system, logo in sorted(LOGOS.items()):
        pair = (find(source, "Dark - Color", logo), find(source, "Light - Color", logo))
        if not all(pair):
            missing.append(logo)
            continue
        write_imageset(systems, system, pair, ["sips", "-Z", "600", "{src}", "--out", "{dest}"])
    words = os.path.join(svg_source, "Matching Word Options (Ports, All Games etc)")
    for system, word in sorted(WORDS.items()):
        pair = tuple(os.path.join(words, color + " (Futura PT Bold)", word + ".svg") for color in ("Black", "White"))
        if not all(map(os.path.exists, pair)):
            missing.append(word)
            continue
        write_imageset(systems, system, pair, ["magick", "-background", "none", "-density", "150", "{src}",
                                               "-resize", "600x600", "-define", "png:exclude-chunks=date,time", "{dest}"])
    makers = namespace("ArcadeLogo")
    for maker, logo in sorted(ARCADE.items()):
        pair = (find(source, "Dark - Color", logo), find(source, "Light - Color", logo))
        if not all(pair):
            missing.append(logo)
            continue
        write_imageset(makers, maker, pair, ["sips", "-Z", "600", "{src}", "--out", "{dest}"])
    if missing:
        sys.exit("Missing logos: " + ", ".join(missing))
    print(f"{len(LOGOS) + len(WORDS)} system and {len(ARCADE)} arcade logos written to {os.path.relpath(CATALOG, ROOT)}")


def namespace(name):
    """A folder of the catalog whose images are named "<name>/<image>"."""
    folder = os.path.join(CATALOG, name)
    os.makedirs(folder)
    write_json(os.path.join(folder, "Contents.json"), {"info": INFO, "properties": {"provides-namespace": True}})
    return folder


def write_imageset(folder, name, pair, command):
    """One image with a version for light backgrounds and one for dark."""
    imageset = os.path.join(folder, name + ".imageset")
    os.makedirs(imageset)
    for src, file in zip(pair, ("light.png", "dark.png")):
        dest = os.path.join(imageset, file)
        subprocess.run([part.format(src=src, dest=dest) for part in command], check=True, capture_output=True)
    write_json(os.path.join(imageset, "Contents.json"), {
        "images": [
            {"filename": "light.png", "idiom": "universal"},
            {"filename": "dark.png", "idiom": "universal",
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ],
        "info": INFO,
    })


def find(source, variant, logo):
    """The two variants don't always spell a file the same way
    ("Sega Model 3 " vs "Sega Model 3", "…Disk System-02", "Pico-8-10",
    "Data East Classics"), one is misspelled ("Sharp X6800"), and accented
    names come out of the zip mangled ("SAM CoupÇ")."""
    for name in (logo, logo + " ", logo + "-02", logo + "-10", logo + " Classics", logo.replace("X68000", "X6800")):
        path = os.path.join(source, variant, name + ".png")
        if os.path.exists(path):
            return path
    folder = os.path.join(source, variant, os.path.dirname(logo))
    plain = ascii_only(os.path.basename(logo))
    for file in os.listdir(folder) if os.path.isdir(folder) else []:
        if file.endswith(".png") and ascii_only(file[:-4]) == plain:
            return os.path.join(folder, file)
    return None


def ascii_only(name):
    """The name with each accented letter as "?", whatever it became."""
    return "".join(c if c.isascii() else "?" for c in unicodedata.normalize("NFC", name))


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
