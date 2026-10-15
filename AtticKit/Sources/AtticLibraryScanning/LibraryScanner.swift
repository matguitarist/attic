import Foundation
import AtticModels

/// Enumerates a ROMs root's immediate subfolders, maps each folder name to
/// a canonical system via `SystemTaxonomy`, and picks an importer per
/// folder by trying each in order — so a single root can mix conventions
/// (one system folder in ES-DE's layout, another in Batocera's) and each is
/// still recognized correctly.
///
/// Deliberately produces `ImportedSystemData` DTOs rather than writing to
/// SwiftData itself — `AtticLibraryScanning` has no dependency on
/// `AtticPersistence`, so this stays independently testable against
/// fixture directories. The app-layer `ScanCoordinator` is what feeds the
/// output into `LibraryStore`.
public struct LibraryScanner: Sendable {
    public struct ScanIssue: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case unrecognizedSystemFolderName
            case noImporterRecognizedFormat
            case importFailed(String)
        }
        public let folderURL: URL
        public let reason: Reason
    }

    public struct ScanResult: Sendable {
        public let systems: [ImportedSystemData]
        public let issues: [ScanIssue]
    }

    private let importers: [LibraryImporter]

    /// ES-DE first: its separate `gamelists/` tree is the more distinctive
    /// signal, so trying it first avoids ever needing a folder to declare
    /// its own convention.
    public init(importers: [LibraryImporter] = [ESDELibraryImporter(), BatoceraLibraryImporter()]) {
        self.importers = importers
    }

    /// `only`, when given, limits the scan to those systems' folders.
    public func scan(romsRootURL: URL, only: Set<CanonicalSystemID>? = nil) -> ScanResult {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: romsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return ScanResult(systems: [], issues: [])
        }

        var systems: [ImportedSystemData] = []
        var issues: [ScanIssue] = []

        for folderURL in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = folderURL.lastPathComponent
            guard !name.hasPrefix("."), isDirectory(folderURL) else { continue }

            guard let definition = SystemTaxonomy.system(forShortName: name) else {
                issues.append(ScanIssue(folderURL: folderURL, reason: .unrecognizedSystemFolderName))
                continue
            }
            if let only, !only.contains(definition.canonicalID) { continue }

            guard let importer = importers.first(where: { $0.detect(systemFolderURL: folderURL) }) else {
                // An empty folder waiting for games (Attic makes one per
                // system) isn't a problem worth reporting.
                if MediaTidier.gameNames(in: folderURL).isEmpty { continue }
                issues.append(ScanIssue(folderURL: folderURL, reason: .noImporterRecognizedFormat))
                continue
            }

            do {
                let data = try importer.importSystem(systemFolderURL: folderURL, canonicalID: definition.canonicalID)
                let discs = DiscPlaylists.listedFiles(in: folderURL)
                // Only the system's own file types are games — gamelist
                // entries included, since a gamelist can list anything.
                systems.append(ImportedSystemData(
                    canonicalID: data.canonicalID,
                    libraryFormat: data.libraryFormat,
                    romsRootURL: data.romsRootURL,
                    // …and discs a .m3u playlist lists are part of that game,
                    // and an arcade board's BIOS set is no game at all.
                    // A gamelist entry whose file is gone from this folder
                    // (which is there: an unplugged drive is never scanned)
                    // was deleted or moved.
                    games: data.games.filter { game in
                        SystemROMExtensions.accepts(game.romRelativePath, for: definition.canonicalID)
                            && !discs.contains(game.romRelativePath)
                            && !ArcadeBIOSSets.isBIOSSet(game.romRelativePath, system: definition.canonicalID)
                            && fileManager.fileExists(atPath: folderURL.appending(path: game.romRelativePath).path)
                    }
                ))
            } catch {
                issues.append(ScanIssue(folderURL: folderURL, reason: .importFailed(String(describing: error))))
            }
        }

        return ScanResult(systems: systems, issues: issues)
    }

    /// Scans several ROMs roots and merges the results — a system folder
    /// name (e.g. "snes") appearing under more than one root produces one
    /// `ImportedSystemData` entry per root; `LibraryStore` upserts by
    /// canonical id, so the last one scanned wins.
    public func scan(romsRootURLs: [URL], only: Set<CanonicalSystemID>? = nil) -> ScanResult {
        let results = romsRootURLs.map { scan(romsRootURL: $0, only: only) }
        return ScanResult(
            systems: results.flatMap(\.systems),
            issues: results.flatMap(\.issues)
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
