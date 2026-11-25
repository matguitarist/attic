import Foundation
import ProcessKit

/// Namco System 246, 256 and Super 256 games, as MAME romsets: `soulclb2.zip`
/// holds the security dongle (`sc23vera.ic002` and its spare area
/// `sc23vera_spr.ic002`), and the `soulclb2` folder beside it the disc or
/// hard disk (`sc21-dvd0d.chd`).
///
/// PCSX2x6 runs them from its own files instead: a `.acgame` naming the
/// game by Namco's ID (NM00007), the dongle as a PS2 memory card image,
/// the boot program from its game library template, and the media.
/// `EmulationFolder.preparePCSX2x6Game` makes those from the set.
public enum Namco2x6 {
    public struct Game: Sendable, Equatable {
        /// Namco's ID, which names the game in PCSX2x6's template.
        public let gameID: String
        /// The set whose folder holds the media, for a clone that shares it.
        public let parent: String?

        init(_ gameID: String, parent: String? = nil) {
            self.gameID = gameID
            self.parent = parent
        }
    }

    /// MAME's sets, by name. The IDs come from the dongles' labels
    /// (SC23 Ver.A is NM00007), as PCSX2x6's game pages list them.
    public static let games: [String: Game] = [
        "rrvac": Game("NM00001"),
        "bldyr3b": Game("NM00002"),
        "vnight": Game("NM00003"),
        "tekken4": Game("NM00004"),
        "tekken4a": Game("NM00004", parent: "tekken4"),
        "tekken4b": Game("NM00004", parent: "tekken4"),
        "tekken4c": Game("NM00004", parent: "tekken4"),
        "wanganmr": Game("NM00005"),
        "scptour": Game("NM00006"),
        "soulclb2": Game("NM00007"),
        "wanganmd": Game("NM00008"),
        "batlgr3": Game("NM00010"),
        "batlgr37": Game("NM00010"),
        "batlgr38": Game("NM00010"),
        "batlgr3j": Game("NM00010", parent: "batlgr3"),
        "prdgp03": Game("NM00011"),
        "timecrs3": Game("NM00012"),
        "timecrs3e": Game("NM00012", parent: "timecrs3"),
        "timecrs3u": Game("NM00012", parent: "timecrs3"),
        "zgundm": Game("NM00013"),
        "batlgr3t": Game("NM00015"),
        "zoidsinf": Game("NM00016"),
        "zgundmdx": Game("NM00017"),
        "fghtjam": Game("NM00018"),
        "tekken51": Game("NM00019"),
        "cobrata": Game("NM00021"),
        "idolm": Game("NM00022"),
        "idolmtower": Game("NM00022", parent: "idolm"),
        "taiko7": Game("NM00023"),
        "gundzaft": Game("NM00024"),
        "zoidiexp": Game("NM00025"),
        "tekken5d": Game("NM00026"),
        "superdbz": Game("NM00027"),
        "kinniku": Game("NM00029"),
        "qgundam": Game("NM00030"),
        "soulclb3": Game("NM00031"),
        "timecrs4": Game("NM00032"),
        "timecrs4j": Game("NM00032", parent: "timecrs4"),
        "taiko8": Game("NM00033"),
        "yuyuhaku": Game("NM00035"),
        "sukuinuf": Game("NM00037"),
        "taiko9": Game("NM00038"),
        "motogp": Game("NM00039"),
        "kinniku2": Game("NM00040"),
        "taiko10": Game("NM00041"),
        "sbxc": Game("NM00042"),
        "gdvsgd": Game("NM00043"),
        "taiko11": Game("NM00044"),
        "acedriv3": Game("NM00047"),
        "fateulc": Game("NM00048"),
        "gdvsgdnx": Game("NM00052"),
        "taiko14": Game("NM00057"),
    ]

    /// PCSX2x6's game library template: a `<gameID>.acgame` and a
    /// `<gameID>/boot.elf` for each game it runs.
    public static let templateURL = URL(string: "https://github.com/PS2Homebrew-arcade/pcsx2x6/releases/download/v0.2.20/game_library_template.7z")!

    public static func game(forSet romURL: URL) -> Game? {
        games[romURL.deletingPathExtension().lastPathComponent.lowercased()]
    }

    // MARK: - Dongle

    /// A dongle's flash: 16,384 pages of 512 bytes, each with 16 spare bytes.
    static let pageCount = 16_384
    static let cardSize = pageCount * (512 + 16)

    /// The dongle as PCSX2x6's memory card image: MAME keeps the pages
    /// (`.ic002`) and their spare bytes (`_spr.ic002`) in two files, the
    /// card has each page followed by its spare bytes. A set that already
    /// has the whole card (`dongle.bin`) gives it as it is. `entries` are
    /// the set's files by name, read on demand.
    static func card(names: [String: Int], read: (String) -> Data?) -> Data? {
        // Files at the top of the zip only: a clone's own files may sit in
        // a folder of it.
        let top = names.filter { !$0.key.contains("/") }
        if let whole = top.first(where: { $0.value == cardSize }), let data = read(whole.key), data.count == cardSize {
            return data
        }
        guard let pages = top.first(where: { $0.value == pageCount * 512 && !$0.key.lowercased().contains("_spr") }),
              let spare = top.first(where: { $0.value == pageCount * 16 && $0.key.lowercased().contains("_spr") }),
              let pageData = read(pages.key), let spareData = read(spare.key),
              pageData.count == pageCount * 512, spareData.count == pageCount * 16 else { return nil }
        return interleave(pages: pageData, spare: spareData)
    }

    static func interleave(pages: Data, spare: Data) -> Data {
        var card = Data(capacity: cardSize)
        for page in 0..<pageCount {
            card.append(pages[(pages.startIndex + page * 512)..<(pages.startIndex + (page + 1) * 512)])
            card.append(spare[(spare.startIndex + page * 16)..<(spare.startIndex + (page + 1) * 16)])
        }
        return card
    }

    /// The dongle card of the set in `zip`, or nil when it has none.
    public static func card(fromSet zip: URL) -> Data? {
        guard let listing = run("/usr/bin/zipinfo", ["-s", zip.path]) else { return nil }
        // "-rw-a--     2.0 fat  8388608 b- defX 96-Dec-24 23:32 sc23vera.ic002"
        var names: [String: Int] = [:]
        for line in String(decoding: listing, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard fields.count == 9, let size = Int(fields[3]) else { continue }
            names[String(fields[8])] = size
        }
        return card(names: names) { run("/usr/bin/unzip", ["-p", zip.path, $0]) }
    }

    // MARK: - Media

    /// The set's disc or hard disk image: in the folder named like it,
    /// else in its parent's.
    public static func media(forSet romURL: URL) -> URL? {
        let folder = romURL.deletingLastPathComponent()
        let set = romURL.deletingPathExtension().lastPathComponent
        for name in [set, game(forSet: romURL)?.parent].compactMap({ $0 }) {
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder.appending(path: name, directoryHint: .isDirectory),
                                                                        includingPropertiesForKeys: nil)) ?? []
            if let chd = entries.filter({ $0.pathExtension.lowercased() == "chd" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
                return chd
            }
        }
        return nil
    }

    static func run(_ executable: String, _ arguments: [String]) -> Data? {
        guard let output = try? Shell.runSync(executable, arguments, options: Shell.Options(stderr: .discard)), output.succeeded else { return nil }
        return output.stdout
    }
}
