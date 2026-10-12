import Foundation
import AppKit
import AtticModels
import AtticEmulation

/// A short `_sysinfo.txt` in each system's ROMs folder, saying what goes
/// there (file types, BIOS, emulator) for someone browsing in the Finder —
/// a summary of the system's help page. Front-ends like ES-DE and
/// Batocera leave their own (`systeminfo.txt`, `_info.txt`); those
/// describe other apps, so Settings offers to move them to the Trash.
enum ROMFolderNotes {
    static let fileName = "_sysinfo.txt"
    /// Other front-ends' notes: per system folder, then at a ROMs root.
    static let foreignFileNames = ["systeminfo.txt", "_info.txt"]
    static let foreignRootFileNames = ["systems.txt"]

    /// Writes the notes into every recognized system folder under the
    /// roots, leaving files whose text hasn't changed untouched.
    static func write(romsRoots: [URL], biosDirectory: URL) {
        for (folder, systemID) in systemFolders(in: romsRoots) {
            let url = folder.appending(path: fileName)
            let text = Self.text(for: systemID, biosDirectory: biosDirectory)
            if (try? String(contentsOf: url, encoding: .utf8)) == text { continue }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Other front-ends' info files under the roots.
    static func foreignFiles(in romsRoots: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for root in romsRoots {
            files += foreignRootFileNames.map { root.appending(path: $0) }
                .filter { fileManager.fileExists(atPath: $0.path) }
            let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                files += foreignFileNames.map { folder.appending(path: $0) }
                    .filter { fileManager.fileExists(atPath: $0.path) }
            }
        }
        return files
    }

    /// Moves `files` to the Trash, so nothing is lost for good. Returns
    /// how many went.
    static func moveToTrash(_ files: [URL]) -> Int {
        files.reduce(0) { count, url in
            (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil ? count + 1 : count
        }
    }

    private static func systemFolders(in romsRoots: [URL]) -> [(URL, CanonicalSystemID)] {
        romsRoots.flatMap { root -> [(URL, CanonicalSystemID)] in
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            return folders.compactMap { folder in
                guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let definition = SystemTaxonomy.system(forShortName: folder.lastPathComponent) else { return nil }
                return (folder, definition.canonicalID)
            }
        }
    }

    // MARK: - Text

    static func text(for systemID: CanonicalSystemID, biosDirectory: URL) -> String {
        var sections: [String] = []

        let name = SystemTaxonomy.definition(for: systemID)?.displayName ?? systemID.rawValue
        sections.append([name, SystemFacts.summary(for: systemID)].compactMap { $0 }.joined(separator: "\n"))

        if let extensions = SystemROMExtensions.extensions(for: systemID) {
            sections.append(String(localized: "Games go in this folder, as any of these file types:")
                + "\n" + extensions.sorted().map { ".\($0)" }.joined(separator: " "))
        }

        if let recommendation = EmulatorCatalog.recommendation(for: systemID) {
            let core = recommendation.recommendedCore.map { String(localized: "\($0.displayName) (RetroArch core)") }
            let emulator = recommendation.prefersStandalone ? recommendation.standalone.first?.name ?? core : core ?? recommendation.standalone.first?.name
            if let emulator {
                sections.append(String(localized: "Recommended emulator: \(emulator)"))
            }

            let biosPath = (biosDirectory.path as NSString).abbreviatingWithTildeInPath
            if recommendation.bios.isEmpty {
                sections.append(String(localized: "BIOS: none needed."))
            } else {
                let lines = recommendation.bios.map { requirement -> String in
                    var parts = [requirement.required ? String(localized: "required") : String(localized: "optional")]
                    if !requirement.supportedDumps.isEmpty {
                        parts.append(String(localized: "for example \(requirement.supportedDumps.prefix(3).joined(separator: ", "))"))
                    } else if let note = requirement.note {
                        parts.append(note)
                    }
                    return "- \(requirement.fileName) (\(parts.joined(separator: " · ")))"
                }
                sections.append(String(localized: "BIOS, in \(biosPath):") + "\n" + lines.joined(separator: "\n"))
            }
        }

        if let notes = SystemHelpContent.info(for: systemID)?.notes, !notes.isEmpty {
            sections.append(notes.map { "- \($0)" }.joined(separator: "\n"))
        }

        sections.append(String(localized: "Written by Attic, which keeps this file up to date: changes to it don't stick. More in Help › Attic Help."))
        return sections.joined(separator: "\n\n") + "\n"
    }
}
