import Foundation

/// One BIOS file as the system panel and help page list it: found or
/// missing, required or not.
public struct BIOSFileStatus: Sendable, Hashable, Identifiable {
    public let fileName: String
    public let isPresent: Bool
    public let required: Bool
    public let note: String?

    public var id: String { fileName.lowercased() }
}

extension Array where Element == BIOSRequirement {
    /// One row per file. A folder requirement (PS2) lists the dumps found
    /// in it, then the known ones still missing; any single dump is
    /// enough, so the missing ones only count as required while there's
    /// none at all.
    public func statuses(in biosDirectory: URL) -> [BIOSFileStatus] {
        flatMap { requirement -> [BIOSFileStatus] in
            guard requirement.isFolder else {
                return [BIOSFileStatus(fileName: requirement.fileName, isPresent: requirement.isPresent(in: biosDirectory),
                                       required: requirement.required, note: requirement.note)]
            }
            let anyOne = String(localized: "Any one is enough", bundle: .module)
            let found = requirement.dumps(in: biosDirectory)
            let foundNames = Set(found.map { $0.lowercased() })
            let missing = requirement.supportedDumps.filter { !foundNames.contains($0.lowercased()) }
            return found.map { BIOSFileStatus(fileName: $0, isPresent: true, required: requirement.required, note: anyOne) }
                + missing.map { BIOSFileStatus(fileName: $0, isPresent: false, required: requirement.required && found.isEmpty, note: anyOne) }
        }
    }
}

extension BIOSRequirement {
    /// The BIOS dumps (.bin files) in a folder requirement's folder, by
    /// name, leaving out the .mec/.nvm files PCSX2 keeps beside them.
    func dumps(in biosDirectory: URL) -> [String] {
        let folder = biosDirectory.appending(path: fileName)
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        return entries
            .filter { $0.pathExtension.lowercased() == "bin" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
