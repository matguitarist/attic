import Foundation

/// Fetches a remote file to a temporary local URL. Abstracted so installer
/// tests can hand back local fixture archives instead of hitting the network.
public protocol FileDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

public struct URLSessionDownloader: FileDownloading {
    public init() {}

    public func download(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EmulatorInstaller.InstallError.downloadFailed(url: url, statusCode: http.statusCode)
        }
        // URLSession deletes its temp file once this call returns — move it
        // somewhere that survives until the caller extracts it.
        let keptURL = FileManager.default.temporaryDirectory.appending(path: "romsbox-\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: temporaryURL, to: keptURL)
        return keptURL
    }
}

/// Installs emulators from their official distribution points: RetroArch
/// and its cores from libretro's buildbot, standalone emulators from their
/// GitHub releases. RomsBox redistributes none of them — every install is
/// a fresh download from upstream, just as if the user had fetched it.
///
/// Cores go into the Emulation folder's cores directory rather than RetroArch's,
/// and get launched with `-L <path>`. RetroArch's directory is frequently a
/// symlink into its sandbox container (left behind by a Mac App Store
/// install), and writing into another app's container triggers macOS's
/// "access data from other apps" prompt; the website build of RetroArch
/// disables library validation and isn't sandboxed, so it loads cores from
/// anywhere.
public struct EmulatorInstaller: Sendable {
    public struct Paths: Sendable {
        public let coresDirectory: URL
        public let coreInfoDirectory: URL
        public let applicationsDirectory: URL

        public init(coresDirectory: URL, coreInfoDirectory: URL, applicationsDirectory: URL) {
            self.coresDirectory = coresDirectory
            self.coreInfoDirectory = coreInfoDirectory
            self.applicationsDirectory = applicationsDirectory
        }
    }

