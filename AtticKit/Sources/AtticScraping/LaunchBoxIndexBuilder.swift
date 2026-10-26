import Foundation
import SQLite3

/// Makes a `LaunchBoxIndex` from the files in LaunchBox's Metadata.zip,
/// read as they stream past rather than loaded: Metadata.xml alone is half
/// a gigabyte.
public enum LaunchBoxIndexBuilder {
    public struct Summary: Sendable, Equatable {
        public let games: Int
        public let images: Int
    }

    /// Writes the index of `platforms`' games to `destination`, replacing
    /// what's there only once it's complete. `metadata` lists the games,
    /// then their other names and pictures (in that order, as LaunchBox
    /// writes it); `files` names games by their No-Intro file, `mame` by
    /// their MAME short name.
    public static func build(metadata: URL, files: URL?, mame: URL?, platforms: Set<String>, to destination: URL) throws -> Summary {
        let partial = destination.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(partial.path, &handle) == SQLITE_OK, let database = handle else {
            sqlite3_close(handle)
            throw LaunchBoxIndexError.unwritable(destination.lastPathComponent)
        }
        let summary: Summary
        do {
            summary = try fill(database, metadata: metadata, files: files, mame: mame, platforms: platforms)
            sqlite3_close(database)
        } catch {
            sqlite3_close(database)
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return summary
    }

    private static func fill(_ database: OpaquePointer, metadata: URL, files: URL?, mame: URL?, platforms: Set<String>) throws -> Summary {
        let writer = Writer(database: database, platforms: platforms)
        try writer.createTables()

        try parse(metadata, elements: ["Game", "GameAlternateName", "GameImage"]) { element, fields in
            switch element {
            case "Game": writer.addGame(fields)
            case "GameAlternateName": writer.addAlternateName(fields)
            default: writer.addImage(fields)
            }
        }
        if let files {
            try parse(files, elements: ["File"]) { _, fields in
                writer.addFileName(fields["FileName"], gameName: fields["GameName"], platform: fields["Platform"])
            }
        }
        if let mame {
            try parse(mame, elements: ["MameFile"]) { _, fields in
                writer.addFileName(fields["FileName"], gameName: fields["Name"], platform: "Arcade")
            }
        }
        return try writer.finish()
    }

    /// Calls `found` with the child elements' text of each element named
    /// one of `elements` right under the root.
    private static func parse(_ url: URL, elements: Set<String>, found: @escaping (String, [String: String]) -> Void) throws {
        guard let stream = InputStream(url: url) else { throw LaunchBoxIndexError.unreadable(url.lastPathComponent) }
        let parser = XMLParser(stream: stream)
        let reader = RecordReader(elements: elements, found: found)
        parser.delegate = reader
        guard parser.parse() else {
            throw LaunchBoxIndexError.unreadable("\(url.lastPathComponent): \(parser.parserError?.localizedDescription ?? "")")
        }
    }

    /// Collects one level of child elements' text for each record.
    private final class RecordReader: NSObject, XMLParserDelegate {
        let elements: Set<String>
        let found: (String, [String: String]) -> Void
        private var depth = 0
        private var record: String?
        private var fields: [String: String] = [:]
        private var field: String?
        private var text = ""

        init(elements: Set<String>, found: @escaping (String, [String: String]) -> Void) {
            self.elements = elements
            self.found = found
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            if depth == 2, elements.contains(elementName) {
                record = elementName
                fields = [:]
            } else if depth == 3, record != nil {
                field = elementName
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if field != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if depth == 3, let name = field {
                if !text.isEmpty { fields[name] = text }
                field = nil
            } else if depth == 2, let record {
                found(record, fields)
                self.record = nil
            }
            depth -= 1
        }
    }

    /// Inserts as the records come, in one transaction.
    private final class Writer {
        let database: OpaquePointer
        let platforms: Set<String>
        private var platformIDs: [String: Int64] = [:]
        private var regionIDs: [String: Int64] = [:]
        /// Each kept game's platform.
        private var gamePlatforms: [Int64: Int64] = [:]
        /// Games by platform and name key, to find a file's game by its name.
        private var gamesByName: [Int64: [String: Int64]] = [:]
        private var statements: [String: OpaquePointer] = [:]
        private var games = 0
        private var images = 0

        init(database: OpaquePointer, platforms: Set<String>) {
            self.database = database
            self.platforms = platforms
        }

        func createTables() throws {
            let schema = """
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            CREATE TABLE platform(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
            CREATE TABLE region(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
            CREATE TABLE game(id INTEGER PRIMARY KEY, platform INTEGER NOT NULL, name TEXT, released TEXT, developer TEXT,
                              publisher TEXT, genres TEXT, players INTEGER, rating REAL, overview BLOB);
            CREATE TABLE name(key TEXT NOT NULL, platform INTEGER NOT NULL, game INTEGER NOT NULL,
                              PRIMARY KEY(key, platform, game)) WITHOUT ROWID;
            CREATE TABLE image(game INTEGER NOT NULL, kind INTEGER NOT NULL, region INTEGER NOT NULL, file BLOB NOT NULL,
                               ext TEXT NOT NULL, PRIMARY KEY(game, kind, region, file)) WITHOUT ROWID;
            BEGIN;
            """
            guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else { throw LaunchBoxIndexError.unwritable("schema") }
            for name in platforms.sorted() {
                let id = Int64(platformIDs.count + 1)
                platformIDs[name] = id
                run("INSERT INTO platform VALUES (?, ?)", [id, name])
            }
        }

        func addGame(_ fields: [String: String]) {
            guard let platform = fields["Platform"].flatMap({ platformIDs[$0] }),
                  let id = fields["DatabaseID"].flatMap(Int64.init), let name = fields["Name"] else { return }
            let released = fields["ReleaseDate"].map { String($0.prefix(10)) } ?? fields["ReleaseYear"]
            let overview = fields["Overview"].flatMap { try? (Data($0.utf8) as NSData).compressed(using: .zlib) as Data }
            run("INSERT OR IGNORE INTO game VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
                id, platform, name, released, fields["Developer"], fields["Publisher"], fields["Genres"],
                fields["MaxPlayers"].flatMap(Int.init), fields["CommunityRating"].flatMap(Double.init), overview
            ])
            gamePlatforms[id] = platform
            games += 1
            addNames(of: name, game: id, platform: platform)
        }

        func addAlternateName(_ fields: [String: String]) {
            guard let id = fields["DatabaseID"].flatMap(Int64.init), let platform = gamePlatforms[id],
                  let name = fields["AlternateName"] else { return }
            addNames(of: name, game: id, platform: platform)
        }

        func addImage(_ fields: [String: String]) {
            guard let id = fields["DatabaseID"].flatMap(Int64.init), gamePlatforms[id] != nil,
                  let kind = fields["Type"].flatMap({ LaunchBoxIndex.Image.Kind.byType[$0] }),
                  let fileName = fields["FileName"] else { return }
            let stored = LaunchBoxIndex.Image.storedFile(fileName)
            run("INSERT OR IGNORE INTO image VALUES (?, ?, ?, ?, ?)",
                [id, Int64(kind.rawValue), region(fields["Region"] ?? ""), stored.file, stored.ext])
            images += 1
        }

        /// A file's name for the game LaunchBox says it is.
        func addFileName(_ fileName: String?, gameName: String?, platform: String?) {
            guard let fileName, let gameName, let platform = platform.flatMap({ platformIDs[$0] }),
                  let names = gamesByName[platform],
                  let game = names[LaunchBoxIndex.key(gameName)] ?? names[LaunchBoxIndex.key(LaunchBoxIndex.stripTags(gameName))]
            else { return }
            insertName(LaunchBoxIndex.key(fileName), game: game, platform: platform)
        }

        private func addNames(of name: String, game: Int64, platform: Int64) {
            for key in Set([LaunchBoxIndex.key(name), LaunchBoxIndex.key(LaunchBoxIndex.stripTags(name))]) where !key.isEmpty {
                insertName(key, game: game, platform: platform)
                if gamesByName[platform, default: [:]][key] == nil { gamesByName[platform, default: [:]][key] = game }
            }
        }

        private func insertName(_ key: String, game: Int64, platform: Int64) {
            guard !key.isEmpty else { return }
            run("INSERT OR IGNORE INTO name VALUES (?, ?, ?)", [key, platform, game])
        }

        private func region(_ name: String) -> Int64 {
            if let id = regionIDs[name] { return id }
            let id = Int64(regionIDs.count + 1)
            regionIDs[name] = id
            run("INSERT INTO region VALUES (?, ?)", [id, name])
            return id
        }

        func finish() throws -> Summary {
            for statement in statements.values { sqlite3_finalize(statement) }
            statements = [:]
            guard sqlite3_exec(database, "COMMIT; VACUUM;", nil, nil, nil) == SQLITE_OK else {
                throw LaunchBoxIndexError.unwritable(String(cString: sqlite3_errmsg(database)))
            }
            return Summary(games: games, images: images)
        }

        /// Each statement prepared once, reused for every row.
        private func run(_ sql: String, _ arguments: [Any?]) {
            let statement: OpaquePointer
            if let prepared = statements[sql] {
                statement = prepared
            } else {
                var prepared: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else { return }
                statements[sql] = prepared
                statement = prepared
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            LaunchBoxIndex.bind(arguments, to: statement)
            sqlite3_step(statement)
        }
    }
}
