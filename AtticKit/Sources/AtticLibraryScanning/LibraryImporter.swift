import Foundation
import AtticModels

/// One library convention's ability to recognize and parse a system folder.
/// `BatoceraLibraryImporter` and `ESDELibraryImporter` conform to this so the
/// orchestrator (`LibraryScanner`, Phase 5) can pick the right one per
/// folder without branching on format itself.
public protocol LibraryImporter: Sendable {
    /// Cheap, filesystem-only heuristic: does this system folder look like
    /// it was produced by this importer's convention? Must not throw or do
    /// expensive work — it's run against every system folder to pick an
    /// importer.
    func detect(systemFolderURL: URL) -> Bool

    /// Parses the system folder into a neutral DTO. Only called after
    /// `detect` has returned true for this folder.
    func importSystem(systemFolderURL: URL, canonicalID: CanonicalSystemID) throws -> ImportedSystemData
}
