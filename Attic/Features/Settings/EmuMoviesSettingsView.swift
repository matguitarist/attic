import SwiftUI
import AtticEmulation

/// Settings › EmuMovies: the forum login for its file server, where
/// Tools › Get Media from EmuMovies… downloads from.
struct EmuMoviesSettingsView: View {
    @State private var store = EmuMoviesCredentialsStore()
    @State private var check: Check?

    private enum Check: Equatable {
        case checking, ok, refused, failed(String)
    }

    var body: some View {
        Form {
            Section("Login") {
                Text("EmuMovies has box art, logos, fan art, screenshots, manuals and system videos for most systems. Its file server takes your EmuMovies forum login; a free account gets the artwork.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("Create an account on emumovies.com", destination: URL(string: "https://emumovies.com/register/")!)
                TextField("Username", text: $store.username, prompt: Text("Required"))
                    .textContentType(.username)
                SecureField("Password", text: $store.password, prompt: Text("Required"))
                    .textContentType(.password)
                Picker("Server", selection: $store.host) {
                    Text("USA").tag(EmuMoviesServer.Host.usa)
                    Text("Europe").tag(EmuMoviesServer.Host.europe)
                }
            }

            Section {
                HStack {
                    status
                    Spacer()
                    Button("Check Login") {
                        guard let server = store.server else { return }
                        check = .checking
                        Task {
                            do {
                                try await server.checkLogin()
                                check = .ok
                            } catch EmuMoviesServer.Failure.login {
                                check = .refused
                            } catch {
                                check = .failed((error as? EmuMoviesServer.Failure).map(Self.message) ?? error.localizedDescription)
                            }
                        }
                    }
                    .disabled(store.server == nil || check == .checking)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.username) { check = nil }
        .onChange(of: store.password) { check = nil }
        .onChange(of: store.host) { check = nil }
    }

    @ViewBuilder
    private var status: some View {
        switch check {
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Connecting…").foregroundStyle(.secondary) }
        case .ok:
            Label("Connected. Use Tools › Get Media from EmuMovies…", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .refused:
            Label("EmuMovies refused this username or password.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case nil:
            Label(store.server == nil ? String(localized: "Add your login to get media from EmuMovies.") : String(localized: "Ready."),
                  systemImage: store.server == nil ? "info.circle" : "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    static func message(_ failure: EmuMoviesServer.Failure) -> String {
        switch failure {
        case .login: String(localized: "EmuMovies refused this username or password.")
        case .cancelled: String(localized: "Stopped.")
        case .transfer(let message):
            message.isEmpty ? String(localized: "Couldn't reach EmuMovies' server.") : String(localized: "Couldn't reach EmuMovies' server: \(message)")
        }
    }
}
