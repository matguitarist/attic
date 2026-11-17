import Foundation

/// Keisho's own list of the Model 1, 2 and 3 sets it runs, with each
/// chip's CRC32. Keisho finds a game by its chips, not by the MAME version
/// its zip came from, so this is the list those systems are checked
/// against, with no DAT to download. The installed Keisho's `games.xml`
/// is read when there is one, so the checks follow the version that runs
/// the games; Attic's copy (`tools/import-keisho-games.py`) stands in until
/// then.
extension ArcadeVerifier {
    /// The installed Keisho's list, else Attic's copy.
    static func keishoSet(emulationRoot: URL?) -> Set? {
        if let root = emulationRoot {
            let folder = EmulationFolder(root: root)
            let installer = EmulatorInstaller(paths: folder.installerPaths)
            if let app = installer.installedAppURL(for: EmulatorCatalog.keisho),
               let set = keishoSet(from: app.appending(path: "Contents/Resources/games.xml"),
                                   version: Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String) {
                return set
            }
        }
        guard let bundled = Bundle.module.url(forResource: "KeishoGames", withExtension: "xml") else { return nil }
        return keishoSet(from: bundled, version: nil)
    }

    /// Reads Keisho's `games.xml`, or Attic's shorter copy of it (whose
    /// root names the version). Optional regions (a drive board's program,
    /// a blank EEPROM) aren't counted.
    static func keishoSet(from url: URL, version: String?) -> Set? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Keisho's comments hold "--", which XML doesn't allow there.
        let cleaned = text.replacing(#/<!--[\s\S]*?-->/#, with: "")
        let parser = XMLParser(data: Data(cleaned.utf8))
        let reader = KeishoReader()
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !reader.machines.isEmpty else { return nil }
        let name = (version ?? reader.version).map { "Keisho \($0)" } ?? "Keisho"
        return Set(name: name, machines: reader.machines, parents: reader.parents, biosCRCs: [])
    }

    private final class KeishoReader: NSObject, XMLParserDelegate {
        var machines: [String: Machine] = [:]
        var parents: [String: [String]] = [:]
        var version: String?

        private var current: String?
        private var parent: String?
        private var devices: [String] = []
        private var title = ""
        private var roms: [ROM] = []
        private var regionRequired = true
        private var inGame = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "keisho":
                version = attributes["version"]
            case "game":
                current = attributes["name"]?.lowercased()
                parent = attributes["parent"]?.lowercased()
                devices = []; title = ""; roms = []
                inGame = true
            case "device" where inGame:
                if let name = attributes["name"]?.lowercased() { devices.append(name) }
            case "region" where inGame:
                regionRequired = attributes["required"] != "false"
            case "file" where inGame && regionRequired:
                guard let name = attributes["name"], let crc = attributes["crc"].flatMap(Self.crc) else { return }
                var rom = ROM(name: name, size: 0, crc: crc)
                if let alternate = attributes["alt_crc"].flatMap(Self.crc) { rom.alternates = [alternate] }
                roms.append(rom)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "title" where inGame:
                title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "region":
                regionRequired = true
            case "game":
                guard let current else { break }
                // A clone's shared chips are in its parent's zip; an I/O
                // board's firmware may be in its device set (model1io.zip).
                let leans = [parent].compactMap { $0 } + devices
                if !leans.isEmpty { parents[current] = leans }
                machines[current] = Machine(title: title.isEmpty ? current : title, cloneOf: parent, romOf: parent, roms: roms, disks: [])
                self.current = nil
                inGame = false
            default:
                break
            }
            text = ""
        }

        /// "0x24b68e64" or "24b68e64".
        static func crc(_ value: String) -> UInt32? {
            UInt32(value.hasPrefix("0x") ? String(value.dropFirst(2)) : value, radix: 16)
        }
    }
}
