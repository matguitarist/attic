import Foundation

/// Which titles a collection gathers: any of `including` (several terms,
/// comma-separated, like "Super Mario, Mario Bros"), but none of
/// `excluding` ("Tennis, Golf, Kart"). Case and accents don't matter.
public struct CollectionSearch: Hashable, Sendable {
    public var including: String
    public var excluding: String

    public init(including: String = "", excluding: String = "") {
        self.including = including
        self.excluding = excluding
    }

    public var includedTerms: [String] { Self.terms(including) }
    public var excludedTerms: [String] { Self.terms(excluding) }
    public var isEmpty: Bool { includedTerms.isEmpty }

    public func matches(_ title: String) -> Bool {
        let included = includedTerms
        guard !included.isEmpty else { return false }
        return included.contains { title.localizedStandardContains($0) }
            && !excludedTerms.contains { title.localizedStandardContains($0) }
    }

    static func terms(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
