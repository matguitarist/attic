import Foundation
import AtticModels
import AtticEmulation

/// Rebuilding an arcade system's sets from the chips its folder holds,
/// shown before it's done.
struct SetRebuildReport {
    let system: CanonicalSystemID
    let folder: URL
    let plan: RebuildPlan
}

extension ToolsCoordinator {
    /// Works out which of the system's sets can be made whole from loose
    /// files and other zips in its folder, and which loose files would be
    /// left of no use. Changes nothing.
    func analyzeRebuild(system: CanonicalSystemID, folder: URL, datsFolder: URL, from host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        activity = Activity(title: String(localized: "Looking for chips…"))
        let source = Self.arcadeSource(for: system)
        let plan = await Task.detached(priority: .userInitiated) { () -> RebuildPlan in
            let top = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            let names = Set(top.map { $0.pathExtension.lowercased() == "zip" ? $0.deletingPathExtension().lastPathComponent : $0.lastPathComponent })
            // Its own cache: the sets wanted here aren't verify's.
            let verifier = ArcadeVerifier.load(from: datsFolder, wanted: names, cacheDirectory: Self.arcadeCache.appending(path: "Rebuild"))
            return verifier.rebuildPlan(folder: folder, preferring: source)
        }.value
        activity = nil
        guard !plan.rebuilds.isEmpty || !plan.leftovers.isEmpty else {
            outcome = Outcome(title: String(localized: "Rebuild Sets"),
                              message: String(localized: "Nothing to rebuild: no set here can be made whole from the files beside it, and no loose files are left over."))
            return
        }
        report = .rebuild(SetRebuildReport(system: system, folder: folder, plan: plan))
    }

    /// Writes the sets' zips (each replaced one goes to the Trash), moves
    /// the leftover loose files to the Trash when asked, then rescans and
    /// verifies the system again.
    func rebuild(_ report: SetRebuildReport, trashingLeftovers: Bool, datsFolder: URL, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        guard !isBusy else { return }
        activity = Activity(title: String(localized: "Rebuilding sets…"), fraction: 0)
        let progress = { @Sendable (value: Double, name: String) -> Void in
            Task { @MainActor in
                self.activity?.fraction = value
                self.activity?.detail = name
            }
        }
        let failed = await Task.detached(priority: .userInitiated) { () -> [String] in
            var failed: [String] = []
            for (index, rebuild) in report.plan.rebuilds.enumerated() {
                progress(Double(index) / Double(report.plan.rebuilds.count), rebuild.name)
                if (try? ArcadeVerifier.rebuild(rebuild)) == nil { failed.append(rebuild.name) }
            }
            // Leftovers only once every set came out whole.
            if trashingLeftovers, failed.isEmpty {
                let manager = FileManager.default
                for file in report.plan.leftovers { try? manager.trashItem(at: file, resultingItemURL: nil) }
                // The folders they leave empty.
                let folders = Set(report.plan.leftovers.map { $0.deletingLastPathComponent() })
                    .filter { $0.standardizedFileURL != report.folder.standardizedFileURL }
                    .sorted { $0.pathComponents.count > $1.pathComponents.count }
                for folder in folders {
                    let left = (try? manager.contentsOfDirectory(atPath: folder.path))?.filter { $0 != ".DS_Store" } ?? ["?"]
                    if left.isEmpty { try? manager.trashItem(at: folder, resultingItemURL: nil) }
                }
            }
            progress(1, "")
            return failed
        }.value
        activity = nil
        await scanCoordinator.scan(romsRootURLs: romsRoots, only: [report.system])
        if !failed.isEmpty {
            outcome = Outcome(title: String(localized: "Rebuild Sets"),
                              message: String(localized: "Couldn't rebuild \(failed.formatted(.list(type: .and))): a chip couldn't be read, or the zip couldn't be written. Those sets were left as they were, and so were the loose files."))
            return
        }
        // What the sets are now.
        await verify(datsFolder: datsFolder, scanCoordinator: scanCoordinator, from: reportHost, system: report.system)
    }
}
