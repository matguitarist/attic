import Foundation

/// What a dump's name says it is beyond a released game, from No-Intro's
/// and GoodTools' tags: "(Proto)", "(Beta 2)", "(Demo, Kiosk)", "(Unl)",
/// "[h1]", "[b]".
public enum DumpTags {
    public enum Kind: String, CaseIterable, Sendable {
        /// Prototypes, betas and alphas.
        case prototype
        /// Demos, samples and kiosk versions.
        case demo
        /// Unlicensed, pirate, aftermarket and homebrew releases.
        case unlicensed
        /// Hacks.
        case hack
        /// Dumps marked bad.
        case badDump
    }

    public static func kinds(of fileName: String) -> Set<Kind> {
        var kinds: Set<Kind> = []
        for group in fileName.matches(of: #/\(([^)]*)\)/#) {
            for tag in group.output.1.split(separator: ",") {
                let word = tag.trimmingCharacters(in: .whitespaces).lowercased()
                    .split(separator: " ").first.map(String.init) ?? ""
                switch word {
                case "proto", "prototype", "beta", "alpha": kinds.insert(.prototype)
                case "demo", "sample", "kiosk": kinds.insert(.demo)
                case "unl", "unlicensed", "pirate", "aftermarket", "homebrew": kinds.insert(.unlicensed)
                case "hack": kinds.insert(.hack)
                default: break
                }
            }
        }
        for group in fileName.matches(of: #/\[([^\]]*)\]/#) {
            let tag = group.output.1.lowercased()
            if tag.wholeMatch(of: #/h\d*[a-z]*/#) != nil { kinds.insert(.hack) }
            if tag.wholeMatch(of: #/b\d*/#) != nil { kinds.insert(.badDump) }
        }
        return kinds
    }
}
