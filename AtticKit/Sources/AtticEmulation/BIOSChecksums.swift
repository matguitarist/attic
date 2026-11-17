import Foundation
import CryptoKit

/// Known good BIOS dumps, by MD5 (from libretro's System.dat and
/// Batocera's list, in KnownBIOS.tsv): is a file the dump an emulator
/// expects, and is a missing one in the BIOS folder under another name.
/// A zipped set (naomi.zip, hikaru.zip) is checked by the chips in it,
/// from MAME's list (KnownBIOSSets.tsv): a zip's own checksum depends on
/// how it was packed.
public enum BIOSChecksums {
    public enum Verdict: Sendable, Hashable {
        /// A known good dump of the file.
        case verified
        /// Named right, but not a dump the emulator is known to take: a
        /// bad dump, another revision, another file.
        case unrecognized
        /// Nothing to check it against (a zipped set, an unlisted file).
        case unchecked
    }

    public struct Entry: Sendable, Hashable {
        public let name: String
        public let size: Int
        public let md5: String
    }

    /// What checking a file found: the verdict, and what it was compared
    /// with, to show.
    public struct Check: Sendable, Hashable {
        public var verdict: Verdict = .unchecked
        /// The known good dumps of the file (for a folder, the one it
        /// matched, if any).
        public var expected: [Entry] = []
        public var md5: String?
        public var size: Int?
        /// Matched once a copier's 512-byte header was skipped.
        public var hasHeader = false
        /// For a zipped set: what it was checked against ("MAME 0.289"),
        /// nil for a single file.
        public var setList: String?
        /// For a zipped set: the chips it lacks. With `needsRevision`,
        /// those of one BIOS revision, when it has none complete: any
        /// revision would do.
        public var missingChips: [Chip] = []
        public var needsRevision = false
        /// For a zipped set: chips named right with other data, as they
        /// should be.
        public var otherChips: [Chip] = []
    }

    /// One chip of a zipped BIOS set, as MAME lists it.
    public struct Chip: Sendable, Hashable {
        public let set: String
        /// The BIOS revision it belongs to; empty for one every revision
        /// needs.
        public let revision: String
        public let name: String
        public let size: Int
        public let crc: UInt32
        /// False for an EEPROM's default contents, which emulators make.
        public let required: Bool

        public var crcText: String { String(format: "%08x", crc) }
    }

    static let entries: [Entry] = {
        guard let url = Bundle.module.url(forResource: "KnownBIOS", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3, let size = Int(parts[1]) else { return nil }
            return Entry(name: String(parts[0]), size: size, md5: String(parts[2]))
        }
    }()

