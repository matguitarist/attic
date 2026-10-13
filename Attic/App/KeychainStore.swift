import Foundation
import Security

/// Minimal Keychain read/write/delete, abstracted behind a protocol so
/// `ScreenScraperCredentialsStore` tests can substitute an in-memory fake
/// instead of touching the real login keychain.
protocol KeychainStoring {
    func read(account: String) -> String?
    func write(account: String, value: String)
    func delete(account: String)
}

/// Real macOS Keychain implementation (`kSecClassGenericPassword`) — used
/// for ScreenScraper account/API credentials instead of UserDefaults, since
/// those are real secrets rather than app preferences.
struct KeychainStore: KeychainStoring {
    private var service = "com.attic.app.screenscraper"

    init() {}

    /// A store for another kind of secret (RetroAchievements' token).
    init(service: String) {
        self.service = service
    }

    func read(account: String) -> String? {
        if let value = read(account: account, service: service) { return value }
        // Saved by the app under its old name (RomsBox): macOS asks once
        // whether Attic may read it, then it moves to Attic's own item.
        // Only ever tried once per item, so a "Deny" isn't asked again.
        let triedKey = "triedRomsBoxKeychain.\(account)"
        guard !UserDefaults.standard.bool(forKey: triedKey) else { return nil }
        UserDefaults.standard.set(true, forKey: triedKey)
        guard let legacy = read(account: account, service: LegacyRomsBoxMigration.legacyKeychainService) else { return nil }
        write(account: account, value: legacy)
        SecItemDelete(baseQuery(account: account, service: LegacyRomsBoxMigration.legacyKeychainService) as CFDictionary)
        return legacy
    }

    private func read(account: String, service: String) -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(account: String, value: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        baseQuery(account: account, service: service)
    }

    private func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
