import Foundation
import RomsBoxModels

enum BatoceraGamelistParserError: Error {
    case malformedXML(Error?)
}

/// Parses a Batocera/RetroBat-style `gamelist.xml`: a flat `<gameList>` of
/// `<game>` entries, each carrying its own `<image>`/`<video>`/`<thumbnail>`
/// path (relative, absolute, or `~`-prefixed) — unlike ES-DE, which has no
/// media tags at all and matches by filename instead (see
/// `ESDELibraryImporter`, Phase 4).
final class BatoceraGamelistParser: NSObject, XMLParserDelegate {
    private let systemFolderURL: URL
    private var games: [ImportedGameRecord] = []

    private var currentText = ""
    private var currentFields: [String: String] = [:]
    private var insideGame = false

    init(systemFolderURL: URL) {
        self.systemFolderURL = systemFolderURL
    }

    func parse(_ data: Data) throws -> [ImportedGameRecord] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw BatoceraGamelistParserError.malformedXML(parser.parserError)
        }
        return games
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentText = ""
        if elementName == "game" {
            insideGame = true
            currentFields = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if insideGame && elementName != "game" {
            currentFields[elementName] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "game" {
            if let record = makeRecord(from: currentFields) {
                games.append(record)
            }
            insideGame = false
        }
        currentText = ""
    }

    private func makeRecord(from fields: [String: String]) -> ImportedGameRecord? {
        guard let rawPath = fields["path"], !rawPath.isEmpty else { return nil }
        let relativePath = Self.normalizeRelativePath(rawPath)
        let title = fields["name"]?.isEmpty == false ? fields["name"]! : (relativePath as NSString).lastPathComponent

        return ImportedGameRecord(
            romRelativePath: relativePath,
            title: title,
            sortTitle: fields["sortname"]?.isEmpty == false ? fields["sortname"] : nil,
            description: fields["desc"]?.isEmpty == false ? fields["desc"] : nil,
            releaseDate: fields["releasedate"].flatMap(Self.parseReleaseDate),
            developer: fields["developer"]?.isEmpty == false ? fields["developer"] : nil,
            publisher: fields["publisher"]?.isEmpty == false ? fields["publisher"] : nil,
            genre: fields["genre"]?.isEmpty == false ? fields["genre"] : nil,
            players: fields["players"]?.isEmpty == false ? fields["players"] : nil,
            rating: fields["rating"].flatMap(Double.init),
            favorite: fields["favorite"] == "true",
            coverArtURL: fields["image"].flatMap(resolveMediaPath),
            titleScreenURL: fields["thumbnail"].flatMap(resolveMediaPath),
            videoURL: fields["video"].flatMap(resolveMediaPath)
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
    private func resolveMediaPath(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("~") {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return systemFolderURL.appending(path: Self.normalizeRelativePath(raw))
    }

    private static func parseReleaseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }
}
