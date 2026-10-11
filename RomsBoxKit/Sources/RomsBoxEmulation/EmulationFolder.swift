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
        EmulatorInstaller.Paths(coresDirectory: cores, coreInfoDirectory: coreInfo, applicationsDirectory: emulators, systemDirectory: bios)
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
    /// emulators' are, then the controller settings (see
    /// `retroArchControllerSettings`).
    public func retroArchPathsConfig(
        for system: CanonicalSystemID,
        controller: ControllerSettings = .default,
        savedConfig: [String: String] = [:],
        previouslyWritten: [String: String] = [:]
    ) -> String {
        retroArchLaunchConfig(for: system, controller: controller, savedConfig: savedConfig, previouslyWritten: previouslyWritten).text
    }

    func retroArchLaunchConfig(
        for system: CanonicalSystemID,
        controller: ControllerSettings,
        savedConfig: [String: String],
        previouslyWritten: [String: String]
    ) -> (text: String, controllerSettingsWritten: [String: String]) {
        var settings: [(key: String, value: String)] = [
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
            ("core_options_path", retroArchCoreOptionsFile.path)
        ]
        let controllerSettings = OwnedSettings.reconcile(
            desired: Self.retroArchControllerSettings(controller, savedConfig: savedConfig),
            previouslyWritten: previouslyWritten,
            current: savedConfig,
            resetValue: Self.retroArchResetValue
        )
        settings += controllerSettings.write
        let text = "# Written by RomsBox before every launch — edits here are overwritten.\n"
            + settings.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n") + "\n"
        return (text, controllerSettings.written)
    }

    /// Writes the per-launch paths config and makes sure the per-system
    /// save/state folders exist. Returns (main config, paths config).
    public func prepareRetroArchLaunch(for system: CanonicalSystemID, controller: ControllerSettings = .default) throws -> (config: URL, appendConfig: URL) {
        try createStructure()
        for directory in [saves(for: system), states(for: system)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let saved = Self.parseRetroArchConfig((try? String(contentsOf: retroArchConfigFile, encoding: .utf8)) ?? "")
        // Before this record existed, RomsBox only ever set the quit combo.
        let previous = readOwnedSettings("retroarch") ?? ["input_quit_gamepad_combo": "4"]
        let config = retroArchLaunchConfig(for: system, controller: controller, savedConfig: saved, previouslyWritten: previous)
        try config.text.write(to: retroArchPathsConfigFile, atomically: true, encoding: .utf8)
        try writeOwnedSettings(config.controllerSettingsWritten, for: "retroarch")
        return (retroArchConfigFile, retroArchPathsConfigFile)
    }

    // MARK: - RetroArch controller settings

    static let playerPorts = 1...4

    /// An axis number the `mfi` driver doesn't have (it reports six), so a
    /// bind to it never fires.
    static let deadAxis = "+9"

    /// What RomsBox wants in RetroArch's config for `controller`. Anything
    /// it wrote before and no longer wants is reset by `OwnedSettings`.
    static func retroArchControllerSettings(_ controller: ControllerSettings, savedConfig: [String: String]) -> [(key: String, value: String)] {
        // Confirm/cancel in RetroArch's own menus. Its default (false) is
        // the Nintendo arrangement: right confirms.
        var settings: [(key: String, value: String)] = [
            ("menu_swap_ok_cancel_buttons", controller.layout == .classic ? "true" : "false")
        ]
        if controller.quitWithSelectStart {
            settings += [("input_quit_gamepad_combo", "4"), ("quit_press_twice", "false")]
        }

        // Binds use the `mfi` driver's button numbers, meaningless to other
        // joypad drivers — skipped for those. A bind in the config takes
        // precedence over the controller's autoconfig, so binding all of a
        // player's buttons replaces the default layout outright.
        let mapping = controller.buttonMapping
        let usesMFi = (savedConfig["input_joypad_driver"] ?? "mfi") == "mfi"
        for port in playerPorts {
            if usesMFi, !mapping.isDefault {
                for button in RetroPadButton.allCases {
                    let physical = mapping.physical(for: button)
                    settings.append(("input_player\(port)_\(button.retroArchName)_btn", String(physical.retroArchMFiIndex)))
                    // L2/R2 are also bound to the triggers' analog axes by
                    // the autoconfig, and an unset axis bind falls back to
                    // it — so once moved off its trigger, that axis is
                    // pointed somewhere that never fires.
                    if button == .l2 || button == .r2, physical != button.defaultPhysical {
                        settings.append(("input_player\(port)_\(button.retroArchName)_axis", deadAxis))
                    }
                }
            }
            if controller.leftStickAsDPad {
                settings.append(("input_player\(port)_analog_dpad_mode", "1"))
            }
        }
        return settings
    }

    /// RetroArch's own default for a key RomsBox stops setting; `nil`
    /// leaves the key as it is.
    static func retroArchResetValue(_ key: String) -> String? {
        if key.hasSuffix("_btn") || key.hasSuffix("_axis") { return "nul" }
        if key.hasSuffix("_analog_dpad_mode") || key == "input_quit_gamepad_combo" { return "0" }
        return nil
    }

    // MARK: - Settings RomsBox wrote into emulators' configs

    private func ownedSettingsFile(_ emulator: String) -> URL {
        config.appending(path: "RomsBox/\(emulator)-settings-written.json")
    }

    func readOwnedSettings(_ emulator: String) -> [String: String]? {
        (try? Data(contentsOf: ownedSettingsFile(emulator))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    func writeOwnedSettings(_ settings: [String: String], for emulator: String) throws {
        let file = ownedSettingsFile(emulator)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }

    /// `key = "value"` lines of a RetroArch config.
    static func parseRetroArchConfig(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    public var retroArchCoreOptionsFile: URL { retroArchConfigDirectory.appending(path: "retroarch-core-options.cfg") }

    /// Sets keys in RetroArch's shared core options file (`key = "value"`
    /// lines), adding any that are missing and leaving every other line as
    /// it is. RetroArch reads the file when the core starts and writes the
    /// values back on exit, so they stick.
    public func setRetroArchCoreOptions(_ options: [String: String]) throws {
        guard !options.isEmpty else { return }
        let file = retroArchCoreOptionsFile
        var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            let line = "\(key) = \"\(value)\""
            if let index = lines.firstIndex(where: { $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key }) {
                lines[index] = line
            } else {
                lines.append(line)
            }
        }
        try FileManager.default.createDirectory(at: retroArchConfigDirectory, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
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
    public func prepareStandaloneLaunch(
        of emulator: StandaloneEmulator,
        for system: CanonicalSystemID,
        quitCombo: Bool = true,
        buttonMapping: ButtonMapping = .default
    ) throws -> [String: String] {
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
        if let pad = portable.padBindings {
            try applyButtonMapping(buttonMapping, to: &ini, pad: pad, emulatorID: emulator.id)
        }
        try ini.contents.write(to: settingsFile, atomically: true, encoding: .utf8)
        return ["HOME": home.path]
    }

    /// Binds the emulator's pad to `mapping` when it isn't the default,
    /// and puts back the default bindings RomsBox replaced once it is again
    /// (unless the user rebound them in the emulator since).
    private func applyButtonMapping(_ mapping: ButtonMapping, to ini: inout IniFile, pad: PortableHome.PadBindings, emulatorID: String) throws {
        func binding(_ physical: PhysicalButton) -> String { pad.prefix + physical.sdlName }
        let desired: [(key: String, value: String)] = mapping.isDefault ? [] : RetroPadButton.allCases.map {
            ("\(pad.section)/\($0.duckStationName)", binding(mapping.physical(for: $0)))
        }
        var current: [String: String] = [:]
        for button in RetroPadButton.allCases {
            current["\(pad.section)/\(button.duckStationName)"] = ini.value(section: pad.section, key: button.duckStationName)
        }
        let defaults = Dictionary(uniqueKeysWithValues: RetroPadButton.allCases.map {
            ("\(pad.section)/\($0.duckStationName)", binding($0.defaultPhysical))
        })
        let result = OwnedSettings.reconcile(
            desired: desired,
            previouslyWritten: readOwnedSettings(emulatorID) ?? [:],
            current: current,
            resetValue: { defaults[$0] }
        )
        for (key, value) in result.write {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            ini.set(section: parts[0], key: parts[1], value: value)
        }
        try writeOwnedSettings(result.written, for: emulatorID)
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
