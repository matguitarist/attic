import Foundation
import Observation
import AtticEmulation

/// The EmuMovies forum login, for its file server. Kept in the shared
/// `ScraperCredentialsVault`; the server picked is a plain setting.
@Observable
@MainActor
final class EmuMoviesCredentialsStore {
    private let vaultStore: ScraperCredentialsVaultStore
    static let hostKey = "emuMoviesHost"

    var username: String { didSet { persist() } }
    var password: String { didSet { persist() } }
    var host: EmuMoviesServer.Host {
        didSet { UserDefaults.standard.set(host.rawValue, forKey: Self.hostKey) }
    }

    init(vaultStore: ScraperCredentialsVaultStore = ScraperCredentialsVaultStore()) {
        self.vaultStore = vaultStore
        let vault = vaultStore.load()
        self.username = vault.emuMoviesUsername
        self.password = vault.emuMoviesPassword
        self.host = UserDefaults.standard.string(forKey: Self.hostKey).flatMap(EmuMoviesServer.Host.init) ?? .usa
    }

    private func persist() {
        var vault = vaultStore.load()
        vault.emuMoviesUsername = username
        vault.emuMoviesPassword = password
        vaultStore.save(vault)
    }

    /// The server with this login, when there's one.
    var server: EmuMoviesServer? {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { return nil }
        return EmuMoviesServer(host: host, username: username, password: password)
    }
}
