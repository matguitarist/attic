import Foundation
import Observation
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// Drives emulator installs from the UI: RetroArch, its cores, and
/// standalone emulators — then wires each result up as a system's default
/// launch target so games become playable without a trip through Settings.
///
/// Every install downloads straight from upstream (see `EmulatorInstaller`);
/// BIOS files are never downloaded, only checked for.
@Observable
@MainActor
final class EmulatorSetupCoordinator {
    /// Install task keys currently running → a label for the UI.
    private(set) var activeInstalls: [String: String] = [:]
    private(set) var lastError: String?

    private let emulationFolderStore: EmulationFolderStore

    init(emulationFolderStore: EmulationFolderStore) {
        self.emulationFolderStore = emulationFolderStore
    }

    /// Rebuilt per use so it always targets the current Emulation folder.
    private var installer: EmulatorInstaller {
        EmulatorInstaller(paths: emulationFolderStore.folder.installerPaths)
    }

    var isBusy: Bool { !activeInstalls.isEmpty }

    func isInstalling(_ key: String) -> Bool { activeInstalls[key] != nil }

    nonisolated static func key(forCore coreIdentifier: String) -> String { "core:\(coreIdentifier)" }
    nonisolated static func key(forStandalone emulator: StandaloneEmulator) -> String { "app:\(emulator.id)" }
    static let retroArchKey = "retroarch"

    // MARK: - Options

    /// One installable choice for a system, best first.
    enum InstallOption: Identifiable, Hashable {
        case core(RecommendedCore)
        case standalone(StandaloneEmulator)

        var id: String {
            switch self {
            case .core(let core): EmulatorSetupCoordinator.key(forCore: core.coreIdentifier)
            case .standalone(let emulator): EmulatorSetupCoordinator.key(forStandalone: emulator)
            }
        }

        var name: String {
            switch self {
            case .core(let core): core.displayName
            case .standalone(let emulator): emulator.name
            }
        }

        var needsRetroArch: Bool {
            if case .core = self { return true }
            return false
        }

        var kindLabel: String {
            switch self {
            case .core: String(localized: "RetroArch core")
            case .standalone: String(localized: "Standalone app")
            }
        }

        var summary: String {
            switch self {
            case .core(let core): core.summary
            case .standalone(let emulator): emulator.summary
            }
        }
    }

    /// The catalog's curated picks for a system, best first.
    func installOptions(for systemID: CanonicalSystemID) -> [InstallOption] {
        guard let recommendation = EmulatorCatalog.recommendation(for: systemID) else { return [] }
        let cores = recommendation.cores.map(InstallOption.core)
        let standalone = recommendation.standalone.map(InstallOption.standalone)
        return recommendation.prefersStandalone ? standalone + cores : cores + standalone
    }

