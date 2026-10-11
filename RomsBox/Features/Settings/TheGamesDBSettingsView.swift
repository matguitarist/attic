import SwiftUI

struct TheGamesDBSettingsView: View {
    @Environment(TheGamesDBCredentialsStore.self) private var credentialsStore

    var body: some View {
        @Bindable var credentialsStore = credentialsStore

        Form {
            Section("API Key") {
                Text("TheGamesDB only needs a self-serve API key — create a free account and generate one from your account page, no separate software-registration review needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("Get an API key on thegamesdb.net", destination: URL(string: "https://thegamesdb.net/")!)
                SecureField("API Key", text: $credentialsStore.apiKey, prompt: Text("Required"))
            }

            Section {
                HStack {
                    Image(systemName: credentialsStore.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(credentialsStore.isConfigured ? .green : .orange)
                    Text(credentialsStore.isConfigured ? String(localized: "Ready to scrape.") : String(localized: "Add an API key to enable scraping."))
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                Text("TheGamesDB matches by searching the ROM's title text rather than an exact filename/CRC match like ScreenScraper, so results can be a bit fuzzier — useful as a fallback while you wait on a ScreenScraper devID, or anytime ScreenScraper has no match.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
