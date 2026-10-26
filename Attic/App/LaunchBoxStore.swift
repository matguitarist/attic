import Foundation
import Observation
import AtticModels
import AtticScraping

/// LaunchBox's games database, kept offline. Downloaded from LaunchBox
/// (109 MB) the first time a scrape needs it and indexed for the
/// library's systems alone — a tenth of that on disk — then the download
/// goes. Built again when a month old, or when a system it doesn't have
/// comes along.
@Observable
@MainActor
final class LaunchBoxStore {
    enum State: Equatable {
        case idle
        case downloading
        case indexing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var builtAt: Date?
    private(set) var platforms: Set<String> = []
    private(set) var gameCount = 0
    private(set) var fileSize: Int64 = 0

    @ObservationIgnored private var index: LaunchBoxIndex?
    @ObservationIgnored private var building: Task<LaunchBoxIndex, Error>?

    static let maximumAge: TimeInterval = 30 * 24 * 3600

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Attic/LaunchBox", directoryHint: .isDirectory)
    }
    private static var indexURL: URL { folder.appending(path: "launchbox.sqlite") }
    private static var manifestURL: URL { folder.appending(path: "launchbox.json") }

    /// What the index holds, beside it.
    private struct Manifest: Codable {
        let built: Date
        let platforms: [String]
    }

    init() {
        if let data = try? Data(contentsOf: Self.manifestURL),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
           let index = try? LaunchBoxIndex(contentsOf: Self.indexURL) {
            self.index = index
            builtAt = manifest.built
            platforms = Set(manifest.platforms)
            gameCount = index.gameCount
            fileSize = Self.size(of: Self.indexURL)
        }
    }

    var isBusy: Bool { state == .downloading || state == .indexing }
    var isDownloaded: Bool { builtAt != nil }

    /// The index, with `systems`' platforms in it: built first if there's
    /// none or it lacks one. One a month old still answers while a fresh
    /// one is made.
    func index(covering systems: [CanonicalSystemID]) async throws -> LaunchBoxIndex {
        let wanted = Set(systems.flatMap(LaunchBoxPlatforms.names(for:)))
        if let index, wanted.isSubset(of: platforms) {
            if let builtAt, Date.now.timeIntervalSince(builtAt) > Self.maximumAge, building == nil {
                Task { _ = try? await rebuild(platforms: platforms) }
            }
            return index
        }
        // Those it had stay, so a system whose games were removed for a
        // while keeps its place.
        return try await rebuild(platforms: wanted.union(platforms))
    }

    /// Downloads and indexes again now, for `systems`.
    func update(for systems: [CanonicalSystemID]) async {
        _ = try? await rebuild(platforms: Set(systems.flatMap(LaunchBoxPlatforms.names(for:))).union(platforms))
    }

    func remove() {
        guard !isBusy else { return }
        index = nil
        try? FileManager.default.removeItem(at: Self.folder)
        builtAt = nil
        platforms = []
        gameCount = 0
        fileSize = 0
        state = .idle
    }

    /// One build at a time: a second caller waits for the first.
    private func rebuild(platforms wanted: Set<String>) async throws -> LaunchBoxIndex {
        if let building { return try await building.value }
        let task = Task { try await build(platforms: wanted) }
        building = task
        defer { building = nil }
        return try await task.value
    }

    private func build(platforms wanted: Set<String>) async throws -> LaunchBoxIndex {
        let work = FileManager.default.temporaryDirectory.appending(path: "Attic-LaunchBox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            state = .downloading
            AppLog.post(.info, "Downloading LaunchBox's games database…")
            let (download, response) = try await URLSession.shared.download(from: LaunchBoxIndex.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appending(path: "Metadata.zip")
            try FileManager.default.moveItem(at: download, to: zip)

            state = .indexing
            let destination = Self.indexURL
            let summary = try await Task.detached(priority: .utility) {
                try Self.unzip(zip, into: work)
                try? FileManager.default.removeItem(at: zip)
                let mame = work.appending(path: "Mame.xml")
                return try LaunchBoxIndexBuilder.build(
                    metadata: work.appending(path: "Metadata.xml"), files: work.appending(path: "Files.xml"),
                    mame: FileManager.default.fileExists(atPath: mame.path) ? mame : nil,
                    platforms: wanted, to: destination
                )
            }.value

            // The old one is gone from disk; this one replaces it.
            let index = try LaunchBoxIndex(contentsOf: destination)
            let built = Date.now
            try JSONEncoder().encode(Manifest(built: built, platforms: wanted.sorted())).write(to: Self.manifestURL, options: .atomic)
            self.index = index
            builtAt = built
            platforms = wanted
            gameCount = summary.games
            fileSize = Self.size(of: destination)
            state = .idle
            AppLog.post(.info, "LaunchBox's games database is ready: \(summary.games) games, \(summary.images) pictures.")
            return index
        } catch {
            state = .failed(error.localizedDescription)
            AppLog.post(.error, "Couldn't get LaunchBox's games database: \(error.localizedDescription)")
            throw error
        }
    }

    /// Only the files the index is made from.
    nonisolated private static func unzip(_ zip: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zip.path, "Metadata.xml", "Files.xml", "Mame.xml", "-d", folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard FileManager.default.fileExists(atPath: folder.appending(path: "Metadata.xml").path) else {
            throw LaunchBoxIndexError.unreadable("Metadata.zip")
        }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
