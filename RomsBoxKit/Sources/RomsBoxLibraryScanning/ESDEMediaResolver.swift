import Foundation

/// ES-DE has no media path tags in gamelist.xml at all — art is matched
/// purely by filename against `<ES-DE root>/downloaded_media/<system>/<type>/`,
/// so resolving art means probing the filesystem, unlike Batocera where the
/// path comes straight out of the XML.
struct ESDEMediaResolver {
    let esdeRoot: URL
    let systemName: String

    private static let imageExtensions = ["png", "jpg", "jpeg"]
    private static let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv"]
    /// ES-DE's own preference order when multiple asset types exist for one
    /// game: a generated `miximage` composite is preferred, falling back to
    /// progressively less-composed art.
    private static let coverArtPreferenceOrder = ["miximages", "covers", "titlescreens", "screenshots"]

    func resolveCoverArt(romNameNoExt: String) -> URL? {
        for mediaType in Self.coverArtPreferenceOrder {
            if let url = firstExistingFile(mediaType: mediaType, nameNoExt: romNameNoExt, extensions: Self.imageExtensions) {
                return url
            }
        }
        return nil
    }

    func resolveTitleScreen(romNameNoExt: String) -> URL? {
        firstExistingFile(mediaType: "titlescreens", nameNoExt: romNameNoExt, extensions: Self.imageExtensions)
    }

    func resolveVideo(romNameNoExt: String) -> URL? {
        firstExistingFile(mediaType: "videos", nameNoExt: romNameNoExt, extensions: Self.videoExtensions)
    }

    private func firstExistingFile(mediaType: String, nameNoExt: String, extensions: [String]) -> URL? {
        let directory = esdeRoot
            .appending(path: "downloaded_media")
            .appending(path: systemName)
            .appending(path: mediaType)
        for ext in extensions {
            let candidate = directory.appending(path: "\(nameNoExt).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
