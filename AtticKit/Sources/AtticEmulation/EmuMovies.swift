import Foundation
import AtticModels
import AtticLibraryScanning

/// EmuMovies' file server (files.emumovies.com), where members get the
/// media EmuMovies Sync downloads on Windows:
///
///     /Official/Artwork/Atari Lynx/Atari Lynx (Boxes-2D)(No-Intro)(EM 2.1).zip
///     /Official/Game Manuals/Atari Lynx (Game Manuals)(EM 1.1)/Klax (USA, Europe).pdf
///     /Official/Platform Videos/Atari Lynx - Unified (16x9)(HD).mp4
///
/// Artwork comes as one archive per system and kind, named after the ROM
/// sets (No-Intro, Redump, MAME); manuals one PDF per game; system videos
/// one file per system. Each section names systems its own way.
public enum EmuMovies {
    public static let artworkFolder = "/Official/Artwork/"
    public static let manualsFolder = "/Official/Game Manuals/"
    public static let videosFolder = "/Official/Platform Videos/"
    /// One video per game, in a folder per system (or per region). The HD
    /// ones are for premium accounts, and empty otherwise.
    public static let videoSnapsFolder = "/Official/Video Snaps (HQ)/"

    /// A system's names on the server: its artwork folder, the start of
    /// its manuals folder's name, and the start of its system video's.
    public struct SystemNames: Sendable, Equatable {
        public let artwork: String?
        public let manuals: String?
        public let video: String?
    }

    public static func names(for system: CanonicalSystemID) -> SystemNames? {
        systemNames[system.rawValue]
    }

    private static func names(_ artwork: String?, manuals: String? = nil, video: String? = nil) -> SystemNames {
        SystemNames(artwork: artwork, manuals: manuals, video: video)
    }

    private static func same(_ name: String) -> SystemNames { SystemNames(artwork: name, manuals: name, video: name) }