    /// The zipped sets' chips, and the list they come from.
    static let sets: (list: String, chips: [Chip]) = {
        guard let url = Bundle.module.url(forResource: "KnownBIOSSets", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ("", []) }
        var list = ""
        var chips: [Chip] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("# ") { list = String(line.dropFirst(2)); continue }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 6, let size = Int(parts[3]), let crc = UInt32(parts[4], radix: 16) else { continue }
            chips.append(Chip(set: String(parts[0]), revision: String(parts[1]), name: String(parts[2]),
                              size: size, crc: crc, required: parts[5] == "1"))
        }
        return (list, chips)
    }()

    /// The chips of the set a zip requirement names ("dc/naomi.zip").
    static func chips(for fileName: String, in chips: [Chip] = sets.chips) -> [Chip] {
        let set = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        return chips.filter { $0.set == set }
    }

    /// Whether a zipped set holds what its emulator reads: every chip
    /// all revisions share, one BIOS revision complete (any one), and no
    /// chip named right with other data. Chips are matched by CRC, so a
    /// set from another MAME version, with other names, still passes.
    static func checkSet(_ zip: URL, chips: [Chip], list: String) -> Check {
        var check = Check(setList: list)
        guard let entries = ZipContents.entries(of: zip)?.filter({ !$0.name.hasSuffix("/") }) else { return check }
        let crcs = Set(entries.map(\.crc))
        let byName = Dictionary(entries.map { (($0.name as NSString).lastPathComponent.lowercased(), $0.crc) }, uniquingKeysWith: { first, _ in first })
        let knownCRCs = Set(chips.map(\.crc))
        // Named like a chip, holding none of the known data.
        var reported = Set<String>()
        for chip in chips {
            let name = chip.name.lowercased()
            guard let crc = byName[name], !knownCRCs.contains(crc), reported.insert(name).inserted else { continue }
            check.otherChips.append(chip)
        }
        check.missingChips = chips.filter { $0.revision.isEmpty && $0.required && !crcs.contains($0.crc) }
        let revisions = Dictionary(grouping: chips.filter { !$0.revision.isEmpty }, by: \.revision)
        if !revisions.isEmpty, !revisions.values.contains(where: { $0.allSatisfy { crcs.contains($0.crc) } }),
           let first = chips.first(where: { !$0.revision.isEmpty })?.revision, let wanted = revisions[first] {
            check.missingChips += wanted
            check.needsRevision = true
        }
        check.verdict = check.missingChips.isEmpty && check.otherChips.isEmpty ? .verified : .unrecognized
        return check
    }

    /// The known dumps of a file, by its path in the BIOS folder
    /// ("dc/dc_boot.bin"); a folder requirement ("pcsx2/bios/") takes any
    /// dump listed in it.
    static func known(for fileName: String, in entries: [Entry] = entries) -> [Entry] {
        let name = fileName.lowercased()
        if name.hasSuffix("/") { return entries.filter { $0.name.lowercased().hasPrefix(name) } }
        return entries.filter { $0.name.lowercased() == name }
    }

    /// Whether `file` is a good dump of `fileName`.
    public static func verdict(of file: URL, as fileName: String) -> Verdict {
        check(file, as: fileName).verdict
    }

    static func verdict(of file: URL, as fileName: String, in entries: [Entry]) -> Verdict {
        check(file, as: fileName, in: entries).verdict
    }

    public static func check(_ file: URL, as fileName: String) -> Check {
        check(file, as: fileName, in: entries)
    }

    static func check(_ file: URL, as fileName: String, in entries: [Entry]) -> Check {
        let known = known(for: fileName, in: entries)
        let isFolder = fileName.hasSuffix("/")
        var check = Check(expected: isFolder ? [] : known)
        if file.pathExtension.lowercased() == "zip" {
            let chips = chips(for: fileName)
            return chips.isEmpty ? check : checkSet(file, chips: chips, list: sets.list)
        }
        let size = MD5Cache.size(of: file)
        check.size = size >= 0 ? size : nil
        check.md5 = MD5Cache.md5(of: file)
        guard !known.isEmpty else { return check }
        if let md5 = check.md5, let match = known.first(where: { $0.md5 == md5 }) {
            check.verdict = .verified
            if isFolder { check.expected = [match] }
            return check
        }
        // A copier's 512-byte header before it (PC Engine System Cards
        // often have one) doesn't make it another dump.
        if known.contains(where: { $0.size + 512 == size }), let md5 = MD5Cache.md5(of: file, skipping: 512),
           let match = known.first(where: { $0.md5 == md5 }) {
            check.verdict = .verified
            check.hasHeader = true
            if isFolder { check.expected = [match] }
            return check
        }
        // The list has only some of the dumps a folder takes (PCSX2
        // checks its own).
        check.verdict = isFolder ? .unchecked : .unrecognized
        return check
    }

    /// The known good dumps of a file, to show what it should be.
    public static func expected(for fileName: String) -> [Entry] {
        fileName.hasSuffix("/") ? [] : known(for: fileName)
    }

    /// A file in the BIOS folder (or a folder in it) that is a good dump
    /// of `fileName` under another name: "PSX BIOS.bin" for scph5501.bin.
    public static func misnamedDump(of fileName: String, in biosDirectory: URL) -> URL? {
        misnamedDump(of: fileName, in: biosDirectory, entries: entries)
    }

    static func misnamedDump(of fileName: String, in biosDirectory: URL, entries: [Entry]) -> URL? {
        let known = known(for: fileName, in: entries)
        guard !known.isEmpty, !fileName.hasSuffix("/") else { return nil }
        let sizes = Set(known.map(\.size))
        let md5s = Set(known.map(\.md5))
        let manager = FileManager.default
        let top = (try? manager.contentsOfDirectory(at: biosDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let nested = top.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .flatMap { (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] }
        // By size first: only a file of a dump's size is read.
        return (top + nested).first { file in
            sizes.contains(MD5Cache.size(of: file)) && MD5Cache.md5(of: file).map(md5s.contains) == true
        }
    }
}

/// Files' MD5s, kept while their size and date don't change: the BIOS
/// lists are drawn often.
enum MD5Cache {
    private struct Key: Hashable {
        let path: String
        let size: Int
        let date: Date
        let skipped: Int
    }

    nonisolated(unsafe) private static var cache: [Key: String] = [:]
    private static let lock = NSLock()

    static func size(of url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return -1 }
        return values?.fileSize ?? -1
    }

    /// The MD5 of the file, or of what follows its first `skipping` bytes.
    static func md5(of url: URL, skipping: Int = 0) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > skipping,
              let date = values.contentModificationDate else { return nil }
        let key = Key(path: url.path, size: size, date: date, skipped: skipping)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let md5 = Insecure.MD5.hash(data: data.dropFirst(skipping)).map { String(format: "%02x", $0) }.joined()
        lock.withLock { cache[key] = md5 }
        return md5
    }
}
