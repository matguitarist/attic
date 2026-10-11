import Foundation

/// Resolves a `.zip` or `.7z` ROM to a real, extracted file before it's
/// handed to RetroArch. (`.7z` goes through macOS's own `tar` — bsdtar /
/// libarchive reads 7-Zip — so no extra tool is needed.) Passing a zip straight through is unreliable two different
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
    private let tarBinaryURL: URL

    public init(
        cacheDirectory: URL = ZippedROMExtractor.defaultCacheDirectory,
        unzipBinaryURL: URL = URL(fileURLWithPath: "/usr/bin/unzip"),
        tarBinaryURL: URL = URL(fileURLWithPath: "/usr/bin/tar")
    ) {
        self.cacheDirectory = cacheDirectory
        self.unzipBinaryURL = unzipBinaryURL
        self.tarBinaryURL = tarBinaryURL
    }

    private enum ArchiveKind {
        case zip, sevenZip

        init?(_ url: URL) {
            switch url.pathExtension.lowercased() {
            case "zip": self = .zip
            case "7z": self = .sevenZip
            default: return nil
            }
        }
    }

    public static var defaultCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appending(path: "RomsBox/ExtractedROMs", directoryHint: .isDirectory)
    }

    /// Returns `romURL` unchanged for anything that isn't a `.zip`/`.7z`,
    /// or an archive this can't confidently resolve to exactly one ROM file (leaves
    /// multi-file archives — e.g. a zipped multi-disc PS1 game — alone
    /// rather than guessing which entry matters). Extraction is cached: a
    /// zip already extracted on a previous launch is reused rather than
    /// re-extracted every time.
    public func resolvedROMURL(for romURL: URL) -> URL {
        guard let kind = ArchiveKind(romURL) else { return romURL }
        guard let entries = try? listEntries(in: romURL, kind: kind), let romEntry = Self.chooseROMEntry(from: entries) else {
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
              (try? extract(entry: romEntry, from: romURL, kind: kind, to: destinationDirectory)) != nil,
              FileManager.default.fileExists(atPath: destination.path) else {
            return romURL
        }
        return destination
    }

    private func listEntries(in archiveURL: URL, kind: ArchiveKind) throws -> [String] {
        let process = Process()
        switch kind {
        case .zip:
            process.executableURL = unzipBinaryURL
            process.arguments = ["-Z1", archiveURL.path]
        case .sevenZip:
            process.executableURL = tarBinaryURL
            process.arguments = ["-tf", archiveURL.path]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    private func extract(entry: String, from archiveURL: URL, kind: ArchiveKind, to destinationDirectory: URL) throws {
        let process = Process()
        switch kind {
        case .zip:
            process.executableURL = unzipBinaryURL
            process.arguments = ["-o", archiveURL.path, entry, "-d", destinationDirectory.path]
        case .sevenZip:
            process.executableURL = tarBinaryURL
            process.arguments = ["-xf", archiveURL.path, "-C", destinationDirectory.path, entry]
        }
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
