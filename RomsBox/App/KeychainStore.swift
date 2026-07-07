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
    private let service = "com.romsbox.app.screenscraper"

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
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
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
