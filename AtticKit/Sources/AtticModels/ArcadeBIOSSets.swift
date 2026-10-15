import Foundation

/// The zips an arcade board's games boot from (neogeo.zip, konamigx.zip):
/// not games, but MAME and FinalBurn Neo look for them beside the games.
public enum ArcadeBIOSSets {
    /// MAME's and FinalBurn Neo's BIOS sets (isbios in their lists).
    public static let names: Set<String> = [
        "3dobios", "airlbios", "aleck64", "alg3do", "alg_bios", "allied", "ar_bios", "aristmk5", "aristmk6", "aristmk7",
        "atarisy1", "awbios", "bubsys", "cchip", "cdibios", "cedmag", "chihiro", "coh1000a", "coh1000c", "coh1000t", "coh1000w",
        "coh1001l", "coh1002e", "coh1002m", "coh1002t", "coh1002v", "coh3002c", "coh3002t", "crysbios", "cubo", "decocass",
        "f355bios", "f355dlx", "galgames", "gp_110", "gq863", "gts1", "hikaru", "hng64", "hod2bios", "isgsm", "iteagle",
        "konamigv", "konamigx", "konendev", "kpython", "kpython2", "kviper", "lindbios", "mac2bios", "macsbios", "maxaflex",
        "megaplay", "megatech", "midssio", "miuchiz", "namcoc69", "namcoc70", "namcoc75", "naomi", "naomi2", "naomigd", "neogeo",
        "nichidvd", "nmk004", "nss", "pgm", "playch10", "pumpitup", "recel", "sammymdl", "segasp", "sfcbox", "shtzone", "skns",
        "slvrball", "stvbios", "su2000", "sys246", "sys256", "sys573", "systemy2", "taitotz", "tourvis", "triforce", "v4bios",
        "ym2608",    ]

    /// Whether `path` (a file in `system`'s folder) is a BIOS set rather
    /// than a game.
    public static func isBIOSSet(_ path: String, system: CanonicalSystemID) -> Bool {
        guard SystemTaxonomy.definition(for: system)?.category == .arcade else { return false }
        let name = (path as NSString).lastPathComponent as NSString
        guard ["zip", "7z"].contains(name.pathExtension.lowercased()) else { return false }
        return names.contains(name.deletingPathExtension.lowercased())
    }
}
