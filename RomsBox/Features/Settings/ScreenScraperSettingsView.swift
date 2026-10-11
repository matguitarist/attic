import SwiftUI

struct ScreenScraperSettingsView: View {
    @Environment(ScreenScraperCredentialsStore.self) private var credentialsStore

    var body: some View {
        @Bindable var credentialsStore = credentialsStore

        Form {
            Section("Developer Credentials") {
                Text("ScreenScraper's API requires a devID/devPassword issued to registered client software — separate from your personal account. Request one on their developer forum, then paste it in below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("Request API access on screenscraper.fr", destination: URL(string: "https://www.screenscraper.fr/forumsujets.php?frub=12")!)
                TextField("Dev ID", text: $credentialsStore.devID, prompt: Text("Required"))
                SecureField("Dev Password", text: $credentialsStore.devPassword, prompt: Text("Required"))
            }

            Section("Your Account (optional)") {
                Text("Adding your own ScreenScraper member login raises your scrape quota and concurrent-thread limit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Username", text: $credentialsStore.userID, prompt: Text("Optional"))
                SecureField("Password", text: $credentialsStore.userPassword, prompt: Text("Optional"))
            }

            Section {
                HStack {
                    Image(systemName: credentialsStore.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(credentialsStore.isConfigured ? .green : .orange)
                    Text(credentialsStore.isConfigured ? String(localized: "Ready to scrape.") : String(localized: "Add a devID/devPassword to enable scraping."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
