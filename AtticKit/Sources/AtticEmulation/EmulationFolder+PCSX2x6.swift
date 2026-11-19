import Foundation
import AtticModels
import AtticLibraryScanning

/// Getting a System 246/256 MAME set ready for PCSX2x6, in
/// `Config/PCSX2x6/games/<set>/`: the `.acgame` it boots, the game's boot
/// program from PCSX2x6's template, and the media. The dongle becomes a
/// memory card in the system's saves folder (games write their settings
/// and records to it), and the BIOS is taken from MAME's sys256.zip.
/// The romset itself is never changed.
extension EmulationFolder {
    public enum PCSX2x6Error: LocalizedError {
        case unknownSet(String)
        case noTemplate(String)
        case noBIOS(URL)
        case noDongle(String)
        case noMedia(String)
        case needsCHDMan
        case conversionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unknownSet(let set):
                String(localized: "PCSX2x6 doesn't know the set “\(set)”. Keep each game zipped with its MAME romset name.", bundle: .module)
            case .noTemplate(let gameID):
                String(localized: "PCSX2x6's game library has no boot program for \(gameID).", bundle: .module)
            case .noBIOS(let folder):
                String(localized: "PCSX2x6 needs MAME's System 256 BIOS: put sys256.zip (or sys246.zip) in \(folder.appending(path: "mame/bios").path).", bundle: .module)
            case .noDongle(let set):
                String(localized: "No security dongle found in \(set).zip.", bundle: .module)
            case .noMedia(let set):
                String(localized: "No disc or hard disk image for \(set): MAME keeps it in the folder named like the game, beside its zip.", bundle: .module)
            case .needsCHDMan:
                String(localized: "This game's disc has to be converted once for PCSX2x6, which needs MAME's chdman tool: install Homebrew (brew.sh), then run “brew install rom-tools” in Terminal.", bundle: .module)
            case .conversionFailed(let set):
                String(localized: "chdman couldn't convert \(set)'s disc for PCSX2x6.", bundle: .module)
            }
        }
    }

    var pcsx2x6Home: URL { configHome(for: EmulatorCatalog.pcsx2x6) }
    private var pcsx2x6Template: URL { pcsx2x6Home.appending(path: "template/system2x6_games", directoryHint: .isDirectory) }

    /// The converted copy of the set's disc, made once: MAME keeps DVDs
    /// and CDs as hard disk CHDs, which PCSX2x6 can't read.
    func pcsx2x6ConvertedMedia(forSet set: String) -> URL {
        pcsx2x6Home.appending(path: "games/\(set)/\(set).chd")
    }

    /// Whether the game still has to have its disc converted, which takes
    /// a few minutes: the caller says so before calling `preparePCSX2x6Game`.
    public func pcsx2x6NeedsConversion(romURL: URL) -> Bool {
        let set = romURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let media = Namco2x6.media(forSet: romURL), CHDHeader.read(media)?.kind == .hardDisk,
              let game = Namco2x6.game(forSet: romURL),
              let template = try? String(contentsOf: pcsx2x6Template.appending(path: "\(game.gameID).acgame"), encoding: .utf8),
              IniFile(contents: template).value(section: "data", key: "media")?.uppercased() != "HDD" else { return false }
        return !FileManager.default.fileExists(atPath: pcsx2x6ConvertedMedia(forSet: set).path)
    }

    /// Sets the game up and returns the `.acgame` to boot. Safe to run
    /// before every launch: what's already there is kept. Blocking — the
    /// template download and a disc conversion take a while.
    public func preparePCSX2x6Game(romURL: URL, chdman: URL?) throws -> URL {
        let fileManager = FileManager.default
        let set = romURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let game = Namco2x6.game(forSet: romURL) else { throw PCSX2x6Error.unknownSet(set) }

        // The template: each game's settings and boot program.
        if !fileManager.fileExists(atPath: pcsx2x6Template.path) {
            try downloadPCSX2x6Template()
        }
        let templateFile = pcsx2x6Template.appending(path: "\(game.gameID).acgame")
        let bootProgram = pcsx2x6Template.appending(path: "\(game.gameID)/boot.elf")
        guard let templateText = try? String(contentsOf: templateFile, encoding: .utf8),
              fileManager.fileExists(atPath: bootProgram.path) else { throw PCSX2x6Error.noTemplate(game.gameID) }
        let template = IniFile(contents: templateText)

        let gameFolder = pcsx2x6Home.appending(path: "games/\(set)", directoryHint: .isDirectory)
        let cards = saves(for: .namco2x6)
        for folder in [gameFolder, cards] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let elf = gameFolder.appending(path: "boot.elf")
        if (try? Data(contentsOf: elf)) != (try? Data(contentsOf: bootProgram)) {
            try? fileManager.removeItem(at: elf)
            try fileManager.copyItem(at: bootProgram, to: elf)
        }

        // The dongle, made once: the game writes to it afterwards.
        let card = cards.appending(path: "\(set).ps2")
        if !fileManager.fileExists(atPath: card.path) {
            guard let data = Namco2x6.card(fromSet: romURL) else { throw PCSX2x6Error.noDongle(set) }
            try data.write(to: card)
        }

        // The media: as it is, or converted once to a DVD image.
        guard let source = Namco2x6.media(forSet: romURL) else { throw PCSX2x6Error.noMedia(set) }
        let mediaType = template.value(section: "data", key: "media")?.uppercased() ?? "DVD"
        let media: URL
        if CHDHeader.read(source)?.kind == .hardDisk, mediaType != "HDD" {
            media = pcsx2x6ConvertedMedia(forSet: set)
            if !fileManager.fileExists(atPath: media.path) {
                guard let chdman else { throw PCSX2x6Error.needsCHDMan }
                try convertToDVD(source, to: media, chdman: chdman, set: set)
            }
        } else {
            // A link beside the .acgame, where PCSX2x6 looks for it.
            media = gameFolder.appending(path: source.lastPathComponent)
            if (try? fileManager.destinationOfSymbolicLink(atPath: media.path)) != source.path {
                try? fileManager.removeItem(at: media)
                try fileManager.createSymbolicLink(at: media, withDestinationURL: source)
            }
        }

        let acgame = gameFolder.appending(path: "\(set).acgame")
        let lines = [
            "[game]",
            "name=\(template.value(section: "game", key: "name") ?? set)",
            "gameid=\(game.gameID)",
            "platform=\(template.value(section: "game", key: "platform") ?? "246")",
            "",
            "[data]",
            // Empty: the files are beside this one.
            "subdir=",
            "elf=boot.elf",
            "dongle=\(card.lastPathComponent)",
            "mediasrc=\(media.lastPathComponent)",
            "media=\(mediaType)"
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: acgame, atomically: true, encoding: .utf8)

        try setPCSX2x6BIOS()
        return acgame
    }

    /// Unpacks MAME's System 256 BIOS (or 246's) into PCSX2x6's bios
    /// folder and points its settings at it.
    private func setPCSX2x6BIOS() throws {
        let candidates = [("sys256.zip", "r27v1602f.8g"), ("sys246.zip", "r27v1602f.7d")].flatMap { zip, file in
            ["mame/bios/\(zip)", "mame/\(zip)", zip].map { (bios.appending(path: $0), file) }
        }
        guard let (zip, file) = candidates.first(where: { FileManager.default.fileExists(atPath: $0.0.path) }) else {
            throw PCSX2x6Error.noBIOS(bios)
        }
        let folder = pcsx2x6Home.appending(path: "bios", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appending(path: file)
        if !FileManager.default.fileExists(atPath: image.path) {
            guard let data = Namco2x6.run("/usr/bin/unzip", ["-p", zip.path, file]), !data.isEmpty else { throw PCSX2x6Error.noBIOS(bios) }
            try data.write(to: image)
        }
        let settingsFile = pcsx2x6Home.appending(path: EmulatorCatalog.pcsx2x6.portableHome!.settingsRelativePath)
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ini = IniFile(contents: (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "")
        ini.set(section: "Folders", key: "Bios", value: folder.path)
        ini.set(section: "Filenames", key: "BIOS", value: file)
        try ini.contents.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    private func downloadPCSX2x6Template() throws {
        let fileManager = FileManager.default
        let archive = pcsx2x6Home.appending(path: ".template.7z")
        let staging = pcsx2x6Home.appending(path: ".template", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: archive)
            try? fileManager.removeItem(at: staging)
        }
        try Data(contentsOf: Namco2x6.templateURL).write(to: archive)
        guard Namco2x6.run("/usr/bin/bsdtar", ["-xf", archive.path, "-C", staging.path]) != nil,
              fileManager.fileExists(atPath: staging.appending(path: "system2x6_games").path) else {
            throw PCSX2x6Error.noTemplate("PCSX2x6")
        }
        let destination = pcsx2x6Template.deletingLastPathComponent()
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)
    }

    /// MAME's hard disk CHD of a disc, as a DVD CHD: the image is taken
    /// out, then packed again. The temporary image goes beside the result.
    private func convertToDVD(_ source: URL, to destination: URL, chdman: URL, set: String) throws {
        let image = destination.deletingLastPathComponent().appending(path: ".\(set).iso")
        let partial = destination.deletingLastPathComponent().appending(path: ".\(set).partial.chd")
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: partial)
        }
        for file in [image, partial] { try? FileManager.default.removeItem(at: file) }
        guard Namco2x6.run(chdman.path, ["extracthd", "-i", source.path, "-o", image.path]) != nil,
              Namco2x6.run(chdman.path, ["createdvd", "-i", image.path, "-o", partial.path]) != nil else {
            throw PCSX2x6Error.conversionFailed(set)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}
