/// The library convention a given system folder was scanned from. Recorded
/// per system (not globally) since a single ROMs root can mix conventions.
public enum LibraryFormat: String, Sendable, Codable, CaseIterable {
    case batocera
    case esde
}

/// One MVP system's identity across the three vocabularies that need to be
/// reconciled: Batocera/RetroBat's folder short-name, ES-DE's folder
/// short-name, and RetroArch core `.info` files' `systemid` field.
public struct SystemDefinition: Sendable, Hashable {
    public let canonicalID: CanonicalSystemID
    public let displayName: String
    public let batoceraShortName: String
    public let esdeShortName: String
    /// RetroArch core `.info` `systemid` values known to map to this system.
    /// Populated from libretro-core-info; may gain entries in Phase 7 once
    /// parsed against real installed `.info` files.
    public let retroArchSystemIDs: [String]

    public init(
        canonicalID: CanonicalSystemID,
        displayName: String,
        batoceraShortName: String,
        esdeShortName: String,
        retroArchSystemIDs: [String]
    ) {
        self.canonicalID = canonicalID
        self.displayName = displayName
        self.batoceraShortName = batoceraShortName
        self.esdeShortName = esdeShortName
        self.retroArchSystemIDs = retroArchSystemIDs
    }
}

/// Canonical system table for the MVP systems, and lookup functions from
/// each format-specific vocabulary to a `SystemDefinition`.
public enum SystemTaxonomy {
    public static let mvpSystems: [SystemDefinition] = [
        SystemDefinition(
            canonicalID: .nes,
            displayName: "Nintendo Entertainment System",
            batoceraShortName: "nes",
            esdeShortName: "nes",
            retroArchSystemIDs: ["nes"]
        ),
        SystemDefinition(
            canonicalID: .snes,
            displayName: "Super Nintendo Entertainment System",
            batoceraShortName: "snes",
            esdeShortName: "snes",
            retroArchSystemIDs: ["super_nes", "snes"]
        ),
        SystemDefinition(
            canonicalID: .genesis,
            displayName: "Sega Genesis / Mega Drive",
            batoceraShortName: "megadrive",
            esdeShortName: "genesis",
            retroArchSystemIDs: ["megadrive", "genesis"]
        ),
        SystemDefinition(
            canonicalID: .psx,
            displayName: "Sony PlayStation",
            batoceraShortName: "psx",
            esdeShortName: "psx",
            retroArchSystemIDs: ["psx"]
        ),
        SystemDefinition(
            canonicalID: .gba,
            displayName: "Game Boy Advance",
            batoceraShortName: "gba",
            esdeShortName: "gba",
            retroArchSystemIDs: ["gba"]
        )
    ]

    private static let byBatoceraShortName: [String: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: mvpSystems.map { ($0.batoceraShortName, $0) })

    private static let byESDEShortName: [String: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: mvpSystems.map { ($0.esdeShortName, $0) })

    private static let byCanonicalID: [CanonicalSystemID: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: mvpSystems.map { ($0.canonicalID, $0) })

    private static let byRetroArchSystemID: [String: SystemDefinition] = {
        var map: [String: SystemDefinition] = [:]
        for definition in mvpSystems {
            for id in definition.retroArchSystemIDs {
                map[id] = definition
            }
        }
        return map
    }()

    public static func system(forBatoceraShortName name: String) -> SystemDefinition? {
        byBatoceraShortName[name]
    }

    public static func system(forESDEShortName name: String) -> SystemDefinition? {
        byESDEShortName[name]
    }

    public static func system(forRetroArchSystemID id: String) -> SystemDefinition? {
        byRetroArchSystemID[id]
    }

    public static func definition(for id: CanonicalSystemID) -> SystemDefinition? {
        byCanonicalID[id]
    }

    /// Looks up a system folder short-name against both conventions' short-name
    /// tables, since the format hasn't necessarily been detected yet at the
    /// point a folder is first encountered.
    public static func system(forShortName name: String) -> SystemDefinition? {
        byBatoceraShortName[name] ?? byESDEShortName[name]
    }
}
