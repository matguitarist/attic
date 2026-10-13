import SwiftUI

/// Settings › Emulators › RetroAchievements: signing in once, for every
/// game Attic launches in RetroArch, DuckStation or PCSX2.
struct RetroAchievementsSection: View {
    @State private var store = RetroAchievementsStore()
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Section {
            if let user = store.username {
                LabeledContent("Signed in as") {
                    HStack {
                        Text(user)
                        Button("Sign Out") { store.signOut() }
                    }
                }
                Toggle(isOn: $store.hardcore) {
                    Text("Hardcore mode")
                    Text("No save states, rewind, cheats or slow motion, for full points and the leaderboards.")
                }
            } else {
                TextField("User Name", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                HStack {
                    if let error = store.error {
                        Text(error).foregroundStyle(.orange).font(.callout)
                    }
                    Spacer()
                    Link("Create an Account", destination: URL(string: "https://retroachievements.org/createaccount.php")!)
                    if store.isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Sign In") {
                            Task {
                                await store.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
                                if store.username != nil { password = "" }
                            }
                        }
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    }
                }
            }
        } header: {
            Text("RetroAchievements")
        } footer: {
            Text("Earn achievements in classic games, in RetroArch, DuckStation and PCSX2. Your password is only sent to retroachievements.org to sign in; Attic keeps the sign-in token it gets back, in the Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
