import Foundation
import RomsBoxModels

enum LibrarySelection: Hashable {
    case allGames
    case favorites
    case recentlyPlayed
    case system(CanonicalSystemID)
    /// A user collection, by `GameCollection.collectionID`.
    case collection(UUID)
}

enum GameSortOrder: String, CaseIterable, Identifiable {
    case title
    case lastPlayed
    case favoriteFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: String(localized: "Title")
        case .lastPlayed: String(localized: "Last Played")
        case .favoriteFirst: String(localized: "Favorites First")
        }
    }
}
