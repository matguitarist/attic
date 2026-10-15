import AppKit
import UniformTypeIdentifiers
import AtticModels
import AtticEmulation

/// Finding missing arcade BIOS sets, one by name or all those in a
/// folder, and putting a copy in the BIOS folder where the emulator that
/// runs the games looks for them (mame/bios for MAME).
enum BIOSSetLocating {
    /// Asks for `name` (konamigx.zip): only a file of that name can be
    /// picked, every other one is greyed out.
    @MainActor
    static func choose(_ name: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose \(name), still zipped.")
        panel.allowedContentTypes = [.zip]
        panel.canChooseDirectories = false
        let filter = NameFilter(name: name)
        panel.delegate = filter
        let chosen = panel.runModal() == .OK ? panel.url : nil
        panel.delegate = nil
        return chosen
    }

    /// Asks for a folder to look through: another front-end's BIOS folder.
    @MainActor
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose a folder with BIOS sets in it, such as another front-end's bios folder.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Search")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The files named `names` in `folder` and its folders, by lowercased
    /// name; the first found wins.
    static func find(_ names: Set<String>, in folder: URL) -> [String: URL] {
        let wanted = Set(names.map { $0.lowercased() })
        var found: [String: URL] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent.lowercased()
            if wanted.contains(name), found[name] == nil { found[name] = url }
            if found.count == wanted.count { break }
        }
        return found
    }

    /// Where `system`'s BIOS sets go.
    static func destination(for system: CanonicalSystemID, biosFolder: URL) -> URL {
        ArcadeVerifier.biosSetFolder(for: system, in: biosFolder)
    }

    /// "BIOS/mame/bios": a folder as it reads within the Emulation folder.
    static func shortPath(_ folder: URL, in emulation: EmulationFolder) -> String {
        let root = emulation.root.path.hasSuffix("/") ? emulation.root.path : emulation.root.path + "/"
        return folder.path.hasPrefix(root) ? String(folder.path.dropFirst(root.count)) : folder.path
    }

    /// Copies `file` into `folder` as `name`, unless it's there already.
    static func copy(_ file: URL, as name: String, into folder: URL) -> Bool {
        let destination = folder.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) { return true }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try? FileManager.default.copyItem(at: file, to: destination)) != nil
    }

    /// Lets folders be opened, and only files named `name` be chosen.
    private final class NameFilter: NSObject, NSOpenSavePanelDelegate {
        let name: String

        init(name: String) { self.name = name }

        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                || url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
