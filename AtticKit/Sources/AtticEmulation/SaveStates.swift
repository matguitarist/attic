import Foundation

/// A RetroArch save state of one game, in its system's States folder:
/// `<game>.state` is slot 0, `<game>.state3` slot 3, each with the
/// screenshot RetroArch saves beside it (`<game>.state3.png`). The
/// automatic state Resume uses (`.state.auto`) isn't a slot.
public struct SaveState: Identifiable, Hashable, Sendable {
    public let slot: Int
    public let url: URL
    public let thumbnail: URL?
    public let date: Date

    public var id: Int { slot }

    public init(slot: Int, url: URL, thumbnail: URL?, date: Date) {
        self.slot = slot
        self.url = url
        self.thumbnail = thumbnail
        self.date = date
    }

    /// The game's numbered states, newest first. `romURL` names the game:
    /// RetroArch names states after the content it was given, which is the
    /// game's own name whether it was zipped, extracted or started from a
    /// MAME .cmd file.
    public static func list(in folder: URL, romURL: URL) -> [SaveState] {
        let base = romURL.deletingPathExtension().lastPathComponent
        let manager = FileManager.default
        let names = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
        return names.compactMap { name -> SaveState? in
            guard name.hasPrefix(base + ".state"), let slot = slot(of: String(name.dropFirst(base.count + ".state".count))) else { return nil }
            let url = folder.appending(path: name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return SaveState(slot: slot, url: url, thumbnail: names.contains(name + ".png") ? folder.appending(path: name + ".png") : nil, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// "" is slot 0, "3" slot 3; anything else (".auto", ".png") isn't a slot.
    static func slot(of suffix: String) -> Int? {
        if suffix.isEmpty { return 0 }
        guard let number = Int(suffix), number > 0, number < 1000 else { return nil }
        return number
    }

    /// RetroArch's arguments to start the game from this state.
    public var launchArguments: [String] { ["--entryslot", String(slot)] }
}
