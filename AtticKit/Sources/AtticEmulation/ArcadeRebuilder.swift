import Foundation
import AtticModels
import AtticLibraryScanning

/// A set's zip to write again from chips found around it: loose files in
/// its system's folder (an unpacked set, or several), its own zip, or
/// another set's.
public struct SetRebuild: Sendable, Hashable, Identifiable {
    public struct Part: Sendable, Hashable {
        /// The name the DAT gives it, in the zip.
        public let name: String
        public let crc: UInt32
        public let source: URL
        /// Its name inside `source` when that's a zip; nil for a loose file.
        public let entry: String?
    }

    /// The set's name: "jojoba".
    public let name: String
    public let title: String
    public let zip: URL
    public let parts: [Part]
    /// What the old zip holds that the new one won't: another version's
    /// chips, or files the set doesn't use.
    public var dropped: [String] = []

    public var id: String { name }
    public var fromLooseFiles: Int { parts.count(where: { $0.entry == nil }) }
    /// Whether the set had no zip of its own.
    public var isNew: Bool { !FileManager.default.fileExists(atPath: zip.path) }
}

/// A set that can't be made whole from what the folder holds: what was
/// found, and what's still missing.
public struct IncompleteSet: Sendable, Hashable, Identifiable {
    public let name: String
    public let title: String
    public let found: [SetRebuild.Part]
    public let missing: [SetProblems.File]
    public var id: String { name }
}

/// What rebuilding a folder's sets would do.
public struct RebuildPlan: Sendable {
    public var rebuilds: [SetRebuild] = []
    public var incomplete: [IncompleteSet] = []
    /// Loose files with nothing left to give: their chip is in a zip (or
    /// will be), or none of the folder's sets uses it.
    public var leftovers: [URL] = []
    public var leftoverBytes: Int64 = 0
    /// The DAT the sets are built for.
    public var dat: String?
}

extension ArcadeVerifier {
    /// Files that are never a set's chips: zips, disc images, notes.
    private static let notChips: Swift.Set<String> = ["zip", "7z", "chd", "txt", "xml", "dat", "md", "pdf", "png", "jpg", "jpeg", "ini", "cfg", "nv", "ds_store"]

    /// Which of `folder`'s sets (its zips, and its folders named like a
    /// set) can be made whole, chip for chip as `preferred`'s DAT lists
    /// them, from what the folder holds; and which loose files would then
    /// be of no use. Reads only.
    public func rebuildPlan(folder: URL, preferring preferred: Source) -> RebuildPlan {
        var plan = RebuildPlan()
        guard let set = sets[preferred] ?? sets.values.first else { return plan }
        plan.dat = set.name
        let manager = FileManager.default
        let top = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let zips = top.filter { $0.pathExtension.lowercased() == "zip" }
        let names = Swift.Set(top.compactMap { url -> String? in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory || url.pathExtension.lowercased() == "zip" else { return nil }
            return (isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent).lowercased()
        }).filter { set.machines[$0] != nil }

        // Every chip at hand, by CRC: loose files first, then zips' entries.
        var loose: [UInt32: URL] = [:]
        var looseFiles: [(url: URL, crc: UInt32, size: Int64)] = []
        if let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: .skipsHiddenFiles) {
            for case let url as URL in enumerator {
                guard url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL || !url.lastPathComponent.hasPrefix("_"),
                      !Self.notChips.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
                      let size = values.fileSize, size > 0, size <= 256 << 20,
                      let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                let crc = CoreUpdateChecker.crc32(of: data)
                looseFiles.append((url, crc, Int64(size)))
                if loose[crc] == nil { loose[crc] = url }
            }
        }
        var zipped: [UInt32: (zip: URL, entry: String)] = [:]
        var zipCRCs: [String: Swift.Set<UInt32>] = [:]
        for zip in zips {
            let entries = Self.entries(of: zip)
            zipCRCs[zip.deletingPathExtension().lastPathComponent.lowercased()] = Swift.Set(entries.map(\.crc))
            for entry in entries where zipped[entry.crc] == nil { zipped[entry.crc] = (zip, entry.name) }
        }

