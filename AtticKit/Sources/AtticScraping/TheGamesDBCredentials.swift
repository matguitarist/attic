/// TheGamesDB only needs a single self-serve API key (free account, no
/// separate "register your software" review) — unlike ScreenScraper's
/// devID/devPassword-per-client-app model.
public struct TheGamesDBCredentials: Sendable, Equatable {
    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public var isConfigured: Bool { !apiKey.isEmpty }
}
