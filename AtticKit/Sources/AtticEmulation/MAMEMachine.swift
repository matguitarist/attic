import Foundation
import AtticModels

/// A home computer or lesser-known console that MAME runs as a machine with
/// the game in one of its media slots, the way Batocera runs them
/// (`mame apple2ee -flop1 game.dsk`). The MAME core takes that command line
/// from a `.cmd` file passed as the content (see the MAME core's
/// `retro_init.cpp`, `loadcmdfile` and `execute_game_cmd`).
///
/// Drivers, slots and autoboot commands come from Batocera's
/// `mess_systems.toml`.
public struct MAMEMachine: Sendable, Hashable {
    /// The MAME driver, e.g. "apple2ee". Empty when each game is its own
    /// romset (LCD games), run like an arcade game.
    public let driver: String
    /// The media slot for most games, e.g. "flop1", "cart", "cass".
    public let media: String
    /// Slots for other file types, by lowercase extension.
    public let mediaByExtension: [String: String]
    /// Typed in once the machine has booted (MAME's `-autoboot_command`),
    /// for computers that load a tape with a command.
    public let autoboot: String?

    public init(_ driver: String, _ media: String, byExtension: [String: String] = [:], autoboot: String? = nil) {
        self.driver = driver
        self.media = media
        self.mediaByExtension = byExtension
        self.autoboot = autoboot
    }

    /// Whether each game is a romset MAME finds by name, with no machine.
    public var runsRomsets: Bool { driver.isEmpty }

    public static func machine(for system: CanonicalSystemID) -> MAMEMachine? {
        machines[system.rawValue]
    }

    /// The MAME cores that read `.cmd` files.
    public static let coreIdentifiers: Set<String> = ["mame_libretro"]

    /// The machine's ROM set file, which the user provides (for example
    /// apple2ee.zip), for the BIOS list.
    public var biosSetFileName: String? { runsRomsets ? nil : driver + ".zip" }

    private static let tape = ["cas": "cass", "wav": "cass", "tap": "cass", "uef": "cass", "csw": "cass"]

    private static let machines: [String: MAMEMachine] = [
        // Consoles and handhelds.
        "advision": .init("advision", "cart"),
        "arcadia": .init("arcadia", "cart"),
        "astrocade": .init("astrocde", "cart"),
        "crvision": .init("crvision", "cart"),
        "scv": .init("scv", "cart"),
        "vc4000": .init("vc4000", "cart"),
        "pv1000": .init("pv1000", "cart"),
        "supracan": .init("supracan", "cart"),
        "vsmile": .init("vsmile", "cart"),
        "loopy": .init("casloopy", "cart"),
        "uzebox": .init("uzebox", "cart"),
        "gamate": .init("gamate", "cart"),
        "gamecom": .init("gamecom", "cart1"),
        "gmaster": .init("gmaster", "cart"),
        "gamepock": .init("gamepock", "cart"),
        "lcdgames": .init("", ""),
        // Computers.
        "apple2": .init("apple2ee", "flop1"),
        "apple2gs": .init("apple2gs", "flop3", byExtension: ["dsk": "flop1", "do": "flop1", "po": "flop1", "nib": "flop1"]),
        "bbcmicro": .init("bbcb", "flop1", byExtension: tape),
        // Its autoboot (*T. then CH."") has a dot, which the MAME core
        // would take for a file name and prefix with a folder.
        "electron": .init("electron64", "cass"),
        "atom": .init("atom", "flop1", byExtension: tape, autoboot: #"\n*DOS\n*DIR\n*CAT\n*RUN""#),
        "archimedes": .init("aa4401", "flop"),
        "coco": .init("coco3", "cart", byExtension: tape.merging(["dsk": "flop1", "vdk": "flop1"]) { $1 }),
        "dragon32": .init("dragon32", "cart", byExtension: tape.merging(["dsk": "flop1", "vdk": "flop1"]) { $1 }),
        "ti99": .init("ti99_4a", "cart"),
        "oricatmos": .init("orica", "cass", autoboot: #"\nCLOAD""\n"#),
        "samcoupe": .init("samcoupe", "flop1"),
        "fm7": .init("fm7", "flop1", byExtension: ["t77": "cass", "wav": "cass"]),
        "fmtowns": .init("fmtmarty", "cdrm"),
        "camplynx": .init("lynx48k", "cass", autoboot: #"mload"""#),
        "adam": .init("adam", "cass", byExtension: ["dsk": "flop1", "col": "cart1", "rom": "cart1", "bin": "cart1"]),
        "bk": .init("bk001001", "cass", autoboot: #"LOAD\n"#),
    ]

    /// The slot `romURL` goes in.
    public func media(for romURL: URL) -> String {
        mediaByExtension[romURL.pathExtension.lowercased()] ?? media
    }

    /// The `.cmd` file's one line: the driver, the game in its slot, the
    /// autoboot command, then the folders MAME looks in for the machine's
    /// own ROMs (last, where the core expects a rompath).
    public func commandLine(romURL: URL, romPaths: [URL]) -> String {
        var words = [driver, "-" + media(for: romURL), Self.quoted(romURL.path)]
        if let autoboot {
            // The core splits on spaces outside quotes and has no escapes,
            // so a command with quotes in it is written without any.
            words += ["-autoboot_delay", "2", "-autoboot_command", autoboot.contains(" ") ? Self.quoted(autoboot) : autoboot]
        }
        words += ["-rompath", Self.quoted(romPaths.map(\.path).joined(separator: ";"))]
        return words.joined(separator: " ")
    }

    /// Writes the `.cmd` file for `romURL` into `folder` and returns it.
    public func writeCommandFile(romURL: URL, romPaths: [URL], in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: romURL.deletingPathExtension().lastPathComponent + ".cmd")
        try (commandLine(romURL: romURL, romPaths: romPaths) + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func quoted(_ text: String) -> String { "\"" + text + "\"" }
}

public extension EmulationFolder {
    /// Writes the `.cmd` file that starts `system`'s MAME machine with
    /// `romURL` in its slot, or returns nil when `system` isn't run that
    /// way. MAME looks for the machine's own set beside the game, in the
    /// BIOS folder and in BIOS/mame.
    func mameCommandFile(for system: CanonicalSystemID, romURL: URL, gameFolder: URL) throws -> URL? {
        guard let machine = MAMEMachine.machine(for: system), !machine.runsRomsets else { return nil }
        return try machine.writeCommandFile(
            romURL: romURL,
            romPaths: [gameFolder, bios, bios.appending(path: "mame", directoryHint: .isDirectory)],
            in: config.appending(path: "MAME commands", directoryHint: .isDirectory)
        )
    }
}
