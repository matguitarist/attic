import AppKit
import LogKitUI
import SwiftUI

extension LogViewerModel {
    /// Window › Log's state, kept for the whole session so filters and Clear
    /// survive closing the window.
    @MainActor static let attic: LogViewerModel = {
        let model = LogViewerModel(store: AppLog.store)
        // Debug lines start hidden, as they always have.
        model.filter.levels = [.info, .warning, .error, .critical]
        model.defaultFilter = model.filter
        return model
    }()
}

/// Window › Log: what Attic did and what emulators printed, with colored
/// levels, filters and search (LogKit's viewer). Follows new messages while a
/// game runs.
struct LogView: View {
    static let windowID = "log"

    var body: some View {
        LogViewer(model: .attic, options: options)
            .navigationTitle("Log")
            .navigationSubtitle(AppLog.fileURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    private var options: LogViewerOptions {
        LogViewerOptions(
            emptyTitle: String(localized: "Nothing Logged Yet"),
            emptyMessage: String(localized: "Play a game: what Attic does and what the emulator says while it starts and runs appear here."),
            // The viewer's copy is in memory; the file is Attic.log, in Attic's own format.
            shareActions: [
                .init(String(localized: "Copy Log File")) { _ in
                    if let text = try? String(contentsOf: AppLog.fileURL, encoding: .utf8) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                },
                .init(String(localized: "Show Log File in Finder")) { _ in
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
                },
            ],
            sourceColor: Self.color(forSource:))
    }

    /// Attic's own lines in the accent color, RetroArch's in teal, other emulators' in indigo.
    static func color(forSource source: String) -> Color {
        switch source {
        case "Attic": .accentColor
        case "RetroArch": .teal
        default: .indigo
        }
    }
}
