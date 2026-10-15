import Foundation
import AtticModels

/// Which DAT a system's games are checked against, and whether it's in
/// the DATs folder: read from the files' names, so it's quick enough for
/// a panel.
public struct DATCoverage: Sendable, Equatable {
    /// Who catalogues the system's dumps.
    public enum Kind: String, Sendable {
        /// Cartridges and other single files: DAT-o-MATIC.
        case noIntro
        /// Discs: redump.org. Not checked yet.
        case redump
        /// Arcade sets, as MAME or FinalBurn Neo lists them.
        case mame, fbneo
        /// Hacks and homebrew: no DAT lists them.
        case none
    }

    public enum Status: Sendable, Equatable {
        /// The DATs found for it: their names, and the newest one's date.
        case present([String], date: Date?)
        case missing
        /// Only DATs for something else: a dev kit's hard drive, memory
        /// cards, digital store downloads, flux images…
        case incompatible([String])
        /// A kind of game Attic doesn't check yet (discs).
        case notSupported
        /// No DAT exists for such games (hacks).
        case notApplicable
    }

    public let kind: Kind
    public let status: Status

    /// Whether Verify Games can check the system's games at all, DAT or
    /// not yet: not discs, nor games no DAT lists.
    public var isCheckable: Bool {
        switch status {
        case .notSupported, .notApplicable: false
        default: true
        }
    }

    /// What `system`'s games would be checked against in `folder`.
    /// `arcadeSource` is the arcade DAT its emulator follows.
    public static func coverage(for system: CanonicalSystemID, isArcade: Bool, arcadeSource: ArcadeVerifier.Source,
                                datsFolder folder: URL) -> DATCoverage {
        if ROMHacks.base(of: system) != nil || unlisted.contains(system) { return DATCoverage(kind: .none, status: .notApplicable) }
        if isArcade {
            let kind: Kind = arcadeSource == .fbneo ? .fbneo : .mame
            let files = ArcadeVerifier.datFiles(in: folder).filter { file in
                let name = file.lastPathComponent.lowercased()
                let isFBNeo = name.contains("finalburn") || name.contains("fbneo")
                return arcadeSource == .fbneo ? isFBNeo : !isFBNeo
            }
            guard !files.isEmpty else { return DATCoverage(kind: kind, status: .missing) }
            return DATCoverage(kind: kind, status: .present(files.map(arcadeName), date: newest(files)))
        }
        // Disc systems are Redump's.
        if discSystems.contains(system) { return DATCoverage(kind: .redump, status: .notSupported) }
        var names: [String] = []
        var dates: [Date] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        for file in files where !ArcadeVerifier.isArcadeZip(file) {
            let entries: [String]
            switch file.pathExtension.lowercased() {
            case "dat", "xml": entries = [file.lastPathComponent]
            case "zip": entries = DATVerifier.zipListing(file).filter { ["dat", "xml"].contains(($0 as NSString).pathExtension.lowercased()) }
            default: continue
            }
            for entry in entries {
                let stem = (((entry as NSString).lastPathComponent) as NSString).deletingPathExtension
                guard DATFile(name: stem, roms: []).system == system else { continue }
                names.append(stem.replacing(#/\s*\(\d{8}-\d{6}\)$/#, with: ""))
                if let date = dateStamp(in: stem) { dates.append(date) }
            }
        }
        guard !names.isEmpty else { return DATCoverage(kind: .noIntro, status: .missing) }
        let usable = names.filter { !isForSomethingElse($0) }
        guard !usable.isEmpty else { return DATCoverage(kind: .noIntro, status: .incompatible(names.sorted())) }
        return DATCoverage(kind: .noIntro, status: .present(usable.sorted(), date: dates.max()))
    }

    /// Systems whose games are discs, which Redump catalogues.
    static let discSystems: Swift.Set<CanonicalSystemID> = [
        .psx, .ps2, .ps3, .psp, .segacd, .saturn, .dreamcast, .gamecube, .wii, .wiiu, .pcenginecd, .pcfx,
        .neogeocd, .threedo, .cdi, .xbox,
    ]

    /// Game engines, ports and fantasy consoles: no DAT lists them.
    static let unlisted: Swift.Set<CanonicalSystemID> = [
        .scummvm, .doom, .quake, .easyrpg, .pico8, .tic80, .wasm4, .ps4, .psvita, .dos,
    ]

    /// DAT-o-MATIC's sets of things other than the games: a dev kit's
    /// hard drives, memory cards, store downloads, flux or tape images.
    static func isForSomethingElse(_ name: String) -> Bool {
        let tags = name.matches(of: #/\(([^)]*)\)/#).map { $0.output.1.lowercased() }
        let other = ["development kit", "memory card", "visual memory", "psn", "digital", "cdn", "flux", "kryoflux", "bitstream",
                     "tapes", "waveform", "a2r", "woz", "npdp", "starlight", "play-yan", "video", "multiboot", "e-reader", "wallpapers", "amiibo"]
        return tags.contains { tag in other.contains { tag.contains($0) } }
    }

    /// "mame0289lx.zip" is "MAME 0.289".
    private static func arcadeName(_ file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        if let match = name.lowercased().wholeMatch(of: #/mame(\d)(\d+)lx/#) {
            return "MAME \(match.output.1).\(match.output.2)"
        }
        return name
    }

    private static func newest(_ files: [URL]) -> Date? {
        files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    /// DAT-o-MATIC's "(20261009-130044)".
    static func dateStamp(in name: String) -> Date? {
        guard let match = name.firstMatch(of: #/\((\d{8})-\d{6}\)/#) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: String(match.output.1))
    }
}
