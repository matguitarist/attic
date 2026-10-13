import Foundation
import CryptoKit

/// Known good BIOS dumps, by MD5 (from libretro's System.dat, in
/// KnownBIOS.tsv): is a file the dump an emulator expects, and is a
/// missing one in the BIOS folder under another name.
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

    struct Entry: Sendable {
        let name: String
        let size: Int
        let md5: String
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
        verdict(of: file, as: fileName, in: entries)
    }

    static func verdict(of file: URL, as fileName: String, in entries: [Entry]) -> Verdict {
        let known = known(for: fileName, in: entries)
        guard !known.isEmpty, file.pathExtension.lowercased() != "zip" else { return .unchecked }
        let size = MD5Cache.size(of: file)
        // A copier's 512-byte header before it (PC Engine System Cards
        // often have one) doesn't make it another dump.
        let isKnown = known.contains { $0.size == size } && MD5Cache.md5(of: file).map { md5 in known.contains { $0.md5 == md5 } } == true
            || known.contains { $0.size + 512 == size } && MD5Cache.md5(of: file, skipping: 512).map { md5 in known.contains { $0.md5 == md5 } } == true
        if isKnown { return .verified }
        // The list has only some of the dumps a folder takes (PCSX2
        // checks its own).
        return fileName.hasSuffix("/") ? .unchecked : .unrecognized
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
