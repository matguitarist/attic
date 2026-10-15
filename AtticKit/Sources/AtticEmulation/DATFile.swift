import Foundation
import AtticModels

/// A ROM set's catalogue of good dumps, as No-Intro (and Redump) publish
/// them: each game's files with their size and CRC32. Reads Logiqx XML,
/// DAT-o-MATIC's format, and the older clrmamepro text format libretro
/// keeps.
public struct DATFile: Sendable {
    public struct ROM: Equatable, Sendable {
        /// The game's name, which its file is named after:
        /// "Super Mario World (USA)".
        public let game: String
        public let name: String
        public let size: Int
        public let crc: UInt32
    }

    /// The set's name: "Nintendo - Super Nintendo Entertainment System".
    public let name: String
    public let roms: [ROM]

    public init(name: String, roms: [ROM]) {
        self.name = name
        self.roms = roms
    }

    public static func read(_ url: URL) -> DATFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let fallbackName = url.deletingPathExtension().lastPathComponent
        return parse(data, fallbackName: fallbackName)
    }

    public static func parse(_ data: Data, fallbackName: String = "") -> DATFile? {
        let start = String(decoding: data.prefix(512), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let dat = start.hasPrefix("<") ? XMLReader.read(data) : clrmamepro(String(decoding: data, as: UTF8.self))
        guard let dat, !dat.roms.isEmpty else { return nil }
        return dat.name.isEmpty ? DATFile(name: fallbackName, roms: dat.roms) : dat
    }

    /// The system the set is for, matched on libretro's names for them:
    /// No-Intro's "Atari - Atari 2600 (Headered)" is libretro's
    /// "Atari - 2600".
    public var system: CanonicalSystemID? {
        let key = Self.systemKey(name)
        return Self.systemByKey[key] ?? Self.aliases[key]
    }

    static func systemKey(_ name: String) -> String {
        let bare = name.replacing(#/\s*\([^)]*\)/#, with: "")
        let parts = bare.components(separatedBy: " - ").map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard let maker = parts.first else { return "" }
        let rest = parts.dropFirst().map { $0.hasPrefix(maker + " ") ? String($0.dropFirst(maker.count + 1)) : $0 }
        return ([maker] + rest).joined().filter { $0.isLetter || $0.isNumber }
    }

    private static let systemByKey: [String: CanonicalSystemID] = {
        var map: [String: CanonicalSystemID] = [:]
        for (system, names) in LibretroDatabase.namesBySystem {
            for name in names { map[systemKey(name)] = system }
        }
        return map
    }()

    /// No-Intro's names that libretro words differently.
    private static let aliases: [String: CanonicalSystemID] = [
        systemKey("Sega - SG-1000 - SC-3000"): .sg1000,
        systemKey("Sega - Mega Drive - Genesis"): .genesis,
        systemKey("Nintendo - Family Computer Disk System"): .fds,
        systemKey("Nintendo - Family Computer"): .nes,
        systemKey("Nintendo - Super Famicom"): .snes,
        systemKey("Atari - 8-bit Family"): .atari800,
        systemKey("Nintendo - Game & Watch"): .gameandwatch
    ]

    // MARK: - clrmamepro

    /// `clrmamepro ( name "…" )` then `game ( name "…" rom ( name "…"
    /// size 123 crc 89ABCDEF ) )` blocks.
    static func clrmamepro(_ text: String) -> DATFile? {
        let tokens = tokenize(text)
        var name = ""
        var roms: [ROM] = []
        var index = 0
        var block: [String] = []
        var game = ""
        var rom: [String: String] = [:]

        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if token == "(" { continue }
            if token == ")" {
                if block.last == "rom", let romName = rom["name"], let size = rom["size"].flatMap(Int.init),
                   let crc = rom["crc"].flatMap({ UInt32($0, radix: 16) }) {
                    roms.append(ROM(game: game, name: romName, size: size, crc: crc))
                }
                if block.last == "rom" { rom = [:] }
                if !block.isEmpty { block.removeLast() }
                continue
            }
            if index < tokens.count, tokens[index] == "(" {
                block.append(token)
                continue
            }
            guard index < tokens.count else { break }
            let value = tokens[index]
            index += 1
            switch block.last {
            case "clrmamepro" where token == "name": name = value
            case "game" where token == "name", "machine" where token == "name": game = value
            case "rom": rom[token] = value
            default: break
            }
        }
        return DATFile(name: name, roms: roms)
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if quoted {
                if character == "\"" {
                    tokens.append(current)
                    current = ""
                    quoted = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "(" || character == ")" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Logiqx XML

    private final class XMLReader: NSObject, XMLParserDelegate {
        private var name = ""
        private var roms: [ROM] = []
        private var game = ""
        private var inHeader = false
        private var text = ""

        static func read(_ data: Data) -> DATFile? {
            let reader = XMLReader()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            // DAT-o-MATIC's files name a DTD on the web: never fetch it.
            parser.shouldResolveExternalEntities = false
            guard parser.parse() || !reader.roms.isEmpty else { return nil }
            return DATFile(name: reader.name, roms: reader.roms)
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch element {
            case "header": inHeader = true
            case "game", "machine": game = attributes["name"] ?? ""
            case "rom":
                guard let romName = attributes["name"], let size = attributes["size"].flatMap(Int.init),
                      let crc = attributes["crc"].flatMap({ UInt32($0, radix: 16) }) else { return }
                roms.append(ROM(game: game, name: romName, size: size, crc: crc))
            default: break
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            if element == "header" { inHeader = false }
            if inHeader, element == "name" { name = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}
