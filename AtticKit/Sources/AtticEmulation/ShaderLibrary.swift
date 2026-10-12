import Foundation

/// A RetroArch shader preset in a slang shader pack.
public struct ShaderPreset: Sendable, Hashable, Identifiable {
    /// Relative to the pack's root, e.g. "crt/crt-easymode.slangp" — what
    /// `SystemSettings.shaderPreset` stores, so it still resolves when the
    /// pack moves.
    public let relativePath: String

    public var id: String { relativePath }
    public var name: String { ShaderLibrary.displayName(forPreset: relativePath) }

    public init(relativePath: String) {
        self.relativePath = relativePath
    }
}

/// One folder of a shader pack ("crt", "handheld"…).
public struct ShaderPresetGroup: Sendable, Hashable, Identifiable {
    public let folder: String
    public let presets: [ShaderPreset]
    public var id: String { folder }
}

public enum ShaderLibrary {
    /// Folders of shader building blocks and test cases, not presets
    /// anyone would pick.
    static let excludedFolders: Set<String> = ["include", "test", "spec"]

    /// Every `.slangp` preset under `root`, grouped by top-level folder
    /// (presets at the root go in a group named ""), each sorted by name.
    public static func presets(in root: URL) -> [ShaderPresetGroup] {
        let root = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var groups: [String: [ShaderPreset]] = [:]
        for case let file as URL in enumerator where file.pathExtension == "slangp" {
            let relative = String(file.resolvingSymlinksInPath().path.dropFirst(prefix.count))
            let parts = relative.split(separator: "/")
            let folder = parts.count > 1 ? String(parts[0]) : ""
            guard !excludedFolders.contains(folder) else { continue }
            groups[folder, default: []].append(ShaderPreset(relativePath: relative))
        }
        return groups
            .map { ShaderPresetGroup(folder: $0.key, presets: $0.value.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) }
            .sorted { $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
    }

    /// "crt/crt-easymode.slangp" → "crt-easymode"; a preset in a subfolder
    /// keeps it ("presets/crt-plus-signal/my-preset" → "crt-plus-signal/my-preset").
    public static func displayName(forPreset path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        let file = (parts.last ?? path).replacingOccurrences(of: ".slangp", with: "")
        return parts.count > 2 ? parts[1..<(parts.count - 1)].joined(separator: "/") + "/" + file : file
    }
}

/// Whether Attic's copy of libretro's shader pack is out of date.
///
/// The pack on libretro's buildbot is rebuilt every night whether anything
/// changed or not, so its date alone says nothing. What does: the shaders'
/// own repository having commits newer than the build Attic installed, and
/// the buildbot having built them since.
public enum ShaderPackUpdateChecker {
    public static let repositoryCommitsURL = URL(string: "https://api.github.com/repos/libretro/slang-shaders/commits?per_page=1")!

    public static func isUpdateAvailable(installedBuild: Date, latestCommit: Date, latestBuild: Date) -> Bool {
        latestCommit > installedBuild && latestBuild > latestCommit
    }

    /// The committer date of the newest commit, from GitHub's commits API.
    public static func latestCommitDate(inCommitsResponse data: Data) -> Date? {
        struct Commit: Decodable {
            struct Details: Decodable {
                struct Person: Decodable { let date: Date }
                let committer: Person
            }
            let commit: Details
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Commit].self, from: data))?.first?.commit.committer.date
    }

    /// When the buildbot built the pack, from its `Last-Modified` header.
    public static func buildDate(lastModified: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: lastModified)
    }

    /// The buildbot's current build date, without downloading the pack.
    @concurrent public static func fetchLatestBuildDate() async throws -> Date? {
        var request = URLRequest(url: EmulatorCatalog.slangShadersURL)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")).flatMap(buildDate)
    }

    @concurrent public static func fetchLatestCommitDate() async throws -> Date? {
        var request = URLRequest(url: repositoryCommitsURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return latestCommitDate(inCommitsResponse: data)
    }
}
