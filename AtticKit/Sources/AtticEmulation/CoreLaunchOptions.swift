import Foundation
import AtticModels

/// Core options Attic sets in RetroArch's core options file right before
/// a launch (see `EmulationFolder.setRetroArchCoreOptions`).
public enum CoreLaunchOptions {
    public static func options(
        system: CanonicalSystemID,
        coreIdentifier: String,
        romURL: URL
    ) -> [String: String] {
        switch coreIdentifier {
        case "mednafen_vb_libretro":
            // Beetle VB's VR mode needs an OpenGL context macOS can't give
            // it (only GL 2.1), so RetroArch's video driver fails and the
            // game quits straight back to Attic. Plain rendering works.
            return ["vb_vr": "disabled"]

        case "fbneo_libretro" where system == .neogeo:
            // Free play: no coins, Start just starts. FinalBurn Neo exposes
            // the MVS "Free play" DIP switch per romset
            // (`fbneo-dipswitch-<set>-Free_play`). Every Neo Geo set shares
            // it; other arcade boards name and wire theirs differently per
            // game, so they're left alone.
            let romset = romURL.deletingPathExtension().lastPathComponent
            return ["fbneo-dipswitch-\(romset)-Free_play": "On"]

        case "puae_libretro" where system == .amigacd32 || system == .cdtv:
            // PUAE boots a disc as a CD32 unless told otherwise; its
            // Automatic model takes this machine for CD images.
            return ["puae_model_cd": system == .cdtv ? "CDTV" : "CD32"]

        default:
            return [:]
        }
    }
}
