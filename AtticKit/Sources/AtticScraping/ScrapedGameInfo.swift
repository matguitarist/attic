import Foundation

/// A scraper-agnostic result shape — both `ScreenScraperClient` and
/// `TheGamesDBClient` flatten their own very different response formats
/// down to this same struct, so the app layer merges scraped data into a
/// `Game` the same way regardless of which source it came from.
public struct ScrapedGameInfo: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var genre: String?
    public var players: String?
    public var developer: String?
    public var publisher: String?
    public var releaseDate: Date?
    /// Normalized to 0...1 regardless of source (ScreenScraper's own
    /// "note" is 0...20; TheGamesDB doesn't provide a numeric rating at
    /// all, so its mapper always leaves this nil).
    public var rating: Double?
    public var coverArtURL: URL?
    /// An in-game screenshot (or the title screen, if that's all there is).
    public var screenshotURL: URL?
    /// A short gameplay video (ScreenScraper's).
    public var videoURL: URL?
    /// The game's logo on a transparent background (ScreenScraper's wheel,
    /// TheGamesDB's clear logo).
    public var logoURL: URL?

    public init(
        title: String? = nil,
        description: String? = nil,
        genre: String? = nil,
        players: String? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        releaseDate: Date? = nil,
        rating: Double? = nil,
        coverArtURL: URL? = nil,
        screenshotURL: URL? = nil,
        videoURL: URL? = nil,
        logoURL: URL? = nil
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
        self.screenshotURL = screenshotURL
        self.videoURL = videoURL
        self.logoURL = logoURL
    }
}
