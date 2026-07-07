import Foundation

/// Turns a ROM filename into a display-friendly title by stripping the
/// extension and any parenthesized/bracketed release tags — `(USA)`,
/// `[!]`, `(Europe) (En,Fr,De)`, `(Rev 1)`, etc. — common in
/// No-Intro/Redump/TOSEC-style filenames.
///
/// Used both for games with no gamelist.xml entry (where the filename is
/// the only title available) and for building a scraper search query from
/// a filename, so both contexts stay consistent with each other and only
/// need to get this right in one place.
public enum ROMFilenameTitleCleaner {
    public static func cleanTitle(fromROMFilename filename: String) -> String {
        let nameNoExt = (filename as NSString).deletingPathExtension
        let withoutTags = nameNoExt.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#,
            with: "",
            options: .regularExpression
        )
        return withoutTags.trimmingCharacters(in: .whitespaces)
    }
}
