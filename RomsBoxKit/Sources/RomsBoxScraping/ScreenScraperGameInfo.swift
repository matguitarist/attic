import Foundation

/// The subset of ScreenScraper's `jeuInfos.php` response RomsBox cares
/// about, already flattened out of ScreenScraper's region/language-array
/// shape into single best-pick values.
public struct ScreenScraperGameInfo: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var genre: String?
    public var players: String?
    public var developer: String?
    public var publisher: String?
    public var releaseDate: Date?
    /// Normalized to 0...1 (ScreenScraper's own "note" is 0...20).
    public var rating: Double?
    public var coverArtURL: URL?

    public init(
        title: String? = nil,
        description: String? = nil,
        genre: String? = nil,
        players: String? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        releaseDate: Date? = nil,
        rating: Double? = nil,
        coverArtURL: URL? = nil
    ) {
        self.title = title
        self.description = description
        self.genre = genre
        self.players = players
        self.developer = developer
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.rating = rating
        self.coverArtURL = coverArtURL
    }
}
