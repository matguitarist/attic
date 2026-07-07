import Foundation

/// One game as parsed by a library importer, with all format-specific
/// quirks (Batocera's inline media tags vs. ES-DE's filename matching,
/// differing `releasedate` formats, etc.) already resolved. Nothing above
/// the importer layer needs to know which convention a game came from.
public struct ImportedGameRecord: Sendable, Hashable {
    /// Path to the ROM file, relative to the system's ROMs folder. Stable
    /// natural key used for upsert during a rescan.
    public let romRelativePath: String
    public let title: String
    public let sortTitle: String?
    public let description: String?
    public let releaseDate: Date?
    public let developer: String?
    public let publisher: String?
    public let genre: String?
    public let players: String?
    public let rating: Double?
    public let favorite: Bool
    public let coverArtURL: URL?
    public let titleScreenURL: URL?
    public let videoURL: URL?

    public init(
        romRelativePath: String,
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
        self.romRelativePath = romRelativePath
        self.title = title
        self.sortTitle = sortTitle
        self.description = description
        self.releaseDate = releaseDate
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.players = players
        self.rating = rating
        self.favorite = favorite
        self.coverArtURL = coverArtURL
        self.titleScreenURL = titleScreenURL
        self.videoURL = videoURL
    }
}

/// The full output of importing one system folder: which system it was,
/// which convention it was recognized as, and its games.
public struct ImportedSystemData: Sendable, Hashable {
    public let canonicalID: CanonicalSystemID
    public let libraryFormat: LibraryFormat
    public let romsRootURL: URL
    public let games: [ImportedGameRecord]

    public init(
        canonicalID: CanonicalSystemID,
        libraryFormat: LibraryFormat,
        romsRootURL: URL,
        games: [ImportedGameRecord]
    ) {
        self.canonicalID = canonicalID
        self.libraryFormat = libraryFormat
        self.romsRootURL = romsRootURL
        self.games = games
    }
}
