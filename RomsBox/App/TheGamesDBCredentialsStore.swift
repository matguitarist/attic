import Foundation
import Observation
import RomsBoxScraping

/// TheGamesDB's single self-serve API key, stored in the Keychain (not
/// UserDefaults) alongside `ScreenScraperCredentialsStore`'s secrets.
@Observable
@MainActor
final class TheGamesDBCredentialsStore {
    private static let apiKeyAccount = "theGamesDBApiKey"

    private let keychain: KeychainStoring

    var apiKey: String { didSet { keychain.write(account: Self.apiKeyAccount, value: apiKey) } }

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        self.apiKey = keychain.read(account: Self.apiKeyAccount) ?? ""
    }

    var credentials: TheGamesDBCredentials {
        TheGamesDBCredentials(apiKey: apiKey)
    }

    var isConfigured: Bool { credentials.isConfigured }
}
