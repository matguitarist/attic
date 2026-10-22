import SwiftUI
import AVFoundation
import AVKit

/// A game's video, looping without controls, for the game panel's header.
struct VideoPreviewView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool
    /// Fills the view, cropping, instead of fitting: a backdrop.
    var fills = false

    /// What AVFoundation plays; MKV, AVI and WMV previews are skipped.
    static let playableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        view.allowsPictureInPicturePlayback = false
        let player = context.coordinator.player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = isMuted
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.player.isMuted = isMuted
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.looper = nil
        view.player = nil
    }
}

/// The game panel's picture: the game's screenshot, then — after a moment
/// on the game, so scrolling past doesn't start videos — its video, when
/// there's one and previews are on.
struct GameHeaderMedia: View {
    let imageURL: URL?
    let videoURL: URL?
    let title: String

    static let previewsKey = "playsVideoPreviews"
    @AppStorage(Self.previewsKey) private var playsPreviews = true
    @AppStorage("videoPreviewsMuted") private var isMuted = true
    @State private var showsVideo = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GameCoverArtView(url: imageURL, title: title, showBackground: false)
            if showsVideo, let videoURL {
                VideoPreviewView(url: videoURL, isMuted: isMuted)
                    .transition(.opacity)
                Button {
                    isMuted.toggle()
                } label: {
                    Label(isMuted ? String(localized: "Sound On") : String(localized: "Sound Off"),
                          systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .labelStyle(.iconOnly)
                        .padding(6)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(8)
                .help(isMuted ? String(localized: "Play the video's sound") : String(localized: "Mute the video"))
            }
        }
        .task(id: [videoURL?.path, playsPreviews.description, String(MediaRevisions.shared.revision(of: videoURL))]) {
            showsVideo = false
            guard playsPreviews, let videoURL, Self.canPlay(videoURL) else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { showsVideo = true }
        }
    }

    static func canPlay(_ url: URL) -> Bool {
        VideoPreviewView.playableExtensions.contains(url.pathExtension.lowercased())
            && FileManager.default.fileExists(atPath: url.path)
    }
}
