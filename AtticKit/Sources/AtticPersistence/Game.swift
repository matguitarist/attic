import Foundation
import SwiftData
import AtticModels

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

    /// Set the moment the user edits title/description/developer/publisher/
    /// genre/players/release date/rating in the detail panel — once true, `applyRescannedMetadata`
    /// stops overwriting those fields from gamelist.xml on future rescans,
    /// same as `favorite` already does. Without this, a corrected title (or
    /// any other hand-edited field) would silently revert the next time the
    /// library gets rescanned.
    public var metadataManuallyEdited: Bool = false

    /// The cover is one the user picked themselves (Edit Info), so rescans
    /// keep it instead of switching back to the gamelist's matched media.
    public var coverArtManuallySet: Bool = false

    /// Set once the play history and favorite another front-end recorded
    /// in its gamelist have been taken in, so they're merged only once.
    public var importedFrontEndHistory: Bool = false

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

    /// The user's collections this game is in (inverse of
    /// `GameCollection.games`).
    public var collections: [GameCollection] = []

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
        takeFrontEndHistory(from: record)
    }

    /// Merges the favorite and play history another front-end recorded
    /// (counts and playtime kept at whichever is higher, the latest play
    /// date), the first time the game is seen with them.
    func takeFrontEndHistory(from record: ImportedGameRecord) {
        guard !importedFrontEndHistory else { return }
        importedFrontEndHistory = true
        if record.favorite { favorite = true }
        guard let history = record.history else { return }
        playCount = max(playCount, history.playCount)
        totalPlaytimeSeconds = max(totalPlaytimeSeconds, history.playtimeSeconds)
        if let played = history.lastPlayed, played > (lastPlayedDate ?? .distantPast) {
            lastPlayedDate = played
        }
    }

    /// Refreshes metadata from a rescanned record. Deliberately leaves
    /// `favorite`, play tracking, and `launchOverride` untouched — those are
    /// app/user state, not source-of-truth metadata. Also skips the
    /// user-editable fields (text, release date, rating) once
    /// `metadataManuallyEdited` is set, and a user-picked cover, so a
    /// hand-corrected title/description/etc. survives future rescans
    /// instead of getting silently overwritten back to whatever
    /// gamelist.xml still says.
    public func applyRescannedMetadata(_ record: ImportedGameRecord, romsRootURL: URL) {
        romAbsolutePath = romsRootURL.appending(path: record.romRelativePath).path
        takeFrontEndHistory(from: record)
        if !metadataManuallyEdited {
            title = record.title
            sortTitle = record.sortTitle ?? record.title
            gameDescription = record.description
            developer = record.developer
            publisher = record.publisher
            genre = record.genre
            players = record.players
            releaseDate = record.releaseDate
            rating = record.rating
        }
        if !coverArtManuallySet {
            coverArtPath = record.coverArtURL?.path ?? Self.stillExisting(coverArtPath)
        }
        // A scraped image the gamelist has no equivalent for (it's kept
        // app-side, not in the ROM tree) stays as long as its file does.
        titleScreenPath = record.titleScreenURL?.path ?? Self.stillExisting(titleScreenPath)
        videoPath = record.videoURL?.path
    }
}

extension Game {
    static func stillExisting(_ path: String?) -> String? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    public var romAbsoluteURL: URL { URL(fileURLWithPath: romAbsolutePath) }

    /// Names the game across rescans (which recreate removed-then-found
    /// games): its system and its path in the system's folder.
    public var collectionKey: String { "\(systemCanonicalID)/\(romRelativePath)" }
    public var coverArtURL: URL? { coverArtPath.map { URL(fileURLWithPath: $0) } }
    public var titleScreenURL: URL? { titleScreenPath.map { URL(fileURLWithPath: $0) } }
    public var videoURL: URL? { videoPath.map { URL(fileURLWithPath: $0) } }

    public var launchOverride: LaunchTargetReference? {
        get { launchOverrideData.flatMap { try? JSONDecoder().decode(LaunchTargetReference.self, from: $0) } }
        set { launchOverrideData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
