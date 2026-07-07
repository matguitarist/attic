import Foundation
import RomsBoxModels

enum LibrarySelection: Hashable {
    case allGames
    case favorites
    case recentlyPlayed
    case system(CanonicalSystemID)
}

enum GameSortOrder: String, CaseIterable, Identifiable {
    case title
    case lastPlayed
    case favoriteFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .lastPlayed: "Last Played"
        case .favoriteFirst: "Favorites First"
        }
    }
}
