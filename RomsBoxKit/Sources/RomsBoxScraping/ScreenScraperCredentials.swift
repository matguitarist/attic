/// Plain, in-memory-only credential bundle — never persisted by this
/// module. The app layer is responsible for storage (Keychain, not
/// UserDefaults, since these are real account/API secrets).
///
/// `devID`/`devPassword` identify RomsBox itself as registered client
/// software with ScreenScraper (required by their API for every request,
/// separate from any end user's own account) and must be requested via
/// ScreenScraper's developer forum. `userID`/`userPassword` are a member's
/// own personal account, which raises scrape/thread quotas but is optional.
public struct ScreenScraperCredentials: Sendable, Equatable {
    public var devID: String
    public var devPassword: String
    public var softwareName: String
    public var userID: String?
    public var userPassword: String?

    public init(
        devID: String,
        devPassword: String,
        softwareName: String = "RomsBox",
        userID: String? = nil,
        userPassword: String? = nil
    ) {
        self.devID = devID
        self.devPassword = devPassword
        self.softwareName = softwareName
        self.userID = userID
        self.userPassword = userPassword
    }

    /// True once the hard-required devID/devPassword are both non-empty —
    /// the minimum needed to call the API at all, independent of whether a
    /// personal member account is also configured.
    public var isConfigured: Bool {
        !devID.isEmpty && !devPassword.isEmpty
    }
}
