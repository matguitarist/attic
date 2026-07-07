import Foundation
import Observation
import RomsBoxScraping

/// TheGamesDB's single self-serve API key, stored in the Keychain via the
/// shared `ScraperCredentialsVault` alongside `ScreenScraperCredentialsStore`'s
/// secrets (one Keychain item for all scraper credentials, not one per field).
@Observable
@MainActor
final class TheGamesDBCredentialsStore {
    private let vaultStore: ScraperCredentialsVaultStore

    var apiKey: String { didSet { persist() } }

    init(vaultStore: ScraperCredentialsVaultStore = ScraperCredentialsVaultStore()) {
        self.vaultStore = vaultStore
        self.apiKey = vaultStore.load().theGamesDBApiKey
    }

    private func persist() {
        var vault = vaultStore.load()
        vault.theGamesDBApiKey = apiKey
        vaultStore.save(vault)
    }

    var credentials: TheGamesDBCredentials {
        TheGamesDBCredentials(apiKey: apiKey)
    }

    var isConfigured: Bool { credentials.isConfigured }
}
