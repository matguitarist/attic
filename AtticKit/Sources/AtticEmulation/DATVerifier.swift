import Foundation
import AtticModels

/// Checks games against the DAT files in a folder (No-Intro's, from
/// DAT-o-MATIC): is each one a known good dump, and under which name.
/// Reads only; nothing is changed.
public struct DATVerifier: Sendable {
    public enum Verdict: String, Sendable {
        /// The data is a dump the DAT lists.
        case verified
        /// Named like a game the DAT lists, but its data isn't that
        /// game's: a bad or altered dump, a hack, another revision.
        case differs
        /// Neither its data nor its name is in the DAT: homebrew, a
        /// hack, a translation, an unlisted dump.
        case unknown
    }

    public struct Check: Equatable, Sendable {
        public let verdict: Verdict
        /// The DAT's name for the game: the one it's verified as, or the
        /// one its name matches.
        public let name: String?

        public init(verdict: Verdict, name: String?) {
            self.verdict = verdict
            self.name = name
        }
    }

    private struct Fingerprint: Hashable {
        let size: Int
        let crc: UInt32
    }

    private struct Index: Sendable {
        var byFingerprint: [Fingerprint: String] = [:]
        var byName: [String: String] = [:]
    }

    private var indexes: [CanonicalSystemID: Index] = [:]
    /// The DATs read, by name, with the system each is for (nil when
    /// none matched).
    public private(set) var sets: [(name: String, system: CanonicalSystemID?)] = []

    public var systems: Set<CanonicalSystemID> { Set(indexes.keys) }

    public init(dats: [DATFile]) {
        for dat in dats {
            sets.append((dat.name, dat.system))
            guard let system = dat.system else { continue }
            var index = indexes[system] ?? Index()
            for rom in dat.roms {
                index.byFingerprint[Fingerprint(size: rom.size, crc: rom.crc)] = rom.game
                index.byName[rom.game.lowercased()] = rom.game
            }
            indexes[system] = index
        }
    }

