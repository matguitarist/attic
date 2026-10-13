import Foundation

/// What's in a zip, read from its central directory without unpacking it.
public enum ZipContents {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let size: Int
        public var crc: UInt32 = 0
    }

    /// The one file a game's zip holds (folders and macOS's own files
    /// aside), with its unpacked size; nil for anything else, such as an
    /// arcade romset's many files.
    public static func singleEntry(of url: URL) -> Entry? {
        guard url.pathExtension.lowercased() == "zip" else { return nil }
        let real = (entries(of: url) ?? []).filter { entry in
            !entry.name.hasSuffix("/") && !entry.name.hasPrefix("__MACOSX/") && !entry.name.hasSuffix(".DS_Store")
        }
        guard real.count == 1 else { return nil }
        return real[0]
    }

    static func entries(of url: URL) -> [Entry]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd(), length >= 22 else { return nil }
        // The end record is in the last 22 bytes, plus up to 64 KB of comment.
        let tailLength = min(length, 22 + 65_535)
        guard (try? handle.seek(toOffset: length - tailLength)) != nil,
              let tail = try? handle.read(upToCount: Int(tailLength)).map([UInt8].init) else { return nil }
        guard let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: { integer(tail, $0, 4) == 0x0605_4B50 }) else { return nil }
        let count = integer(tail, end + 10, 2)
        let directorySize = integer(tail, end + 12, 4)
        let directoryOffset = integer(tail, end + 16, 4)
        guard directoryOffset != 0xFFFF_FFFF, (try? handle.seek(toOffset: UInt64(directoryOffset))) != nil,
              let directory = try? handle.read(upToCount: directorySize).map([UInt8].init) else { return nil }

        var entries: [Entry] = []
        var offset = 0
        for _ in 0..<count {
            guard offset + 46 <= directory.count, integer(directory, offset, 4) == 0x0201_4B50 else { return nil }
            let crc = UInt32(integer(directory, offset + 16, 4))
            let size = integer(directory, offset + 24, 4)
            let nameLength = integer(directory, offset + 28, 2)
            let extraLength = integer(directory, offset + 30, 2)
            let commentLength = integer(directory, offset + 32, 2)
            guard offset + 46 + nameLength <= directory.count, size != 0xFFFF_FFFF else { return nil }
            let name = String(decoding: directory[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, size: size, crc: crc))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// A little-endian integer.
    private static func integer(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> Int {
        guard offset >= 0, offset + count <= bytes.count else { return -1 }
        return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
    }
}
