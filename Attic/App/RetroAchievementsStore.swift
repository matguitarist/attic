import Foundation
import Observation
import AtticModels

/// The RetroAchievements account emulators are given (see
/// `AchievementsAccount`). Signing in sends the password to
/// retroachievements.org once, for a token; only the token is kept, in the
/// Keychain, and the user name and hardcore choice in the settings.
@Observable
@MainActor
final class RetroAchievementsStore {
    nonisolated private static let usernameKey = "retroAchievementsUser"
    nonisolated static let hardcoreKey = "retroAchievementsHardcore"
    nonisolated private static let keychain = KeychainStore(service: "com.attic.app.retroachievements")

    private(set) var username: String? = UserDefaults.standard.string(forKey: usernameKey)
    var hardcore: Bool = UserDefaults.standard.bool(forKey: hardcoreKey) {
        didSet { UserDefaults.standard.set(hardcore, forKey: Self.hardcoreKey) }
    }
    private(set) var isSigningIn = false
    private(set) var error: String?

    /// What launches use: nil until signed in.
    nonisolated static var currentAccount: AchievementsAccount? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              let token = keychain.read(account: username) else { return nil }
        return AchievementsAccount(username: username, token: token, hardcore: UserDefaults.standard.bool(forKey: hardcoreKey))
    }

    func signIn(username: String, password: String) async {
        isSigningIn = true
        error = nil
        defer { isSigningIn = false }
        do {
            let (user, token) = try await Self.login(username: username, password: password)
            Self.keychain.write(account: user, value: token)
            UserDefaults.standard.set(user, forKey: Self.usernameKey)
            self.username = user
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        if let username { Self.keychain.delete(account: username) }
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
        username = nil
    }

    // MARK: - retroachievements.org

    private struct LoginError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The same sign-in RetroArch and the emulators use (`login2`).
    private static func login(username: String, password: String) async throws -> (user: String, token: String) {
        var request = URLRequest(url: URL(string: "https://retroachievements.org/dorequest.php")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        request.setValue("Attic/\(version)", forHTTPHeaderField: "User-Agent")
        var form = URLComponents()
        form.queryItems = [.init(name: "r", value: "login2"), .init(name: "u", value: username), .init(name: "p", value: password)]
        // URLComponents leaves "+" alone, which a form body reads as a space.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        struct Response: Decodable {
            let Success: Bool
            let User: String?
            let Token: String?
            let Error: String?
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.Success, let user = response.User, let token = response.Token else {
            throw LoginError(message: response.Error ?? String(localized: "RetroAchievements didn't accept that sign-in."))
        }
        return (user, token)
    }
}
