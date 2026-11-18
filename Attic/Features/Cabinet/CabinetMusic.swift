import AVFoundation
import Foundation
import Observation

/// Music while browsing Cabinet Mode, as EmulationStation plays its music
/// folder: shuffled tracks from the Emulation folder's Music folder, or from
/// Music/<system> while that system's games are shown when it has one.
/// Silent while a game runs, a game's page plays its video, or the attract
/// mode shows.
@MainActor
@Observable
final class CabinetMusic: NSObject, AVAudioPlayerDelegate {
    static let shared = CabinetMusic()
    static let enabledKey = "cabinetPlaysMusic"
    nonisolated static let folderName = "Music"
    nonisolated static let playableExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    private var player: AVAudioPlayer?
    private var folder: URL?
    private var queue: [URL] = []
    private var isPaused = false
    private let volume: Float = 0.5

    /// The tracks in `folder`, by name.
    nonisolated static func tracks(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { playableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The folder to play from: the system's own when it has tracks, else
    /// the Music folder itself.
    nonisolated static func folder(in root: URL, system: String?) -> URL {
        let music = root.appending(path: folderName, directoryHint: .isDirectory)
        if let system {
            let own = music.appending(path: system, directoryHint: .isDirectory)
            if !tracks(in: own).isEmpty { return own }
        }
        return music
    }

    /// Plays from `folder`, carrying on when it's the one already playing.
    func play(from folder: URL) {
        guard folder != self.folder || player == nil else {
            resume()
            return
        }
        self.folder = folder
        queue = []
        next()
    }

    func stop() {
        player?.stop()
        player = nil
        folder = nil
        queue = []
    }

    /// Quiet for a moment (a game, a video), picked up where it was.
    func pause() {
        isPaused = true
        player?.pause()
    }

    func resume() {
        isPaused = false
        if player?.isPlaying == false { player?.play() }
    }

    private func next() {
        guard let folder else { return }
        if queue.isEmpty { queue = Self.tracks(in: folder).shuffled() }
        guard !queue.isEmpty else {
            player = nil
            return
        }
        let track = queue.removeFirst()
        player = try? AVAudioPlayer(contentsOf: track)
        player?.delegate = self
        player?.volume = volume
        if !isPaused { player?.play() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }
}
