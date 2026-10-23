import SwiftUI

/// Settings › SteamGridDB: the API key for Steam games' missing artwork.
struct SteamGridDBSettingsView: View {
    @State private var store = SteamGridDBCredentialsStore()

    var body: some View {
        Form {
            Section("API Key") {
                Text("Steam games get their artwork from the Steam store. When it has no portrait cover, hero picture or logo for a game, Attic looks on SteamGridDB, which needs a free API key: sign in with Steam on steamgriddb.com, then generate one under Preferences › API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("Get an API key on steamgriddb.com", destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
                SecureField("API Key", text: $store.apiKey, prompt: Text("Optional"))
            }

            Section {
                HStack {
                    Image(systemName: store.trimmedKey != nil ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(store.trimmedKey != nil ? .green : .secondary)
                    Text(store.trimmedKey != nil
                         ? String(localized: "Used for Steam games' missing artwork. Run Tools › Import Steam Games… again to fill it in.")
                         : String(localized: "Without a key, Steam games only get the Steam store's artwork."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