    /// Every other core libretro publishes for this Mac that runs the
    /// system — the long tail behind the curated picks.
    func otherCoreOptions(for systemID: CanonicalSystemID, retroArchStore: RetroArchSettingsStore) -> [InstallOption] {
        let curated = Set(EmulatorCatalog.recommendation(for: systemID)?.cores.map(\.coreIdentifier) ?? [])
        let available = retroArchStore.availableCores(for: systemID).filter { !curated.contains($0.coreIdentifier) }
        var options = available.map { InstallOption.core(RecommendedCore($0.coreIdentifier, $0.displayName, "")) }
        // A core the user installed themselves that isn't in the arm64
        // availability list still belongs here, so it can be picked.
        let listed = curated.union(available.map(\.coreIdentifier))
        for core in retroArchStore.cores(for: systemID) where !listed.contains(core.coreIdentifier) {
            options.append(.core(RecommendedCore(core.coreIdentifier, core.displayName, "")))
        }
        return options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func install(
        _ option: InstallOption,
        for systems: [GameSystem],
        makeDefault: Bool,
        retroArchStore: RetroArchSettingsStore,
        profiles: [EmulatorProfile],
        modelContext: ModelContext
    ) async {
        // Already on disk: just assign it — no point re-downloading.
        if isInstalled(option, retroArchStore: retroArchStore), retroArchStore.isInstalled || !option.needsRetroArch {
            assign(option, to: systems, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
            return
        }
        switch option {
        case .core(let core):
            await installCore(core, for: systems, makeDefault: makeDefault, retroArchStore: retroArchStore, profiles: profiles)
        case .standalone(let emulator):
            await installStandalone(emulator, for: systems, makeDefault: makeDefault, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
        }
    }

    private func assign(
        _ option: InstallOption,
        to systems: [GameSystem],
        retroArchStore: RetroArchSettingsStore,
        profiles: [EmulatorProfile],
        modelContext: ModelContext
    ) {
        let target: LaunchTargetReference
        switch option {
        case .core(let core):
            target = .retroArchCore(coreIdentifier: core.coreIdentifier)
        case .standalone(let emulator):
            guard let appURL = installer.installedAppURL(for: emulator) else { return }
            target = .emulatorProfile(id: profile(for: emulator, appURL: appURL, existing: profiles, modelContext: modelContext).id)
        }
        for system in systems { system.defaultLaunchTarget = target }
        try? modelContext.save()
    }

    func isInstalled(_ option: InstallOption, retroArchStore: RetroArchSettingsStore) -> Bool {
        switch option {
        case .core(let core): retroArchStore.core(withIdentifier: core.coreIdentifier) != nil
        case .standalone(let emulator): isStandaloneInstalled(emulator)
        }
    }

    // MARK: - Status

    enum SystemStatus: Equatable {
        /// Default target set and actually launchable.
        case ready(String)
        /// A default is set, but its core/app is gone.
        case broken(String)
        case notSetUp

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    func status(of system: GameSystem, retroArchStore: RetroArchSettingsStore, profiles: [EmulatorProfile]) -> SystemStatus {
        switch system.defaultLaunchTarget {
        case .none:
            return .notSetUp
        case .retroArchCore(let identifier)?:
            guard let core = retroArchStore.core(withIdentifier: identifier) else {
                return .broken(String(localized: "The \(identifier) core isn't installed."))
            }
            guard retroArchStore.isInstalled else { return .broken(String(localized: "RetroArch isn't installed.")) }
            return .ready(core.displayName)
        case .emulatorProfile(let id)?:
            guard let profile = profiles.first(where: { $0.id == id }) else {
                return .broken(String(localized: "Its custom emulator was deleted."))
            }
            guard FileManager.default.fileExists(atPath: profile.executablePath) else {
                return .broken("\(profile.name) isn't installed anymore.")
            }
            return .ready(profile.name)
        }
    }

    /// Required BIOS files for the system's chosen core (or, with none
    /// chosen, its recommended one) that aren't in the Emulation folder's
    /// BIOS directory (which every emulator Attic launches is pointed at).
    func missingBIOS(for system: GameSystem) -> [BIOSRequirement] {
        let systemDirectory = emulationFolderStore.folder.bios
        return Self.biosRequirements(for: system).filter { requirement in
            requirement.required && !FileManager.default.fileExists(atPath: systemDirectory.appending(path: requirement.fileName).path)
        }
    }

    /// The system's BIOS files as its chosen core needs them.
    static func biosRequirements(for system: GameSystem) -> [BIOSRequirement] {
        guard let recommendation = EmulatorCatalog.recommendation(for: system.systemID) else { return [] }
        if case .retroArchCore(let identifier) = system.defaultLaunchTarget {
            return recommendation.bios(forCore: identifier)
        }
        return recommendation.bios
    }

    var biosDirectoryPath: String {
        (emulationFolderStore.folder.bios.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Installs

    func installRetroArch(retroArchStore: RetroArchSettingsStore) async {
        await run(Self.retroArchKey, label: String(localized: "Installing RetroArch…"), failure: String(localized: "Couldn't install RetroArch")) {
            let appURL = try await self.installer.installRetroArch()
            retroArchStore.installURL = appURL
            retroArchStore.refresh()
        }
    }

    /// Installs `core` (plus RetroArch and the core info files if missing)
    /// and makes it the default for each of `systems` that doesn't already
    /// have a working emulator — or for all of them when `makeDefault`.
    func installCore(
        _ core: RecommendedCore,
        for systems: [GameSystem],
        makeDefault: Bool,
        retroArchStore: RetroArchSettingsStore,
        profiles: [EmulatorProfile]
    ) async {
        if !retroArchStore.isInstalled {
            await installRetroArch(retroArchStore: retroArchStore)
            guard retroArchStore.isInstalled else { return }
        }
        await run(Self.key(forCore: core.coreIdentifier), label: String(localized: "Installing \(core.displayName)…"), failure: String(localized: "Couldn't install \(core.displayName)")) {
            try await self.ensureCoreInfoFiles()
            try await self.installer.installCore(core.coreIdentifier)
            retroArchStore.refresh()
            for system in systems where makeDefault || !self.hasWorkingDefault(system, retroArchStore: retroArchStore, profiles: profiles) {
                system.defaultLaunchTarget = .retroArchCore(coreIdentifier: core.coreIdentifier)
            }
            try systems.first?.modelContext?.save()
        }
    }

    /// Installs a standalone emulator, creates (or reuses) a custom
    /// emulator profile for it, and assigns it like `installCore` does.
    func installStandalone(
        _ emulator: StandaloneEmulator,
        for systems: [GameSystem],
        makeDefault: Bool,
        retroArchStore: RetroArchSettingsStore,
        profiles: [EmulatorProfile],
        modelContext: ModelContext
    ) async {
        await run(Self.key(forStandalone: emulator), label: String(localized: "Installing \(emulator.name)…"), failure: String(localized: "Couldn't install \(emulator.name)")) {
            let appURL = try await self.installer.installStandalone(emulator)
            let profile = self.profile(for: emulator, appURL: appURL, existing: profiles, modelContext: modelContext)
            for system in systems where makeDefault || !self.hasWorkingDefault(system, retroArchStore: retroArchStore, profiles: profiles) {
                system.defaultLaunchTarget = .emulatorProfile(id: profile.id)
            }
            try modelContext.save()
        }
    }

    /// One click for the whole library: installs the best option for every
    /// system that has no working emulator yet. Systems that already work
    /// are left alone.
    func setUpAllSystems(
        _ systems: [GameSystem],
        retroArchStore: RetroArchSettingsStore,
        profiles: [EmulatorProfile],
        modelContext: ModelContext
    ) async {
        let needingSetup = systems.filter { !hasWorkingDefault($0, retroArchStore: retroArchStore, profiles: profiles) }
        for system in needingSetup {
            guard let recommendation = EmulatorCatalog.recommendation(for: system.systemID) else { continue }
            if recommendation.prefersStandalone, let emulator = recommendation.standalone.first {
                await installStandalone(emulator, for: [system], makeDefault: true, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
            } else if let core = recommendation.recommendedCore {
                await installCore(core, for: [system], makeDefault: true, retroArchStore: retroArchStore, profiles: profiles)
            }
        }
    }

    func systemsNeedingSetup(_ systems: [GameSystem], retroArchStore: RetroArchSettingsStore, profiles: [EmulatorProfile]) -> [GameSystem] {
        systems.filter { !hasWorkingDefault($0, retroArchStore: retroArchStore, profiles: profiles) }
    }

    func isStandaloneInstalled(_ emulator: StandaloneEmulator) -> Bool {
        installer.installedAppURL(for: emulator) != nil
    }

    func dismissError() { lastError = nil }

    // MARK: - Core updates

    private static let lastCoreUpdateCheckKey = "lastCoreUpdateCheck"

    /// Keyed by core identifier; only cores that have been checked.
    private(set) var coreUpdateStatuses: [String: CoreUpdateStatus] = [:]
    private(set) var isCheckingForCoreUpdates = false
    private(set) var lastCoreUpdateCheck: Date? = UserDefaults.standard.object(forKey: lastCoreUpdateCheckKey) as? Date
    private var remoteCoreChecksums: [String: UInt32] = [:]

    func coresWithUpdates(retroArchStore: RetroArchSettingsStore) -> [RetroArchCoreInfo] {
        retroArchStore.cores.filter { coreUpdateStatuses[$0.coreIdentifier] == .updateAvailable }
    }

    /// Compares every installed core — Attic's and RetroArch's own —
    /// against the buildbot's checksums.
    /// `quiet` (the automatic launch check) keeps network failures out of
    /// the error alert — being offline at launch isn't worth interrupting for.
    func checkForCoreUpdates(retroArchStore: RetroArchSettingsStore, quiet: Bool = false) async {
        guard !isCheckingForCoreUpdates else { return }
        isCheckingForCoreUpdates = true
        defer { isCheckingForCoreUpdates = false }
        do {
            remoteCoreChecksums = try await installer.fetchRemoteCoreChecksums()
        } catch {
            if !quiet { lastError = String(localized: "Couldn't check for core updates: \(error.localizedDescription)") }
            return
        }
        await recomputeStatuses(for: retroArchStore.cores)
        lastCoreUpdateCheck = .now
        UserDefaults.standard.set(Date.now, forKey: Self.lastCoreUpdateCheckKey)
    }

    /// Once a day at most, quietly — called at launch.
    func checkForCoreUpdatesIfDue(retroArchStore: RetroArchSettingsStore) async {
        if let last = lastCoreUpdateCheck, Date.now.timeIntervalSince(last) < 24 * 3600 {
            // Still show what was found last time, from fresh local CRCs.
            if remoteCoreChecksums.isEmpty, let checksums = try? await installer.fetchRemoteCoreChecksums() {
                remoteCoreChecksums = checksums
                await recomputeStatuses(for: retroArchStore.cores)
            }
            return
        }
        await checkForCoreUpdates(retroArchStore: retroArchStore, quiet: true)
    }

    /// Downloads the current build into the Emulation folder's Cores. For a
    /// core that lived in RetroArch's own folder, the new copy shadows the
    /// old one (Attic's folder is indexed first) — RetroArch's folder is
    /// often inside its sandbox container, which Attic doesn't write to.
    func updateCore(_ core: RetroArchCoreInfo, retroArchStore: RetroArchSettingsStore) async {
        await run(Self.key(forCore: core.coreIdentifier), label: String(localized: "Updating \(core.displayName)…"), failure: String(localized: "Couldn't update \(core.displayName)")) {
            try await self.installer.installCore(core.coreIdentifier)
            retroArchStore.refresh()
            if let updated = retroArchStore.core(withIdentifier: core.coreIdentifier) {
                await self.recomputeStatuses(for: [updated])
            }
        }
    }

    func updateAllCores(retroArchStore: RetroArchSettingsStore) async {
        for core in coresWithUpdates(retroArchStore: retroArchStore) {
            await updateCore(core, retroArchStore: retroArchStore)
        }
    }

    /// CRCs a few megabytes per core, so off the main actor.
    private func recomputeStatuses(for cores: [RetroArchCoreInfo]) async {
        let remote = remoteCoreChecksums
        let inputs = cores.map { ($0.coreIdentifier, $0.dylibURL) }
        let results = await Task.detached(priority: .utility) {
            inputs.map { ($0.0, CoreUpdateChecker.status(ofCoreAt: $0.1, coreIdentifier: $0.0, remoteChecksums: remote)) }
        }.value
        for (identifier, status) in results {
            coreUpdateStatuses[identifier] = status
        }
    }

    // MARK: - Helpers

    private func hasWorkingDefault(_ system: GameSystem, retroArchStore: RetroArchSettingsStore, profiles: [EmulatorProfile]) -> Bool {
        if case .ready = status(of: system, retroArchStore: retroArchStore, profiles: profiles) { return true }
        return false
    }

    private var didInstallCoreInfo = false

    /// Keeps the "All Cores" menus current: re-downloads libretro's core
    /// info and arm64 availability list when missing or over a week old.
    /// Quiet on failure (offline is fine — the menus just use what's there).
    func refreshCoreCatalogIfStale(retroArchStore: RetroArchSettingsStore) async {
        let availabilityFile = emulationFolderStore.folder.coreInfo.appending(path: AvailableCoreIndex.availabilityFileName)
        let modified = (try? FileManager.default.attributesOfItem(atPath: availabilityFile.path))?[.modificationDate] as? Date
        guard modified.map({ Date.now.timeIntervalSince($0) > 7 * 24 * 3600 }) ?? true else { return }
        guard (try? await installer.installCoreInfoFiles()) != nil else { return }
        didInstallCoreInfo = true
        retroArchStore.refresh()
    }

    /// Fetched once per session — cheap insurance that the info files
    /// (which say which system each core runs) match the cores just
    /// downloaded from the same nightly buildbot.
    private func ensureCoreInfoFiles() async throws {
        guard !didInstallCoreInfo else { return }
        try await installer.installCoreInfoFiles()
        didInstallCoreInfo = true
    }

    private func profile(for emulator: StandaloneEmulator, appURL: URL, existing: [EmulatorProfile], modelContext: ModelContext) -> EmulatorProfile {
        let executableURL = appURL.appending(path: emulator.executableRelativePath)
        // Matched by catalog ID or path — never by name, so a profile the
        // user made for their own copy (e.g. DuckStation in /Applications)
        // isn't silently repointed at the portable install.
        if let match = existing.first(where: { $0.catalogEmulatorID == emulator.id || $0.executablePath == executableURL.path }) {
            match.executablePath = executableURL.path
            match.catalogEmulatorID = emulator.id
            for systemID in emulator.systems where !match.assignedSystemIDs.contains(systemID) {
                match.assignedSystemIDs.append(systemID)
            }
            return match
        }
        let profile = EmulatorProfile(
            name: emulator.name,
            executableURL: executableURL,
            argumentTemplate: emulator.argumentTemplate,
            assignedSystemIDs: emulator.systems
        )
        profile.catalogEmulatorID = emulator.id
        modelContext.insert(profile)
        return profile
    }

    private func run(_ key: String, label: String, failure: String, _ work: @MainActor () async throws -> Void) async {
        guard activeInstalls[key] == nil else { return }
        activeInstalls[key] = label
        defer { activeInstalls.removeValue(forKey: key) }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = "\(failure): \(error.localizedDescription)"
        }
    }
}
