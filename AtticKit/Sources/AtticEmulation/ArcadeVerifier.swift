import Foundation
import AtticModels
import AtticLibraryScanning

/// Checks arcade romsets against the DAT of the emulator that runs them —
/// FinalBurn Neo's, or MAME's game list (`-listxml`): is every chip there
/// with the data that version expects, counting what a clone takes from
/// its parent's zip and a game from its BIOS set; and is each disc image
/// (a CHD) the right one. Zips are read from their directory, CHDs from
/// their header: nothing is unpacked.
public struct ArcadeVerifier: Sendable {
    public enum Source: String, Sendable, Codable, CaseIterable {
        case fbneo, mame
    }

    struct ROM: Sendable, Codable, Hashable {
        let name: String
        let size: Int
        let crc: UInt32
    }

    struct Disk: Sendable, Codable, Hashable {
        let name: String
        let sha1: String
    }

    struct Machine: Sendable, Codable {
        let title: String
        let cloneOf: String?
        let romOf: String?
        let roms: [ROM]
        let disks: [Disk]
    }

    struct Set: Sendable, Codable {
        /// "MAME 0.289", "FinalBurn Neo v1.0.0.03".
        let name: String
        let machines: [String: Machine]
        /// Every machine's parent and BIOS, to find the zips a set leans on.
        let parents: [String: [String]]
        /// ROMs dozens of games list: a BIOS's. FinalBurn Neo lists each of
        /// a board's BIOS versions in every game, when one of them is
        /// enough (MAME marks them).
        let biosCRCs: Swift.Set<UInt32>
    }

    /// How many games must list a ROM for it to be a BIOS's.
    static let biosSharing = 20

    private var sets: [Source: Set] = [:]

    public var sources: Swift.Set<Source> { Swift.Set(sets.keys) }
    public var names: [String] { sets.values.map(\.name).sorted() }
    /// The DAT read for a source: "MAME 0.289".
    public func name(of source: Source) -> String? { sets[source]?.name }

    init(sets: [Source: Set]) {
        self.sets = sets
    }

    /// No arcade DAT: nothing checked.
    public static let none = ArcadeVerifier(sets: [:])

    // MARK: - Checking

    static func hex(_ crc: UInt32) -> String { String(format: "%08x", crc) }

    /// ROM file names, the first eight of them: "a.c1, b.c2 and 3 more".
    static func listed(_ names: [String]) -> String {
        let shown = Array(names.prefix(8))
        guard names.count > shown.count else { return shown.formatted(.list(type: .and)) }
        return String(localized: "\(shown.joined(separator: ", ")) and \(names.count - shown.count) more", bundle: .module)
    }

