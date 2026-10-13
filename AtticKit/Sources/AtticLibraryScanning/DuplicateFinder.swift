import Foundation
import AtticModels

/// Copies of the same game in one system folder that differ only by
/// region, language, revision or release status — `Zelda (USA)`,
/// `Zelda (Europe) (En,Fr,De)`, `Zelda (USA) (Rev 1)` — and which one to
/// keep: a finished release over betas, prototypes and bad dumps, then
/// World, USA, Europe, Japan, then the latest revision.
///
/// Anything else in a name's tags makes it a different game: `(Disc 2)`,
/// `(Tengen)`, `(Unl)`, a hack. Multi-file games (`.cue` with `.bin`
/// tracks) aren't looked at.
public enum DuplicateFinder {
    public struct Group: Sendable, Equatable {
        public let keep: URL
        public let others: [URL]
    }

    /// Region preference, most wanted first.
    static let regions = ["world", "usa", "europe", "japan"]
    static let otherRegions: Set<String> = [
        "us", "eu", "jp", "uk", "korea", "brazil", "france", "germany", "spain", "italy", "australia", "asia",
        "canada", "netherlands", "sweden", "taiwan", "china", "hong kong", "russia", "scandinavia", "denmark",
        "norway", "finland", "portugal", "greece", "poland", "mexico", "argentina", "latin america", "unknown",
    ]
    /// Files that make up a game with others, so aren't compared alone.
    static let multiFileExtensions: Set<String> = ["cue", "bin", "gdi", "raw", "img", "sub", "ccd", "toc", "m3u", "iso"]

    public static func groups(in folder: URL) -> [Group] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .filter { !multiFileExtensions.contains($0.pathExtension.lowercased()) }
        var byKey: [String: [(url: URL, rank: Rank)]] = [:]
        for file in files {
            guard let (key, rank) = identity(of: file.lastPathComponent) else { continue }
            byKey[key, default: []].append((file, rank))
        }
        // A zip is the same game as the file it holds — unless the plain
        // copies come in several formats (a cartridge .nes and a disk
        // .fds), which are different games; their zips are then left be.
        let sets = byKey.values.flatMap { copies -> [[(url: URL, rank: Rank)]] in
            let plain = Dictionary(grouping: copies.filter { !archiveExtensions.contains($0.url.pathExtension.lowercased()) }) {
                $0.url.pathExtension.lowercased()
            }
            guard plain.count > 1 else { return [copies] }
            return Array(plain.values)
        }
        return sets.filter { $0.count > 1 }.map { copies in
            let sorted = copies.sorted { $0.rank < $1.rank }
            return Group(keep: sorted[0].url, others: sorted.dropFirst().map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
        .sorted { $0.keep.lastPathComponent < $1.keep.lastPathComponent }
    }

    /// Lower is better.
    struct Rank: Comparable {
        var unfinished: Int
        var region: Int
        var revision: Int
        /// A zip or 7z of the game, against the game itself: the plain file
        /// starts without being unpacked first.
        var archived: Int
        var length: Int

        static func < (a: Rank, b: Rank) -> Bool {
            (a.unfinished, a.region, -a.revision, a.archived, a.length) < (b.unfinished, b.region, -b.revision, b.archived, b.length)
        }
    }

    static let archiveExtensions: Set<String> = ["zip", "7z"]

    /// What makes the game itself (title, extension and identifying tags)
    /// and how good this copy is; nil when there's no title to go by.
    static func identity(of fileName: String) -> (key: String, rank: Rank)? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let name = (fileName as NSString).deletingPathExtension
        guard let firstTag = name.firstIndex(where: { $0 == "(" || $0 == "[" }) else { return nil }
        let title = name[..<firstTag].trimmingCharacters(in: .whitespaces).lowercased()
        guard !title.isEmpty else { return nil }

        var rank = Rank(unfinished: 0, region: regions.count + 1, revision: 0, archived: archiveExtensions.contains(ext) ? 1 : 0, length: name.count)
        var identifying: [String] = []
        let tags = name[firstTag...].matches(of: /[\(\[]([^\)\]]*)[\)\]]/)
        for tag in tags {
            let isBracket = tag.output.0.hasPrefix("[")
            let text = String(tag.output.1).trimmingCharacters(in: .whitespaces)
            let lowered = text.lowercased()
            let parts = lowered.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            if parts.allSatisfy({ regions.contains($0) || otherRegions.contains($0) }) {
                rank.region = min(rank.region, parts.compactMap { regions.firstIndex(of: $0) }.min() ?? regions.count)
            } else if text.split(separator: ",").allSatisfy({ $0.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[A-Z][a-z](-[A-Z][a-z])?/) != nil }) {
                continue // languages
            } else if let match = lowered.wholeMatch(of: /rev\s*([0-9a-z]+)/) {
                rank.revision = revisionValue(String(match.output.1))
            } else if let match = lowered.wholeMatch(of: /v\s*([0-9]+(\.[0-9]+)*)/) {
                rank.revision = Int((Double(match.output.1) ?? 0) * 100)
            } else if lowered.wholeMatch(of: /(beta|proto|prototype|demo|sample|kiosk|alt|preview|promo)(\s*[0-9a-z]*)?/) != nil {
                rank.unfinished = max(rank.unfinished, 1)
            } else if isBracket, lowered == "!" {
                continue // verified good dump
            } else if isBracket, lowered.wholeMatch(of: /[bhoaft][0-9]*/) != nil {
                // GoodTools' bad dump, hack, overdump, alternate, fix, trainer.
                rank.unfinished = max(rank.unfinished, 2)
            } else {
                identifying.append(lowered)
            }
        }
        return ("\(title)|\(identifying.sorted().joined(separator: "|"))", rank)
    }

    private static func revisionValue(_ text: String) -> Int {
        if let number = Int(text) { return number }
        // Rev A, Rev B…
        return text.unicodeScalars.first.map { Int($0.value) - 96 } ?? 0
    }
}
