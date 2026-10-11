import Foundation
import RomsBoxModels

/// Parses a libretro core `.info` file's key=value format, e.g.:
/// ```
/// corename = "Snes9x"
/// supported_extensions = "smc|sfc|swc|fig|bs|st"
/// systemname = "Super Nintendo Entertainment System"
/// systemid = "super_nes"
/// database = "Nintendo - Super Nintendo Entertainment System"
/// ```
enum RetroArchCoreInfoParser {
    static func parse(contents: String, coreIdentifier: String, dylibURL: URL) -> RetroArchCoreInfo {
        var fields: [String: String] = [:]
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equalsIndex].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }

        let extensions = (fields["supported_extensions"] ?? "")
            .split(separator: "|")
            .map(String.init)
        let systemID = fields["systemid"]
        let canonicalSystemID = systemID.flatMap { SystemTaxonomy.system(forRetroArchSystemID: $0)?.canonicalID }

        // `systemid` names one system; `database` lists all of them.
        var systems: [CanonicalSystemID] = canonicalSystemID.map { [$0] } ?? []
        for name in (fields["database"] ?? "").split(separator: "|") {
            if let system = LibretroDatabase.system(forDatabaseName: String(name)), !systems.contains(system) {
                systems.append(system)
            }
        }

        return RetroArchCoreInfo(
            coreIdentifier: coreIdentifier,
            displayName: fields["corename"] ?? coreIdentifier,
            dylibURL: dylibURL,
            supportedExtensions: extensions,
            systemID: systemID,
            canonicalSystemID: canonicalSystemID,
            systems: systems
        )
    }
}
