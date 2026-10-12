import Foundation
import Observation
import AtticEmulation

/// libretro's slang shader pack, which System Settings' looks and the
/// shader library use: where it comes from, downloading it, and whether
/// Attic's copy has an update.
@Observable
@MainActor
final class ShaderPackStore {
    /// Settings › Emulators › "Retro look by default".
    static let retroLookByDefaultKey = "retroLookByDefault"

    enum Source: Equatable {
        /// Downloaded by Attic into the Emulation folder; `build` is when
        /// libretro built it.
        case attic(build: Date?)
        /// RetroArch's own, installed by its Online Updater.
        case retroArch(URL)
        case missing
    }

    private let emulationFolderStore: EmulationFolderStore
    private(set) var isDownloading = false
    private(set) var isCheckingForUpdate = false
    private(set) var updateAvailable = false
    private(set) var lastError: String?
    /// Bumped whenever the pack changes on disk, so views re-read it.
    private(set) var revision = 0

    init(emulationFolderStore: EmulationFolderStore) {
        self.emulationFolderStore = emulationFolderStore
    }

    private var folder: EmulationFolder { emulationFolderStore.folder }

    var source: Source {
        _ = revision
        guard let root = folder.shaderPackRoot else { return .missing }
        if root == folder.retroArchShadersDirectory { return .attic(build: folder.shaderPackInfo?.build) }
        return .retroArch(root)
    }

    /// Every preset in the pack in use, by folder.
    var presetGroups: [ShaderPresetGroup] {
        _ = revision
        return folder.shaderPackRoot.map(ShaderLibrary.presets(in:)) ?? []
    }

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        lastError = nil
        defer {
            isDownloading = false
            revision += 1
        }
        do {
            // Read before downloading, so a build published meanwhile is
            // never recorded as the one installed.
            let build = try? await ShaderPackUpdateChecker.fetchLatestBuildDate()
            try await EmulatorInstaller(paths: folder.installerPaths).installShaderPack(into: folder.retroArchShadersDirectory)
            try folder.setShaderPackInfo(.init(build: build ?? .now))
            updateAvailable = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Only Attic's own copy is checked: RetroArch updates its pack itself.
    func checkForUpdate() async {
        guard case .attic(let build?) = source, !isCheckingForUpdate else { return }
        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }
        guard let commit = try? await ShaderPackUpdateChecker.fetchLatestCommitDate(),
              let latestBuild = try? await ShaderPackUpdateChecker.fetchLatestBuildDate() else { return }
        updateAvailable = ShaderPackUpdateChecker.isUpdateAvailable(installedBuild: build, latestCommit: commit, latestBuild: latestBuild)
    }
}