        func isBIOS(_ rom: ROM) -> Bool { set.biosCRCs.contains(rom.crc) || rom.name.lowercased().contains("bios") }
        // The chips a set's own zip holds: not its parent's, nor a BIOS's.
        func own(_ machine: Machine) -> [ROM] { machine.roms.filter { !$0.inParent && !isBIOS($0) } }

        var inZips = zipCRCs.values.reduce(into: Swift.Set<UInt32>()) { $0.formUnion($1) }
        for name in names.sorted() {
            guard let machine = set.machines[name] else { continue }
            let wanted = own(machine)
            let has = zipCRCs[name] ?? []
            // Already whole: left as it is.
            guard !wanted.isEmpty, !wanted.allSatisfy({ has.contains($0.crc) }) else { continue }
            var parts: [SetRebuild.Part] = []
            for rom in wanted {
                if has.contains(rom.crc), let found = zipped[rom.crc], found.zip.deletingPathExtension().lastPathComponent.lowercased() == name {
                    parts.append(.init(name: rom.name, crc: rom.crc, source: found.zip, entry: found.entry))
                } else if let file = loose[rom.crc] {
                    parts.append(.init(name: rom.name, crc: rom.crc, source: file, entry: nil))
                } else if let found = zipped[rom.crc] {
                    parts.append(.init(name: rom.name, crc: rom.crc, source: found.zip, entry: found.entry))
                }
            }
            // Only a set that comes out whole.
            guard parts.count == wanted.count else {
                let found = Swift.Set(parts.map(\.crc))
                plan.incomplete.append(IncompleteSet(name: name, title: machine.title, found: parts,
                                                     missing: wanted.filter { !found.contains($0.crc) }.map { .init(name: $0.name, expected: Self.hex($0.crc)) }))
                continue
            }
            var rebuild = SetRebuild(name: name, title: machine.title, zip: folder.appending(path: name + ".zip"), parts: parts)
            let kept = Swift.Set(wanted.map(\.crc))
            let oldZip = folder.appending(path: name + ".zip")
            if FileManager.default.fileExists(atPath: oldZip.path) {
                rebuild.dropped = Self.entries(of: oldZip).filter { !kept.contains($0.crc) }.map(\.name)
            }
            plan.rebuilds.append(rebuild)
            inZips.formUnion(parts.map(\.crc))
        }

        // What the folder's sets use at all, parents' chips included
        // through their own zips.
        let used = names.reduce(into: Swift.Set<UInt32>()) { result, name in
            result.formUnion(set.machines[name]?.roms.map(\.crc) ?? [])
        }
        for file in looseFiles where inZips.contains(file.crc) || !used.contains(file.crc) {
            plan.leftovers.append(file.url)
            plan.leftoverBytes += file.size
        }
        return plan
    }

    public enum RebuildError: Error {
        case unreadable(String)
        case zipFailed
    }

    /// Writes the set's zip from its parts, checks it, then puts it in
    /// place; the zip it replaces goes to the Trash.
    public static func rebuild(_ rebuild: SetRebuild) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appending(path: "attic-rebuild-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        for part in rebuild.parts {
            let data: Data
            if let entry = part.entry {
                guard let unzipped = run("/usr/bin/unzip", ["-p", part.source.path, entry]) else { throw RebuildError.unreadable(part.name) }
                data = unzipped
            } else {
                data = try Data(contentsOf: part.source)
            }
            guard CoreUpdateChecker.crc32(of: data) == part.crc else { throw RebuildError.unreadable(part.name) }
            let target = staging.appending(path: part.name)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }

        // Beside the old one, so the move into place stays on its disk.
        let written = rebuild.zip.deletingLastPathComponent().appending(path: ".\(rebuild.name).attic-rebuild.zip")
        try? manager.removeItem(at: written)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-q", "-X", "-D", "-9", written.path] + rebuild.parts.map(\.name)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let crcs = Swift.Set((ZipContents.entries(of: written) ?? []).map(\.crc))
        guard process.terminationStatus == 0, rebuild.parts.allSatisfy({ crcs.contains($0.crc) }) else {
            try? manager.removeItem(at: written)
            throw RebuildError.zipFailed
        }
        if manager.fileExists(atPath: rebuild.zip.path) {
            try manager.trashItem(at: rebuild.zip, resultingItemURL: nil)
        }
        try manager.moveItem(at: written, to: rebuild.zip)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
