import Foundation
import AtticModels
import AtticLibraryScanning

/// A game to move to the Trash, with what's needed to find its files and
/// its media.
struct GameToRemove: Sendable, Hashable {
    let rom: URL
    let systemFolder: URL
    let relativePath: String
}

extension ToolsCoordinator {
    /// Moves games to the Trash, every file of each (a cue sheet's tracks,
    /// a playlist's discs, an arcade set's disc images) and its media, then
    /// rescans so they leave the library. The Finder's Put Back restores
    /// them.
    func trashGames(_ games: [GameToRemove], romsRoots: [URL], scanCoordinator: ScanCoordinator, from host: Host) async {
        guard !isBusy, !games.isEmpty else { return }
        reportHost = host
        activity = Activity(title: String(localized: "Moving games to the Trash…"), fraction: 0)
        let progress = { @Sendable (value: Double, name: String) -> Void in
            Task { @MainActor in
                self.activity?.fraction = value
                self.activity?.detail = name
            }
        }
        let (trashed, bytes) = await Task.detached(priority: .userInitiated) { Self.trash(games, progress: progress) }.value
        activity = Activity(title: String(localized: "Refreshing the library…"))
        await scanCoordinator.scan(romsRootURLs: romsRoots)
        activity = nil
        outcome = Outcome(
            title: String(localized: "Remove Games"),
            message: String(localized: "\(trashed) games moved to the Trash, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). To bring one back, use Put Back in the Trash, then File › Refresh Library.")
        )
    }

    nonisolated private static func trash(_ games: [GameToRemove], progress: @Sendable (Double, String) -> Void) -> (Int, Int64) {
        let manager = FileManager.default
        var trashed = 0
        var bytes: Int64 = 0
        for (index, game) in games.enumerated() {
            progress(Double(index) / Double(games.count), game.rom.lastPathComponent)
            let files = FrontEndMedia.files(ofGame: game.rom)
            let size = files.reduce(Int64(0)) { $0 + FrontEndMedia.bytes(under: $1) }
            var moved = false
            for file in files where (try? manager.trashItem(at: file, resultingItemURL: nil)) != nil { moved = true }
            guard moved else { continue }
            trashed += 1
            bytes += size
            for kind in MediaKind.allCases {
                let base = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: kind)
                for file in MediaFolder.existingFiles(base: base) + [base.appendingPathExtension("pdf")]
                where manager.fileExists(atPath: file.path) {
                    try? manager.trashItem(at: file, resultingItemURL: nil)
                    CoverArtThumbnailCache.shared.invalidate(file)
                }
            }
        }
        progress(1, "")
        return (trashed, bytes)
    }
}