    private static let systemNames: [String: SystemNames] = [
        "3do": names("3DO Interactive Multiplayer", manuals: "3DO Interactive Multiplayer", video: "Panasonic 3DO"),
        "amiga": same("Commodore Amiga"),
        "amstradcpc": same("Amstrad CPC"),
        "atari2600": same("Atari 2600"),
        "atari5200": same("Atari 5200"),
        "atari7800": same("Atari 7800"),
        "atari800": same("Atari 8-bit"),
        "atarijaguar": same("Atari Jaguar"),
        "atarilynx": same("Atari Lynx"),
        "atarist": same("Atari ST"),
        "atomiswave": names("Sammy Atomiswave", video: "Sammy Atomiswave"),
        "c128": names("Commodore 128", video: "Commodore 128"),
        "c64": same("Commodore 64"),
        "cdi": names("Philips CD-I", video: "Philips CD-i"),
        "channelf": same("Fairchild Channel F"),
        "colecovision": same("ColecoVision"),
        "cps1": names("Capcom CPS1", manuals: "Capcom CPS-1", video: "Capcom Play System"),
        "cps2": names("Capcom CPS2", video: "Capcom Play System II"),
        "cps3": names("Capcom CPS3", video: "Capcom Play System III"),
        "dos": same("Microsoft MS-DOS"),
        "dreamcast": same("Sega Dreamcast"),
        "fbneo": names("Final Burn Alpha", video: "Final Burn Alpha"),
        "fds": names("Nintendo Famicom Disk System", video: "Nintendo Famicom Disk System"),
        "gameandwatch": names("Nintendo Game & Watch", video: "Game & Watch"),
        "gamecube": same("Nintendo GameCube"),
        "gamegear": names("Sega Game Gear", video: "Sega Game Gear"),
        "gb": same("Nintendo Game Boy"),
        "gba": same("Nintendo Game Boy Advance"),
        "gbc": names("Nintendo Gameboy Color", manuals: "Nintendo Game Boy Color", video: "Nintendo Game Boy Color"),
        "genesis": names("Sega Genesis - Mega Drive", manuals: "Sega Genesis", video: "Sega Genesis"),
        "intellivision": same("Mattel Intellivision"),
        "mame": same("MAME"),
        "mastersystem": same("Sega Master System"),
        "model2": names("Sega Model 2", video: "Sega Model 2"),
        "model3": names("Sega Model 3", video: "Sega Model 3"),
        "msx": names("Microsoft MSX", video: "Microsoft MSX"),
        "n3ds": names("Nintendo 3DS", video: "Nintendo 3DS"),
        "n64": same("Nintendo 64"),
        "n64dd": names("Nintendo 64DD", manuals: "Nintendo 64DD"),
        "naomi": names("Sega Naomi - Naomi 2", video: "Sega Naomi"),
        "naomi2": names("Sega Naomi - Naomi 2", video: "Sega Naomi"),
        "naomigd": names("Sega Naomi - Naomi 2", video: "Sega Naomi"),
        "nds": same("Nintendo DS"),
        "neogeo": names("SNK Neo Geo MVS", manuals: "SNK Neo-Geo MVS", video: "SNK Neo Geo MVS"),
        "neogeocd": names("SNK Neo Geo CD", video: "SNK Neo Geo CD"),
        "nes": names("Nintendo Entertainment System", manuals: "Nintendo NES", video: "Nintendo Entertainment System"),
        "ngp": names("SNK Neo Geo Pocket", video: "SNK Neo Geo Pocket"),
        "ngpc": names("SNK Neo Geo Pocket Color", video: "SNK Neo Geo Pocket Color"),
        "odyssey2": same("Magnavox Odyssey 2"),
        "pc98": names("NEC PC-98"),
        "pcengine": names("NEC PC Engine - Turbografx 16", manuals: "NEC TurboGrafx-16", video: "NEC TurboGrafx-16"),
        "pcenginecd": names("NEC PC Engine CD - Turbografx CD", manuals: "NEC PC Engine CD", video: "NEC TurboGrafx-CD"),
        "pcfx": names("NEC PC-FX", video: "NEC PC-FX"),
        "plus4": names("Commodore 16 - Plus 4", video: "Commodore 16 & Plus4"),
        "pokemini": names("Nintendo Pokemon Mini", video: "Nintendo Pokemon Mini"),
        "ps2": same("Sony PlayStation 2"),
        "ps3": same("Sony PlayStation 3"),
        "psp": names("Sony Playstation Portable", manuals: "Sony PlayStation Portable", video: "Sony PlayStation Portable"),
        "psvita": names("Sony PlayStation Vita", video: "Sony PlayStation Vita"),
        "psx": same("Sony PlayStation"),
        "satellaview": names("Nintendo Satellaview", video: "Nintendo Satellaview"),
        "saturn": same("Sega Saturn"),
        "scummvm": names("ScummVM", video: "ScummVM"),
        "sega32x": same("Sega 32X"),
        "segacd": same("Sega CD"),
        "sg1000": same("Sega SG-1000"),
        "snes": names("Super Nintendo Entertainment System", manuals: "Nintendo Super Nintendo", video: "Super Nintendo Entertainment System"),
        "steam": names(nil, video: "Steam"),
        "stv": names("Sega ST-V", video: "Sega ST-V"),
        "sufami": names("Bandai Sufami Turbo", video: "Bandai Sufami Turbo"),
        "supergrafx": names("NEC PC-Engine SuperGrafx", video: "NEC SuperGrafx"),
        "triforce": names("Sega Triforce", video: "Sega Triforce"),
        "vectrex": same("GCE Vectrex"),
        "vic20": names("Commodore Vic-20", video: "Commodore VIC-20"),
        "virtualboy": same("Nintendo Virtual Boy"),
        "wii": same("Nintendo Wii"),
        "wiiu": same("Nintendo Wii U"),
        "wonderswan": names("Bandai Wonderswan", manuals: "Bandai WonderSwan", video: "Bandai WonderSwan"),
        "wonderswancolor": names("Bandai Wonderswan Color", manuals: "Bandai WonderSwan Color", video: "Bandai WonderSwan Color"),
        "x68000": names("Sharp X68000", video: "Sharp X68000"),
        "xbox": names("Microsoft XBOX", manuals: "Microsoft XBOX", video: "Microsoft - Xbox"),
        "zx81": names(nil, video: "Sinclair ZX81"),
        "zxspectrum": same("Sinclair ZX Spectrum")
    ]

