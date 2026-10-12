import Foundation

/// ROM hacks kept in a folder of their own (`snesh` beside `snes`), as many
/// packs do, so they get their own place in the library. They play exactly
/// like the system they're made for: its emulators, file types, BIOS, help
/// and logo all apply (see `CanonicalSystemID.baseSystem`).
public enum ROMHacks {
    struct Entry {
        let hack: CanonicalSystemID
        let base: CanonicalSystemID
        /// Folder names, most common first.
        let folderNames: [String]
    }

    static let entries: [Entry] = [
        Entry(hack: .nesh, base: .nes, folderNames: ["nesh", "famicomh"]),
        Entry(hack: .snesh, base: .snes, folderNames: ["snesh", "sfch"]),
        Entry(hack: .n64h, base: .n64, folderNames: ["n64h"]),
        Entry(hack: .gbh, base: .gb, folderNames: ["gbh"]),
        Entry(hack: .gbch, base: .gbc, folderNames: ["gbch"]),
        Entry(hack: .gbah, base: .gba, folderNames: ["gbah"]),
        Entry(hack: .ndsh, base: .nds, folderNames: ["ndsh"]),
        Entry(hack: .genesish, base: .genesis, folderNames: ["genh", "genesish", "megadriveh", "mdh"]),
        Entry(hack: .mastersystemh, base: .mastersystem, folderNames: ["smsh", "mastersystemh"]),
        Entry(hack: .gamegearh, base: .gamegear, folderNames: ["ggh", "gamegearh"]),
        Entry(hack: .pcengineh, base: .pcengine, folderNames: ["pceh", "pcengineh", "tg16h"]),
        Entry(hack: .psxh, base: .psx, folderNames: ["psxh"]),
    ]

    private static let baseByHack = Dictionary(uniqueKeysWithValues: entries.map { ($0.hack, $0.base) })

    static func base(of hack: CanonicalSystemID) -> CanonicalSystemID? {
        baseByHack[hack]
    }

    /// The hacks of `systems`, for whatever runs them.
    public static func hacks(of systems: [CanonicalSystemID]) -> [CanonicalSystemID] {
        entries.filter { systems.contains($0.base) }.map(\.hack)
    }

    /// One definition per hack folder, named and filed after its base.
    static func definitions(basedOn systems: [SystemDefinition]) -> [SystemDefinition] {
        entries.compactMap { entry in
            guard let base = systems.first(where: { $0.canonicalID == entry.base }) else { return nil }
            return SystemDefinition(
                canonicalID: entry.hack,
                displayName: "\(base.displayName) Hacks",
                batoceraShortName: entry.folderNames[0],
                esdeShortName: entry.folderNames[0],
                retroArchSystemIDs: [],
                category: base.category,
                otherShortNames: Array(entry.folderNames.dropFirst())
            )
        }
    }
}

public extension CanonicalSystemID {
    static let nesh = CanonicalSystemID("nesh")
    static let snesh = CanonicalSystemID("snesh")
    static let n64h = CanonicalSystemID("n64h")
    static let gbh = CanonicalSystemID("gbh")
    static let gbch = CanonicalSystemID("gbch")
    static let gbah = CanonicalSystemID("gbah")
    static let ndsh = CanonicalSystemID("ndsh")
    static let genesish = CanonicalSystemID("genesish")
    static let mastersystemh = CanonicalSystemID("mastersystemh")
    static let gamegearh = CanonicalSystemID("gamegearh")
    static let pcengineh = CanonicalSystemID("pcengineh")
    static let psxh = CanonicalSystemID("psxh")

    /// The system whose emulators, file types, BIOS and help apply: the
    /// one a ROM-hack folder's games are made for, else the system itself.
    var baseSystem: CanonicalSystemID { ROMHacks.base(of: self) ?? self }

    /// Whether this is a folder of ROM hacks for another system.
    var isROMHacks: Bool { ROMHacks.base(of: self) != nil }
}
