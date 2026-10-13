import Foundation
import AtticModels

/// PS Vita games are installed into Vita3K rather than played from files,
/// and run by title ID. This lists what's installed and keeps a
/// `<Title> [<ID>].psvita` file (holding the ID, ES-DE's convention) in
/// the ROMs folder's `psvita` folder for each, so they show up in the
/// library like any other game.
public enum Vita3KLibrary {
    public struct InstalledGame: Equatable, Sendable {
        public let titleID: String
        public let title: String
    }

    /// Vita3K's own data folder; it doesn't follow HOME.
    public static var defaultAppsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Vita3K/Vita3K/fs/ux0/app", directoryHint: .isDirectory)
    }

    public static func installedGames(in appsFolder: URL = defaultAppsFolder) -> [InstalledGame] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: appsFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.compactMap { folder in
            let titleID = folder.lastPathComponent
            guard titleID.wholeMatch(of: /[A-Z]{4}[0-9]{5}/) != nil else { return nil }
            let sfo = (try? Data(contentsOf: folder.appending(path: "sce_sys/param.sfo"))).map(paramSFO) ?? [:]
            return InstalledGame(titleID: titleID, title: sfo["TITLE"] ?? sfo["STITLE"] ?? titleID)
        }
        .sorted { $0.title < $1.title }
    }

    /// A dumped PS Vita or PS4 game folder (with `sce_sys/param.sfo`): its
    /// system, title and title ID. PS4 IDs start with CUSA and the like,
    /// Vita ones with PCS and others.
    public static func consoleGame(in folder: URL) -> (system: CanonicalSystemID, title: String, titleID: String)? {
        guard let data = try? Data(contentsOf: folder.appending(path: "sce_sys/param.sfo")) else { return nil }
        let values = paramSFO(data)
        guard let id = values["TITLE_ID"] else { return nil }
        let isPS4 = ["CUSA", "PLAS", "PCAS", "PLJS", "PLJM", "PCJS", "PCKS"].contains(String(id.prefix(4)))
        return (isPS4 ? .ps4 : .psvita, values["TITLE"] ?? id, id)
    }

    /// Whether a .pkg is a PS Vita one (not PS3's or PS4's): its header's
    /// content ID ("UP0001-PCSE00120_00-…") holds a Vita title ID.
    public static func isVitaPackage(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 0x60), header.count >= 0x54 else { return false }
        try? handle.close()
        // PS3 and Vita packages start "\u{7F}PKG"; PS4's "\u{7F}CNT".
        guard header.prefix(4) == Data([0x7F, 0x50, 0x4B, 0x47]),
              let contentID = String(data: header[0x30..<0x54], encoding: .ascii) else { return false }
        let parts = contentID.split(separator: "-")
        guard parts.count > 1 else { return false }
        let titleID = parts[1].prefix(9)
        return ["PCS", "VCA", "VCJ", "VLA", "VLJ"].contains { titleID.hasPrefix($0) }
    }

    /// Writes a `.psvita` file for each installed game that has none yet.
    /// Only when the ROMs root has a `psvita` folder: making one is how
    /// someone says they play Vita games. Returns how many were added.
    @discardableResult
    public static func addShortcuts(romsRoots: [URL], appsFolder: URL = defaultAppsFolder) -> Int {
        let fileManager = FileManager.default
        guard let folder = romsRoots.map({ $0.appending(path: "psvita", directoryHint: .isDirectory) })
            .first(where: { fileManager.fileExists(atPath: $0.path) }) else { return 0 }
        let games = installedGames(in: appsFolder)
        guard !games.isEmpty else { return 0 }

        let existing = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let known = Set(existing.filter { $0.pathExtension.lowercased() == "psvita" }.map { ArgumentTemplate.titleID(romURL: $0) })
        var added = 0
        for game in games where !known.contains(game.titleID) {
            let name = "\(fileName(game.title)) [\(game.titleID)].psvita"
            if (try? Data(game.titleID.utf8).write(to: folder.appending(path: name))) != nil { added += 1 }
        }
        return added
    }

    /// Without characters a file name can't hold.
    private static func fileName(_ title: String) -> String {
        title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The text values of a PARAM.SFO: a header, an index of entries, then
    /// a key table and a data table.
    public static func paramSFO(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? u16(at) | u16(at + 2) << 16 : 0 }
        func cString(_ at: Int, limit: Int) -> String? {
            guard at >= 0, at < bytes.count else { return nil }
            let end = min(at + limit, bytes.count)
            let slice = bytes[at..<end].prefix { $0 != 0 }
            return String(bytes: slice, encoding: .utf8)
        }
        guard bytes.count >= 20, bytes[0...3] == [0, 0x50, 0x53, 0x46] else { return [:] }
        let (keyTable, dataTable, count) = (u32(8), u32(12), u32(16))
        var values: [String: String] = [:]
        for index in 0..<min(count, 1024) {
            let entry = 20 + index * 16
            // 0x0204 is UTF-8 text.
            guard u16(entry + 2) == 0x0204,
                  let key = cString(keyTable + u16(entry), limit: 64),
                  let value = cString(dataTable + u32(entry + 12), limit: u32(entry + 4)) else { continue }
            values[key] = value
        }
        return values
    }
}
