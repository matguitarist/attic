import Foundation

/// One BIOS file as the system panel and help page list it: found or
/// missing, required or not.
public struct BIOSFileStatus: Sendable, Hashable, Identifiable {
    public let fileName: String
    public let isPresent: Bool
    public let required: Bool
    public let note: String?
    /// For a file that's there: whether it's a known good dump, and the
    /// checksums compared.
    public var check = BIOSChecksums.Check()
    public var verdict: BIOSChecksums.Verdict { check.verdict }
    /// Where the file is, when it's there.
    public var url: URL?
    /// For a missing file: a good dump of it in the BIOS folder under
    /// another name, and where it should go.
    public var misnamed: URL?
    public var expectedURL: URL?

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
                let url = biosDirectory.appending(path: requirement.fileName)
                let isPresent = requirement.isPresent(in: biosDirectory)
                var status = BIOSFileStatus(fileName: requirement.fileName, isPresent: isPresent,
                                            required: requirement.required, note: requirement.note)
                status.expectedURL = url
                if isPresent {
                    status.url = url
                    status.check = BIOSChecksums.check(url, as: requirement.fileName)
                } else {
                    status.check.expected = BIOSChecksums.expected(for: requirement.fileName)
                    status.misnamed = BIOSChecksums.misnamedDump(of: requirement.fileName, in: biosDirectory)
                }
                return [status]
            }
            let anyOne = String(localized: "Any one is enough", bundle: .module)
            let found = requirement.dumps(in: biosDirectory)
            let foundNames = Set(found.map { $0.lowercased() })
            let missing = requirement.supportedDumps.filter { !foundNames.contains($0.lowercased()) }
            let folder = biosDirectory.appending(path: requirement.fileName)
            return found.map { name in
                var status = BIOSFileStatus(fileName: name, isPresent: true, required: requirement.required, note: anyOne)
                status.url = folder.appending(path: name)
                status.check = BIOSChecksums.check(folder.appending(path: name), as: requirement.fileName)
                return status
            }
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
