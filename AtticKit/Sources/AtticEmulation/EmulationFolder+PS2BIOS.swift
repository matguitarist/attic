import Foundation

extension EmulationFolder {
    /// Where PCSX2, core and app alike, looks for PS2 BIOS dumps.
    public var ps2BIOS: URL { bios.appending(path: "pcsx2/bios", directoryHint: .isDirectory) }

    /// Every PS2 BIOS dump is exactly 4 MiB (PlayStation ones are 512 KiB).
    static let ps2BIOSSize = 4 * 1024 * 1024

    /// PCSX2 only looks in `ps2BIOS`, so PS2 dumps dropped straight into
    /// BIOS/ (where every other system's files go) are moved there, along
    /// with the .mec/.nvm files PCSX2 keeps next to each one. A dump
    /// already in place under the same name is left alone. Returns the
    /// names of the dumps moved.
    @discardableResult
    public func movePS2BIOSIntoPlace() -> [String] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: bios, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: .skipsHiddenFiles
        ) else { return [] }

        let dumps = entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return url.pathExtension.lowercased() == "bin"
                && values?.isRegularFile == true
                && values?.fileSize == Self.ps2BIOSSize
        }
        guard !dumps.isEmpty else { return [] }
        try? fileManager.createDirectory(at: ps2BIOS, withIntermediateDirectories: true)

        var moved: [String] = []
        for dump in dumps {
            let stem = dump.deletingPathExtension().lastPathComponent.lowercased()
            let companions = entries.filter {
                $0 != dump && $0.deletingPathExtension().lastPathComponent.lowercased() == stem
                    && ["mec", "nvm"].contains($0.pathExtension.lowercased())
            }
            for file in [dump] + companions {
                let destination = ps2BIOS.appending(path: file.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                do {
                    try fileManager.moveItem(at: file, to: destination)
                    if file == dump { moved.append(dump.lastPathComponent) }
                } catch {
                    continue
                }
            }
        }
        return moved
    }
}