    /// The starts of a system's video snaps folders' names, which follow
    /// none of the other names. A system split by region has several.
    public static func videoSnapsPrefixes(for system: CanonicalSystemID) -> [String] {
        videoSnapsNames[system.rawValue] ?? []
    }

    private static let videoSnapsNames: [String: [String]] = [
        "3do": ["Panasonic 3DO"], "amiga": ["Commodore Amiga"], "amstradcpc": ["Amstrad CPC"],
        "atari2600": ["Atari 2600"], "atari5200": ["Atari 5200"], "atari7800": ["Atari 7800"],
        "atarijaguar": ["Atari Jaguar"], "atarilynx": ["Atari Lynx"], "atarist": ["Atari ST"],
        "atomiswave": ["Sammy Atomiswave"], "c64": ["Commodore 64"], "cdi": ["Phillips CD-i"],
        "channelf": ["Fairchild Channel F"], "colecovision": ["Colecovision"],
        "cps1": ["Capcom CPS-1"], "cps2": ["Capcom CPS-2"], "cps3": ["Capcom CPS-3"],
        "dos": ["Microsoft DOS"], "dreamcast": ["Sega Dreamcast"], "fds": ["Nintendo Famicom Disk System"],
        "gameandwatch": ["Nintendo Game & Watch"], "gamecube": ["Nintendo GameCube"], "gamegear": ["Sega Game Gear"],
        "gb": ["Nintendo Game Boy"], "gba": ["Nintendo GBA"], "gbc": ["Nintendo Game Boy Color"],
        "genesis": ["Sega Genesis - USA", "Sega Mega Drive - Europe", "Sega Mega Drive - Japan"],
        "intellivision": ["Mattel Intellivision"], "mame": ["MAME Arcade"], "mastersystem": ["Sega Master System"],
        "model2": ["Sega Model 2"], "model3": ["Sega Model 3"], "msx": ["Microsoft MSX - Carts", "Microsoft MSX - Discs"],
        "n3ds": ["Nintendo 3DS"], "n64": ["Nintendo 64"], "n64dd": ["Nintendo 64DD"],
        "naomi": ["Sega Naomi - Naomi 2"], "naomi2": ["Sega Naomi - Naomi 2"], "naomigd": ["Sega Naomi - Naomi 2"],
        "nds": ["Nintendo DS"], "neogeo": ["SNK Neo Geo MVS"], "neogeocd": ["SNK Neo Geo CD"],
        "nes": ["Nintendo Entertainment System"], "ngp": ["SNK Neo Geo Pocket"], "ngpc": ["SNK Neo Geo Pocket Color"],
        "odyssey2": ["Magnavox Odyssey 2"], "pc98": ["NEC PC-98"],
        "pcengine": ["NEC TurboGrafx 16", "NEC PC Engine"], "pcenginecd": ["NEC TurboGrafx CD", "NEC PC Engine CD"],
        "pcfx": ["NEC PC-FX"], "pokemini": ["Nintendo Pokemon Mini"], "ps2": ["Sony Playstation 2"],
        "ps3": ["Sony Playstation 3 - Retail", "Sony Playstation 3 - PSN"], "psp": ["Sony PSP"], "psx": ["Sony Playstation"],
        "saturn": ["Sega Saturn"], "scummvm": ["ScummVM"], "sega32x": ["Sega 32X"], "segacd": ["Sega CD"],
        "sg1000": ["Sega SG-1000"], "snes": ["Nintendo Super Nintendo", "Nintendo Super Famicom"],
        "sufami": ["Bandai Sufami Turbo"], "supergrafx": ["NEC PC-Engine SuperGrafx"], "triforce": ["Sega Triforce"],
        "vectrex": ["GCE Vectrex"], "vic20": ["Commodore VIC-20"], "virtualboy": ["Nintendo Virtual Boy"],
        "wii": ["Nintendo Wii"], "wiiu": ["Nintendo Wii U", "Nintendo WiiU"], "wonderswan": ["Bandai WonderSwan"],
        "wonderswancolor": ["Bandai WonderSwan Color"], "x68000": ["Sharp X68000"], "xbox": ["Microsoft XBOX"],
        "zxspectrum": ["Sinclair ZX Spectrum"]
    ]

