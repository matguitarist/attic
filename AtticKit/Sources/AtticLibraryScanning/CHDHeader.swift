import Foundation

/// What a CHD file says about itself, read from its header and metadata
/// (CHD version 5, what chdman has written since 2012) without chdman.
public struct CHDHeader: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case cd, gdrom, dvd, hardDisk, other
    }

    public let kind: Kind
    /// The disc's size unpacked.
    public let logicalBytes: UInt64
    /// The codecs used, by their chdman names ("cdlz", "cdzl", "cdfl"…).
    public let codecs: [String]
    /// Tracks of a CD or GD-ROM.
    public let tracks: Int?
    /// SHA-1 of the data and metadata, as `chdman info` shows it.
    public let sha1: String

    public static func read(_ url: URL) -> CHDHeader? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 124), header.count == 124 else { return nil }
        return parse(header) { offset, count in
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
    }

    /// `header` is the file's first 124 bytes; `read` gives `count` bytes
    /// at an offset, for the metadata entries.
    static func parse(_ header: Data, read: (UInt64, Int) -> Data?) -> CHDHeader? {
        let bytes = [UInt8](header)
        guard bytes.count >= 124, String(decoding: bytes[0..<8], as: UTF8.self) == "MComprHD",
              integer(bytes, 12, 4) == 5 else { return nil }

        let codecs = (0..<4).compactMap { index -> String? in
            let code = bytes[(16 + index * 4)..<(20 + index * 4)]
            guard code.contains(where: { $0 != 0 }) else { return nil }
            return String(decoding: code, as: UTF8.self)
        }
        let sha1 = bytes[84..<104].map { String(format: "%02x", $0) }.joined()

        // Metadata entries: a tag, flags and length, the next entry's
        // offset, then the data.
        var tags: [String] = []
        var offset = integer(bytes, 48, 8)
        var seen = Set<UInt64>()
        while offset != 0, seen.insert(offset).inserted, tags.count < 1000,
              let entry = read(offset, 16).map([UInt8].init), entry.count == 16 {
            tags.append(String(decoding: entry[0..<4], as: UTF8.self))
            offset = integer(entry, 8, 8)
        }

        let kind: Kind
        if tags.contains("CHGD") {
            kind = .gdrom
        } else if tags.contains(where: { ["CHT2", "CHTR", "CHCD"].contains($0) }) {
            kind = .cd
        } else if tags.contains("DVD ") {
            kind = .dvd
        } else if tags.contains("GDDD") {
            kind = .hardDisk
        } else {
            kind = .other
        }
        let trackCount = tags.filter { ["CHT2", "CHTR", "CHGD"].contains($0) }.count
        return CHDHeader(kind: kind, logicalBytes: integer(bytes, 32, 8), codecs: codecs,
                         tracks: trackCount > 0 ? trackCount : nil, sha1: sha1)
    }

    /// A big-endian integer.
    private static func integer(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt64 {
        bytes[offset..<(offset + count)].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
