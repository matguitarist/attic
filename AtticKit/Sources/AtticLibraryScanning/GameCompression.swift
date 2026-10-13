import Foundation
import AtticModels

/// What compressing the games in the ROMs folders would do: disc games to
/// CHD, cartridge games to ZIP. Both lossless, and what's replaced goes
/// to the Trash only once the new file is checked.
public struct GameCompressionPlan: Sendable {
    public var discs: [CHDConversion.Candidate] = []
    public var cartridges: [URL] = []

    public init(discs: [CHDConversion.Candidate] = [], cartridges: [URL] = []) {
        self.discs = discs
        self.cartridges = cartridges
    }

    public enum Step: Hashable, Sendable, CaseIterable {
        case discs, cartridges
    }

    public var isEmpty: Bool { discs.isEmpty && cartridges.isEmpty }

    public var steps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .discs: !discs.isEmpty
            case .cartridges: !cartridges.isEmpty
            }
        }
    }

    public func only(_ steps: Set<Step>) -> GameCompressionPlan {
        var plan = self
        if !steps.contains(.discs) { plan.discs = [] }
        if !steps.contains(.cartridges) { plan.cartridges = [] }
        return plan
    }

    public static func plan(romsRoots: [URL]) -> GameCompressionPlan {
        var plan = GameCompressionPlan()
        for root in romsRoots {
            let folders = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for folder in folders {
                guard let system = SystemTaxonomy.system(forShortName: folder.lastPathComponent.lowercased())?.canonicalID else { continue }
                plan.discs += CHDConversion.candidates(in: folder, system: system)
                plan.cartridges += ROMZipping.candidates(in: folder, system: system)
            }
        }
        return plan
    }

    public struct Result: Sendable {
        public var compressed = 0
        public var failed = 0
        public var savedBytes: Int64 = 0

        public init() {}
    }

    /// Carries out `plan`; discs only with `chdman`. `progress` gets the
    /// share done, by size (a disc takes far longer than a cartridge),
    /// and the game being compressed.
    public static func apply(_ plan: GameCompressionPlan, chdman: URL?, progress: (Double, String) -> Void = { _, _ in }) -> Result {
        let discs = chdman == nil ? [] : plan.discs
        let total = Double(max(discs.reduce(0) { $0 + $1.bytes } + plan.cartridges.reduce(0) { $0 + MediaFolder.fileSize($1) }, 1))
        var done: Int64 = 0
        var result = Result()

        for disc in discs {
            let before = disc.bytes
            progress(Double(done) / total, disc.source.deletingPathExtension().lastPathComponent)
            if let chdman, CHDConversion.convert(disc, chdman: chdman) {
                result.compressed += 1
                result.savedBytes += before - MediaFolder.fileSize(disc.destination)
            } else {
                result.failed += 1
            }
            done += before
        }
        for rom in plan.cartridges {
            let before = MediaFolder.fileSize(rom)
            progress(Double(done) / total, rom.deletingPathExtension().lastPathComponent)
            if let zip = ROMZipping.zip(rom) {
                result.compressed += 1
                result.savedBytes += before - MediaFolder.fileSize(zip)
            }
            done += before
        }
        progress(1, "")
        return result
    }
}