    // MARK: - Listings

    /// A file or folder in a listing of the server.
    public struct Entry: Sendable, Equatable, Codable {
        public let name: String
        public let isFolder: Bool
        public let size: Int64
        /// The date the listing shows, as written: a folder's changes
        /// when files are added to it or taken out.
        public var modified = ""
    }

    /// An FTP `LIST` answer, in the DOS style EmuMovies' (Microsoft) server
    /// gives or the Unix style most others do.
    ///
    ///     06-01-18  05:18PM             22145735 Atari Lynx (2D Carts)(32assassin 2.0).zip
    ///     02-10-25  10:30AM       <DIR>          Atari Lynx (Game Manuals)(EM 1.1)
    ///     -rw-r--r--   1 owner group  22145735 Jun  1  2018 Atari Lynx (2D Carts)(32assassin 2.0).zip
    public static func entries(inListing listing: String) -> [Entry] {
        listing.split(whereSeparator: \.isNewline).compactMap { line in
            let line = String(line)
            if let match = line.wholeMatch(of: /(\d\d-\d\d-\d\d+\s+\d\d:\d\d[AP]M)\s+(<DIR>|\d+)\s+(.+)/) {
                let folder = match.2 == "<DIR>"
                return Entry(name: String(match.3), isFolder: folder, size: folder ? 0 : Int64(match.2) ?? 0, modified: String(match.1))
            }
            if let match = line.wholeMatch(of: /([dl-])[rwxsStT-]{9}\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w{3}\s+\d+\s+[\d:]+)\s(.+)/) {
                let name = String(match.4)
                guard name != ".", name != ".." else { return nil }
                return Entry(name: name, isFolder: match.1 == "d", size: Int64(match.2) ?? 0, modified: String(match.3))
            }
            return nil
        }
    }

    /// Folder listings kept from one look to the next, so a folder is read
    /// again only when the listing of its parent shows it changed: the
    /// manuals of a big system take a while to list.
    public struct ListingCache: Codable, Sendable {
        struct Listing: Codable, Sendable {
            /// The folder's date in its parent's listing when it was read.
            var modified: String
            var read: Date
            var entries: [Entry]
        }

        var listings: [String: Listing] = [:]
        /// Read again past this, in case a file was replaced in place,
        /// which leaves the folder's date alone.
        static let maxAge: TimeInterval = 30 * 24 * 3600

        public init() {}

        /// What `path` held, if `folder` (its entry in its parent's
        /// listing) shows it hasn't changed since.
        public func entries(of path: String, folder: Entry, now: Date = .now) -> [Entry]? {
            guard let listing = listings[path], !folder.modified.isEmpty, listing.modified == folder.modified,
                  now.timeIntervalSince(listing.read) < Self.maxAge else { return nil }
            return listing.entries
        }

        public mutating func store(_ entries: [Entry], of path: String, folder: Entry, now: Date = .now) {
            listings[path] = Listing(modified: folder.modified, read: now, entries: entries)
        }

        public static func load(from url: URL) -> ListingCache {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ListingCache.self, from: $0) } ?? ListingCache()
        }

        public func save(to url: URL) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }

    // MARK: - Artwork packs

    /// An archive of one kind of artwork for one system, which may be
    /// split in parts (`….part1.rar`, `….part2.rar`).
    public struct Pack: Sendable, Equatable, Identifiable, Hashable {
        /// The name without its extension and part number.
        public let name: String
        /// Its files on the server, in order.
        public let files: [String]
        public let size: Int64
        public let kind: MediaKind
        public var id: String { name }

        public var isSplit: Bool { files.count > 1 }
    }

    /// The artwork packs in a system's folder that Attic has a place for.
    public static func packs(in entries: [Entry]) -> [Pack] {
        var parts: [String: [Entry]] = [:]
        for entry in entries where !entry.isFolder {
            guard let name = packName(entry.name) else { continue }
            parts[name, default: []].append(entry)
        }
        return parts.compactMap { name, entries in
            guard let kind = kind(ofPack: name) else { return nil }
            let files = entries.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return Pack(name: name, files: files, size: entries.reduce(0) { $0 + $1.size }, kind: kind)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `Atari Lynx (Logos)(EM 2.1).zip` → `Atari Lynx (Logos)(EM 2.1)`;
    /// nil when it isn't an archive.
    static func packName(_ file: String) -> String? {
        guard let match = file.wholeMatch(of: /(.+?)(\.part\d+)?\.(zip|rar|7z)/.ignoresCase()) else { return nil }
        return String(match.1)
    }

    /// The kind of artwork a pack holds, from the first bracket after the
    /// system's name: `Atari Lynx (Boxes-2D)(No-Intro)(EM 2.1)` holds covers.
    /// Backs, spines, carts, marquees and the like have no place in Attic.
    static func kind(ofPack name: String) -> MediaKind? {
        guard let match = name.firstMatch(of: /[(\[]([^)\]]+)[)\]]/) else { return nil }
        let tag = match.1.lowercased()
        if tag.contains("back") || tag.contains("spine") || tag.contains("texture") || tag.contains("full") { return nil }
        if tag.contains("3d box") || tag.contains("boxes-3d") { return .boxes3D }
        if tag.contains("2d box") || tag.contains("boxes-2d") || tag == "boxes" || tag == "box art" { return .covers }
        if tag.contains("logo") || tag.contains("wheel") { return .logos }
        if tag.contains("background") || tag.contains("fanart") { return .fanart }
        if tag.contains("snap") { return .screenshots }
        // Flat cartridges and discs, not their labels alone, their tops or 3D renders.
        if tag.contains("label") || tag.contains("top") { return nil }
        if tag.contains("2d cart") || tag.contains("disc") { return .physicalMedia }
        return nil
    }

    /// The pack to use for each kind: EmuMovies' own newest set first,
    /// then gameplay over title snaps, and a single archive over a split
    /// one when split ones can't be opened.
    public static func bestPacks(_ packs: [Pack], canOpenSplit: Bool) -> [MediaKind: Pack] {
        Dictionary(grouping: packs.filter { canOpenSplit || !$0.isSplit }, by: \.kind).compactMapValues { candidates in
            candidates.max { rank($0) < rank($1) }
        }
    }

    private static func rank(_ pack: Pack) -> (Int, Int, Int, String) {
        let name = pack.name.lowercased()
        let official = name.contains("(em ") || name.contains("[em ") ? 1 : 0
        let gameplay = name.contains("title") ? 0 : 1
        let named = name.contains("no-intro") || name.contains("redump") || name.contains("mame") ? 1 : 0
        // The version last, so `EM 2.1` comes before `EM 1.2`.
        let version = name.firstMatch(of: /em ([\d.]+)/).map { String($0.1) } ?? ""
        return (official, gameplay, named, version)
    }

    // MARK: - Manuals and videos

    /// The folder of PDF manuals for a system whose manuals folders start
    /// with `prefix`: the whole set rather than its Japanese or extras one.
    public static func manualsFolder(in entries: [Entry], prefix: String) -> String? {
        let folders = entries.filter { $0.isFolder && isNamed($0.name, startingWith: prefix) }.map(\.name)
        func preference(_ name: String) -> Int {
            let name = name.lowercased()
            if name.contains("(cbz)") || name.contains("extras") || name.contains("japan") || name.contains("brazil") || name.contains("europe") { return 0 }
            return name.contains("usa") ? 1 : 2
        }
        return folders.max { (preference($0), $0) < (preference($1), $1) }
    }

    /// A system's video, wide and in HD when there's one.
    /// A system's video snaps folders, best first: a file in the first
    /// one wins over the same file in the next. Hacks, homebrew and other
    /// side sets are left out.
    public static func videoSnapsFolders(in entries: [Entry], prefixes: [String]) -> [String] {
        func preference(_ name: String) -> Int {
            let name = name.lowercased()
            if name.contains("no-intro") || name.contains("redump") { return 0 }
            if name.contains("(usa)") { return 1 }
            return 2
        }
        let skipped = ["hacks", "homebrew", "translations", "tko", "hyperspin"]
        return entries.filter { entry in
            let name = entry.name.lowercased()
            return entry.isFolder && prefixes.contains { name.hasPrefix($0.lowercased() + " (") } && !skipped.contains { name.contains($0) }
        }
        .map(\.name)
        .sorted { (preference($0), $0) < (preference($1), $1) }
    }

    public static func systemVideo(in entries: [Entry], prefix: String) -> Entry? {
        let videos = entries.filter { !$0.isFolder && $0.name.lowercased().hasSuffix(".mp4") && $0.name.lowercased().hasPrefix(prefix.lowercased() + " - ") }
        func preference(_ entry: Entry) -> Int {
            let name = entry.name
            if name.hasPrefix(prefix + " - Unified (16x9)(HD)") { return 3 }
            if name.contains("(16x9)") { return 2 }
            return name.contains("EM Default") ? 1 : 0
        }
        return videos.max { (preference($0), $1.name) < (preference($1), $0.name) }
    }

    /// `Sega 32X (Game Manuals)` starts with Sega 32X, `Sega 32X CD …` doesn't.
    private static func isNamed(_ name: String, startingWith prefix: String) -> Bool {
        guard name.lowercased().hasPrefix(prefix.lowercased()) else { return false }
        let rest = name.dropFirst(prefix.count)
        return rest.isEmpty || rest.hasPrefix(" (") || rest.hasPrefix(" [") || rest.hasPrefix(" - ")
    }

    // MARK: - Matching

    /// Which of `files` goes with each game, by name: the same name first,
    /// then the same title (ignoring punctuation, a leading or trailing
    /// "The", and a subtitle one side lacks) in the closest region.
    /// `games` and `files` are names without extensions; the answer maps
    /// each game matched to its file.
    public static func match(games: [String], files: [String]) -> [String: String] {
        let exact = Set(files)
        var byTitle: [String: [String]] = [:]
        var byMainTitle: [String: [String]] = [:]
        for file in files {
            byTitle[title(file), default: []].append(file)
            byMainTitle[mainTitle(file), default: []].append(file)
        }
        var matches: [String: String] = [:]
        for game in games {
            if exact.contains(game) {
                matches[game] = game
            } else if let candidates = byTitle[title(game)] {
                matches[game] = closest(to: game, in: candidates)
            } else if let candidates = byMainTitle[mainTitle(game)] {
                // Only when one side has no subtitle: "Gordo 106" is
                // "Gordo 106 - The Mutated Lab Monkey", but "Zelda - A"
                // isn't "Zelda - B".
                let plain = candidates.filter { !hasSubtitle($0) || !hasSubtitle(game) }
                if Set(plain.map(title)).count == 1 { matches[game] = closest(to: game, in: plain) }
            }
        }
        return matches
    }

    private static func closest(to game: String, in candidates: [String]) -> String? {
        let wanted = regions(game)
        return candidates.max { a, b in
            let (ra, rb) = (regions(a).intersection(wanted).count, regions(b).intersection(wanted).count)
            return ra != rb ? ra < rb : a.count > b.count
        }
    }

    /// The name before its first bracket.
    private static func bare(_ name: String) -> String {
        String(name.prefix { $0 != "(" && $0 != "[" }).trimmingCharacters(in: .whitespaces)
    }

    static func title(_ name: String) -> String {
        simplified(bare(name))
    }

    private static func mainTitle(_ name: String) -> String {
        let bare = bare(name)
        return simplified(bare.components(separatedBy: " - ").first ?? bare)
    }

    private static func hasSubtitle(_ name: String) -> Bool { bare(name).contains(" - ") }

    private static func simplified(_ title: String) -> String {
        var title = title.lowercased()
        title = title.replacing(/, the\b/, with: "")
        if title.hasPrefix("the ") { title.removeFirst(4) }
        return String(title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// `Klax (USA, Europe)` → USA, Europe. A world release is both.
    private static func regions(_ name: String) -> Set<String> {
        guard let match = name.firstMatch(of: /\(([^)]*)\)/) else { return [] }
        let regions = Set(match.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return regions.contains("world") ? regions.union(["usa", "europe"]) : regions
    }
}
