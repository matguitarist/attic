import Foundation
import Observation
import RomsBoxScraping

/// ScreenScraper devID/devPassword (registered client software, required
/// by the API) and an optional personal ssid/sspassword — all stored in
/// the Keychain, never UserDefaults, since these are real account secrets.
@Observable
@MainActor
final class ScreenScraperCredentialsStore {
    private static let devIDAccount = "devID"
    private static let devPasswordAccount = "devPassword"
    private static let userIDAccount = "userID"
    private static let userPasswordAccount = "userPassword"

    private let keychain: KeychainStoring

    var devID: String { didSet { keychain.write(account: Self.devIDAccount, value: devID) } }
    var devPassword: String { didSet { keychain.write(account: Self.devPasswordAccount, value: devPassword) } }
    var userID: String { didSet { keychain.write(account: Self.userIDAccount, value: userID) } }
    var userPassword: String { didSet { keychain.write(account: Self.userPasswordAccount, value: userPassword) } }

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        self.devID = keychain.read(account: Self.devIDAccount) ?? ""
        self.devPassword = keychain.read(account: Self.devPasswordAccount) ?? ""
        self.userID = keychain.read(account: Self.userIDAccount) ?? ""
        self.userPassword = keychain.read(account: Self.userPasswordAccount) ?? ""
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