    /// nil when there's no DAT, or the set can't be read (a 7z).
    public func check(_ url: URL, preferring preferred: Source, biosDirectory: URL) -> DATVerifier.Check? {
        guard url.pathExtension.lowercased() == "zip" else { return nil }
        let setName = url.deletingPathExtension().lastPathComponent.lowercased()
        // A set the preferred DAT doesn't list may be in the other's.
        let available = ([preferred] + Source.allCases.filter { $0 != preferred }).compactMap { sets[$0] }
        guard !available.isEmpty else { return nil }
        guard let set = available.first(where: { $0.machines[setName] != nil }), let machine = set.machines[setName] else {
            return DATVerifier.Check(verdict: .unknown, name: nil)
        }

        let folder = url.deletingLastPathComponent()
        var pool = Self.entries(of: url)
        for name in Self.chain(of: setName, in: set) {
            if let zip = Self.zip(named: name, near: folder, biosDirectory: biosDirectory) {
                pool += Self.entries(of: zip)
            }
        }
        let crcs = Swift.Set(pool.map(\.crc))
        let names = Swift.Set(pool.map { ($0.name as NSString).lastPathComponent.lowercased() })

        var missing: [UInt32] = []
        var missingNames: [String] = []
        var wrongNames: [String] = []
        // A board's BIOS versions, and those a game carries itself (The
        // Irritating Maze's own and its Japanese hack): any one does.
        func isBIOS(_ rom: ROM) -> Bool {
            set.biosCRCs.contains(rom.crc) || rom.name.lowercased().contains("bios")
        }
        let biosROMs = machine.roms.filter(isBIOS)
        for rom in machine.roms where !crcs.contains(rom.crc) && !isBIOS(rom) {
            if names.contains(rom.name.lowercased()) {
                // The CRC it should have, and the one it has.
                let found = pool.first { ($0.name as NSString).lastPathComponent.lowercased() == rom.name.lowercased() }?.crc
                wrongNames.append(String(localized: "\(rom.name) (CRC \(Self.hex(rom.crc)), yours \(found.map(Self.hex) ?? "?"))", bundle: .module))
            } else {
                missing.append(rom.crc)
                missingNames.append(rom.name)
            }
        }
        // Any one BIOS version does; none at all, and the game can't start.
        let biosMissing = !biosROMs.isEmpty && !biosROMs.contains { crcs.contains($0.crc) }
        var missingDisks: [String] = []
        var wrongDisks: [String] = []
        let folders = [setName] + Self.chain(of: setName, in: set)
        for disk in machine.disks {
            let candidates = folders.map { folder.appending(path: $0).appending(path: disk.name + ".chd") }
            guard let chd = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                missingDisks.append(disk.name)
                continue
            }
            if let header = CHDHeader.read(chd), header.sha1.lowercased() != disk.sha1.lowercased() {
                wrongDisks.append(String(localized: "\(disk.name) (SHA-1 \(disk.sha1.lowercased()), yours \(header.sha1.lowercased()))", bundle: .module))
            }
        }