    /// Every DAT in `folder`, and in the zips there (DAT-o-MATIC's daily
    /// pack is one).
    public static func load(from folder: URL) -> DATVerifier {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var dats: [DATFile] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            switch file.pathExtension.lowercased() {
            case "dat", "xml":
                if let dat = DATFile.read(file) { dats.append(dat) }
            case "zip":
                for name in zipListing(file) where ["dat", "xml"].contains((name as NSString).pathExtension.lowercased()) {
                    if let data = unzip(file, entry: name),
                       let dat = DATFile.parse(data, fallbackName: ((name as NSString).lastPathComponent as NSString).deletingPathExtension) {
                        dats.append(dat)
                    }
                }
            default: break
            }
        }
        return DATVerifier(dats: dats)
    }

    /// nil when there's no DAT for the system, or the game isn't a single
    /// file that can be checked (an arcade romset, a disc).
    public func check(_ url: URL, system: CanonicalSystemID) -> Check? {
        guard let index = indexes[system] else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        guard let fingerprints = Self.fingerprints(of: url, system: system, isKnown: { index.byFingerprint[$0] != nil }) else { return nil }
        if let game = fingerprints.lazy.compactMap({ index.byFingerprint[$0] }).first {
            return Check(verdict: .verified, name: game)
        }
        if let game = index.byName[stem.lowercased()] {
            return Check(verdict: .differs, name: game)
        }
        return Check(verdict: .unknown, name: nil)
    }

    // MARK: - Fingerprints

    /// Whether the file is one a cartridge DAT can list: not a disc
    /// image (Redump's), whose tracks a DAT lists one by one.
    public static func canCheck(_ url: URL) -> Bool {
        !["chd", "cue", "bin", "gdi", "iso", "m3u", "rvz", "gcz", "cso", "pbp", "cdi", "wbfs", "wua", "wux", "rpx", "ccd", "img", "mds", "nrg"]
            .contains(url.pathExtension.lowercased())
    }

    private static let cartridgeLimit = 512 << 20

    /// The file's size and CRC32, and again without a copier or emulator
    /// header (No-Intro lists most systems' dumps without one).
    private static func fingerprints(of url: URL, system: CanonicalSystemID, isKnown: (Fingerprint) -> Bool) -> [Fingerprint]? {
        switch url.pathExtension.lowercased() {
        case "zip":
            guard let entries = ZipContents.entries(of: url)?.filter({ !$0.name.hasSuffix("/") && !$0.name.hasPrefix("__MACOSX/") && !$0.name.hasSuffix(".DS_Store") }),
                  let entry = entries.max(by: { $0.size < $1.size }) else { return nil }
            // A game of several files (a few come with a save No-Intro
            // lists): known when each of them is.
            if entries.count > 1 {
                let all = entries.map { Fingerprint(size: $0.size, crc: $0.crc) }
                return all.allSatisfy(isKnown) ? [Fingerprint(size: entry.size, crc: entry.crc)] : nil
            }
            // The zip has the whole file's CRC; only a header means
            // unpacking it.
            let whole = Fingerprint(size: entry.size, crc: entry.crc)
            guard !isKnown(whole), headerLength(system: system, size: entry.size, start: nil) != 0 || mayHaveHeader(system),
                  entry.size <= cartridgeLimit, let data = unzip(url) else { return [whole] }
            return [whole] + headerless(data, system: system)
        case "7z":
            guard let names = sevenZipListing(url), names.count == 1, let data = run("/usr/bin/bsdtar", ["-xOf", url.path]) else { return nil }
            return [Fingerprint(size: data.count, crc: CoreUpdateChecker.crc32(of: data))] + headerless(data, system: system)
        case _ where !canCheck(url):
            return nil
        default:
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= cartridgeLimit,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return [Fingerprint(size: size, crc: CoreUpdateChecker.crc32(of: data))] + headerless(data, system: system)
        }
    }

    private static func headerless(_ data: Data, system: CanonicalSystemID) -> [Fingerprint] {
        let length = headerLength(system: system, size: data.count, start: data.prefix(16))
        guard length > 0, data.count > length else { return [] }
        let body = data.dropFirst(length)
        return [Fingerprint(size: body.count, crc: CoreUpdateChecker.crc32(of: Data(body)))]
    }

    /// Systems whose dumps often carry a header, found by looking.
    private static func mayHaveHeader(_ system: CanonicalSystemID) -> Bool {
        [.nes, .fds, .atari7800, .atarilynx].contains(system)
    }

    /// How long the header at the start of a ROM is: iNES and fwNES
    /// (16 bytes), A78 (128), Lynx's (64), a SNES copier's (512).
    static func headerLength(system: CanonicalSystemID, size: Int, start: Data?) -> Int {
        if system == .snes { return size % 1024 == 512 ? 512 : 0 }
        guard let start else { return 0 }
        let bytes = [UInt8](start)
        func has(_ magic: String, at offset: Int) -> Bool {
            let magic = Array(magic.utf8)
            return bytes.count >= offset + magic.count && Array(bytes[offset..<(offset + magic.count)]) == magic
        }
        if has("NES\u{1A}", at: 0) || has("FDS\u{1A}", at: 0) { return 16 }
        if has("ATARI7800", at: 1) { return 128 }
        if has("LYNX", at: 0) { return 64 }
        return 0
    }

    // MARK: - Archives

    private static func zipListing(_ url: URL) -> [String] {
        (ZipContents.entries(of: url) ?? []).map(\.name).filter { !$0.hasSuffix("/") && !$0.hasPrefix("__MACOSX/") }
    }

    /// The zip's files, one after the other; or only `entry`.
    private static func unzip(_ url: URL, entry: String? = nil) -> Data? {
        // unzip reads a name as a pattern: "[b]" in one is escaped as a
        // one-character set.
        let pattern = entry.map { $0.replacing(#/[\[\*\?]/#) { "[\($0.output)]" } }
        return run("/usr/bin/unzip", ["-p", url.path] + (pattern.map { [$0] } ?? []))
    }

    private static func sevenZipListing(_ url: URL) -> [String]? {
        guard let data = run("/usr/bin/bsdtar", ["-tf", url.path]) else { return nil }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.hasSuffix("/") }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
