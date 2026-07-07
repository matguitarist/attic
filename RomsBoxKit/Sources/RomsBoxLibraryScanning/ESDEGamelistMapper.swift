import Foundation
import RomsBoxModels

/// Maps raw `gamelist.xml` fields (via `GamelistXMLFieldParser`) into
/// `ImportedGameRecord`s using ES-DE's convention: no media tags at all —
/// art comes from `ESDEMediaResolver` filename matching, not the XML.
enum ESDEGamelistMapper {
    static func parse(_ data: Data, mediaResolver: ESDEMediaResolver) throws -> [ImportedGameRecord] {
        try GamelistXMLFieldParser().parse(data).compactMap { fields in
            makeRecord(from: fields, mediaResolver: mediaResolver)
        }
    }

    private static func makeRecord(from fields: [String: String], mediaResolver: ESDEMediaResolver) -> ImportedGameRecord? {
        guard let rawPath = fields.nonEmpty("path") else { return nil }
        let relativePath = normalizeRelativePath(rawPath)
        let nameNoExt = (relativePath as NSString).deletingPathExtension
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
            coverArtURL: mediaResolver.resolveCoverArt(romNameNoExt: nameNoExt),
            titleScreenURL: mediaResolver.resolveTitleScreen(romNameNoExt: nameNoExt),
            videoURL: mediaResolver.resolveVideo(romNameNoExt: nameNoExt)
        )
    }

    static func normalizeRelativePath(_ raw: String) -> String {
        var path = raw
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }
}
