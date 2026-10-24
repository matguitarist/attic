import Foundation
import AppKit
import AtticModels
import AtticEmulation
import AtticLibraryScanning

/// A folder per system in ROMs (see `createSystemFolders`), each with a
/// short `_sysinfo.txt` saying what goes
/// there (file types, BIOS, emulator) for someone browsing in the Finder —
/// a summary of the system's help page, in English. Front-ends like ES-DE and
/// Batocera leave their own (`systeminfo.txt`, `_info.txt`); those
/// describe other apps, so tidying up (`MediaTidier`) moves them to the
/// Trash.
enum ROMFolderNotes {
    static let fileName = "_sysinfo.txt"

    /// Systems whose folder Attic has already made, so one the user
    /// deletes isn't made again, while systems new in an update get theirs.
    static let createdFoldersKey = "createdSystemFolders"

    /// Makes a folder in the first ROMs folder for every system Attic
    /// knows (ES-DE's name for it), so it's clear where games go. Skips
    /// systems that already have one under any name, and removed systems.
    static func createSystemFolders(romsRoots: [URL], defaults: UserDefaults = .standard) {
        let fileManager = FileManager.default
        guard let root = romsRoots.first, fileManager.fileExists(atPath: root.path) else { return }
        // APFS ignores case, so "SNES" counts as "snes".
        let existing = Set(romsRoots.flatMap { root in
            ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []).map { $0.lowercased() }
        })
        var created = Set(defaults.stringArray(forKey: createdFoldersKey) ?? [])
        for definition in SystemTaxonomy.allSystems
        where !created.contains(definition.canonicalID.rawValue) && !RemovedSystems.contains(definition.canonicalID) {
            if !definition.allShortNames.contains(where: { existing.contains($0.lowercased()) }) {
                try? fileManager.createDirectory(at: root.appending(path: definition.esdeShortName, directoryHint: .isDirectory), withIntermediateDirectories: false)
            }
            created.insert(definition.canonicalID.rawValue)
        }
        defaults.set(created.sorted(), forKey: createdFoldersKey)
    }

    /// Media folders already made ("<system>/<kind>"), likewise.
    static let createdMediaFoldersKey = "createdMediaFolders"

    /// Makes `Media/<system>/<kind>` for every system folder, so media
    /// copied in by hand has a place to go (see `MediaFolder.createFolders`).
    static func createMediaFolders(romsRoots: [URL], defaults: UserDefaults = .standard) {
        let created = Set(defaults.stringArray(forKey: createdMediaFoldersKey) ?? [])
        let made = MediaFolder.createFolders(romsRoots: romsRoots, created: created)
        guard !made.isEmpty else { return }
        defaults.set(created.union(made).sorted(), forKey: createdMediaFoldersKey)
    }

    /// Writes the notes into every recognized system folder under the
    /// roots, leaving files whose text hasn't changed untouched.
    static func write(romsRoots: [URL], biosDirectory: URL) {
        for (folder, systemID) in systemFolders(in: romsRoots) {
            let url = folder.appending(path: fileName)
            let text = Self.text(for: systemID, biosDirectory: biosDirectory, folderName: folder.lastPathComponent)
            if (try? String(contentsOf: url, encoding: .utf8)) == text { continue }
            try? text.write(to: url, atomically: true, encoding: .utf8)
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

    private static func englishName(_ medium: PhysicalMedium) -> String {
        switch medium {
        case .cartridge: "the cartridge"
        case .disc: "the disc"
        case .card: "the card"
        case .disk: "the disk"
        case .cassette: "the cassette"
        case .board: "the arcade board"
        }
    }

    private static func english(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "en")
        return String(localized: resource)
    }

    /// In English whatever the app's language: these files outlive the
    /// app's settings and get shared along with the ROMs folder.
    /// `folderName` is the system's ROMs folder, which its media folder
    /// is named after.
    static func text(for systemID: CanonicalSystemID, biosDirectory: URL, folderName: String? = nil) -> String {
        var sections: [String] = []

        let name = SystemTaxonomy.definition(for: systemID)?.displayName ?? systemID.rawValue
        if let info = SystemHelpContent.info(for: systemID) {
            let category = SystemTaxonomy.definition(for: systemID)?.category ?? .console
            sections.append("\(name)\n\(info.manufacturer) · \(info.year) · \(category.englishTitle)")
        } else {
            sections.append(name)
        }

        if let extensions = SystemROMExtensions.extensions(for: systemID) {
            sections.append("Games go in this folder, as any of these file types:"
                + "\n" + extensions.sorted().map { ".\($0)" }.joined(separator: " "))
        }

        if let recommendation = EmulatorCatalog.recommendation(for: systemID) {
            let core = recommendation.recommendedCore.map { "\($0.displayName) (RetroArch core)" }
            let emulator = recommendation.prefersStandalone ? recommendation.standalone.first?.name ?? core : core ?? recommendation.standalone.first?.name
            if let emulator {
                sections.append("Recommended emulator: \(emulator)")
            }

            let biosPath = (biosDirectory.path as NSString).abbreviatingWithTildeInPath
            if recommendation.bios.isEmpty {
                sections.append("BIOS: none needed.")
            } else {
                let lines = recommendation.bios.map { requirement -> String in
                    var parts = [requirement.required ? "required" : "optional"]
                    if !requirement.supportedDumps.isEmpty {
                        parts.append("for example \(requirement.supportedDumps.prefix(3).joined(separator: ", "))")
                    } else if let note = requirement.note {
                        parts.append(note)
                    }
                    return "- \(requirement.fileName) (\(parts.joined(separator: " · ")))"
                }
                sections.append("BIOS, in \(biosPath):\n" + lines.joined(separator: "\n"))
            }
        }

        if let folder = folderName ?? SystemTaxonomy.definition(for: systemID)?.esdeShortName {
            let kinds = MediaFolder.kinds(for: systemID).map { kind -> String in
                let what = switch kind {
                case .covers: "box art, the front of the box"
                case .boxes3D: "the box in 3D"
                case .physicalMedia: PhysicalMedium.of(systemID).map(englishName) ?? "the cartridge or disc"
                case .logos: "the game's logo, on a transparent background"
                case .marquees: "the cabinet's lit header"
                case .bezels: "art framing the game's picture, as a PNG with a transparent window"
                case .fanart: "wide art for behind the game"
                case .screenshots: "a picture of the game playing"
                case .videos: "a short video of the game playing"
                case .manuals: "the manual, as a PDF"
                }
                return "- \(kind.rawValue): \(what)"
            }
            sections.append("Media for these games goes in \(EmulationLayout.media)/\(folder)/ beside the ROMs folder, one folder per kind,"
                + " each file named after its game's ROM file (\(EmulationLayout.media)/\(folder)/\(MediaKind.covers.rawValue)/Game (USA).png):\n"
                + kinds.joined(separator: "\n"))
        }

        if let notes = SystemHelpContent.info(for: systemID)?.notes, !notes.isEmpty {
            sections.append(notes.map { "- \(english($0))" }.joined(separator: "\n"))
        }

        sections.append("Written by Attic, which keeps this file up to date: changes to it don't stick. More in Help › Attic Help.")
        return sections.joined(separator: "\n\n") + "\n"
    }
}
