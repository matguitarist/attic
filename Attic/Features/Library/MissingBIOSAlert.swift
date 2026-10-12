import SwiftUI
import AppKit

/// The alert for a game held back by `LaunchCoordinator` because its
/// emulator's BIOS is missing.
struct MissingBIOSAlert: ViewModifier {
    /// Only one window shows it: Cabinet Mode while it's up, else the
    /// library.
    let isActive: Bool

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore

    func body(content: Content) -> some View {
        @Bindable var launchCoordinator = launchCoordinator
        content.alert(
            "\(launchCoordinator.missingBIOS?.systemName ?? "") Needs a BIOS",
            isPresented: Binding(
                get: { isActive && launchCoordinator.missingBIOS != nil },
                set: { if !$0 { launchCoordinator.missingBIOS = nil } }
            ),
            presenting: launchCoordinator.missingBIOS
        ) { missing in
            Button("Show BIOS Folder") {
                try? FileManager.default.createDirectory(at: missing.folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(missing.folder)
            }
            Button("Play Anyway") {
                launchCoordinator.play(game: missing.game, retroArchStore: retroArchStore, checkingBIOS: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { missing in
            let put = String(localized: "Put \(missing.fileNames.joined(separator: ", ")) in the BIOS folder first; without it the emulator can't start. Dump BIOS files from hardware you own; Attic never downloads them.")
            Text([put, missing.supportedDumps.map { $0 + "." }].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }
}

extension View {
    func missingBIOSAlert(isActive: Bool) -> some View {
        modifier(MissingBIOSAlert(isActive: isActive))
    }
}