    public enum InstallError: LocalizedError, Equatable {
        case downloadFailed(url: URL, statusCode: Int)
        case extractionFailed(String)
        case missingFileInArchive(String)
        case retroArchVersionNotFound
        case releaseNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .downloadFailed(let url, let statusCode):
                String(localized: "Download failed (HTTP \(statusCode)): \(url.lastPathComponent)", bundle: .module)
            case .extractionFailed(let detail):
                String(localized: "Couldn't unpack the download: \(detail)", bundle: .module)
            case .missingFileInArchive(let name):
                String(localized: "The download didn't contain \(name).", bundle: .module)
            case .retroArchVersionNotFound:
                String(localized: "Couldn't find the latest RetroArch release on libretro's site.", bundle: .module)
            case .releaseNotFound(let name):
                String(localized: "Couldn't find the latest \(name) release for macOS.", bundle: .module)
            }
        }
    }

    public let paths: Paths
    private let downloader: FileDownloading

    public init(paths: Paths, downloader: FileDownloading = URLSessionDownloader()) {
        self.paths = paths
        self.downloader = downloader
    }

    // MARK: - RetroArch cores

    /// Downloads one core into RomsBox's cores directory, replacing any
    /// older copy. Returns the installed dylib.
    @discardableResult
    @concurrent public func installCore(_ coreIdentifier: String) async throws -> URL {
        let archive = try await downloader.download(from: EmulatorCatalog.coreDownloadURL(for: coreIdentifier))
        defer { try? FileManager.default.removeItem(at: archive) }

        let fileName = "\(coreIdentifier).dylib"
        let staging = try extractToStaging(archive, near: paths.coresDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }

        let extracted = staging.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw InstallError.missingFileInArchive(fileName)
        }
        return try moveIntoPlace(extracted, in: paths.coresDirectory)
    }

    /// Downloads every core's `.info` file. RomsBox reads these to learn
    /// each core's system and supported extensions, and RetroArch's own
    /// info directory is often empty on a fresh install.
    @concurrent public func installCoreInfoFiles() async throws {
        let archive = try await downloader.download(from: EmulatorCatalog.coreInfoArchiveURL)
        defer { try? FileManager.default.removeItem(at: archive) }

        let staging = try extractToStaging(archive, near: paths.coreInfoDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }

        let infoFiles = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "info" } ?? []
        guard !infoFiles.isEmpty else { throw InstallError.missingFileInArchive("any .info files") }
        for file in infoFiles {
            try moveIntoPlace(file, in: paths.coreInfoDirectory)
        }
        try? await saveAvailableCoreList()
    }

    /// Records which cores the buildbot actually has for Apple Silicon, so
    /// "All Cores" menus only offer installable ones. Best-effort: without
    /// it, `AvailableCoreIndex` just lists every core the info files know.
    private func saveAvailableCoreList() async throws {
        let index = try await downloader.download(from: EmulatorCatalog.buildbotCoresURL)
        defer { try? FileManager.default.removeItem(at: index) }
        let identifiers = AvailableCoreIndex.coreIdentifiers(inBuildbotIndex: (try? String(contentsOf: index, encoding: .utf8)) ?? "")
        guard !identifiers.isEmpty else { return }
        try (identifiers.joined(separator: "\n") + "\n")
            .write(to: paths.coreInfoDirectory.appending(path: AvailableCoreIndex.availabilityFileName), atomically: true, encoding: .utf8)
    }

    /// Downloads the buildbot's current CRC32 for every core.
    @concurrent public func fetchRemoteCoreChecksums() async throws -> [String: UInt32] {
        let index = try await downloader.download(from: EmulatorCatalog.buildbotCoreChecksumsURL)
        defer { try? FileManager.default.removeItem(at: index) }
        return CoreUpdateChecker.remoteChecksums(inIndexExtended: try String(contentsOf: index, encoding: .utf8))
    }

    public func isCoreInstalled(_ coreIdentifier: String) -> Bool {
        FileManager.default.fileExists(atPath: paths.coresDirectory.appending(path: "\(coreIdentifier).dylib").path)
    }

    // MARK: - Standalone emulators

    /// Each standalone emulator gets its own folder (`Emulators/<Name>/`).
    public func appDirectory(for emulator: StandaloneEmulator) -> URL {
        paths.applicationsDirectory.appending(path: emulator.name, directoryHint: .isDirectory)
    }

    /// The copy in the Emulation folder, or — only for emulators without a
    /// portable setup — one the user installed in /Applications or
    /// ~/Applications. For portable emulators a copy elsewhere keeps its
    /// data in ~/Library, so it isn't the install RomsBox manages; for the
    /// others the data lives in ~/Library either way, so any copy will do.
    public func installedAppURL(for emulator: StandaloneEmulator) -> URL? {
        var candidates = [appDirectory(for: emulator)]
        if emulator.portableHome == nil {
            candidates += [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
            ]
        }
        return candidates
            .map { $0.appending(path: emulator.appBundleName) }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: emulator.executableRelativePath).path) }
    }

    @discardableResult
    @concurrent public func installStandalone(_ emulator: StandaloneEmulator) async throws -> URL {
        let destination = appDirectory(for: emulator)
        let staging: URL
        switch emulator.archive {
        case .zip:
            let archive = try await downloader.download(from: emulator.downloadURL)
            defer { try? FileManager.default.removeItem(at: archive) }
            staging = try extractToStaging(archive, near: destination)
        case .dolphinReleaseFeed:
            let feed = try await downloader.download(from: emulator.downloadURL)
            defer { try? FileManager.default.removeItem(at: feed) }
            guard let dmgURL = Self.macOSDiskImageURL(inDolphinReleaseFeed: try Data(contentsOf: feed)) else {
                throw InstallError.releaseNotFound(emulator.name)
            }
            let dmg = try await downloader.download(from: dmgURL)
            defer { try? FileManager.default.removeItem(at: dmg) }
            staging = try Self.copyApp(named: emulator.appBundleName, fromDiskImage: dmg, near: destination)
        }
        defer { try? FileManager.default.removeItem(at: staging) }

        let app = staging.appending(path: emulator.appBundleName)
        guard FileManager.default.fileExists(atPath: app.appending(path: emulator.executableRelativePath).path) else {
            throw InstallError.missingFileInArchive(emulator.appBundleName)
        }
        return try moveIntoPlace(app, in: destination)
    }

    // MARK: - RetroArch itself

    /// Installs the latest stable RetroArch (Metal build) from libretro's
    /// buildbot into `retroArchInstallDirectory`.
    @discardableResult
    @concurrent public func installRetroArch() async throws -> URL {
        let indexURL = try await downloader.download(from: EmulatorCatalog.retroArchStableIndexURL)
        defer { try? FileManager.default.removeItem(at: indexURL) }
        let indexHTML = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        guard let version = Self.latestStableVersion(inBuildbotIndex: indexHTML) else {
            throw InstallError.retroArchVersionNotFound
        }

        let dmg = try await downloader.download(from: EmulatorCatalog.retroArchDownloadURL(version: version))
        defer { try? FileManager.default.removeItem(at: dmg) }

        let destination = Self.retroArchInstallDirectory
        let staging = try Self.copyApp(named: "RetroArch.app", fromDiskImage: dmg, near: destination)
        defer { try? FileManager.default.removeItem(at: staging) }
        return try moveIntoPlace(staging.appending(path: "RetroArch.app"), in: destination)
    }

    /// Mounts `dmg` read-only and copies `appName` off it into a new
    /// staging directory near `destination` (returned), so a failure never
    /// leaves a half-copied app in place.
    private static func copyApp(named appName: String, fromDiskImage dmg: URL, near destination: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory.appending(path: "romsbox-dmg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path])
        defer {
            try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: mountPoint)
        }

        let app = mountPoint.appending(path: appName)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw InstallError.missingFileInArchive(appName)
        }
        let staging = try makeStagingDirectory(near: destination)
        do {
            try run("/usr/bin/ditto", [app.path, staging.appending(path: appName).path])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return staging
    }

    /// The macOS download in Dolphin's release feed — the same JSON
    /// Dolphin's own updater reads.
    static func macOSDiskImageURL(inDolphinReleaseFeed data: Data) -> URL? {
        struct Feed: Decodable {
            struct Artifact: Decodable { let system: String; let url: URL }
            let artifacts: [Artifact]
        }
        return (try? JSONDecoder().decode(Feed.self, from: data))?.artifacts
            .first { $0.system.hasPrefix("macOS") && $0.url.pathExtension == "dmg" }?
            .url
    }

    /// RetroArch is a regular app the user may also open on its own, so it
    /// goes where Mac apps live — /Applications when writable (it is for
    /// admin users), else ~/Applications — not into the Emulation folder.
    /// Only its *config* moves there (see `EmulationFolder`).
    public static var retroArchInstallDirectory: URL {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return FileManager.default.isWritableFile(atPath: systemApplications.path)
            ? systemApplications
            : FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    }

    /// The highest `x.y.z` folder linked from the buildbot's /stable/ index.
    static func latestStableVersion(inBuildbotIndex html: String) -> String? {
        let pattern = /href="\/stable\/(\d+)\.(\d+)\.(\d+)\/"/
        return html.matches(of: pattern)
            .map { (Int($0.1)!, Int($0.2)!, Int($0.3)!) }
            .max { $0 < $1 }
            .map { "\($0.0).\($0.1).\($0.2)" }
    }

    // MARK: - Helpers

    /// A scratch directory on the same volume as `destination`, so the
    /// final move into place is a cheap, atomic rename rather than a
    /// cross-volume copy (home folders and /Applications can live on
    /// different volumes from the system temp directory).
    private static func makeStagingDirectory(near destination: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
    }

    private func extractToStaging(_ archive: URL, near destination: URL) throws -> URL {
        let staging = try Self.makeStagingDirectory(near: destination)
        do {
            // ditto, not unzip: it preserves the code signatures, symlinks
            // and extended attributes inside .app bundles.
            try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return staging
    }

    /// Replaces `directory/<item name>` with `item`, creating `directory`
    /// if needed.
    @discardableResult
    private func moveIntoPlace(_ item: URL, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: item.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: item)
        } else {
            try fileManager.moveItem(at: item, to: destination)
        }
        return destination
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw InstallError.extractionFailed(detail.isEmpty ? "\(executable) exited with \(process.terminationStatus)" : detail)
        }
    }
}
