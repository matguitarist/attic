import Foundation
import Observation
import AtticModels

/// Files games dropped on the library window into the right ROMs folder:
/// by the system they're dropped on, else the system shown if it takes
/// them, else their file type, asking when that could mean several
/// systems. Moves files on the same disk, copies them from another one.
@Observable
@MainActor
final class ROMImportCoordinator {
    /// Files whose system Attic has to ask about.
    struct Question: Identifiable {
        let id = UUID()
        let files: [URL]
        let choices: [CanonicalSystemID]
    }

    private(set) var question: Question?
    /// The summary shown once everything's placed.
    var summary: String?

    private var queue: [Question] = []
    private var romsRoots: [URL] = []
    private var added: [CanonicalSystemID: Int] = [:]
    private var alreadyThere = 0
    private var unknown: [String] = []
    private var finish: () -> Void = {}

    /// Disc images that name other files, which go along with them.
    private static let leadExtensions: Set<String> = ["cue", "gdi", "ccd", "m3u", "toc"]

    func receive(_ urls: [URL], into system: CanonicalSystemID? = nil, shown: CanonicalSystemID? = nil,
                 romsRoots: [URL], then finish: @escaping () -> Void) {
        guard !romsRoots.isEmpty, !urls.isEmpty else { return }
        self.romsRoots = romsRoots
        self.finish = finish
        added = [:]
        alreadyThere = 0
        unknown = []

        var asking: [[CanonicalSystemID]: [URL]] = [:]
        for group in Self.groups(urls) {
            let lead = group[0]
            let ext = Self.effectiveExtension(lead)
            if let system {
                place(group, in: system)
            } else if let shown, SystemROMExtensions.extensions(for: shown)?.contains(ext) == true {
                place(group, in: shown)
            } else {
                let choices = ROMImport.systems(forExtension: ext)
                switch choices.count {
                case 0: unknown.append(lead.lastPathComponent)
                case 1: place(group, in: choices[0])
                default: asking[choices, default: []] += group
                }
            }
        }
        queue = asking.map { Question(files: $0.value, choices: $0.key) }
            .sorted { $0.files[0].lastPathComponent < $1.files[0].lastPathComponent }
        next()
    }

    func answer(_ system: CanonicalSystemID?) {
        if let system, let question {
            for group in Self.groups(question.files) { place(group, in: system) }
        } else if let question {
            unknown += question.files.map(\.lastPathComponent)
        }
        next()
    }

    private func next() {
        if queue.isEmpty {
            question = nil
            summary = makeSummary()
            if !added.isEmpty { finish() }
        } else {
            question = queue.removeFirst()
        }
    }

    // MARK: - Placing

    private func place(_ files: [URL], in system: CanonicalSystemID) {
        guard let folder = ROMImport.folder(for: system, romsRoots: romsRoots) else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, file) in files.enumerated() {
            let destination = folder.appending(path: file.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else {
                if index == 0 { alreadyThere += 1 }
                continue
            }
            let moved = Self.sameVolume(file, folder) ? (try? fileManager.moveItem(at: file, to: destination)) != nil : false
            if moved || (try? fileManager.copyItem(at: file, to: destination)) != nil, index == 0 {
                added[system, default: 0] += 1
            }
        }
    }

    private func makeSummary() -> String? {
        var parts: [String] = []
        if !added.isEmpty {
            let systems = added.sorted { $0.value > $1.value }.map { system, count in
                "\(SystemTaxonomy.definition(for: system)?.displayName ?? system.rawValue) (\(count))"
            }
            parts.append(String(localized: "Added to \(systems.formatted(.list(type: .and)))."))
        }
        if alreadyThere > 0 {
            parts.append(String(localized: "\(alreadyThere) were already in your ROMs folder."))
        }
        if !unknown.isEmpty {
            parts.append(String(localized: "Not added, no system takes them: \(unknown.prefix(5).formatted(.list(type: .and)))."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: - Files

    /// Each game's files together: a .cue with the .bin files named like
    /// it, and so on. The lead file comes first.
    static func groups(_ urls: [URL]) -> [[URL]] {
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let leads = sorted.filter { leadExtensions.contains($0.pathExtension.lowercased()) }
        var taken = Set<URL>()
        var groups: [[URL]] = []
        for lead in leads {
            let stem = lead.deletingPathExtension().lastPathComponent
            let companions = sorted.filter { $0 != lead && !taken.contains($0) && !leads.contains($0) && $0.lastPathComponent.hasPrefix(stem) }
            taken.formUnion(companions + [lead])
            groups.append([lead] + companions)
        }
        return groups + sorted.filter { !taken.contains($0) }.map { [$0] }
    }

    /// A zip holding a single kind of file goes by that file's type
    /// (Game.zip with Game.sfc is a SNES game); anything else by its own.
    static func effectiveExtension(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" else { return ext }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return ext }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        let inner = Set(output.split(separator: "\n").filter { !$0.hasSuffix("/") }.map { ($0 as NSString).pathExtension.lowercased() })
        return inner.count == 1 ? inner.first! : ext
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let first = try? a.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let second = try? b.resourceValues(forKeys: key).volumeIdentifier as? NSObject else { return false }
        return first.isEqual(second)
    }
}
