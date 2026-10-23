import Foundation
import Observation

/// SteamGridDB's API key, for Steam games' artwork the Steam store
/// doesn't have. Kept in the shared `ScraperCredentialsVault`.
@Observable
@MainActor
final class SteamGridDBCredentialsStore {
    private let vaultStore: ScraperCredentialsVaultStore

    var apiKey: String { didSet { persist() } }

    init(vaultStore: ScraperCredentialsVaultStore = ScraperCredentialsVaultStore()) {
        self.vaultStore = vaultStore
        self.apiKey = vaultStore.load().steamGridDBApiKey
    }

    private func persist() {
        var vault = vaultStore.load()
        vault.steamGridDBApiKey = apiKey
        vaultStore.save(vault)
    }

    var trimmedKey: String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
