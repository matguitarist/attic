import Foundation

/// The arcade companies Attic has a logo for (`ArcadeLogo/<id>` in the
/// app's SystemLogos catalog), and which of them made a game, read from its
/// manufacturer as MAME and the scrapers write it ("Cave (AMI license)",
/// "Data East Corporation", "Raizing / Eighting").
public enum ArcadeMaker {
    /// Logo name → the words a manufacturer starts with, most specific first.
    static let makers: [(id: String, names: [String])] = [
        ("americanlasergames", ["American Laser Games"]),
        ("atari", ["Atari"]),
        ("banpresto", ["Banpresto"]),
        ("capcom", ["Capcom"]),
        ("cave", ["Cave"]),
        ("dataeast", ["Data East"]),
        ("eighting", ["Eighting", "8ing"]),
        ("gaelco", ["Gaelco"]),
        ("irem", ["Irem"]),
        ("jaleco", ["Jaleco"]),
        ("kaneko", ["Kaneko"]),
        ("konami", ["Konami"]),
        ("midway", ["Midway", "Bally Midway"]),
        ("namco", ["Namco", "Bandai Namco"]),
        ("nichibutsu", ["Nichibutsu", "Nihon Bussan"]),
        ("nintendo", ["Nintendo"]),
        ("psikyo", ["Psikyo"]),
        ("raizing", ["Raizing"]),
        ("romstar", ["Romstar"]),
        ("sega", ["Sega"]),
        ("seibukaihatsu", ["Seibu Kaihatsu", "Seibu"]),
        ("snk", ["SNK"]),
        ("stern", ["Stern"]),
        ("taito", ["Taito"]),
        ("technos", ["Technos"]),
        ("tecmo", ["Tecmo", "Koei Tecmo"]),
        ("toaplan", ["Toaplan"]),
        ("universal", ["Universal"]),
        ("videosystem", ["Video System"]),
        ("visco", ["Visco"]),
        ("williams", ["Williams"]),
    ]

    /// Every maker's logo name.
    public static var ids: [String] { makers.map(\.id) }

    /// The logo name of the company that made a game, from its
    /// manufacturer; the first company named wins ("Raizing / Eighting" →
    /// raizing). `nil` for a company without a logo.
    public static func id(forManufacturer manufacturer: String) -> String? {
        let first = manufacturer
            .components(separatedBy: CharacterSet(charactersIn: "/(,+&"))[0]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !first.isEmpty else { return nil }
        var best: (id: String, length: Int)?
        for maker in makers {
            for name in maker.names {
                let name = name.lowercased()
                guard first == name || first.hasPrefix(name + " ") || first.hasPrefix(name + ".") else { continue }
                if name.count > best?.length ?? 0 { best = (maker.id, name.count) }
            }
        }
        return best?.id
    }
}
