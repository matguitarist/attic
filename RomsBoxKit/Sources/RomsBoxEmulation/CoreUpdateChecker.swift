import Foundation

/// Whether an installed core matches what libretro's buildbot currently
/// publishes.
public enum CoreUpdateStatus: Sendable, Equatable {
    case upToDate
    case updateAvailable
    /// The buildbot no longer lists it (or never did — e.g. a core the user
    /// built themselves), so there's nothing to compare against.
    case notOnBuildbot
}

/// Detects core updates the way RetroArch's own Online Updater does: the
/// buildbot's `.index-extended` lists a CRC32 of each core's *uncompressed*
/// dylib, so comparing it with the CRC32 of the installed file says exactly
/// whether the code changed.
///
/// Dates can't be used for this: the buildbot rebuilds nearly every core
/// every night (221 of 230 on one checked day), changed or not.
public enum CoreUpdateChecker {
    /// `<date> <crc32 hex> <core>.dylib.zip` lines → core identifier → CRC.
    public static func remoteChecksums(inIndexExtended contents: String) -> [String: UInt32] {
        var checksums: [String: UInt32] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 3,
                  let crc = UInt32(parts[1], radix: 16),
                  parts[2].hasSuffix(".dylib.zip") else { continue }
            checksums[String(parts[2].dropLast(".dylib.zip".count))] = crc
        }
        return checksums
    }

    public static func status(ofCoreAt dylibURL: URL, coreIdentifier: String, remoteChecksums: [String: UInt32]) -> CoreUpdateStatus {
        guard let remote = remoteChecksums[coreIdentifier] else { return .notOnBuildbot }
        guard let local = try? crc32(ofFileAt: dylibURL) else { return .updateAvailable }
        return local == remote ? .upToDate : .updateAvailable
    }

    // MARK: - CRC32

    /// Standard CRC-32 (IEEE 802.3, as zlib computes it), streamed in
    /// chunks so multi-megabyte cores aren't loaded whole.
    public static func crc32(ofFileAt url: URL) throws -> UInt32 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            crc = update(crc, with: chunk)
        }
        return crc ^ 0xFFFF_FFFF
    }

    public static func crc32(of data: Data) -> UInt32 {
        update(0xFFFF_FFFF, with: data) ^ 0xFFFF_FFFF
    }

    private static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        var crc = crc
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }
}
