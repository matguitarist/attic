import Foundation

/// Ready-made searches for well-known series, to start a collection from.
/// Each lists the titles' usual spellings (and regional names), and leaves
/// out spin-offs that share the name but not the series — sports games,
/// party games, unrelated games with a similar title.
public struct SeriesTemplate: Identifiable, Hashable, Sendable {
    public let name: String
    public let search: CollectionSearch
    /// Names its logo goes by in ES-DE and Batocera themes, when not
    /// its own name squeezed ("mario" for Super Mario).
    let logoAliases: [String]

    public var id: String { name }

    init(_ name: String, _ including: String, excluding: String = "", logo logoAliases: [String] = []) {
        self.name = name
        self.search = CollectionSearch(including: including, excluding: excluding)
        self.logoAliases = logoAliases
    }

    /// The file names (without extension) a logo for a collection called
    /// `name` may have in a folder of theme logos, best first: a
    /// template's aliases (the template named so, give or take a leading
    /// "The"), the whole name squeezed to lowercase letters and digits,
    /// with and without "the", then each of its words ("Mario Bros"
    /// finds mario.png).
    public static func logoNames(for name: String) -> [String] {
        let squeezed = squeeze(name)
        let bare = squeezed.hasPrefix("the") ? String(squeezed.dropFirst(3)) : squeezed
        var names = named(name)?.logoAliases ?? []
        names += [squeezed, bare]
        names += name.split(whereSeparator: \.isWhitespace).map { squeeze(String($0)) }
            .filter { $0.count >= 4 && $0 != "the" }
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The template a collection called `name` is, give or take a
    /// leading "The", case and accents: "Legend of Zelda" is The Legend
    /// of Zelda, "pokemon" is Pokémon.
    public static func named(_ name: String) -> SeriesTemplate? {
        func bare(_ text: String) -> String {
            let squeezed = squeeze(text)
            return squeezed.hasPrefix("the") ? String(squeezed.dropFirst(3)) : squeezed
        }
        let wanted = bare(name)
        guard !wanted.isEmpty else { return nil }
        return all.first { bare($0.name) == wanted }
    }

    private static func squeeze(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public static let all: [SeriesTemplate] = [
        // Nintendo
        SeriesTemplate("Super Mario", "Super Mario, Mario Bros, Mario Land, Mario 64, Mario Sunshine, Mario Galaxy, Mario 3D",
                       excluding: "Kart, Party, Tennis, Golf, Strikers, Olympic, Paint, Picross, Puzzle, Dr. Mario, Teaches, Hotel Mario, Pinball, Sports, Baseball, Basketball, Hoops", logo: ["mario"]),
        SeriesTemplate("Mario Kart", "Mario Kart"),
        SeriesTemplate("Mario Party", "Mario Party"),
        SeriesTemplate("The Legend of Zelda", "Zelda", excluding: "Picross", logo: ["zelda"]),
        SeriesTemplate("Metroid", "Metroid", excluding: "Pinball"),
        SeriesTemplate("Kirby", "Kirby", excluding: "Pinball"),
        SeriesTemplate("Donkey Kong", "Donkey Kong", excluding: "Konga", logo: ["donkeykong", "dk"]),
        SeriesTemplate("Pokémon", "Pokemon, Pokémon", excluding: "Pinball, Puzzle League, Snap, Trading Card"),
        SeriesTemplate("Fire Emblem", "Fire Emblem"),
        SeriesTemplate("Star Fox", "Star Fox, Starfox, StarFox, Starwing"),
        SeriesTemplate("F-Zero", "F-Zero"),
        SeriesTemplate("Wario", "Wario"),
        SeriesTemplate("Yoshi", "Yoshi"),
        SeriesTemplate("EarthBound", "EarthBound, Mother 1, Mother 2, Mother 3"),
        // Sega
        SeriesTemplate("Sonic the Hedgehog", "Sonic", excluding: "Sonic Wings, Sonic Blast Man, Sonic Boom, Sonic Champ", logo: ["sonic"]),
        SeriesTemplate("Streets of Rage", "Streets of Rage, Bare Knuckle"),
        SeriesTemplate("Phantasy Star", "Phantasy Star"),
        SeriesTemplate("Shinobi", "Shinobi"),
        SeriesTemplate("Golden Axe", "Golden Axe"),
        SeriesTemplate("Alex Kidd", "Alex Kidd"),
        SeriesTemplate("Ecco the Dolphin", "Ecco"),
        // Capcom
        SeriesTemplate("Mega Man", "Mega Man, Megaman, Rockman"),
        SeriesTemplate("Street Fighter", "Street Fighter", excluding: "Street Fighter 2010"),
        SeriesTemplate("Resident Evil", "Resident Evil, Biohazard"),
        SeriesTemplate("Final Fight", "Final Fight"),
        SeriesTemplate("Ghosts 'n Goblins", "Ghosts 'n Goblins, Ghouls 'n Ghosts, Ghosts n Goblins, Ghouls n Ghosts, Makaimura, Gargoyle's Quest"),
        // Konami
        SeriesTemplate("Castlevania", "Castlevania, Akumajou Dracula, Akumajo Dracula, Vampire Killer, Dracula X"),
        SeriesTemplate("Contra", "Contra, Probotector"),
        SeriesTemplate("Metal Gear", "Metal Gear"),
        SeriesTemplate("Gradius", "Gradius, Life Force, Salamander"),
        SeriesTemplate("Teenage Mutant Ninja Turtles", "Teenage Mutant, TMNT, Turtles in Time", logo: ["tmnt"]),
        SeriesTemplate("Silent Hill", "Silent Hill"),
        // Square Enix
        SeriesTemplate("Final Fantasy", "Final Fantasy"),
        SeriesTemplate("Dragon Quest", "Dragon Quest, Dragon Warrior"),
        SeriesTemplate("Mana", "Secret of Mana, Seiken Densetsu, Legend of Mana, Sword of Mana, Trials of Mana, Final Fantasy Adventure"),
        SeriesTemplate("Chrono", "Chrono Trigger, Chrono Cross"),
        // SNK
        SeriesTemplate("Metal Slug", "Metal Slug"),
        SeriesTemplate("The King of Fighters", "King of Fighters", logo: ["kof"]),
        SeriesTemplate("Fatal Fury", "Fatal Fury, Garou, Real Bout"),
        SeriesTemplate("Samurai Shodown", "Samurai Shodown, Samurai Spirits"),
        // Others
        SeriesTemplate("Tekken", "Tekken"),
        SeriesTemplate("Mortal Kombat", "Mortal Kombat"),
        SeriesTemplate("Crash Bandicoot", "Crash Bandicoot, Crash Team, Crash Bash"),
        SeriesTemplate("Spyro", "Spyro"),
        SeriesTemplate("Tomb Raider", "Tomb Raider"),
        SeriesTemplate("Gran Turismo", "Gran Turismo"),
        SeriesTemplate("Ridge Racer", "Ridge Racer"),
        SeriesTemplate("Tony Hawk's", "Tony Hawk"),
        SeriesTemplate("Ninja Gaiden", "Ninja Gaiden, Shadow Warriors"),
        SeriesTemplate("Double Dragon", "Double Dragon"),
        SeriesTemplate("Bomberman", "Bomberman"),
        SeriesTemplate("Pac-Man", "Pac-Man, Pac Man, Pacman", excluding: "Pinball"),
        SeriesTemplate("Bubble Bobble", "Bubble Bobble, Rainbow Islands, Puzzle Bobble, Bust-a-Move"),
        SeriesTemplate("Bonk", "Bonk, PC Genjin"),
        SeriesTemplate("Adventure Island", "Adventure Island, Takahashi Meijin"),
        SeriesTemplate("Star Wars", "Star Wars"),
        SeriesTemplate("Tetris", "Tetris"),
    ]
}
