import Foundation

/// Info that's likely another game's, as a scraper sometimes matches the
/// wrong one: a description that opens by naming a different game. (The
/// same description under two names is nearly always one game under its
/// regional names, so it isn't counted.)
public enum MetadataCheck {
    public struct Game: Sendable {
        /// What the game is known by in the result: its file's path.
        public let id: String
        public let title: String
        /// Its file's name, which often names it better than a scraped title.
        public let romName: String
        public let description: String?

        public init(id: String, title: String, romName: String, description: String?) {
            self.id = id
            self.title = title
            self.romName = romName
            self.description = description
        }
    }

    public enum Doubt: Hashable, Sendable {
        /// The description opens by naming another game: "Grind Stormer is
        /// a 1993 vertically scrolling shooter", under Virtua Fighter 4.
        case describesAnotherGame(String)
    }

    /// The doubts about each game that has some, by its id.
    public static func doubts(_ games: [Game]) -> [String: Doubt] {
        var doubts: [String: Doubt] = [:]
        for game in games {
            guard let description = game.description, let subject = subject(of: description),
                  !names(subject, sameAs: game.title), !names(subject, sameAs: game.romName) else { continue }
            doubts[game.id] = .describesAnotherGame(subject)
        }
        return doubts
    }

    /// Whether `subject` could be `name`: a word in common, or one inside
    /// the other with the spaces gone ("Fresman", "Fres Man").
    static func names(_ subject: String, sameAs name: String) -> Bool {
        let subjectWords = words(subject), nameWords = words(name)
        guard !subjectWords.isEmpty else { return true }
        if !subjectWords.isDisjoint(with: nameWords) { return true }
        let squashedSubject = squashed(subject), squashedName = squashed(name)
        guard !squashedSubject.isEmpty, !squashedName.isEmpty else { return false }
        return squashedSubject.contains(squashedName) || squashedName.contains(squashedSubject)
            || subjectWords.contains { $0.count >= 4 && squashedName.contains($0) }
            || nameWords.contains { $0.count >= 4 && squashedSubject.contains($0) }
            // A letter or two apart: "Xanagams", "Xanagrams".
            || (squashedSubject.count >= 6 && distance(squashedSubject, squashedName) <= 2)
    }

    /// Letters to add, remove or change to turn one into the other.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 2 else { return 3 }
        var previous = Array(0...b.count)
        for (i, letter) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (letter == b[j] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }

    private static func squashed(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    /// What the description's first sentence is about, when it opens like
    /// "X is a…" or "X was an…" and X names something.
    static func subject(of description: String) -> String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
            // "Ikaruga (Japanese: 斑鳩) is…": the aside isn't the name.
            .replacingOccurrences(of: #"\s*[\(（][^\)）]*[\)）]"#, with: "", options: .regularExpression)
        guard let match = text.range(of: #"^[^.!?\n]{2,60}?(?=\s+(?:is|was)\s+(?:a|an|the)\s)"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let subject = String(text[match]).trimmingCharacters(in: .whitespaces)
        // A title's few words, not the start of a sentence about the game.
        guard let first = subject.first, first.isUppercase || first.isNumber,
              subject.split(separator: " ").count <= 5, !subject.contains(","),
              !sentenceStarts.contains(where: { subject.lowercased().hasPrefix($0) }) else { return nil }
        // …and what it is, a kind of game: "Bruno is a baby Ottifant" is
        // the story, not another game.
        let sentence = text[match.upperBound...].prefix { !".!?\n".contains($0) }.lowercased()
        guard gameWords.contains(where: { sentence.contains($0) }) else { return nil }
        return subject
    }

    private static let gameWords = [
        "game", "shooter", "shoot", "platform", "puzzle", "rpg", "role-playing", "role playing", "adventure", "fighting",
        "racing", "racer", "beat-", "beat 'em", "simulation", "simulator", "strategy", "sports", "sequel", "clone",
        "conversion", "port of", "remake", "compilation", "pinball", "quiz", "mahjong", "arcade",
    ]

    private static let sentenceStarts = [
        "a ", "an ", "this ", "these ", "it ", "there", "here", "what", "now ", "for ", "from ", "in ", "on ", "as ",
        "you ", "your ", "one ", "each ", "the player", "the hero", "the game", "the goal", "the object", "the aim",
        "the story", "the sequel", "the classic", "the first", "the second", "the third",
    ]

    /// A name's words that tell it apart: lowercased, without the little
    /// ones and those any game's description might open with.
    static func words(_ text: String) -> Set<String> {
        let all = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return Set(all.filter { $0.count > 1 && !commonWords.contains($0) })
    }

    private static let commonWords: Set<String> = [
        "the", "an", "of", "and", "in", "to", "for", "on", "no", "de", "la", "le", "vs", "it", "its", "this", "that",
        "game", "games", "title", "sequel", "version", "series", "player", "players", "arcade", "one", "new",
        "usa", "europe", "japan", "world", "rev", "en", "ja",
    ]
}
