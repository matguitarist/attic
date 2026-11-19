import Foundation
import AtticModels

/// Sega Chihiro games in Tovarichtch's xemu fork. It's an `xemu.app` with
/// the same identity as the official one, so it gets a home of its own
/// (`Config/xemu Chihiro`) and its own settings file, given with
/// `-config_path`; the official xemu's setup is never touched.
///
/// The board's dumps come from MAME's chihiro.zip, unpacked once into that
/// home; the Xbox boot ROM (mcpx_1.0.bin) and the network board's firmware
/// (ver1305.bin) are used when they're in the BIOS folder.
extension EmulationFolder {
    public enum XemuChihiroError: LocalizedError {
        case noBIOS(URL)

        public var errorDescription: String? {
            switch self {
            case .noBIOS(let folder):
                String(localized: "xemu Chihiro needs MAME's Chihiro BIOS: put chihiro.zip in \(folder.appending(path: "mame/bios").path).", bundle: .module)
            }
        }
    }

    /// The board's files, by the setting that names each, in the order
    /// the fork's wiki lists them. The media board's flash has an older
    /// and a newer dump.
    static let chihiroROMs: [(key: String, files: [String])] = [
        ("bios_path", ["chihiro_xbox_bios.bin"]),
        ("mediaboard_path", ["fpr21042_m29w160et.bin", "fpr-23887_29lv160te.ic4", "fpr-23887.bin"]),
        ("ic10_path", ["ic10_g24lc64.bin"]),
        ("ic11_path", ["ic11_24lc024.bin"]),
        ("pc20_path", ["pc20_g24lc64.bin"]),
    ]

    /// The environment and the arguments (before the game's) that start
    /// the fork with its own settings, pointed at the board's files.
    public func xemuChihiroLaunch() throws -> (environment: [String: String], arguments: [String]) {
        let fileManager = FileManager.default
        let home = configHome(for: EmulatorCatalog.xemuChihiro)
        let roms = home.appending(path: "roms", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: roms, withIntermediateDirectories: true)
        try unpackChihiroBIOS(into: roms)

        let settingsFile = home.appending(path: "xemu.toml")
        var toml = TOMLSettings(contents: (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "")
        for (key, files) in Self.chihiroROMs {
            guard let file = files.map({ roms.appending(path: $0) }).first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                throw XemuChihiroError.noBIOS(bios)
            }
            toml.set(table: "chihiro.roms", key: key, string: file.path)
        }
        if let firmware = firstFile(named: "ver1305.bin", in: ["", "chihiro", "mame", "mame/bios"]) {
            toml.set(table: "chihiro.roms", key: "net_firmware_path", string: firmware.path)
        }
        if let bootROM = firstFile(named: "mcpx_1.0.bin", in: ["", "xbox", "xemu", "chihiro"]) {
            toml.set(table: "sys.files", key: "bootrom_path", string: bootROM.path)
        }
        if toml.value(table: "general", key: "show_welcome") == nil {
            toml.set(table: "general", key: "show_welcome", bool: false)
        }
        try toml.contents.write(to: settingsFile, atomically: true, encoding: .utf8)
        return (["HOME": home.path], ["-config_path", settingsFile.path])
    }

    /// Unpacks chihiro.zip into `folder` when a file is missing there. A
    /// folder of the dumps (BIOS/chihiro) does as well.
    private func unpackChihiroBIOS(into folder: URL) throws {
        let fileManager = FileManager.default
        let needed = Self.chihiroROMs.map(\.files)
        let present = { needed.allSatisfy { $0.contains { fileManager.fileExists(atPath: folder.appending(path: $0).path) } } }
        guard !present() else { return }
        if let zip = firstFile(named: "chihiro.zip", in: ["mame/bios", "mame", ""]) {
            _ = Namco2x6.run("/usr/bin/unzip", ["-o", "-j", "-q", zip.path, "-d", folder.path])
        } else {
            for file in needed.flatMap({ $0 }) {
                if let loose = firstFile(named: file, in: ["chihiro", ""]), !fileManager.fileExists(atPath: folder.appending(path: file).path) {
                    try fileManager.copyItem(at: loose, to: folder.appending(path: file))
                }
            }
        }
        guard present() else { throw XemuChihiroError.noBIOS(bios) }
    }

    private func firstFile(named name: String, in folders: [String]) -> URL? {
        folders.map { ($0.isEmpty ? bios : bios.appending(path: $0, directoryHint: .isDirectory)).appending(path: name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
