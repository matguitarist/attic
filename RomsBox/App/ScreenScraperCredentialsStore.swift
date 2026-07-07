import Foundation
import Observation
import RomsBoxScraping

/// ScreenScraper devID/devPassword (registered client software, required
/// by the API) and an optional personal ssid/sspassword — all stored in
/// the Keychain, never UserDefaults, since these are real account secrets.
/// Persisted via the shared `ScraperCredentialsVault` (one Keychain item
/// for all scraper credentials) rather than one item per field.
@Observable
@MainActor
final class ScreenScraperCredentialsStore {
    private let vaultStore: ScraperCredentialsVaultStore

    var devID: String { didSet { persist() } }
    var devPassword: String { didSet { persist() } }
    var userID: String { didSet { persist() } }
    var userPassword: String { didSet { persist() } }

    init(vaultStore: ScraperCredentialsVaultStore = ScraperCredentialsVaultStore()) {
        self.vaultStore = vaultStore
        let vault = vaultStore.load()
        self.devID = vault.screenScraperDevID
        self.devPassword = vault.screenScraperDevPassword
        self.userID = vault.screenScraperUserID
        self.userPassword = vault.screenScraperUserPassword
    }

    private func persist() {
        var vault = vaultStore.load()
        vault.screenScraperDevID = devID
        vault.screenScraperDevPassword = devPassword
        vault.screenScraperUserID = userID
        vault.screenScraperUserPassword = userPassword
        vaultStore.save(vault)
    }

    var credentials: ScreenScraperCredentials {
        ScreenScraperCredentials(
            devID: devID,
            devPassword: devPassword,
            userID: userID.isEmpty ? nil : userID,
            userPassword: userPassword.isEmpty ? nil : userPassword
        )
    }

    var isConfigured: Bool { credentials.isConfigured }
}
