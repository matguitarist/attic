import Foundation

enum GamelistXMLParserError: Error {
    case malformedXML(Error?)
}

/// Convention-agnostic `gamelist.xml` reader: extracts each `<game>` element
/// into a flat `[tagName: trimmedText]` dictionary, with no opinion on which
/// tags mean what. Batocera- and ES-DE-specific field mapping (including,
/// for Batocera, resolving inline media path tags) happens one layer up in
/// each importer, since that's where the two conventions actually diverge.
final class GamelistXMLFieldParser: NSObject, XMLParserDelegate {
    private var games: [[String: String]] = []
    private var currentText = ""
    private var currentFields: [String: String] = [:]
    private var insideGame = false

    func parse(_ data: Data) throws -> [[String: String]] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw GamelistXMLParserError.malformedXML(parser.parserError)
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
            games.append(currentFields)
            insideGame = false
        }
        currentText = ""
    }
}

/// Both Batocera/RetroBat and ES-DE use the same `<releasedate>` format.
enum GamelistDateParsing {
    static func parseReleaseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }
}

extension Dictionary where Key == String, Value == String {
    /// nil for both a missing key and an empty (whitespace-trimmed) value —
    /// gamelist.xml frequently has empty tags (`<desc></desc>`) that should
    /// be treated the same as an absent tag.
    func nonEmpty(_ key: String) -> String? {
        guard let value = self[key], !value.isEmpty else { return nil }
        return value
    }
}
