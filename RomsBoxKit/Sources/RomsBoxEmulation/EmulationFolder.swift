import Foundation
import RomsBoxModels

/// The one user-visible folder holding everything emulation-related —
/// ROMs, BIOS, saves, emulator config and portable emulators — so backing
/// up or moving to another Mac means copying a single folder.
///
///     Emulation/
///       ROMs/ gamelists/ downloaded_media/   (ES-DE layout, untouched)
///       BIOS/
///       Saves/<system>/      States/<system>/
///       Cores/  Cores/Info/                  (RetroArch cores + .info)
///       Config/RetroArch/                    (RetroArch's own config)
///       Config/<Emulator>/                   (standalone emulators' data)
///       Emulators/<Emulator>/<App>.app
///
/// Nothing inside stores an absolute path that RomsBox doesn't rewrite on
/// every launch, which is what keeps the folder portable across Macs and
/// user names.
public struct EmulationFolder: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var bios: URL { root.appending(path: "BIOS", directoryHint: .isDirectory) }
    public var saves: URL { root.appending(path: "Saves", directoryHint: .isDirectory) }
    public var states: URL { root.appending(path: "States", directoryHint: .isDirectory) }
    public var cores: URL { root.appending(path: "Cores", directoryHint: .isDirectory) }
    public var coreInfo: URL { cores.appending(path: "Info", directoryHint: .isDirectory) }
    public var config: URL { root.appending(path: "Config", directoryHint: .isDirectory) }
    public var emulators: URL { root.appending(path: "Emulators", directoryHint: .isDirectory) }

    public var retroArchConfigDirectory: URL { config.appending(path: "RetroArch", directoryHint: .isDirectory) }
    /// RetroArch's main config when launched by RomsBox (`--config`).
    public var retroArchConfigFile: URL { retroArchConfigDirectory.appending(path: "retroarch.cfg") }
    /// Rewritten before every launch and passed with `--appendconfig`, so
    /// its absolute paths always match where this folder currently is.
    public var retroArchPathsConfigFile: URL { retroArchConfigDirectory.appending(path: "romsbox-paths.cfg") }

    public func saves(for system: CanonicalSystemID) -> URL { saves.appending(path: system.rawValue, directoryHint: .isDirectory) }
    public func states(for system: CanonicalSystemID) -> URL { states.appending(path: system.rawValue, directoryHint: .isDirectory) }

    /// Where a standalone emulator's data lives — passed to it as `HOME`.
    public func configHome(for emulator: StandaloneEmulator) -> URL {
        config.appending(path: emulator.name, directoryHint: .isDirectory)
    }

    public var installerPaths: EmulatorInstaller.Paths {
        EmulatorInstaller.Paths(coresDirectory: cores, coreInfoDirectory: coreInfo, applicationsDirectory: emulators)
    }

    /// Defaults to the folder containing the ROMs folder when it follows
    /// the usual `…/ROMs` naming (as ES-DE and Batocera layouts do), so the
    /// emulation folder sits next to the ROMs it serves; otherwise
    /// `~/Emulation`.
    public static func defaultRoot(romsRoots: [URL]) -> URL {
        if let romsRoot = romsRoots.first(where: { $0.lastPathComponent.lowercased() == "roms" }) {
            return romsRoot.deletingLastPathComponent()
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Emulation", directoryHint: .isDirectory)
    }

    /// Creates any missing top-level folders. Existing ones (whatever their
    /// capitalization — APFS is case-insensitive) are left as they are.
    public func createStructure() throws {
        for directory in [bios, saves, states, cores, coreInfo, config, retroArchConfigDirectory, emulators] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - RetroArch

    /// The `--appendconfig` contents for launching a game of `system`:
    /// every directory RetroArch reads or writes, pointed into this folder,
    /// with saves and states split per system the same way standalone
    /// emulators' are.
    /// With `quitCombo`, Start + Select quits immediately — RetroArch's own
    /// `input_quit_gamepad_combo` (4 = Start + Select in its option list),
    /// with the "press twice to confirm" step turned off.
    public func retroArchPathsConfig(for system: CanonicalSystemID, quitCombo: Bool = true) -> String {
        var settings: [(String, String)] = [
            ("system_directory", bios.path),
            ("libretro_directory", cores.path),
            ("libretro_info_path", coreInfo.path),
            ("savefile_directory", saves(for: system).path),
            ("savestate_directory", states(for: system).path),
            // RomsBox already splits by system; RetroArch's own per-core
            // subfolders would nest a second level under that.
            ("sort_savefiles_enable", "false"),
            ("sort_savestates_enable", "false"),
            ("sort_savefiles_by_content_enable", "false"),
            ("sort_savestates_by_content_enable", "false"),
            ("rgui_config_directory", retroArchConfigDirectory.appending(path: "overrides").path),
            ("input_remapping_directory", retroArchConfigDirectory.appending(path: "remaps").path),
            ("global_core_options", "true"),
            ("core_options_path", retroArchConfigDirectory.appending(path: "retroarch-core-options.cfg").path)
        ]
        if quitCombo {
            settings += [("input_quit_gamepad_combo", "4"), ("quit_press_twice", "false")]
        }
        return "# Written by RomsBox before every launch — edits here are overwritten.\n"
            + settings.map { "\($0.0) = \"\($0.1)\"" }.joined(separator: "\n") + "\n"
    }

    /// Writes the per-launch paths config and makes sure the per-system
    /// save/state folders exist. Returns (main config, paths config).
    public func prepareRetroArchLaunch(for system: CanonicalSystemID, quitCombo: Bool = true) throws -> (config: URL, appendConfig: URL) {
        try createStructure()
        for directory in [saves(for: system), states(for: system)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try retroArchPathsConfig(for: system, quitCombo: quitCombo).write(to: retroArchPathsConfigFile, atomically: true, encoding: .utf8)
        return (retroArchConfigFile, retroArchPathsConfigFile)
    }

    /// Starts RomsBox's RetroArch config from the user's existing one, so
    /// controller binds and video settings carry over instead of resetting
    /// to RetroArch's defaults. Never overwrites an existing config.
    public func seedRetroArchConfig(from existing: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: retroArchConfigFile.path),
              fileManager.fileExists(atPath: existing.path) else { return }
        try fileManager.createDirectory(at: retroArchConfigDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: existing, to: retroArchConfigFile)
    }

    // MARK: - Standalone emulators

    /// Points a standalone emulator's own settings file at this folder's
    /// BIOS/save/state directories, and returns the environment to launch
    /// it with. Re-run before every launch so the paths follow the folder.
    public func prepareStandaloneLaunch(of emulator: StandaloneEmulator, for system: CanonicalSystemID, quitCombo: Bool = true) throws -> [String: String] {
        guard let portable = emulator.portableHome else { return [:] }
        let home = configHome(for: emulator)
        let settingsFile = home.appending(path: portable.settingsRelativePath)
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        for directory in [saves(for: system), states(for: system), bios] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var ini = IniFile(contents: (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "")
        for setting in portable.settings {
            if setting.onlyIfMissing, ini.value(section: setting.section, key: setting.key) != nil { continue }
            ini.set(section: setting.section, key: setting.key, value: expand(setting.value, system: system))
        }
        for setting in portable.quitComboSettings {
            if quitCombo {
                ini.set(section: setting.section, key: setting.key, value: setting.value)
            } else if ini.value(section: setting.section, key: setting.key) == setting.value {
                // Only undo our own binding, never one the user set.
                ini.remove(section: setting.section, key: setting.key)
            }
        }
        try ini.contents.write(to: settingsFile, atomically: true, encoding: .utf8)
        return ["HOME": home.path]
    }

    private func expand(_ template: String, system: CanonicalSystemID) -> String {
        template
            .replacingOccurrences(of: "{bios}", with: bios.path)
            .replacingOccurrences(of: "{saves}", with: saves(for: system).path)
            .replacingOccurrences(of: "{states}", with: states(for: system).path)
    }

    // MARK: - Importing

    /// Copies every file under `source` that isn't already in `destination`
    /// (matched by relative path), keeping subfolders. Nothing is moved or
    /// overwritten. Returns the relative paths copied.
    @discardableResult
    public static func copyMissingFiles(from source: URL, to destination: URL) throws -> [String] {
        let fileManager = FileManager.default
        let source = source.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var copied: [String] = []
        let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relativePath = String(file.resolvingSymlinksInPath().path.dropFirst(sourcePrefix.count))
            guard !relativePath.isEmpty, !relativePath.hasPrefix(".") else { continue }
            let target = destination.appending(path: relativePath)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: file, to: target)
            copied.append(relativePath)
        }
        return copied.sorted()
    }
}
