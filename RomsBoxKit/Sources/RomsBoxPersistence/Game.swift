import Foundation
import SwiftData
import RomsBoxModels

@Model
public final class Game {
    /// Denormalized alongside the `system` relationship so upsert lookups
    /// can filter by canonical id without a join.
    public var systemCanonicalID: String
    /// Natural key (together with `systemCanonicalID`) for upsert on rescan.
    public var romRelativePath: String
    public var romAbsolutePath: String

    public var title: String
    public var sortTitle: String
    public var gameDescription: String?
    public var releaseDate: Date?
    public var developer: String?
    public var publisher: String?
    public var genre: String?
    public var players: String?
    public var rating: Double?

    /// App-owned once the game first exists — later rescans do not overwrite
    /// this from the source gamelist.xml, so an in-app toggle isn't fought
    /// by the next rescan.
    public var favorite: Bool

    public var coverArtPath: String?
    public var titleScreenPath: String?
    public var videoPath: String?

    public var playCount: Int
    public var totalPlaytimeSeconds: Double
    public var lastPlayedDate: Date?
    private var launchOverrideData: Data?

    public var system: GameSystem?

    @Relationship(deleteRule: .cascade, inverse: \PlaySession.game)
    public var playSessions: [PlaySession] = []

    public init(
        system: GameSystem?,
        systemCanonicalID: CanonicalSystemID,
        romRelativePath: String,
        romAbsoluteURL: URL,
        title: String,
        sortTitle: String? = nil,
        description: String? = nil,
        releaseDate: Date? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        genre: String? = nil,
        players: String? = nil,
        rating: Double? = nil,
        favorite: Bool = false,
        coverArtURL: URL? = nil,
        titleScreenURL: URL? = nil,
        videoURL: URL? = nil
    ) {
        self.system = system
        self.systemCanonicalID = systemCanonicalID.rawValue
        self.romRelativePath = romRelativePath
        self.romAbsolutePath = romAbsoluteURL.path
        self.title = title
        self.sortTitle = sortTitle ?? title
        self.gameDescription = description
        self.releaseDate = releaseDate
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.players = players
        self.rating = rating
        self.favorite = favorite
        self.coverArtPath = coverArtURL?.path
        self.titleScreenPath = titleScreenURL?.path
        self.videoPath = videoURL?.path
        self.playCount = 0
        self.totalPlaytimeSeconds = 0
        self.lastPlayedDate = nil
    }

    public convenience init(system: GameSystem, systemCanonicalID: CanonicalSystemID, romsRootURL: URL, record: ImportedGameRecord) {
        self.init(
            system: system,
            systemCanonicalID: systemCanonicalID,
            romRelativePath: record.romRelativePath,
            romAbsoluteURL: romsRootURL.appending(path: record.romRelativePath),
            title: record.title,
            sortTitle: record.sortTitle,
            description: record.description,
            releaseDate: record.releaseDate,
            developer: record.developer,
            publisher: record.publisher,
            genre: record.genre,
            players: record.players,
            rating: record.rating,
            favorite: record.favorite,
            coverArtURL: record.coverArtURL,
            titleScreenURL: record.titleScreenURL,
            videoURL: record.videoURL
        )
    }

    /// Refreshes metadata from a rescanned record. Deliberately leaves
    /// `favorite`, play tracking, and `launchOverride` untouched — those are
    /// app/user state, not source-of-truth metadata.
    public func applyRescannedMetadata(_ record: ImportedGameRecord, romsRootURL: URL) {
        romAbsolutePath = romsRootURL.appending(path: record.romRelativePath).path
        title = record.title
        sortTitle = record.sortTitle ?? record.title
        gameDescription = record.description
        releaseDate = record.releaseDate
        developer = record.developer
        publisher = record.publisher
        genre = record.genre
        players = record.players
        rating = record.rating
        coverArtPath = record.coverArtURL?.path
        titleScreenPath = record.titleScreenURL?.path
        videoPath = record.videoURL?.path
    }
}

extension Game {
    public var romAbsoluteURL: URL { URL(fileURLWithPath: romAbsolutePath) }
    public var coverArtURL: URL? { coverArtPath.map { URL(fileURLWithPath: $0) } }
    public var titleScreenURL: URL? { titleScreenPath.map { URL(fileURLWithPath: $0) } }
    public var videoURL: URL? { videoPath.map { URL(fileURLWithPath: $0) } }

    public var launchOverride: LaunchTargetReference? {
        get { launchOverrideData.flatMap { try? JSONDecoder().decode(LaunchTargetReference.self, from: $0) } }
        set { launchOverrideData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
