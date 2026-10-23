import Foundation

/// All scraper credentials combined into one Codable blob, stored as a
/// single Keychain item rather than one item per field. Each *distinct*
/// Keychain item can trigger its own macOS access-authorization prompt on
/// a freshly (ad-hoc) signed build — with 5 separate fields across two
/// credential stores, that meant up to 5-6 password prompts on a single
/// launch. One shared item means at most one prompt.
struct ScraperCredentialsVault: Codable, Equatable {
    var screenScraperDevID: String = ""
    var screenScraperDevPassword: String = ""
    var screenScraperUserID: String = ""
    var screenScraperUserPassword: String = ""
    var theGamesDBApiKey: String = ""
    var steamGridDBApiKey: String = ""

    var isEmpty: Bool { self == ScraperCredentialsVault() }

    init() {}

    // Each key may be missing: a vault saved before a field existed must
    // still load, or `load()` would treat it as unreadable and save over
    // every key in it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> String { (try? container.decodeIfPresent(String.self, forKey: key)) ?? "" }
        screenScraperDevID = value(.screenScraperDevID)
        screenScraperDevPassword = value(.screenScraperDevPassword)
        screenScraperUserID = value(.screenScraperUserID)
        screenScraperUserPassword = value(.screenScraperUserPassword)
        theGamesDBApiKey = value(.theGamesDBApiKey)
        steamGridDBApiKey = value(.steamGridDBApiKey)
    }
}

/// Reads/writes `ScraperCredentialsVault` as one JSON-encoded Keychain
/// item. `ScreenScraperCredentialsStore` and `TheGamesDBCredentialsStore`
/// each own a disjoint subset of its fields; every write re-reads the
/// current blob first so one store's save can't clobber the other's.
final class ScraperCredentialsVaultStore {
    private static let account = "scraperCredentialsVault"

    /// The original per-field accounts, from before credentials were
    /// consolidated into one item — read once to migrate forward so
    /// switching to the vault doesn't silently drop already-saved,
    /// already-working credentials (confirmed: TheGamesDB scraping was
    /// already working, meaning a real API key exists under the old
    /// per-field scheme).
    private static let legacyDevIDAccount = "devID"
    private static let legacyDevPasswordAccount = "devPassword"
    private static let legacyUserIDAccount = "userID"
    private static let legacyUserPasswordAccount = "userPassword"
    private static let legacyTheGamesDBApiKeyAccount = "theGamesDBApiKey"

    private let keychain: KeychainStoring
    private var didAttemptMigration = false

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    func load() -> ScraperCredentialsVault {
        if let raw = keychain.read(account: Self.account),
           let data = raw.data(using: .utf8),
           let vault = try? JSONDecoder().decode(ScraperCredentialsVault.self, from: data) {
            return vault
        }

        // No vault item yet — either a fresh install, or an existing one
        // upgrading from the old per-field scheme. Try migrating exactly
        // once per process; if there's nothing to migrate this just saves
        // an empty vault and behaves like a fresh install from then on.
        if !didAttemptMigration {
            didAttemptMigration = true
            let migrated = migrateFromLegacyAccounts()
            save(migrated)
            return migrated
        }
        return ScraperCredentialsVault()
    }

    func save(_ vault: ScraperCredentialsVault) {
        guard let data = try? JSONEncoder().encode(vault),
              let raw = String(data: data, encoding: .utf8) else { return }
        keychain.write(account: Self.account, value: raw)
    }

    private func migrateFromLegacyAccounts() -> ScraperCredentialsVault {
        var vault = ScraperCredentialsVault()
        vault.screenScraperDevID = keychain.read(account: Self.legacyDevIDAccount) ?? ""
        vault.screenScraperDevPassword = keychain.read(account: Self.legacyDevPasswordAccount) ?? ""
        vault.screenScraperUserID = keychain.read(account: Self.legacyUserIDAccount) ?? ""
        vault.screenScraperUserPassword = keychain.read(account: Self.legacyUserPasswordAccount) ?? ""
        vault.theGamesDBApiKey = keychain.read(account: Self.legacyTheGamesDBApiKeyAccount) ?? ""

        if !vault.isEmpty {
            keychain.delete(account: Self.legacyDevIDAccount)
            keychain.delete(account: Self.legacyDevPasswordAccount)
            keychain.delete(account: Self.legacyUserIDAccount)
            keychain.delete(account: Self.legacyUserPasswordAccount)
            keychain.delete(account: Self.legacyTheGamesDBApiKeyAccount)
        }
        return vault
    }
}
