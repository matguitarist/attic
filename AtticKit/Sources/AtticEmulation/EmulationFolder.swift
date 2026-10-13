import Foundation
import AtticModels

/// The one user-visible folder holding everything emulation-related —
/// ROMs, BIOS, saves, emulator config and portable emulators — so backing
/// up or moving to another Mac means copying a single folder.
///
///     Emulation/
///       ROMs/<system>/
///       Media/<system>/<kind>/               (covers, screenshots, videos, manuals)
///       Gamelists/<system>/gamelist.xml      (names and descriptions)
///       Collections/<Name>/                  (collection.json, logo, artwork)
///       BIOS/
///       Saves/<system>/      States/<system>/
///       Cores/  Cores/Info/                  (RetroArch cores + .info)
///       Config/RetroArch/                    (RetroArch's own config)
///       Config/<Emulator>/                   (standalone emulators' data)
///       Emulators/<Emulator>/<App>.app
///
/// Nothing inside stores an absolute path that Attic doesn't rewrite on
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
    public var media: URL { root.appending(path: EmulationLayout.media, directoryHint: .isDirectory) }
    public var gamelists: URL { root.appending(path: EmulationLayout.gamelists, directoryHint: .isDirectory) }
    public var collections: URL { root.appending(path: EmulationLayout.collections, directoryHint: .isDirectory) }

    public var retroArchConfigDirectory: URL { config.appending(path: "RetroArch", directoryHint: .isDirectory) }
    /// RetroArch's main config when launched by Attic (`--config`).
    public var retroArchConfigFile: URL { retroArchConfigDirectory.appending(path: "retroarch.cfg") }
    /// Rewritten before every launch and passed with `--appendconfig`, so
    /// its absolute paths always match where this folder currently is.
    public var retroArchPathsConfigFile: URL { retroArchConfigDirectory.appending(path: "attic-paths.cfg") }

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

    /// Renames ES-DE's `downloaded_media` and `gamelists` (and Attic's own
    /// earlier lowercase `collections`) in `parent` to Attic's names (see
    /// `EmulationLayout`). Returns the renamed folders' old and new paths.
    @discardableResult
    public static func adoptFolderNames(in parent: URL) -> [(from: URL, to: URL)] {
        let fileManager = FileManager.default
        // Exact spellings: APFS ignores case, so `gamelists` "exists" as
        // `Gamelists` too.
        let names = Set((try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? [])
        var renamed: [(URL, URL)] = []
        for (old, new) in [(EmulationLayout.esdeMedia, EmulationLayout.media),
                           (EmulationLayout.esdeGamelists, EmulationLayout.gamelists),
                           ("collections", EmulationLayout.collections)]
        where names.contains(old) && !names.contains(new) {
            let from = parent.appending(path: old, directoryHint: .isDirectory)
            let to = parent.appending(path: new, directoryHint: .isDirectory)
            // Through a temporary name, which a case-only rename needs.
            let step = parent.appending(path: ".\(new)-\(UUID().uuidString)", directoryHint: .isDirectory)
            guard (try? fileManager.moveItem(at: from, to: step)) != nil else { continue }
            if (try? fileManager.moveItem(at: step, to: to)) != nil {
                renamed.append((from, to))
            } else {
                try? fileManager.moveItem(at: step, to: from)
            }
        }
        return renamed
    }

    /// Creates any missing top-level folders. Existing ones (whatever their
    /// capitalization — APFS is case-insensitive) are left as they are.
    public func createStructure() throws {
        for directory in [bios, saves, states, cores, coreInfo, config, retroArchConfigDirectory, emulators, media, gamelists, collections] {
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
        systemSettings: SystemSettings = SystemSettings(),
        savedConfig: [String: String] = [:],
        previouslyWritten: [String: String] = [:],
        systemSettingsOwned: [String: OwnedValue] = [:]
    ) -> String {
        retroArchLaunchConfig(
            for: system, controller: controller, systemSettings: systemSettings, savedConfig: savedConfig,
            previouslyWritten: previouslyWritten, systemSettingsOwned: systemSettingsOwned
        ).text
    }

    func retroArchLaunchConfig(
        for system: CanonicalSystemID,
        controller: ControllerSettings,
        systemSettings: SystemSettings = SystemSettings(),
        savedConfig: [String: String],
        previouslyWritten: [String: String],
        systemSettingsOwned: [String: OwnedValue] = [:]
    ) -> (text: String, controllerSettingsWritten: [String: String], systemSettingsOwned: [String: OwnedValue]) {
        var settings: [(key: String, value: String)] = [
            ("system_directory", bios.path),
            ("libretro_directory", cores.path),
            ("libretro_info_path", coreInfo.path),
            ("savefile_directory", saves(for: system).path),
            ("savestate_directory", states(for: system).path),
            // Attic already splits by system; RetroArch's own per-core
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
        // System Settings. RetroArch saves these into retroarch.cfg on
        // exit like anything else, so each one is put back to the user's
        // own value once the launched system no longer sets it.
        let systemResult = Self.reconcileKeepingOriginals(
            desired: SystemSettingsSupport.retroArchConfig(systemSettings, system: system),
            owned: systemSettingsOwned,
            current: savedConfig,
            fallback: { SystemSettingsSupport.retroArchDefaults[$0] }
        )
        settings += systemResult.write
        let text = "# Written by Attic before every launch — edits here are overwritten.\n"
            + settings.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n") + "\n"
        return (text, controllerSettings.written, systemResult.owned)
    }

    /// Writes the per-launch paths config and makes sure the per-system
    /// save/state folders exist. Returns (main config, paths config).
    public func prepareRetroArchLaunch(
        for system: CanonicalSystemID,
        controller: ControllerSettings = .default,
        systemSettings: SystemSettings = SystemSettings()
    ) throws -> (config: URL, appendConfig: URL) {
        try createStructure()
        for directory in [saves(for: system), states(for: system)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let saved = Self.parseRetroArchConfig((try? String(contentsOf: retroArchConfigFile, encoding: .utf8)) ?? "")
        // Before this record existed, Attic only ever set the quit combo.
        let previous = readOwnedSettings("retroarch") ?? ["input_quit_gamepad_combo": "4"]
        let config = retroArchLaunchConfig(
            for: system, controller: controller, systemSettings: systemSettings, savedConfig: saved,
            previouslyWritten: previous, systemSettingsOwned: readOwned("retroarch-system") ?? [:]
        )
        try config.text.write(to: retroArchPathsConfigFile, atomically: true, encoding: .utf8)
        try writeOwnedSettings(config.controllerSettingsWritten, for: "retroarch")
        try writeOwned(config.systemSettingsOwned, for: "retroarch-system")
        return (retroArchConfigFile, retroArchPathsConfigFile)
    }

    /// Sets `core`'s options for `settings` (resolution, widescreen…) in
    /// the shared core options file, and puts back any Attic set for
    /// another system or core that this launch doesn't.
    public func setSystemCoreOptions(_ settings: SystemSettings, core: String) throws {
        let current = Self.parseRetroArchConfig((try? String(contentsOf: retroArchCoreOptionsFile, encoding: .utf8)) ?? "")
        let result = Self.reconcileKeepingOriginals(
            desired: SystemSettingsSupport.coreOptions(settings, core: core).sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
            owned: readOwned("retroarch-core-options") ?? [:],
            current: current,
            fallback: SystemSettingsSupport.coreOptionDefault
        )
        try setRetroArchCoreOptions(Dictionary(result.write.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }))
        try writeOwned(result.owned, for: "retroarch-core-options")
    }

    // MARK: - What "Default" means

    /// What each System Setting is when left on Default: the emulator's
    /// current value, as the user set it (not one Attic set for a launch).
    /// A setting stays `nil` when its value can't be told apart, such as a
    /// resolution that isn't one of Attic's choices.
    public func currentDefaults(
        for backend: SystemSettingsBackend,
        dolphinGFXFile: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Dolphin/Config/GFX.ini")
    ) -> SystemSettings {
        var defaults = SystemSettings()
        switch backend {
        case .retroArch(let core):
            let config = Self.parseRetroArchConfig((try? String(contentsOf: retroArchConfigFile, encoding: .utf8)) ?? "")
            let value = Self.usersOwnValue(in: config, owned: readOwned("retroarch-system") ?? [:]) {
                SystemSettingsSupport.retroArchDefaults[$0]
            }
            defaults.integerScaling = value("video_scale_integer").map { $0 == "true" }
            defaults.runAheadFrames = value("run_ahead_enabled") == "true" ? value("run_ahead_frames").flatMap { Int($0) } : 0
            defaults.rewind = value("rewind_enable").map { $0 == "true" }
            defaults.resume = value("savestate_auto_load").map { $0 == "true" }

            let options = Self.parseRetroArchConfig((try? String(contentsOf: retroArchCoreOptionsFile, encoding: .utf8)) ?? "")
            let option = Self.usersOwnValue(in: options, owned: readOwned("retroarch-core-options") ?? [:], fallback: SystemSettingsSupport.coreOptionDefault)
            guard let map = SystemSettingsSupport.coreOptions[core] else { break }
            func matches(_ wanted: [String: String]) -> Bool { wanted.allSatisfy { option($0.key) == $0.value } }
            func flag(_ mapping: (@Sendable (Bool) -> [String: String])?) -> Bool? {
                guard let mapping else { return nil }
                return matches(mapping(true)) ? true : matches(mapping(false)) ? false : nil
            }
            if let resolution = map.resolution {
                defaults.internalResolution = map.resolutionChoices.first { matches(resolution($0)) }
            }
            defaults.widescreen = flag(map.widescreen)
            defaults.geometryCorrection = flag(map.geometryCorrection)
            defaults.unlimitedSprites = flag(map.unlimitedSprites)
            defaults.lcdColors = flag(map.lcdColors)

        case .duckStation:
            let file = configHome(for: EmulatorCatalog.duckStation).appending(path: "Library/Application Support/DuckStation/settings.ini")
            let ini = IniFile(contents: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
            let owned = readOwnedSettings("duckstation-system") ?? [:]
            // A value Attic wrote is removed again on Default, back to
            // DuckStation's own default.
            func value(_ section: String, _ key: String) -> String? {
                let current = ini.value(section: section, key: key)
                return current == owned["\(section)/\(key)"] ? nil : current
            }
            defaults.internalResolution = Int(value("GPU", "ResolutionScale") ?? "1")
            defaults.widescreen = (value("GPU", "WidescreenHack") ?? "false") == "true"
            defaults.geometryCorrection = (value("GPU", "PGXPEnable") ?? "false") == "true"
            defaults.rewind = (value("Main", "RewindEnable") ?? "false") == "true"

        case .dolphin:
            // Attic's Dolphin settings only last one run, so the file
            // always has the user's own.
            let ini = IniFile(contents: (try? String(contentsOf: dolphinGFXFile, encoding: .utf8)) ?? "")
            defaults.internalResolution = Int(ini.value(section: "Settings", key: "InternalResolution") ?? "1")
            defaults.widescreen = (ini.value(section: "Settings", key: "wideScreenHack") ?? "False").lowercased() == "true"

        case .other:
            break
        }
        return defaults
    }

    /// Reads a key the way the user has it: the value from before Attic
    /// set it, while Attic's own value is still there.
    static func usersOwnValue(in current: [String: String], owned: [String: OwnedValue], fallback: @escaping (String) -> String?) -> (String) -> String? {
        { key in
            if let record = owned[key], current[key] == record.written {
                return record.original ?? fallback(key)
            }
            return current[key] ?? fallback(key)
        }
    }

    // MARK: - Shaders

    /// libretro's slang shader pack, which Attic downloads on request.
    public var retroArchShadersDirectory: URL {
        retroArchConfigDirectory.appending(path: "shaders/shaders_slang", directoryHint: .isDirectory)
    }

    /// Where shader packs are looked for: Attic's own, then the one
    /// RetroArch's Online Updater installed in its shader directory.
    public var shaderPackRoots: [URL] {
        var roots = [retroArchShadersDirectory]
        let saved = Self.parseRetroArchConfig((try? String(contentsOf: retroArchConfigFile, encoding: .utf8)) ?? "")
        if let directory = saved["video_shader_dir"], !directory.isEmpty, !directory.hasPrefix(":") {
            let expanded = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
            roots += [expanded.appending(path: "shaders_slang", directoryHint: .isDirectory), expanded]
        }
        return roots
    }

    /// The first shader pack found, for listing its presets.
    public var shaderPackRoot: URL? {
        shaderPackRoots.first { FileManager.default.fileExists(atPath: $0.appending(path: "crt").path) }
    }

    /// A preset path as `SystemSettings.shaderPreset` stores it: absolute
    /// for the user's own files, else relative to a shader pack.
    public func shaderPresetURL(forPath path: String) -> URL? {
        let candidates = path.hasPrefix("/")
            ? [URL(fileURLWithPath: path)]
            : shaderPackRoots.map { $0.appending(path: path) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The preset file for `look`, or `nil` when no shader pack has it.
    public func shaderPresetURL(for look: SystemSettings.Look) -> URL? {
        SystemSettingsSupport.shaderPreset(for: look).flatMap(shaderPresetURL(forPath:))
    }

    /// RetroArch's `--set-shader` for these settings: the chosen preset,
    /// else the look's; an empty path turns shaders off for the run. No
    /// arguments when nothing was chosen or the preset can't be found.
    public func retroArchShaderArguments(for settings: SystemSettings) -> [String] {
        if let path = settings.shaderPreset {
            return shaderPresetURL(forPath: path).map { ["--set-shader", $0.path] } ?? []
        }
        guard let look = settings.look else { return [] }
        if look == .none { return ["--set-shader", ""] }
        return shaderPresetURL(for: look).map { ["--set-shader", $0.path] } ?? []
    }

    /// When the buildbot built the shader pack Attic downloaded.
    public struct ShaderPackInfo: Codable, Sendable {
        public var build: Date
        public init(build: Date) { self.build = build }
    }

    private var shaderPackInfoFile: URL {
        retroArchShadersDirectory.deletingLastPathComponent().appending(path: "attic-shaders.json")
    }

    public var shaderPackInfo: ShaderPackInfo? {
        guard FileManager.default.fileExists(atPath: retroArchShadersDirectory.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: shaderPackInfoFile)).flatMap { try? decoder.decode(ShaderPackInfo.self, from: $0) }
    }

    public func setShaderPackInfo(_ info: ShaderPackInfo) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: shaderPackInfoFile, options: .atomic)
    }

    /// Settings Attic owns in an emulator's config: what it last wrote,
    /// and the user's own value from before, to put back when it stops.
    public struct OwnedValue: Codable, Hashable, Sendable {
        public var written: String
        public var original: String?
    }

    /// Like `OwnedSettings.reconcile`, but a key Attic stops setting goes
    /// back to the user's own value instead of a fixed default.
    static func reconcileKeepingOriginals(
        desired: [(key: String, value: String)],
        owned: [String: OwnedValue],
        current: [String: String],
        fallback: (String) -> String?
    ) -> (write: [(key: String, value: String)], owned: [String: OwnedValue]) {
        var write = desired
        var newOwned: [String: OwnedValue] = [:]
        for (key, value) in desired {
            // The user's own value is what was there before Attic set it —
            // unless they've changed it since, in the emulator.
            let original = owned[key].map { current[key] == $0.written ? $0.original : current[key] } ?? current[key]
            newOwned[key] = OwnedValue(written: value, original: original)
        }
        for (key, record) in owned.sorted(by: { $0.key < $1.key }) where newOwned[key] == nil && current[key] == record.written {
            if let reset = record.original ?? fallback(key) { write.append((key, reset)) }
        }
        return (write, newOwned)
    }

    // MARK: - RetroArch controller settings

    static let playerPorts = 1...4

    /// An axis number the `mfi` driver doesn't have (it reports six), so a
    /// bind to it never fires.
    static let deadAxis = "+9"

    /// What Attic wants in RetroArch's config for `controller`. Anything
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

    /// RetroArch's own default for a key Attic stops setting; `nil`
    /// leaves the key as it is.
    static func retroArchResetValue(_ key: String) -> String? {
        if key.hasSuffix("_btn") || key.hasSuffix("_axis") { return "nul" }
        if key.hasSuffix("_analog_dpad_mode") || key == "input_quit_gamepad_combo" { return "0" }
        return nil
    }

    // MARK: - Settings Attic wrote into emulators' configs

    private func ownedSettingsFile(_ emulator: String) -> URL {
        config.appending(path: "Attic/\(emulator)-settings-written.json")
    }

    func readOwnedSettings(_ emulator: String) -> [String: String]? {
        (try? Data(contentsOf: ownedSettingsFile(emulator))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    func writeOwnedSettings(_ settings: [String: String], for emulator: String) throws {
        try writeOwned(settings, for: emulator)
    }

    func readOwned<Value: Decodable>(_ emulator: String) -> Value? {
        (try? Data(contentsOf: ownedSettingsFile(emulator))).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    func writeOwned<Value: Encodable>(_ value: Value, for emulator: String) throws {
        let file = ownedSettingsFile(emulator)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: file, options: .atomic)
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

    /// Starts Attic's RetroArch config from the user's existing one, so
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
        buttonMapping: ButtonMapping = .default,
        systemSettings: SystemSettings = SystemSettings()
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
        if emulator.id == EmulatorCatalog.duckStation.id {
            try applyDuckStationSettings(systemSettings, to: &ini)
        }
        try ini.contents.write(to: settingsFile, atomically: true, encoding: .utf8)
        return ["HOME": home.path]
    }

    /// Binds the emulator's pad to `mapping` when it isn't the default,
    /// and puts back the default bindings Attic replaced once it is again
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

    /// System Settings for DuckStation. One it stops setting is removed
    /// (back to DuckStation's default) if it still has Attic's value.
    private func applyDuckStationSettings(_ settings: SystemSettings, to ini: inout IniFile) throws {
        let previous = readOwnedSettings("duckstation-system") ?? [:]
        var written: [String: String] = [:]
        for setting in SystemSettingsSupport.duckStationSettings(settings) {
            let id = "\(setting.section)/\(setting.key)"
            if let value = setting.value {
                ini.set(section: setting.section, key: setting.key, value: value)
                written[id] = value
            } else if let old = previous[id], ini.value(section: setting.section, key: setting.key) == old {
                ini.remove(section: setting.section, key: setting.key)
            }
        }
        try writeOwnedSettings(written, for: "duckstation-system")
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