        var details: [String] = []
        if biosMissing, let bios = Self.chain(of: setName, in: set).last {
            details.append(String(localized: "BIOS set \(bios).zip missing", bundle: .module))
        }
        if !wrongNames.isEmpty {
            details.append(String(localized: "\(wrongNames.count) ROMs from another version: \(Self.listed(wrongNames))", bundle: .module))
        }
        if !missing.isEmpty {
            // Another set's zip may hold them: a game the emulator lists
            // on its own, kept as another's clone ("in puzzledp.zip").
            let elsewhere = Self.zips(holding: missing, in: folder, besides: [setName] + Self.chain(of: setName, in: set))
            details.append(elsewhere.isEmpty
                ? String(localized: "\(missing.count) ROMs missing: \(Self.listed(missingNames))", bundle: .module)
                : String(localized: "\(missing.count) ROMs missing: \(Self.listed(missingNames)) (in \(elsewhere.map { $0 + ".zip" }.formatted(.list(type: .and))))", bundle: .module))
        }
        for disk in wrongDisks { details.append(String(localized: "disc image \(disk) from another version", bundle: .module)) }
        for disk in missingDisks { details.append(String(localized: "disc image \(disk).chd missing", bundle: .module)) }
        let detail = details.isEmpty ? nil : details.joined(separator: "; ")
        let verdict: DATVerifier.Verdict = !wrongNames.isEmpty || !wrongDisks.isEmpty ? .differs
            : !missing.isEmpty || biosMissing || !missingDisks.isEmpty ? .incomplete : .verified
        return DATVerifier.Check(verdict: verdict, name: machine.title, detail: detail.map { "\(set.name): \($0)" })
    }

    /// The other zips in `folder` that hold any of `crcs`, by set name.
    private static func zips(holding crcs: [UInt32], in folder: URL, besides: [String]) -> [String] {
        let index = FolderIndex.crcs(in: folder)
        let skipped = Swift.Set(besides)
        return Swift.Set(crcs.flatMap { index[$0] ?? [] }).filter { !skipped.contains($0) }.sorted()
    }

    /// The parents and BIOS sets a set leans on, nearest first.
    private static func chain(of name: String, in set: Set) -> [String] {
        var result: [String] = []
        var queue = set.parents[name] ?? []
        while let next = queue.first {
            queue.removeFirst()
            guard !result.contains(next), result.count < 8 else { continue }
            result.append(next)
            queue += set.parents[next] ?? []
        }
        return result
    }

    /// A parent's or BIOS's zip: beside the game, else in the BIOS folder
    /// or one of its folders (dc/naomi.zip, fbneo/neogeo.zip).
    private static func zip(named name: String, near folder: URL, biosDirectory: URL) -> URL? {
        let file = name + ".zip"
        let subfolders = ((try? FileManager.default.contentsOfDirectory(at: biosDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        return ([folder, biosDirectory] + subfolders).map { $0.appending(path: file) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func entries(of zip: URL) -> [ZipContents.Entry] {
        (ZipContents.entries(of: zip) ?? []).filter { !$0.name.hasSuffix("/") }
    }

    // MARK: - Loading

    /// Whether a DAT (from its first bytes, or a zip's file name) is an
    /// arcade one, which No-Intro's checks leave alone.
    static func isArcade(head: String) -> Bool {
        head.contains("<mame") || head.contains("FinalBurn") || head.range(of: #"<name>[^<]*MAME"#, options: .regularExpression) != nil
    }

    public static func isArcadeZip(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix("mame") && name.hasSuffix("lx.zip")
    }

    /// The arcade DATs in `folder` (MAME's `mame0289lx.zip` as it comes),
    /// keeping only the sets in `wanted` — MAME's list has some 50,000.
    /// What's read is cached in `cacheDirectory` until the DATs change.
    public static func load(from folder: URL, wanted: Swift.Set<String>, cacheDirectory: URL) -> ArcadeVerifier {
        let wanted = Swift.Set(wanted.map { $0.lowercased() })
        var sets: [Source: Set] = [:]
        for file in datFiles(in: folder) {
            let signature = Self.signature(of: file)
            let cache = cacheDirectory.appending(path: "Arcade-\(signature.hash).json")
            if let cached = (try? Data(contentsOf: cache)).flatMap({ try? JSONDecoder().decode(CachedSet.self, from: $0) }),
               cached.signature == signature, wanted.isSubset(of: cached.wanted) {
                sets[cached.source] = sets[cached.source] ?? cached.set
                continue
            }
            guard let (source, set) = parse(file, wanted: wanted) else { continue }
            if sets[source] == nil { sets[source] = set }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(CachedSet(signature: signature, wanted: wanted, source: source, set: set)).write(to: cache, options: .atomic)
        }
        return ArcadeVerifier(sets: sets)
    }

    private struct CachedSet: Codable {
        let signature: String
        let wanted: Swift.Set<String>
        let source: Source
        let set: Set
    }

    private static func signature(of file: URL) -> String {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(file.lastPathComponent)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    /// Newest first, so a newer MAME list wins over an older one.
    private static func datFiles(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { file in
            if isArcadeZip(file) { return true }
            guard ["dat", "xml"].contains(file.pathExtension.lowercased()),
                  let handle = try? FileHandle(forReadingFrom: file),
                  let head = try? handle.read(upToCount: 4096) else { return false }
            try? handle.close()
            return isArcade(head: String(decoding: head, as: UTF8.self))
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    static func parse(_ file: URL, wanted: Swift.Set<String>) -> (Source, Set)? {
        var xml = file
        var temporary: URL?
        if isArcadeZip(file) {
            // MAME's list unpacks to some 300 MB: read as a stream from a
            // temporary file rather than into memory.
            let out = FileManager.default.temporaryDirectory.appending(path: "attic-\(UUID().uuidString).xml")
            FileManager.default.createFile(atPath: out.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: out) else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", file.path]
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            try? handle.close()
            xml = out
            temporary = out
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        guard let parser = XMLParser(contentsOf: xml) else { return nil }
        let reader = Reader(wanted: wanted)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        parser.parse()
        guard !reader.parents.isEmpty || !reader.machines.isEmpty else { return nil }
        let source: Source = reader.name.contains("FinalBurn") ? .fbneo : .mame
        let name = reader.build.map { "MAME \($0.components(separatedBy: " ").first ?? $0)" } ?? reader.name
        let bios = Swift.Set(reader.sharing.filter { $0.value >= biosSharing }.keys)
        return (source, Set(name: name, machines: reader.machines, parents: reader.parents, biosCRCs: bios))
    }

    /// MAME's `<machine>` and Logiqx's `<game>`: their roms (but not a
    /// BIOS choice's, nor dumps nobody has), disks, parent and BIOS.
    private final class Reader: NSObject, XMLParserDelegate {
        let wanted: Swift.Set<String>
        var machines: [String: Machine] = [:]
        var parents: [String: [String]] = [:]
        var name = ""
        var build: String?
        /// How many games list each ROM merged from elsewhere.
        var sharing: [UInt32: Int] = [:]

        private var current: String?
        private var cloneOf: String?
        private var romOf: String?
        private var isDevice = false
        private var title = ""
        private var roms: [ROM] = []
        private var disks: [Disk] = []
        private var text = ""
        private var inHeader = false

        init(wanted: Swift.Set<String>) {
            self.wanted = wanted
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "mame":
                build = attributes["build"]
                name = "MAME"
            case "header":
                inHeader = true
            case "machine", "game":
                current = attributes["name"]?.lowercased()
                cloneOf = attributes["cloneof"]?.lowercased()
                romOf = attributes["romof"]?.lowercased()
                isDevice = attributes["isdevice"] == "yes"
                title = ""; roms = []; disks = []
            case "rom":
                if attributes["merge"] != nil, let crc = attributes["crc"].flatMap({ UInt32($0, radix: 16) }) {
                    sharing[crc, default: 0] += 1
                }
                guard current.map(wanted.contains) == true, attributes["status"] != "nodump", attributes["bios"] == nil,
                      let name = attributes["name"], let size = attributes["size"].flatMap(Int.init),
                      let crc = attributes["crc"].flatMap({ UInt32($0, radix: 16) }) else { return }
                roms.append(ROM(name: name, size: size, crc: crc))
            case "disk":
                guard current.map(wanted.contains) == true, attributes["status"] != "nodump",
                      let name = attributes["name"], let sha1 = attributes["sha1"] else { return }
                disks.append(Disk(name: name, sha1: sha1))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "header":
                inHeader = false
            case "name" where inHeader:
                name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "description" where current != nil:
                title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "machine", "game":
                guard let current, !isDevice else { break }
                let leans = [cloneOf, romOf].compactMap { $0 }.filter { $0 != current }
                if !leans.isEmpty { parents[current] = Array(NSOrderedSet(array: leans)) as? [String] ?? leans }
                if wanted.contains(current) {
                    machines[current] = Machine(title: ArcadeNameIndex.cleanedTitle(title), cloneOf: cloneOf, romOf: romOf, roms: roms, disks: disks)
                }
                self.current = nil
            default:
                break
            }
            text = ""
        }
    }
}

/// Which zips of a folder hold which chips, read once per folder for a
/// run of checks.
private enum FolderIndex {
    nonisolated(unsafe) private static var cache: [String: (date: Date, index: [UInt32: [String]])] = [:]
    private static let lock = NSLock()

    static func crcs(in folder: URL) -> [UInt32: [String]] {
        let zips = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? [])
            .filter { $0.pathExtension.lowercased() == "zip" }
        // The folder's date (a zip added or removed), or the newest zip's:
        // one changed in place leaves the folder's as it was.
        let folderDate = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let date = zips.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .reduce(folderDate, max)
        if let cached = lock.withLock({ cache[folder.path] }), cached.date == date { return cached.index }
        var index: [UInt32: [String]] = [:]
        for zip in zips {
            let name = zip.deletingPathExtension().lastPathComponent.lowercased()
            for entry in ZipContents.entries(of: zip) ?? [] { index[entry.crc, default: []].append(name) }
        }
        lock.withLock { cache[folder.path] = (date, index) }
        return index
    }
}
