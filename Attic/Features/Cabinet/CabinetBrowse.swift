import SwiftUI
import AtticModels
import AtticPersistence

/// How Cabinet Mode narrows and orders a section's games: the search typed
/// with X, and the Start menu's View page. Shared by the shelf, the header
/// and the menu.
@Observable @MainActor
final class CabinetBrowse {
    static let sortKey = "cabinetSort"

    var search = "" {
        didSet { scheduleSearch() }
    }
    /// `search` once typing pauses: filtering thousands of games after
    /// every letter made fast typing drop letters.
    private(set) var appliedSearch = ""
    private var searchTask: Task<Void, Never>?
    var sort: CabinetSort {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey) }
    }
    var favoritesOnly = false
    /// 0 for any.
    var minPlayers = 0
    /// One of `genres`' terms, empty for any.
    var genre = ""

    init() {
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(CabinetSort.init(rawValue:)) ?? .section
    }

    var isFiltered: Bool { !search.isEmpty || favoritesOnly || minPlayers > 1 || !genre.isEmpty }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !search.isEmpty else {
            appliedSearch = ""
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            appliedSearch = search
        }
    }

    func clearFilters() {
        search = ""
        favoritesOnly = false
        minPlayers = 0
        genre = ""
    }

    /// Families of the genres scrapers give, as search terms (any of them).
    static let genres: [(name: String, terms: String)] = [
        (String(localized: "Platform"), "Platform"),
        (String(localized: "Action"), "Action"),
        (String(localized: "Adventure"), "Adventure"),
        (String(localized: "Shooter"), "Shooter"),
        (String(localized: "Shoot 'em Up"), "Shoot'em Up, Shoot 'em Up, Shmup"),
        (String(localized: "Beat 'em Up"), "Beat'em Up, Beat 'em Up, Brawler"),
        (String(localized: "Fighting"), "Fight"),
        (String(localized: "Racing"), "Race, Racing"),
        (String(localized: "Sports"), "Sports"),
        (String(localized: "Puzzle"), "Puzzle"),
        (String(localized: "RPG"), "Role Playing, Role-Playing, RPG"),
        (String(localized: "Strategy"), "Strategy"),
        (String(localized: "Simulation"), "Simulation"),
        (String(localized: "Light Gun"), "Lightgun, Light Gun")
    ]

    /// `games` (in the section's own order) searched, filtered and sorted.
    func apply(to games: [Game]) -> [Game] {
        var shown = games
        if !appliedSearch.isEmpty { shown = shown.filter { TitleBrowsing.matches($0.title, query: appliedSearch) } }
        if favoritesOnly { shown = shown.filter(\.favorite) }
        if minPlayers > 1 {
            shown = shown.filter { game in
                (game.players?.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max() ?? 0) >= minPlayers
            }
        }
        if !genre.isEmpty {
            let terms = genre.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            shown = shown.filter { game in terms.contains { game.genre?.localizedStandardContains($0) == true } }
        }
        switch sort {
        case .section:
            break
        case .title:
            shown.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        case .year:
            shown.sort { ($0.releaseDate ?? .distantFuture, $0.sortTitle) < ($1.releaseDate ?? .distantFuture, $1.sortTitle) }
        case .mostPlayed:
            shown.sort { ($0.playCount, $1.sortTitle) > ($1.playCount, $0.sortTitle) }
        case .lastPlayed:
            shown.sort { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        }
        return shown
    }

    /// What narrows the games, for the header.
    var chips: [String] {
        var chips: [String] = []
        if !search.isEmpty { chips.append("“\(search)”") }
        if favoritesOnly { chips.append(String(localized: "Favorites")) }
        if minPlayers > 1 { chips.append(String(localized: "\(minPlayers)+ players")) }
        if let name = Self.genres.first(where: { $0.terms == genre })?.name { chips.append(name) }
        if sort != .section { chips.append(sort.title) }
        return chips
    }
}

extension CabinetSort {
    var title: String {
        switch self {
        case .section: String(localized: "Section's Order")
        case .title: String(localized: "By Title")
        case .year: String(localized: "By Year")
        case .mostPlayed: String(localized: "Most Played")
        case .lastPlayed: String(localized: "Last Played")
        }
    }
}
