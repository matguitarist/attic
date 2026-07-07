import Foundation
import RomsBoxModels

/// Maps raw `gamelist.xml` fields (via `GamelistXMLFieldParser`) into
/// `ImportedGameRecord`s using Batocera/RetroBat's convention: each
/// `<game>` carries its own `<image>`/`<video>`/`<thumbnail>` path
/// (relative, absolute, or `~`-prefixed) — unlike ES-DE, which has no media
/// tags at all and matches by filename instead (see `ESDEGamelistMapper`).
enum BatoceraGamelistParser {
    static func parse(_ data: Data, systemFolderURL: URL) throws -> [ImportedGameRecord] {
        try GamelistXMLFieldParser().parse(data).compactMap { fields in
            makeRecord(from: fields, systemFolderURL: systemFolderURL)
        }
    }

    private static func makeRecord(from fields: [String: String], systemFolderURL: URL) -> ImportedGameRecord? {
        guard let rawPath = fields.nonEmpty("path") else { return nil }
        let relativePath = normalizeRelativePath(rawPath)
        let title = fields.nonEmpty("name") ?? ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: relativePath)

        return ImportedGameRecord(
            romRelativePath: relativePath,
            title: title,
            sortTitle: fields.nonEmpty("sortname"),
            description: fields.nonEmpty("desc"),
            releaseDate: GamelistDateParsing.parseReleaseDate(fields["releasedate"]),
            developer: fields.nonEmpty("developer"),
            publisher: fields.nonEmpty("publisher"),
            genre: fields.nonEmpty("genre"),
            players: fields.nonEmpty("players"),
            rating: fields["rating"].flatMap(Double.init),
            favorite: fields["favorite"] == "true",
            coverArtURL: fields["image"].flatMap { resolveMediaPath($0, systemFolderURL: systemFolderURL) },
            titleScreenURL: fields["thumbnail"].flatMap { resolveMediaPath($0, systemFolderURL: systemFolderURL) },
            videoURL: fields["video"].flatMap { resolveMediaPath($0, systemFolderURL: systemFolderURL) }
        )
    }

    private static func normalizeRelativePath(_ raw: String) -> String {
        var path = raw
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }

    /// Batocera/RetroBat gamelist.xml media paths may be relative to the
    /// system folder (`./media/image.png`), absolute (`/Users/.../image.png`),
    /// or home-relative (`~/.emulationstation/downloaded_images/...`).
    private static func resolveMediaPath(_ raw: String, systemFolderURL: URL) -> URL? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("~") {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return systemFolderURL.appending(path: normalizeRelativePath(raw))
    }
}
