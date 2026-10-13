import Foundation

/// Fetches a remote file to a temporary local URL. Abstracted so installer
/// tests can hand back local fixture archives instead of hitting the network.
public protocol FileDownloading: Sendable {
    func download(from url: URL) async throws -> URL
    /// What identifies the file now at `url` (its ETag or date), to tell a
    /// new build behind a fixed link; nil when unknown.
    func stamp(of url: URL) async -> String?
}

public extension FileDownloading {
    func stamp(of url: URL) async -> String? { nil }
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
        let keptURL = FileManager.default.temporaryDirectory.appending(path: "attic-\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: temporaryURL, to: keptURL)
        return keptURL
    }

    public func stamp(of url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let parts = [http.value(forHTTPHeaderField: "ETag"), http.value(forHTTPHeaderField: "Last-Modified")].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// An emulator's current release upstream: what identifies the build (to
/// tell when there's a newer one) and where to download it.
public struct StandaloneRelease: Sendable, Equatable, Codable {
    /// Changes with every new build.
    public let identity: String
    /// The release's name, when it has one ("v2.8.2").
    public let version: String?
    let downloadURL: URL
    /// The downloaded file's name, which often holds the version too.
    public let fileName: String
}

/// Installs emulators from their official distribution points: RetroArch
/// and its cores from libretro's buildbot, standalone emulators from their
/// GitHub releases. Attic redistributes none of them — every install is
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
        /// RetroArch's system (BIOS) folder, where some cores' support
        /// files go.
        public let systemDirectory: URL?

        public init(coresDirectory: URL, coreInfoDirectory: URL, applicationsDirectory: URL, systemDirectory: URL? = nil) {
            self.coresDirectory = coresDirectory
            self.coreInfoDirectory = coreInfoDirectory
            self.applicationsDirectory = applicationsDirectory
            self.systemDirectory = systemDirectory
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

    // MARK: - Shaders

    /// Downloads libretro's slang shader pack into `directory`, replacing
    /// any older copy.
    @concurrent public func installShaderPack(into directory: URL) async throws {
        let archive = try await downloader.download(from: EmulatorCatalog.slangShadersURL)
        defer { try? FileManager.default.removeItem(at: archive) }
        let staging = try extractToStaging(archive, near: directory)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.fileExists(atPath: staging.appending(path: "crt").path) else {
            throw InstallError.missingFileInArchive("crt")
        }
        _ = try FileManager.default.replaceItemAt(directory, withItemAt: staging)
    }

    // MARK: - RetroArch cores

    /// Downloads one core into Attic's cores directory, replacing any
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
        let installed = try moveIntoPlace(extracted, in: paths.coresDirectory)
        // Best-effort: the core is installed either way, and RetroArch's
        // Online Updater can fetch these too.
        try? await installSystemFiles(forCore: coreIdentifier)
        return installed
    }

    /// The support files some cores need in RetroArch's system folder
    /// (fonts and data for PPSSPP, Dolphin, PCSX2, blueMSX) — open-source
    /// files libretro publishes for RetroArch's "Core System Files"
    /// downloader. Never BIOS files. Only adds files that are missing.
    @concurrent public func installSystemFiles(forCore coreIdentifier: String) async throws {
        guard let systemDirectory = paths.systemDirectory,
              let archiveName = EmulatorCatalog.coreSystemFiles[coreIdentifier] else { return }
        let archive = try await downloader.download(from: EmulatorCatalog.systemFilesURL(archiveName))
        defer { try? FileManager.default.removeItem(at: archive) }
        let staging = try extractToStaging(archive, near: systemDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        try EmulationFolder.copyMissingFiles(from: staging, to: systemDirectory)
    }

    /// Downloads every core's `.info` file. Attic reads these to learn
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
    /// data in ~/Library, so it isn't the install Attic manages; for the
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

    /// The emulator's current release, without downloading it.
    @concurrent public func latestRelease(of emulator: StandaloneEmulator) async throws -> StandaloneRelease {
        switch emulator.archive {
        case .zip:
            // A fixed link to the latest build: its file date tells builds apart.
            let stamp = await downloader.stamp(of: emulator.downloadURL)
            return StandaloneRelease(identity: stamp ?? emulator.downloadURL.absoluteString, version: nil,
                                     downloadURL: emulator.downloadURL, fileName: emulator.downloadURL.lastPathComponent)
        case .dolphinReleaseFeed:
            let feed = try await downloader.download(from: emulator.downloadURL)
            defer { try? FileManager.default.removeItem(at: feed) }
            guard let dmgURL = Self.macOSDiskImageURL(inDolphinReleaseFeed: try Data(contentsOf: feed)) else {
                throw InstallError.releaseNotFound(emulator.name)
            }
            let version = dmgURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "dolphin-", with: "")
            return StandaloneRelease(identity: dmgURL.absoluteString, version: version, downloadURL: dmgURL, fileName: dmgURL.lastPathComponent)
        case .githubRelease(let assetSuffix):
            let feed = try await downloader.download(from: emulator.downloadURL)
            defer { try? FileManager.default.removeItem(at: feed) }
            guard let release = Self.release(inGitHubRelease: try Data(contentsOf: feed), suffix: assetSuffix) else {
                throw InstallError.releaseNotFound(emulator.name)
            }
            return release
        }
    }

    /// The release an emulator was installed from, recorded at install.
    public func installedRelease(of emulator: StandaloneEmulator) -> StandaloneRelease? {
        (try? Data(contentsOf: releaseRecord(for: emulator))).flatMap { try? JSONDecoder().decode(StandaloneRelease.self, from: $0) }
    }

    /// Records `release` as installed, for an emulator installed before
    /// Attic kept track (taken as current).
    public func recordInstalledRelease(_ release: StandaloneRelease, of emulator: StandaloneEmulator) {
        try? JSONEncoder().encode(release).write(to: releaseRecord(for: emulator), options: .atomic)
    }

    private func releaseRecord(for emulator: StandaloneEmulator) -> URL {
        appDirectory(for: emulator).appending(path: ".attic-release.json")
    }

    @discardableResult
    @concurrent public func installStandalone(_ emulator: StandaloneEmulator) async throws -> URL {
        let destination = appDirectory(for: emulator)
        let release = try await latestRelease(of: emulator)
        let asset = try await downloader.download(from: release.downloadURL)
        defer { try? FileManager.default.removeItem(at: asset) }
        let staging: URL
        switch emulator.archive {
        case .zip:
            staging = try extractToStaging(asset, near: destination)
        case .dolphinReleaseFeed:
            staging = try Self.copyApp(named: emulator.appBundleName, fromDiskImage: asset, near: destination)
        case .githubRelease:
            staging = try extractAnyArchive(asset, named: release.fileName, appName: emulator.appBundleName, near: destination)
        }
        defer { try? FileManager.default.removeItem(at: staging) }

        // A bare binary: the archive's contents are the emulator.
        if !emulator.appBundleName.hasSuffix(".app") {
            let executable = staging.appending(path: emulator.executableRelativePath)
            guard FileManager.default.fileExists(atPath: executable.path) else {
                throw InstallError.missingFileInArchive(emulator.executableRelativePath)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let installed = try moveIntoPlace(staging, in: destination, as: emulator.appBundleName)
            recordInstalledRelease(release, of: emulator)
            return installed
        }

        // Archives put the app at the top or inside a folder — look a few
        // levels down rather than relying on each project's layout.
        guard let app = Self.findApp(named: emulator.appBundleName, in: staging),
              FileManager.default.fileExists(atPath: app.appending(path: emulator.executableRelativePath).path) else {
            throw InstallError.missingFileInArchive(emulator.appBundleName)
        }
        let installed = try moveIntoPlace(app, in: destination, as: emulator.appBundleName)
        recordInstalledRelease(release, of: emulator)
        return installed
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
        let mountPoint = FileManager.default.temporaryDirectory.appending(path: "attic-dmg-\(UUID().uuidString)")
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

    /// The download in a GitHub "latest release" API response whose name
    /// ends with `suffix`, skipping debug-symbol builds.
    static func assetURL(inGitHubRelease data: Data, suffix: String) -> URL? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let assets: [Asset]
        }
        return (try? JSONDecoder().decode(Release.self, from: data))?.assets
            .first { matches($0.name, suffix: suffix) && !$0.name.contains("-dbg-") && !$0.name.contains("debug") }?
            .browser_download_url
    }

    /// The asset of a GitHub "latest release" API response whose name ends
    /// with `suffix`, as a release (identified by the asset's ID and date).
    static func release(inGitHubRelease data: Data, suffix: String) -> StandaloneRelease? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let id: Int
                let name: String
                let browser_download_url: URL
                let updated_at: String?
            }
            let tag_name: String?
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let asset = release.assets.first(where: { matches($0.name, suffix: suffix) && !$0.name.contains("-dbg-") && !$0.name.contains("debug") })
        else { return nil }
        return StandaloneRelease(identity: "\(asset.id) \(asset.updated_at ?? "")", version: release.tag_name,
                                 downloadURL: asset.browser_download_url, fileName: asset.name)
    }

    /// `suffix` ends the name; a `*` in it matches anything (a version).
    static func matches(_ name: String, suffix: String) -> Bool {
        guard let star = suffix.firstIndex(of: "*") else { return name.hasSuffix(suffix) }
        let (head, tail) = (String(suffix[..<star]), String(suffix[suffix.index(after: star)...]))
        guard let headRange = name.range(of: head, options: .backwards) else { return false }
        return name[headRange.upperBound...].hasSuffix(tail)
    }

    /// Unpacks a downloaded release into a new staging directory, by its
    /// file name's extension.
    private func extractAnyArchive(_ archive: URL, named name: String, appName: String, near destination: URL) throws -> URL {
        let lowercased = name.lowercased()
        if lowercased.hasSuffix(".zip") {
            return try extractToStaging(archive, near: destination)
        }
        if lowercased.hasSuffix(".dmg") {
            return try Self.copyApp(named: appName, fromDiskImage: archive, near: destination)
        }
        // .7z, .tar.xz, .tar.gz: macOS's bsdtar reads them all.
        let staging = try Self.makeStagingDirectory(near: destination)
        do {
            try Self.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return staging
    }

    static func findApp(named appName: String, in directory: URL, depth: Int = 3) -> URL? {
        let direct = directory.appending(path: appName)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        // A versioned name: "PCSX2-v2.8.2.app" for "PCSX2.app".
        let stem = (appName as NSString).deletingPathExtension
        if let versioned = entries.first(where: { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix(stem + "-") }) {
            return versioned
        }
        guard depth > 0 else { return nil }
        for entry in entries where entry.pathExtension != "app"
            && (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let found = findApp(named: appName, in: entry, depth: depth - 1) { return found }
        }
        return nil
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

    /// Replaces `directory/<name>` (by default the item's own name) with
    /// `item`, creating `directory` if needed.
    @discardableResult
    private func moveIntoPlace(_ item: URL, in directory: URL, as name: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: name ?? item.lastPathComponent)
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
