import Foundation

/// Scans installed `.dylib` cores and their matching `.info` files into a
/// lookup table. A manual "Refresh Cores" trigger is sufficient for MVP —
/// no filesystem watching.
public enum RetroArchCoreIndex {
    public static func scan(coresDirectory: URL, infoDirectory: URL) -> [RetroArchCoreInfo] {
        scan(coresDirectories: [coresDirectory], infoDirectories: [infoDirectory])
    }

    /// Scans several cores directories (RomsBox's own, then RetroArch's),
    /// looking each core's `.info` file up across several info directories
    /// — RetroArch's info folder is empty on a fresh install, while RomsBox
    /// keeps its own copy of libretro's info files. The first directory to
    /// provide a given core wins, so a RomsBox-installed core shadows an
    /// older copy in RetroArch's folder.
    public static func scan(coresDirectories: [URL], infoDirectories: [URL]) -> [RetroArchCoreInfo] {
        let fileManager = FileManager.default
        var coresByIdentifier: [String: RetroArchCoreInfo] = [:]

        for coresDirectory in coresDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(at: coresDirectory, includingPropertiesForKeys: nil) else {
                continue
            }
            for dylibURL in entries where dylibURL.pathExtension == "dylib" {
                let coreIdentifier = dylibURL.deletingPathExtension().lastPathComponent
                guard coresByIdentifier[coreIdentifier] == nil else { continue }
                let contents = infoDirectories.lazy
                    .compactMap { try? String(contentsOf: $0.appending(path: "\(coreIdentifier).info"), encoding: .utf8) }
                    .first
                guard let contents else { continue }
                coresByIdentifier[coreIdentifier] = RetroArchCoreInfoParser.parse(contents: contents, coreIdentifier: coreIdentifier, dylibURL: dylibURL)
            }
        }
        return coresByIdentifier.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
