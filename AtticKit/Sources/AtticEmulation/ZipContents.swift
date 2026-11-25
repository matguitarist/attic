import Foundation
import ArchiveKit

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

    /// Read from the zip's central directory by ArchiveKit (ZIP64 too); nil
    /// for a file that isn't a zip or is cut short.
    static func entries(of url: URL) -> [Entry]? {
        guard let entries = try? Zip.entries(url) else { return nil }
        return entries.map { Entry(name: $0.name, size: Int(clamping: $0.size), crc: $0.crc32) }
    }
}
