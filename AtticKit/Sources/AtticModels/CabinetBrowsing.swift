import Foundation

/// How Cabinet Mode orders a section's games (Start menu › View).
public enum CabinetSort: String, CaseIterable, Sendable {
    /// The section's own order: titles, or most recent first in Recently
    /// Played and Recently Added, a collection's chosen order.
    case section
    case title, year, mostPlayed, lastPlayed
}

/// Title search and A–Z jumps for Cabinet Mode, where there's no keyboard
/// to scroll fifteen thousand games.
public enum TitleBrowsing {
    /// Whether every word of `query` is in `title`, ignoring case and
    /// accents.
    public static func matches(_ title: String, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { title.localizedStandardContains($0) }
    }

    /// The letter a title files under: "A"…"Z", or "#" for digits and
    /// anything else. Accents fold ("É" is "E"), a leading "The" doesn't
    /// count when the list is sorted by `sortTitle`.
    public static func letter(of title: String) -> String {
        guard let first = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .first(where: { !$0.isWhitespace && $0 != "'" && $0 != "\"" }) else { return "#" }
        let upper = String(first).uppercased()
        return ("A"..."Z").contains(upper) && upper.count == 1 ? upper : "#"
    }

    /// Where an L2/R2 press lands in a list sorted by title: the next
    /// letter's first title, or this letter's first (else the previous
    /// letter's) going back. Nil when there's nowhere to go.
    public static func jump(from index: Int, in titles: [String], forward: Bool) -> Int? {
        guard titles.indices.contains(index) else { return titles.isEmpty ? nil : 0 }
        let letters = titles.map(letter(of:))
        let current = letters[index]
        if forward {
            return letters[(index + 1)...].firstIndex { $0 != current }
        }
        let groupStart = (letters[..<index].lastIndex { $0 != current }).map { $0 + 1 } ?? 0
        if groupStart < index { return groupStart }
        guard index > 0 else { return nil }
        let previous = letters[index - 1]
        return (letters[..<(index - 1)].lastIndex { $0 != previous }).map { $0 + 1 } ?? 0
    }
}
