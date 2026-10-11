import Foundation
import RomsBoxModels

/// libretro's canonical database names (the `database` field in core
/// `.info` files) for each system RomsBox knows. A core's `database` list
/// names *every* system it runs — Genesis Plus GX lists Game Gear, Master
/// System, Mega-CD and Mega Drive — which its single `systemid` can't.
/// Names verified against libretro's current info files.
public enum LibretroDatabase {
    static let namesBySystem: [CanonicalSystemID: [String]] = [
        .nes: ["Nintendo - Nintendo Entertainment System"],
        .snes: ["Nintendo - Super Nintendo Entertainment System"],
        .gba: ["Nintendo - Game Boy Advance"],
        .genesis: ["Sega - Mega Drive - Genesis"],
        .mastersystem: ["Sega - Master System - Mark III"],
        .gamegear: ["Sega - Game Gear"],
        .segacd: ["Sega - Mega-CD - Sega CD"],
        .sega32x: ["Sega - 32X"],
        .saturn: ["Sega - Saturn"],
        .dreamcast: ["Sega - Dreamcast"],
        .psx: ["Sony - PlayStation"],
        .atari2600: ["Atari - 2600"],
        .atari5200: ["Atari - 5200"],
        .atari7800: ["Atari - 7800"],
        .atarilynx: ["Atari - Lynx"],
        .atarijaguar: ["Atari - Jaguar"],
        .pcengine: ["NEC - PC Engine - TurboGrafx 16"],
        .pcenginecd: ["NEC - PC Engine CD - TurboGrafx-CD"],
        .supergrafx: ["NEC - PC Engine SuperGrafx"],
        .pcfx: ["NEC - PC-FX"],
        .threedo: ["The 3DO Company - 3DO"],
        .cdi: ["Philips - CD-i"]
    ]

    private static let systemByName: [String: CanonicalSystemID] = {
        var map: [String: CanonicalSystemID] = [:]
        for (system, names) in namesBySystem {
            for name in names { map[name] = system }
        }
        return map
    }()

    public static func system(forDatabaseName name: String) -> CanonicalSystemID? {
        systemByName[name]
    }
}
