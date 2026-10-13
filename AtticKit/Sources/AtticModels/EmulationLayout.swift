import Foundation

/// The folder names Attic uses beside `ROMs` in the Emulation folder,
/// capitalized like the rest (BIOS, Saves, States…), and the names ES-DE
/// gives the same folders, which are still read — and renamed to Attic's
/// own the first time Attic sees them in its Emulation folder.
public enum EmulationLayout {
    public static let media = "Media"
    public static let gamelists = "Gamelists"
    public static let collections = "Collections"

    /// ES-DE's `downloaded_media` and `gamelists`.
    public static let esdeMedia = "downloaded_media"
    public static let esdeGamelists = "gamelists"

    /// Every name a media or gamelists folder may have, Attic's first.
    public static let mediaNames = [media, esdeMedia]
    public static let gamelistsNames = [gamelists, esdeGamelists]
}
