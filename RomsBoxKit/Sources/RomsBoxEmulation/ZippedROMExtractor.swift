import Foundation

/// Resolves a `.zip` ROM to a real, extracted file before it's handed to
/// RetroArch. Passing a zip straight through is unreliable two different
/// ways: many libretro cores (e.g. Mesen for NES, mGBA for GBA — confirmed
/// against both cores' real `.info` files, neither lists "zip" in
/// `supported_extensions`) don't natively read zips at all, and even
/// RetroArch's own `archive.zip#file` syntax for picking a specific entry
/// is broken specifically when passed via the command line rather than
/// chosen through RetroArch's UI (a long-standing bug,
/// libretro/RetroArch#12577 — content loads fine through the UI, but the
/// same path on the command line fails or falls back to an on-screen
/// "pick a file from this archive" browser that just sits there paused
/// until someone interacts with it).
public struct ZippedROMExtractor: Sendable {
    private let cacheDirectory: URL
    private let unzipBinaryURL: URL

    public init(
        cacheDirectory: URL = ZippedROMExtractor.defaultCacheDirectory,
        unzipBinaryURL: URL = URL(fileURLWithPath: "/usr/bin/unzip")
    ) {
        self.cacheDirectory = cacheDirectory
        self.unzipBinaryURL = unzipBinaryURL
    }

    public static var defaultCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appending(path: "RomsBox/ExtractedROMs", directoryHint: .isDirectory)
    }

    /// Returns `romURL` unchanged for anything that isn't a `.zip`, or a
    /// zip this can't confidently resolve to exactly one ROM file (leaves
    /// multi-file archives — e.g. a zipped multi-disc PS1 game — alone
    /// rather than guessing which entry matters). Extraction is cached: a
    /// zip already extracted on a previous launch is reused rather than
    /// re-extracted every time.
    public func resolvedROMURL(for romURL: URL) -> URL {
        guard romURL.pathExtension.lowercased() == "zip" else { return romURL }
        guard let entries = try? listEntries(in: romURL), let romEntry = Self.chooseROMEntry(from: entries) else {
            return romURL
        }

        let destinationDirectory = cacheDirectory.appending(
            path: romURL.deletingPathExtension().lastPathComponent,
            directoryHint: .isDirectory
        )
        let destination = destinationDirectory.appending(path: romEntry)

        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        guard (try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)) != nil,
              (try? extract(entry: romEntry, from: romURL, to: destinationDirectory)) != nil,
              FileManager.default.fileExists(atPath: destination.path) else {
            return romURL
        }
        return destination
    }

    private func listEntries(in zipURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = unzipBinaryURL
        process.arguments = ["-Z1", zipURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    private func extract(entry: String, from zipURL: URL, to destinationDirectory: URL) throws {
        let process = Process()
        process.executableURL = unzipBinaryURL
        process.arguments = ["-o", zipURL.path, entry, "-d", destinationDirectory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    /// A zip with exactly one real (non-directory, non-macOS-metadata)
    /// entry is unambiguous. Anything else — an empty archive, or multiple
    /// files where it's unclear which one is "the" ROM — is left alone.
    static func chooseROMEntry(from entries: [String]) -> String? {
        let realEntries = entries.filter { entry in
            !entry.hasSuffix("/") && !entry.hasPrefix("__MACOSX/") && !entry.hasSuffix(".DS_Store")
        }
        guard realEntries.count == 1 else { return nil }
        return realEntries.first
    }
}
