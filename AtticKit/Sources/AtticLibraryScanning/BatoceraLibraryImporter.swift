import Foundation
import AtticModels

/// Batocera/RetroBat convention: `gamelist.xml` sits directly inside the
/// system folder (`roms/<system>/gamelist.xml`), and each `<game>` entry
/// carries its own explicit media paths.
public struct BatoceraLibraryImporter: LibraryImporter {
    public init() {}

    public func detect(systemFolderURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: systemFolderURL.appending(path: "gamelist.xml").path)
    }

    public func importSystem(systemFolderURL: URL, canonicalID: CanonicalSystemID) throws -> ImportedSystemData {
        let gamelistURL = systemFolderURL.appending(path: "gamelist.xml")
        let data = try Data(contentsOf: gamelistURL)
        let games = try BatoceraGamelistParser.parse(data, systemFolderURL: systemFolderURL)
        return ImportedSystemData(
            canonicalID: canonicalID,
            libraryFormat: .batocera,
            romsRootURL: systemFolderURL,
            games: games
        )
    }
}
