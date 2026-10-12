import Foundation
import RomsBoxModels

/// Enumerates a ROMs root's immediate subfolders, maps each folder name to
/// a canonical system via `SystemTaxonomy`, and picks an importer per
/// folder by trying each in order — so a single root can mix conventions
/// (one system folder in ES-DE's layout, another in Batocera's) and each is
/// still recognized correctly.
///
/// Deliberately produces `ImportedSystemData` DTOs rather than writing to
/// SwiftData itself — `RomsBoxLibraryScanning` has no dependency on
/// `RomsBoxPersistence`, so this stays independently testable against
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

    public func scan(romsRootURL: URL) -> ScanResult {
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

            guard let importer = importers.first(where: { $0.detect(systemFolderURL: folderURL) }) else {
                issues.append(ScanIssue(folderURL: folderURL, reason: .noImporterRecognizedFormat))
                continue
            }

            do {
                let data = try importer.importSystem(systemFolderURL: folderURL, canonicalID: definition.canonicalID)
                // Only the system's own file types are games — gamelist
                // entries included, since a gamelist can list anything.
                systems.append(ImportedSystemData(
                    canonicalID: data.canonicalID,
                    libraryFormat: data.libraryFormat,
                    romsRootURL: data.romsRootURL,
                    games: data.games.filter { SystemROMExtensions.accepts($0.romRelativePath, for: definition.canonicalID) }
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
    public func scan(romsRootURLs: [URL]) -> ScanResult {
        let results = romsRootURLs.map(scan(romsRootURL:))
        return ScanResult(
            systems: results.flatMap(\.systems),
            issues: results.flatMap(\.issues)
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
