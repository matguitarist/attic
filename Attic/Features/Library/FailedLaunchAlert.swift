import SwiftUI
import AppKit
import AtticEmulation

/// The alert for a game the emulator couldn't run, from what it printed:
/// MAME's missing chips, a bad dump, or content that failed to load.
struct FailedLaunchAlert: ViewModifier {
    /// Only one window shows it: Cabinet Mode while it's up, else the
    /// library.
    let isActive: Bool

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.alert(
            "“\(launchCoordinator.failedLaunch?.game.title ?? "")” Can't Start",
            isPresented: Binding(
                get: { isActive && launchCoordinator.failedLaunch != nil },
                set: { if !$0 { launchCoordinator.failedLaunch = nil } }
            ),
            presenting: launchCoordinator.failedLaunch
        ) { failed in
            Button("Show Log") { openWindow(id: LogView.windowID) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([failed.game.romAbsoluteURL]) }
            Button("OK", role: .cancel) {}
        } message: { failed in
            Text(Self.message(for: failed.problem))
        }
    }

    static func message(for problem: LaunchProblem) -> String {
        let emulator = problem.emulator ?? String(localized: "The emulator")
        var paragraphs: [String] = []
        if !problem.missingFiles.isEmpty {
            paragraphs.append(String(localized: "\(emulator) needs files that aren't in this game's set: \(list(problem.missingFiles))."))
        }
        if !problem.wrongFiles.isEmpty {
            paragraphs.append(String(localized: "Some of its files are a bad dump or from another version: \(list(problem.wrongFiles))."))
        }
        if paragraphs.isEmpty {
            paragraphs.append(String(localized: "\(emulator) said: \(problem.fatalMessage ?? "")"))
        } else {
            // Arcade sets change from one MAME version to the next.
            paragraphs.append(String(localized: "Arcade sets have to match the emulator's version. Verify the game to see what differs, or replace the set with one made for \(emulator)."))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// The first few names, then how many more.
    private static func list(_ files: [String]) -> String {
        let shown = files.prefix(5).joined(separator: ", ")
        return files.count > 5 ? String(localized: "\(shown) and \(files.count - 5) more") : shown
    }
}

extension View {
    func failedLaunchAlert(isActive: Bool) -> some View {
        modifier(FailedLaunchAlert(isActive: isActive))
    }
}
