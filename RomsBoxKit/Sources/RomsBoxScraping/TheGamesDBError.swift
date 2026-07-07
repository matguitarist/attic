public enum TheGamesDBError: Error, Sendable, Equatable {
    case malformedResponse(String)
    case noMatch
    /// Invalid/expired API key, or the free-tier monthly allowance is
    /// exhausted — TheGamesDB reports both as an HTTP 401/403 without
    /// clearly distinguishing which.
    case credentialsRejectedOrQuotaExceeded(String)
    case network(String)
    case notConfigured
}
