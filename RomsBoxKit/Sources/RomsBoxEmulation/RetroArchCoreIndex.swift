import Foundation

/// Scans installed `.dylib` cores and their matching `.info` files into a
/// lookup table. A manual "Refresh Cores" trigger is sufficient for MVP —
/// no filesystem watching.
public enum RetroArchCoreIndex {
    public static func scan(coresDirectory: URL, infoDirectory: URL) -> [RetroArchCoreInfo] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: coresDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var cores: [RetroArchCoreInfo] = []
        for dylibURL in entries where dylibURL.pathExtension == "dylib" {
            let coreIdentifier = dylibURL.deletingPathExtension().lastPathComponent
            let infoURL = infoDirectory.appending(path: "\(coreIdentifier).info")
            guard let contents = try? String(contentsOf: infoURL, encoding: .utf8) else { continue }
            cores.append(RetroArchCoreInfoParser.parse(contents: contents, coreIdentifier: coreIdentifier, dylibURL: dylibURL))
        }
        return cores.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
