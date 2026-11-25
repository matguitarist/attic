import Foundation
import FileKit

/// Minimal Keychain read/write/delete, abstracted behind a protocol so
/// `ScreenScraperCredentialsStore` tests can substitute a store in memory
/// (`KeychainStore(keychain: .inMemory(service:))`) instead of touching
/// the real login keychain.
protocol KeychainStoring {
    func read(account: String) -> String?
    func write(account: String, value: String)
    func delete(account: String)
}

/// The macOS Keychain through FileKit (generic passwords, one service per
/// kind of secret) — used for ScreenScraper account/API credentials
/// instead of UserDefaults, since those are real secrets rather than app
/// preferences.
struct KeychainStore: KeychainStoring {
    private let keychain: Keychain

    init() {
        self.init(service: "com.attic.app.screenscraper")
    }

    /// A store for another kind of secret (RetroAchievements' token).
    init(service: String) {
        self.init(keychain: Keychain(service: service))
    }

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    func read(account: String) -> String? {
        if let value = keychain.string(for: account) { return value }
        // Saved by the app under its old name (RomsBox): macOS asks once
        // whether Attic may read it, then it moves to Attic's own item.
        // Only ever tried once per item, so a "Deny" isn't asked again.
        let triedKey = "triedRomsBoxKeychain.\(account)"
        guard !UserDefaults.standard.bool(forKey: triedKey) else { return nil }
        UserDefaults.standard.set(true, forKey: triedKey)
        guard (try? keychain.adopt(account, from: Keychain(service: LegacyRomsBoxMigration.legacyKeychainService))) == true else { return nil }
        return keychain.string(for: account)
    }

    func write(account: String, value: String) {
        try? keychain.set(value, for: account)
    }

    func delete(account: String) {
        try? keychain.remove(account)
    }
}
