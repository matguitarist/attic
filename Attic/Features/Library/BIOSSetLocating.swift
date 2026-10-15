import AppKit
import UniformTypeIdentifiers

/// Finding a missing arcade BIOS set wherever it is, and putting a copy
/// with the games, where MAME and FinalBurn Neo look for it.
enum BIOSSetLocating {
    /// Asks for `name` (konamigx.zip).
    @MainActor
    static func choose(_ name: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose \(name), still zipped.")
        panel.allowedContentTypes = [.zip]
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Copies `file` into each of `folders` as `name`, unless it's there
    /// already. False when a copy failed.
    static func copy(_ file: URL, as name: String, into folders: Set<URL>) -> Bool {
        folders.allSatisfy { folder in
            let destination = folder.appending(path: name)
            return FileManager.default.fileExists(atPath: destination.path)
                || (try? FileManager.default.copyItem(at: file, to: destination)) != nil
        }
    }
}
