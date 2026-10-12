public enum ScreenScraperError: Error, Sendable, Equatable {
    /// The response body didn't decode as expected — often because
    /// ScreenScraper returns a plain-text error string instead of JSON for
    /// account/credential/quota failures rather than an HTTP error status.
    case malformedResponse(String)
    /// ScreenScraper had no match for this rom/system combination.
    case noMatch
    /// devID/devPassword rejected, or the account is over its daily/thread
    /// quota — ScreenScraper conflates these into similar text responses.
    case credentialsRejectedOrQuotaExceeded(String)
    case network(String)
    case notConfigured
}
