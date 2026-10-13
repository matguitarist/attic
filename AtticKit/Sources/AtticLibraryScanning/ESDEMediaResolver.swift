import Foundation
import AtticModels

/// ES-DE has no media path tags in gamelist.xml at all — art is matched
/// purely by filename against `<root>/Media/<system>/<type>/` (ES-DE's
/// `downloaded_media` too),
/// so resolving art means probing the filesystem, unlike Batocera where the
/// path comes straight out of the XML.
///
/// Falls back to Batocera-style media kept *inside* the ROM folder
/// (`<system>/images/<rom>-boxart.png`, `<system>/videos/<rom>-video.mp4`),
/// which libraries assembled from Batocera packs often carry even when the
/// rest of the layout is ES-DE's.
struct ESDEMediaResolver {
    let esdeRoot: URL
    let systemName: String
    var systemFolder: URL? = nil

    private static let imageExtensions = MediaFolder.imageExtensions
    private static let videoExtensions = MediaFolder.videoExtensions
    /// The box art first. Mix images and title screens (which Attic no
    /// longer keeps, see `MediaKind`) only stand in for a library that
    /// hasn't been tidied up, after a screenshot.
    private static let coverArtPreferenceOrder = ["covers", "screenshots", "miximages", "titlescreens"]
    /// Batocera's `-<suffix>` image names, box art first.
    private static let inFolderCoverSuffixes = ["boxart", "thumb", "image", "mix"]

    func resolveCoverArt(romNameNoExt: String) -> URL? {
        for mediaType in Self.coverArtPreferenceOrder {
            if let url = firstExistingFile(mediaType: mediaType, nameNoExt: romNameNoExt, extensions: Self.imageExtensions) {
                return url
            }
        }
        for suffix in Self.inFolderCoverSuffixes {
            if let url = firstInFolderFile(subfolder: "images", name: "\(romNameNoExt)-\(suffix)", extensions: Self.imageExtensions) {
                return url
            }
        }
        return nil
    }

    /// A shot of the game itself, for the detail panel's header: an
    /// in-game screenshot, or its title screen when there's none.
    /// (`Game.titleScreenPath` holds whichever was found.)
    func resolveTitleScreen(romNameNoExt: String) -> URL? {
        firstExistingFile(mediaType: "screenshots", nameNoExt: romNameNoExt, extensions: Self.imageExtensions)
            ?? firstExistingFile(mediaType: "titlescreens", nameNoExt: romNameNoExt, extensions: Self.imageExtensions)
            // Batocera packs name their screenshot `<rom>-image`.
            ?? firstInFolderFile(subfolder: "images", name: "\(romNameNoExt)-image", extensions: Self.imageExtensions)
    }

    func resolveVideo(romNameNoExt: String) -> URL? {
        firstExistingFile(mediaType: "videos", nameNoExt: romNameNoExt, extensions: Self.videoExtensions)
            ?? firstInFolderFile(subfolder: "videos", name: "\(romNameNoExt)-video", extensions: Self.videoExtensions)
    }

    private func firstInFolderFile(subfolder: String, name: String, extensions: [String]) -> URL? {
        guard let systemFolder else { return nil }
        let directory = systemFolder.appending(path: subfolder)
        for ext in extensions {
            let candidate = directory.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// In Attic's `Media` folder, else ES-DE's `downloaded_media`.
    private func firstExistingFile(mediaType: String, nameNoExt: String, extensions: [String]) -> URL? {
        for folderName in EmulationLayout.mediaNames {
            let directory = esdeRoot
                .appending(path: folderName)
                .appending(path: systemName)
                .appending(path: mediaType)
            for ext in extensions {
                let candidate = directory.appending(path: "\(nameNoExt).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
