import Foundation
import AtticModels

enum LibrarySelection: Hashable {
    case allGames
    case favorites
    case recentlyPlayed
    /// The newest games, most recent first.
    case recentlyAdded
    case system(CanonicalSystemID)
    /// A user collection, by `GameCollection.collectionID`.
    case collection(UUID)
}

enum GameSortOrder: String, CaseIterable, Identifiable {
    case title
    /// Systems in the sidebar's order, then oldest first: a series reads
    /// in order. Collections' default.
    case systemThenRelease
    case lastPlayed
    case dateAdded
    case favoriteFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: String(localized: "Title")
        case .systemThenRelease: String(localized: "System, then Release Date")
        case .lastPlayed: String(localized: "Last Played")
        case .dateAdded: String(localized: "Date Added")
        case .favoriteFirst: String(localized: "Favorites First")
        }
    }
}
