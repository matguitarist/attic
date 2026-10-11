import SwiftUI
import UniformTypeIdentifiers
import RomsBoxPersistence

/// Which game the library window's Edit Info sheet is showing. One per
/// library window; the inspector, the grid's context menu and Game › Edit
/// Info… all open the sheet by setting `game`.
@Observable
@MainActor
final class GameInfoEditor {
    var game: Game?
}

extension FocusedValues {
    @Entry var gameInfoEditor: GameInfoEditor?
}

/// Every piece of a game's metadata in one sheet, including what the
/// inspector can't edit in place (cover, sort title, release date,
/// rating). Changes apply on Save only, and mark the game as hand-edited
/// so rescans and later scrapes leave them alone.
struct EditGameInfoView: View {
    let game: Game

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var sortTitle: String
    @State private var developer: String
    @State private var publisher: String
    @State private var genre: String
    @State private var players: String
    @State private var hasReleaseDate: Bool
    @State private var releaseDate: Date
    @State private var rating: Double?
    @State private var gameDescription: String
    /// A newly picked image not yet copied in, or `removesCustomCover`.
    @State private var pickedCoverURL: URL?
    @State private var removesCustomCover = false
    @State private var showsImagePicker = false
    @State private var coverError: String?
    @State private var isDropTargeted = false

    init(game: Game) {
        self.game = game
        _title = State(initialValue: game.title)
        // Empty means "same as the title" — the common case, and it keeps
        // following the title if that's edited.
        _sortTitle = State(initialValue: game.sortTitle == game.title ? "" : game.sortTitle)
        _developer = State(initialValue: game.developer ?? "")
        _publisher = State(initialValue: game.publisher ?? "")
        _genre = State(initialValue: game.genre ?? "")
        _players = State(initialValue: game.players ?? "")
        _hasReleaseDate = State(initialValue: game.releaseDate != nil)
        _releaseDate = State(initialValue: game.releaseDate ?? Self.defaultReleaseDate)
        _rating = State(initialValue: game.rating)
        _gameDescription = State(initialValue: game.gameDescription ?? "")
    }

    /// Gamelists store release dates as UTC midnight, so the picker works in
    /// UTC too — otherwise west of Greenwich every date shows a day early.
    private static let utc = TimeZone(identifier: "UTC")!
    private static var defaultReleaseDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var displayedCoverURL: URL? {
        if let pickedCoverURL { return pickedCoverURL }
        if removesCustomCover { return nil }
        return game.coverArtURL
    }

    var body: some View {
        Form {
            coverSection

            Section("Game") {
                TextField("Title", text: $title, prompt: Text("Required"))
                TextField("Sort As", text: $sortTitle, prompt: Text(trimmedTitle.isEmpty ? String(localized: "Same as title") : trimmedTitle))
                    .help("Where the game sorts in the library, e.g. “Legend of Zelda, The”. Leave empty to sort by title.")
                TextField("Developer", text: $developer, prompt: Text("Not set"))
                TextField("Publisher", text: $publisher, prompt: Text("Not set"))
                TextField("Genre", text: $genre, prompt: Text("Not set"))
                TextField("Players", text: $players, prompt: Text("Not set"))
                Toggle("Release Date", isOn: $hasReleaseDate.animation())
                if hasReleaseDate {
                    DatePicker("Released", selection: $releaseDate, displayedComponents: .date)
                        .environment(\.timeZone, Self.utc)
                }
                LabeledContent("Rating") {
                    StarRatingPicker(rating: $rating)
                }
            }

            Section("Description") {
                TextEditor(text: $gameDescription)
                    .font(.callout)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .navigationTitle("Edit Info")
        .fileImporter(isPresented: $showsImagePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { pick(url) }
        }
    }

    private var coverSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                GameCoverArtView(url: displayedCoverURL, title: trimmedTitle, showBackground: false)
                    .frame(width: 110, height: 110 / (3.0 / 4.0))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.tint, lineWidth: 3)
                        }
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { return false }
                        pick(url)
                        return true
                    } isTargeted: { isDropTargeted = $0 }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cover Art").font(.headline)
                    Text("Choose an image or drag one onto the cover.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Choose Image…") { showsImagePicker = true }
                        if pickedCoverURL != nil || (game.coverArtManuallySet && !removesCustomCover) {
                            Button("Remove") {
                                pickedCoverURL = nil
                                removesCustomCover = game.coverArtManuallySet
                            }
                        }
                    }
                    if let coverError {
                        Text(coverError).font(.callout).foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func pick(_ url: URL) {
        pickedCoverURL = url
        removesCustomCover = false
        coverError = nil
    }

    private func save() {
        if let pickedCoverURL {
            do {
                game.coverArtPath = try CustomCoverArt.store(pickedCoverURL, for: game).path
                game.coverArtManuallySet = true
            } catch {
                coverError = error.localizedDescription
                return
            }
        } else if removesCustomCover {
            CustomCoverArt.remove(for: game)
            // The next rescan or scrape fills it back in.
            game.coverArtPath = nil
            game.coverArtManuallySet = false
        }

        game.title = trimmedTitle
        let sortAs = sortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        game.sortTitle = sortAs.isEmpty ? trimmedTitle : sortAs
        game.developer = Self.optional(developer)
        game.publisher = Self.optional(publisher)
        game.genre = Self.optional(genre)
        game.players = Self.optional(players)
        game.releaseDate = hasReleaseDate ? releaseDate : nil
        game.rating = rating
        game.gameDescription = Self.optional(gameDescription)
        game.metadataManuallyEdited = true
        try? game.modelContext?.save()
        dismiss()
    }

    /// Cleared text saves as `nil`, the way imported and scraped data say
    /// "no value".
    private static func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Five stars over gamelists' 0…1 rating; clicking the current rating
/// clears it.
struct StarRatingPicker: View {
    @Binding var rating: Double?

    private var stars: Int { Int(((rating ?? 0) * 5).rounded()) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star == stars ? nil : Double(star) / 5
                } label: {
                    Image(systemName: star <= stars ? "star.fill" : "star")
                        .foregroundStyle(star <= stars ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(star) stars"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Rating"))
    }
}

/// Covers the user picks, copied next to scraped media so they don't
/// depend on the original file staying put.
enum CustomCoverArt {
    static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appending(path: "RomsBox/CustomMedia", directoryHint: .isDirectory)
    }

    static func store(_ source: URL, for game: Game) throws -> URL {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let systemDirectory = directory.appending(path: game.systemCanonicalID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)
        remove(for: game)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = systemDirectory.appending(path: "\(baseName(for: game)).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        CoverArtThumbnailCache.shared.invalidate(destination)
        return destination
    }

    /// Deletes the game's custom cover, whatever its image type.
    static func remove(for game: Game) {
        let systemDirectory = directory.appending(path: game.systemCanonicalID, directoryHint: .isDirectory)
        let base = baseName(for: game)
        let files = (try? FileManager.default.contentsOfDirectory(at: systemDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.deletingPathExtension().lastPathComponent == base {
            try? FileManager.default.removeItem(at: file)
            CoverArtThumbnailCache.shared.invalidate(file)
        }
    }

    /// The ROM's path within its system folder, flattened — two games with
    /// the same file name in different subfolders keep separate covers.
    private static func baseName(for game: Game) -> String {
        (game.romRelativePath as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: "__")
    }
}
