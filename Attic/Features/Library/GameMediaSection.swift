import SwiftUI
import UniformTypeIdentifiers
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// Every kind of media the game's system can have, as a tile each: the
/// picture when it's there, a dashed one when it's missing. Click to open
/// it (or choose one when missing); drop a file on a tile to replace it.
struct GameMediaSection: View {
    let game: Game

    /// Bumped when a tile's file changes, so the thumbnails redraw.
    @State private var revision = 0
    @State private var failure: String?

    private var kinds: [MediaKind] {
        MediaFolder.kinds(for: CanonicalSystemID(game.systemCanonicalID))
    }

    var body: some View {
        let files = kinds.map { ($0, url(of: $0)) }
        let missing = files.filter { $0.1 == nil }.count
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                ForEach(files, id: \.0) { kind, url in
                    tile(kind, url: url)
                }
            }
            .id(revision)
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Media")
                Spacer()
                if missing > 0 {
                    Text("\(missing) missing").foregroundStyle(.secondary)
                }
            }
        }
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {}
    }

    private func tile(_ kind: MediaKind, url: URL?) -> some View {
        let system = CanonicalSystemID(game.systemCanonicalID)
        let title = kind == .physicalMedia ? PhysicalMedium.of(system).map { $0.singularTitle.capitalized } ?? kind.singularTitle : kind.singularTitle
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(.quaternary.opacity(url == nil ? 0 : 0.5))
                if let url {
                    if kind == .videos || kind == .manuals {
                        Image(systemName: Self.symbol(kind))
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    } else {
                        GameCoverArtView(url: url, title: game.title, showBackground: false)
                            .padding(4)
                    }
                } else {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary)
                    Image(systemName: Self.symbol(kind))
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(url == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url { NSWorkspace.shared.open(url) } else { choose(kind) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let source = urls.first else { return false }
            return replace(kind, with: source)
        }
        .contextMenu {
            if let url {
                Button("Open") { NSWorkspace.shared.open(url) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Divider()
            }
            Button(url == nil ? "Choose File…" : "Replace…") { choose(kind) }
            if let url {
                Button("Move to Trash") { remove(kind, at: url) }
            }
        }
        .help(url == nil ? String(localized: "No \(title.lowercased()): click to choose one, or drop a file here") : url!.lastPathComponent)
    }

    // MARK: - Files

    /// Where the game's `kind` is: what the library points to for the box,
    /// screenshot and video, else the file in its media folder.
    private func url(of kind: MediaKind) -> URL? {
        func existing(_ url: URL?) -> URL? {
            url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        }
        switch kind {
        case .covers: return existing(game.coverArtURL) ?? inFolder(kind)
        case .screenshots: return existing(GameDetailView.headerImageURL(for: game).flatMap { $0 == game.coverArtURL ? nil : $0 }) ?? inFolder(kind)
        case .videos: return game.previewVideoURL
        case .manuals: return game.manualURL
        default: return inFolder(kind)
        }
    }

    private func inFolder(_ kind: MediaKind) -> URL? {
        MediaFolder.existingFiles(base: base(kind)).first
    }

    private func base(_ kind: MediaKind) -> URL {
        MediaFolder.baseURL(forSystemFolder: game.systemFolderURL, romRelativePath: game.romRelativePath, kind: kind)
    }

    private func allowedTypes(_ kind: MediaKind) -> [UTType] {
        switch kind {
        case .videos: [.movie]
        case .manuals: [.pdf]
        default: [.image]
        }
    }

    private func choose(_ kind: MediaKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes(kind)
        panel.message = String(localized: "Choose the game's \(kind.singularTitle.lowercased())")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        _ = replace(kind, with: source)
    }

    private func replace(_ kind: MediaKind, with source: URL) -> Bool {
        guard let type = UTType(filenameExtension: source.pathExtension),
              allowedTypes(kind).contains(where: type.conforms(to:)) else {
            failure = String(localized: "That isn't a kind of file a \(kind.singularTitle.lowercased()) can be.")
            return false
        }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        do {
            let stored: URL
            if kind == .manuals {
                let destination = base(kind).appendingPathExtension("pdf")
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                stored = destination
            } else {
                stored = try game.storeMedia(Data(contentsOf: source), fileExtension: source.pathExtension, kind: kind)
            }
            // What the library points to follows.
            switch kind {
            case .covers:
                game.coverArtPath = stored.path
                game.coverArtManuallySet = true
            case .screenshots: game.titleScreenPath = stored.path
            case .videos: game.videoPath = stored.path
            default: break
            }
            try? game.modelContext?.save()
            revision += 1
            return true
        } catch {
            failure = String(localized: "Couldn't use \(source.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    private func remove(_ kind: MediaKind, at url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        CoverArtThumbnailCache.shared.invalidate(url)
        switch kind {
        case .covers where game.coverArtPath == url.path:
            game.coverArtPath = nil
            game.coverArtManuallySet = false
        case .screenshots where game.titleScreenPath == url.path: game.titleScreenPath = nil
        case .videos where game.videoPath == url.path: game.videoPath = nil
        default: break
        }
        try? game.modelContext?.save()
        revision += 1
    }

    static func symbol(_ kind: MediaKind) -> String {
        switch kind {
        case .covers: "photo"
        case .boxes3D: "shippingbox"
        case .physicalMedia: "opticaldisc"
        case .screenshots: "camera.viewfinder"
        case .videos: "film"
        case .manuals: "book"
        case .logos: "textformat"
        case .marquees: "lightbulb"
        case .fanart: "paintpalette"
        case .bezels: "tv"
        }
    }
}

extension MediaKind {
    /// One of them: "3D Box", "Logo"…
    var singularTitle: String {
        switch self {
        case .covers: String(localized: "Box")
        case .boxes3D: String(localized: "3D Box")
        case .physicalMedia: String(localized: "Cartridge")
        case .logos: String(localized: "Logo")
        case .marquees: String(localized: "Marquee")
        case .bezels: String(localized: "Bezel")
        case .fanart: String(localized: "Fan Art")
        case .screenshots: String(localized: "Screenshot")
        case .videos: String(localized: "Video")
        case .manuals: String(localized: "Manual")
        }
    }
}
