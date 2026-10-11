import Foundation

/// TheGamesDB's genre, developer and publisher names by id. Game results
/// only carry ids (its `include` param offers just `boxart` and
/// `platform`), so the names come from the three list endpoints — fetched
/// together, cached on disk, and refreshed monthly: three requests a month
/// instead of three per game against a small monthly allowance.
public struct TheGamesDBNames: Codable, Sendable, Equatable {
    public var genres: [Int: String]
    public var developers: [Int: String]
    public var publishers: [Int: String]
    public var fetchedDate: Date

    public init(genres: [Int: String] = [:], developers: [Int: String] = [:], publishers: [Int: String] = [:], fetchedDate: Date = .now) {
        self.genres = genres
        self.developers = developers
        self.publishers = publishers
        self.fetchedDate = fetchedDate
    }

    func covers(_ game: TheGamesDBGame) -> Bool {
        (game.genres ?? []).allSatisfy { genres[$0] != nil }
            && (game.developers ?? []).allSatisfy { developers[$0] != nil }
            && (game.publishers ?? []).allSatisfy { publishers[$0] != nil }
    }
}

/// Holds the names in memory and on disk, and decides when to refetch:
/// when there are none, when they're a month old, or when a game names an
/// id they don't have (a newly added developer) and they're over a day old.
actor TheGamesDBNameCache {
    static let maxAge: TimeInterval = 30 * 24 * 3600
    static let missingIDRetryAge: TimeInterval = 24 * 3600

    private let fileURL: URL?
    private var names: TheGamesDBNames?
    private var loadedFromDisk = false

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func names(for game: TheGamesDBGame, fetch: @Sendable () async throws -> TheGamesDBNames) async -> TheGamesDBNames? {
        loadFromDiskIfNeeded()
        // Nothing to look up: don't spend requests on it.
        if TheGamesDBNames(fetchedDate: .distantPast).covers(game) { return names }
        if let names {
            let age = Date.now.timeIntervalSince(names.fetchedDate)
            let isFresh = age < Self.maxAge && (names.covers(game) || age < Self.missingIDRetryAge)
            if isFresh { return names }
        }
        // Names are a nice-to-have: if the lists can't be fetched, the
        // scrape still succeeds with whatever names were cached.
        guard let fetched = try? await fetch() else { return names }
        names = fetched
        save(fetched)
        return fetched
    }

    private func loadFromDiskIfNeeded() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        names = try? JSONDecoder().decode(TheGamesDBNames.self, from: data)
    }

    private func save(_ names: TheGamesDBNames) {
        guard let fileURL, let data = try? JSONEncoder().encode(names) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// `/v1/Genres`, `/v1/Developers` and `/v1/Publishers`: `data.<kind>` is
/// an object keyed by id.
struct TheGamesDBNameListEnvelope: Decodable {
    let data: [String: TheGamesDBNameListData]?

    struct TheGamesDBNameListData: Decodable {
        let id: Int?
        let name: String?
    }

    enum CodingKeys: String, CodingKey { case data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `data` holds `count` next to the list, so decode it loosely.
        let inner = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .data)
        var entries: [String: TheGamesDBNameListData] = [:]
        for key in inner.allKeys where key.stringValue != "count" {
            if let list = try? inner.decode([String: TheGamesDBNameListData].self, forKey: key) {
                entries.merge(list) { first, _ in first }
            }
        }
        data = entries
    }

    var names: [Int: String] {
        var result: [Int: String] = [:]
        for (key, entry) in data ?? [:] {
            guard let id = entry.id ?? Int(key), let name = entry.name else { continue }
            result[id] = name
        }
        return result
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
