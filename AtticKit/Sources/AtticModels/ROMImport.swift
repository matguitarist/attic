import Foundation

/// Which system a game file dropped on Attic belongs to, from its file
/// type — so it can be filed in the right ROMs folder.
public enum ROMImport {
    /// Extensions several systems accept but that mean one in practice
    /// (Genesis Plus GX also reads .sms, mGBA also reads .gb).
    static let usualSystem: [String: CanonicalSystemID] = [
        "nes": .nes, "unf": .nes, "unif": .nes, "fds": .fds,
        "sfc": .snes, "smc": .snes, "bs": .satellaview, "st": .sufami, "ndd": .n64dd,
        "gb": .gb, "dmg": .gb, "sgb": .gb, "gbc": .gbc, "cgb": .gbc,
        "md": .genesis, "gen": .genesis, "smd": .genesis, "32x": .sega32x,
        "sms": .mastersystem, "gg": .gamegear, "sg": .sg1000, "col": .colecovision,
        "pce": .pcengine, "sgx": .supergrafx,
        "ws": .wonderswan, "ngp": .ngp, "ngc": .ngpc, "ngpc": .ngpc,
        "a52": .atari5200, "xex": .atari800, "atr": .atari800, "atx": .atari800, "lnx": .atarilynx,
        "gcm": .gamecube, "wbfs": .wii, "cso": .psp, "zso": .psp, "pbp": .psp, "cdi": .dreamcast, "neo": .neogeo,
        "d64": .c64, "t64": .c64, "g64": .c64, "x64": .c64, "crt": .c64, "prg": .c64,
        "tzx": .zxspectrum, "dim": .x68000, "ipf": .amiga, "hdf": .amiga, "wad": .doom,
    ]

    /// The systems a file with this extension could be for: the one it
    /// usually means, else every system that accepts it, by name. Empty
    /// when none does. ROM-hack folders are never guessed; drop on one
    /// to file a hack there.
    public static func systems(forExtension fileExtension: String) -> [CanonicalSystemID] {
        let ext = fileExtension.lowercased()
        if let usual = usualSystem[ext] { return [usual] }
        return SystemTaxonomy.allSystems
            .filter { !$0.canonicalID.isROMHacks && SystemROMExtensions.extensions(for: $0.canonicalID)?.contains(ext) == true }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map(\.canonicalID)
    }

    /// The system's folder under the ROMs folders, under whichever of its
    /// names exists, else (to be made) under ES-DE's name in the first.
    public static func folder(for system: CanonicalSystemID, romsRoots: [URL]) -> URL? {
        guard let definition = SystemTaxonomy.definition(for: system), let first = romsRoots.first else { return nil }
        let fileManager = FileManager.default
        for root in romsRoots {
            let names = Set(((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []))
            // APFS ignores case, so match the folder's own spelling.
            for name in definition.allShortNames {
                if let existing = names.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    return root.appending(path: existing, directoryHint: .isDirectory)
                }
            }
        }
        return first.appending(path: definition.esdeShortName, directoryHint: .isDirectory)
    }
}
