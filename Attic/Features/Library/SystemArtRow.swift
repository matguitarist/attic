import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AtticLibraryScanning
import AtticPersistence

/// One of a system's own pictures (`MediaFolder.SystemArt`): a thumbnail,
/// Choose… and Remove, and a drop target.
struct SystemArtRow: View {
    let system: GameSystem
    let art: MediaFolder.SystemArt
    let title: LocalizedStringKey
    let help: LocalizedStringKey

    /// Bumped when the picture changes.
    @State private var check = 0

    var body: some View {
        let _ = check
        let own = system.ownArt(art)
        LabeledContent {
            HStack {
                if let own {
                    Group {
                        if let image = SystemLogoCache.image(at: own) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 40)
                        } else {
                            Text(verbatim: own.lastPathComponent)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([own]) }
                    }
                    Button("Remove") { update(nil) }
                }
                Button("Choose…") { Self.choose(videos: art == .video) { update($0) } }
            }
        } label: {
            Text(title)
            Text(help)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let picture = urls.first(where: art == .video ? Self.isVideo : Self.isPicture) else { return false }
            update(picture)
            return true
        }
    }

    private func update(_ picture: URL?) {
        Self.set(art, to: picture, for: system)
        check += 1
    }

    static func isPicture(_ url: URL) -> Bool {
        MediaFolder.imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isVideo(_ url: URL) -> Bool {
        MediaFolder.videoExtensions.contains(url.pathExtension.lowercased())
    }

    static func choose(videos: Bool = false, message: String? = nil, then pick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = videos ? [.movie] : [.png, .heic, .webP, .jpeg]
        panel.prompt = String(localized: "Choose")
        if let message { panel.message = message }
        panel.begin { response in
            if response == .OK, let url = panel.url { pick(url) }
        }
    }

    /// Into the system's media folder; nil removes it.
    static func set(_ art: MediaFolder.SystemArt, to picture: URL?, for system: GameSystem) {
        do {
            try MediaFolder.setSystemArt(art, to: picture, forSystemFolder: system.romsRootURL)
        } catch {
            AppLog.post(.error, "Couldn't set \(system.displayName)'s \(art.rawValue): \(error.localizedDescription)")
        }
    }
}
