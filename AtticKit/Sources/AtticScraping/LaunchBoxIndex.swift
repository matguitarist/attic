import Foundation
import SQLite3
import Synchronization

/// The LaunchBox Games Database, offline: what its Metadata.zip says about
/// the games of some platforms, kept as a small SQLite file to look games
/// up in — their facts and description, and the names of their pictures on
/// LaunchBox's image server.
///
/// The download is 109 MB (a 516 MB XML inside); for one library's
/// platforms the index is a tenth of that: only the fields Attic shows,
/// descriptions compressed, pictures by their 16-byte ids, and only the
/// kinds of picture Attic keeps.
public final class LaunchBoxIndex: Sendable {
    /// Where its pictures are, by file name.
    public static let imagesURL = URL(string: "https://images.launchbox-app.com/")!
    public static let downloadURL = URL(string: "https://gamesdb.launchbox-app.com/Metadata.zip")!

    /// The connection, one lookup at a time.
    private let database: Mutex<OpaquePointer?>

    public init(contentsOf url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw LaunchBoxIndexError.unreadable(url.lastPathComponent)
        }
        database = Mutex(handle)
    }

    deinit {
        _ = database.withLock { sqlite3_close($0) }
    }

    // MARK: - Looking up

    /// A game to find: its file's name without extension (No-Intro's, or
    /// MAME's short name) and its title, on any of `platforms`.
    public struct Query: Sendable {
        public var fileName: String
        public var title: String?
        public var platforms: [String]

        public init(fileName: String, title: String? = nil, platforms: [String]) {
            self.fileName = fileName
            self.title = title
            self.platforms = platforms
        }
    }

    /// What LaunchBox has for the game, its pictures from the region its
    /// file is from where there's a choice; nil when it isn't there.
    public func info(for query: Query) -> ScrapedGameInfo? {
        database.withLock { database -> ScrapedGameInfo? in
            guard let database, let game = Self.gameID(for: query, in: database) else { return nil }
            return Self.info(ofGame: game, region: Self.region(ofFileName: query.fileName), in: database)
        }
    }

    /// How many games it has, for Settings.
    public var gameCount: Int {
        database.withLock { database in
            guard let database else { return 0 }
            var count = 0
            Self.query(database, "SELECT count(*) FROM game") { count = Int(sqlite3_column_int64($0, 0)) }
            return count
        }
    }

    /// Its file's name, then the name without its tags, then the title:
    /// the first that's a name of a game on one of the platforms, in their
    /// order.
    private static func gameID(for query: Query, in database: OpaquePointer) -> Int64? {
        let platformIDs = query.platforms.compactMap { platformID(named: $0, in: database) }
        guard !platformIDs.isEmpty else { return nil }
        var keys = [key(query.fileName), key(stripTags(query.fileName))]
        if let title = query.title { keys += [key(title), key(stripTags(title))] }
        for name in keys where !name.isEmpty {
            var found: [(platform: Int64, game: Int64)] = []
            Self.query(database, "SELECT platform, game FROM name WHERE key = ?", [name]) {
                found.append((sqlite3_column_int64($0, 0), sqlite3_column_int64($0, 1)))
            }
            for platform in platformIDs {
                if let match = found.first(where: { $0.platform == platform }) { return match.game }
            }
        }
        return nil
    }

    private static func platformID(named name: String, in database: OpaquePointer) -> Int64? {
        var id: Int64?
        query(database, "SELECT id FROM platform WHERE name = ?", [name]) { id = sqlite3_column_int64($0, 0) }
        return id
    }

    private static func info(ofGame game: Int64, region: String?, in database: OpaquePointer) -> ScrapedGameInfo? {
        var info: ScrapedGameInfo?
        query(database, "SELECT name, released, developer, publisher, genres, players, rating, overview FROM game WHERE id = ?",
              [game]) { row in
            var result = ScrapedGameInfo()
            result.title = text(row, 0)
            result.releaseDate = text(row, 1).flatMap(releaseDate)
            result.developer = text(row, 2)
            result.publisher = text(row, 3)
            // "Action; Platform" in LaunchBox.
            result.genre = text(row, 4)?.replacingOccurrences(of: "; ", with: ", ")
            if sqlite3_column_type(row, 5) != SQLITE_NULL { result.players = String(sqlite3_column_int(row, 5)) }
            // Out of five there.
            if sqlite3_column_type(row, 6) != SQLITE_NULL { result.rating = min(1, max(0, sqlite3_column_double(row, 6) / 5)) }
            if let bytes = sqlite3_column_blob(row, 7) {
                let compressed = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 7)))
                result.description = (try? (compressed as NSData).decompressed(using: .zlib) as Data)
                    .flatMap { String(data: $0, encoding: .utf8) }
            }
            info = result
        }
        guard var info else { return nil }

        var regions: [Int64: String] = [:]
        query(database, "SELECT id, name FROM region") { regions[sqlite3_column_int64($0, 0)] = text($0, 1) ?? "" }
        var images: [Image] = []
        query(database, "SELECT kind, region, file, ext FROM image WHERE game = ?", [game]) { row in
            guard let kind = Image.Kind(rawValue: Int(sqlite3_column_int(row, 0))), let bytes = sqlite3_column_blob(row, 2) else { return }
            let file = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 2)))
            images.append(Image(kind: kind, region: regions[sqlite3_column_int64(row, 1)] ?? "",
                                file: Image.fileName(file, ext: text(row, 3) ?? "jpg")))
        }
        func best(_ kinds: Image.Kind...) -> URL? {
            for kind in kinds {
                let ofKind = images.filter { $0.kind == kind }
                // The file's own region, then North America's (most
                // complete), the world's, any.
                let order = [region, "North America", "World", "United States", ""].compactMap { $0 }
                let chosen = order.lazy.compactMap { wanted in ofKind.first { $0.region == wanted } }.first ?? ofKind.first
                if let chosen { return imagesURL.appending(path: chosen.file) }
            }
            return nil
        }
        // Arcade games have no box: their flyer is the cover, as on
        // ScreenScraper.
        info.coverArtURL = best(.boxFront, .boxFrontReconstructed, .flyer)
        info.box3DURL = best(.box3D)
        info.logoURL = best(.clearLogo)
        info.screenshotURL = best(.screenshot, .titleScreen)
        info.fanartURL = best(.fanart)
        info.physicalMediaURL = best(.cart, .disc)
        return info
    }

    /// The LaunchBox region of a No-Intro file name's first region tag.
    static func region(ofFileName name: String) -> String? {
        let tags = name.split(separator: "(").dropFirst().map { $0.split(separator: ")").first.map(String.init) ?? "" }
        for tag in tags {
            for part in tag.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                switch part {
                case "USA", "Canada": return "North America"
                case "Europe", "UK", "Australia": return "Europe"
                case "Japan": return "Japan"
                case "World": return "World"
                case "France": return "France"
                case "Germany": return "Germany"
                case "Spain": return "Spain"
                case "Italy": return "Italy"
                case "Korea": return "Korea"
                case "Brazil": return "Brazil"
                default: continue
                }
            }
        }
        return nil
    }

    /// "1994-11-21", or a year alone.
    static func releaseDate(_ text: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return nil }
        return calendar.date(from: DateComponents(year: year, month: parts[safe: 1] ?? 1, day: parts[safe: 2] ?? 1))
    }

    struct Image {
        /// The kinds of LaunchBox picture kept, by their number in the index.
        enum Kind: Int, CaseIterable {
            case boxFront = 1, box3D, clearLogo, screenshot, titleScreen, fanart, disc, cart, marquee, boxFrontReconstructed, flyer

            /// Its `Type` in Metadata.xml.
            var launchBoxType: String {
                switch self {
                case .boxFront: "Box - Front"
                case .box3D: "Box - 3D"
                case .clearLogo: "Clear Logo"
                case .screenshot: "Screenshot - Gameplay"
                case .titleScreen: "Screenshot - Game Title"
                case .fanart: "Fanart - Background"
                case .disc: "Disc"
                case .cart: "Cart - Front"
                case .marquee: "Arcade - Marquee"
                case .boxFrontReconstructed: "Box - Front - Reconstructed"
                case .flyer: "Advertisement Flyer - Front"
                }
            }

            static let byType = Dictionary(uniqueKeysWithValues: allCases.map { ($0.launchBoxType, $0) })
        }

        let kind: Kind
        let region: String
        let file: String

        /// A picture's id back as its file name: 16 bytes are a UUID, as
        /// almost all are; anything else was kept as it was.
        static func fileName(_ file: Data, ext: String) -> String {
            let stem = file.count == 16
                ? file.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }.uuidString.lowercased()
                : String(decoding: file, as: UTF8.self)
            return "\(stem).\(ext)"
        }

        /// What `fileName` reads back.
        static func storedFile(_ name: String) -> (file: Data, ext: String) {
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension.lowercased()
            if let uuid = UUID(uuidString: stem), uuid.uuidString.lowercased() == stem.lowercased() {
                return (withUnsafeBytes(of: uuid.uuid) { Data($0) }, ext)
            }
            return (Data(stem.utf8), ext)
        }
    }

    // MARK: - Names

    /// A name as compared: lowercase letters and digits only, accents
    /// gone, "&" as "and", and a trailing ", The" (No-Intro's) moved to
    /// the front.
    static func key(_ name: String) -> String {
        var name = name.trimmingCharacters(in: .whitespaces)
        for article in ["The", "A", "An"] {
            // "Legend of Zelda, The - A Link to the Past" too.
            for separator in [" - ", ": ", " ("] {
                if let range = name.range(of: ", \(article)\(separator)") {
                    name = "\(article) " + name.replacingCharacters(in: range, with: separator)
                }
            }
            if name.hasSuffix(", \(article)") { name = "\(article) " + name.dropLast(article.count + 2) }
        }
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// A file's name without its tags: "Sonic (USA) (Rev 1) [!]" → "Sonic".
    static func stripTags(_ name: String) -> String {
        var result = ""
        var depth = 0
        for character in name {
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth = max(0, depth - 1)
            default: if depth == 0 { result.append(character) }
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Runs `sql` with `arguments` bound, calling `row` for each result row.
    @discardableResult
    static func query(_ database: OpaquePointer, _ sql: String, _ arguments: [Any] = [], row: (OpaquePointer) -> Void = { _ in }) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(arguments, to: statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(statement)
            case SQLITE_DONE: return true
            default: return false
            }
        }
    }

    static func bind(_ arguments: [Any?], to statement: OpaquePointer) {
        for (offset, argument) in arguments.enumerated() {
            let index = Int32(offset + 1)
            switch argument {
            case let value as String: sqlite3_bind_text(statement, index, value, -1, transient)
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as Data:
                _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient) }
            default: sqlite3_bind_null(statement, index)
            }
        }
    }

    static func text(_ row: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(row, column).map { String(cString: $0) }
    }
}

public enum LaunchBoxIndexError: Error, Sendable, Equatable {
    case unreadable(String)
    case unwritable(String)
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
