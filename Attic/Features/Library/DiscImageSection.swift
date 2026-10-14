import SwiftUI
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// A disc game's files: their format and size and, for a CHD, how much it
/// saved and its SHA-1; with the conversion to CHD or back.
struct DiscImageSection: View {
    let game: Game
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(RomsRootsStore.self) private var romsRootsStore

    var body: some View {
        // Read each time: a header and a few file sizes.
        if let details = DiscDetails(game.romAbsoluteURL) {
            Section("Disc Image") {
                LabeledContent("Format", value: details.formatText)
                LabeledContent("Size", value: details.sizeText)
                if !details.codecs.isEmpty {
                    LabeledContent("Compression", value: details.codecs.joined(separator: ", "))
                }
                if let sha1 = details.sha1 {
                    LabeledContent("SHA-1") {
                        Text(verbatim: sha1)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                conversionRow(details)
            }
        }
    }

    @ViewBuilder
    private func conversionRow(_ details: DiscDetails) -> some View {
        let compression = tools.compression(for: game).flatMap { $0.isDiscs ? $0 : nil }
        let back = tools.conversionBack(for: game)
        if compression != nil || back != nil {
            if tools.chdman == nil {
                CHDManInstallRow()
            } else {
                HStack {
                    Spacer()
                    if let compression {
                        Button("Compress to CHD") { run(compression) }
                    }
                    if let back {
                        Button(String(localized: "Convert Back to \(details.originalFormat)")) { run(back) }
                            .help("Turns the CHD back into the files it was made from, for an emulator that doesn't read CHD.")
                    }
                }
                .disabled(tools.isBusy)
            }
        }
    }

    private func run(_ conversion: ToolsCoordinator.GameConversion) {
        Task {
            await tools.run(conversion, title: game.title, romsRoots: romsRootsStore.rootURLs, scanCoordinator: scanCoordinator)
        }
    }
}

/// What a disc game's files are.
struct DiscDetails {
    var format: String
    var kind: CHDHeader.Kind?
    var discs = 1
    var tracks: Int?
    var bytes: Int64 = 0
    /// For a CHD: its size unpacked.
    var logicalBytes: Int64?
    var codecs: [String] = []
    var sha1: String?

    /// nil for a file that isn't a disc image.
    init?(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let parts = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .compactMap { DiscDetails(url.deletingLastPathComponent().appending(path: $0)) }
            guard let first = parts.first else { return nil }
            self = first
            discs = parts.count
            tracks = nil
            sha1 = parts.count == 1 ? first.sha1 : nil
            bytes = parts.reduce(0) { $0 + $1.bytes }
            let logical = parts.compactMap(\.logicalBytes)
            logicalBytes = logical.count == parts.count ? logical.reduce(0, +) : nil
            if Set(parts.map(\.format)).count > 1 { format = parts.map(\.format).joined(separator: ", ") }
            return
        }
        switch ext {
        case "chd":
            guard let header = CHDHeader.read(url) else { return nil }
            format = "CHD"
            kind = header.kind
            tracks = header.tracks
            bytes = MediaFolder.fileSize(url)
            logicalBytes = Int64(header.logicalBytes)
            codecs = Array(Set(header.codecs.map(Self.codecName))).sorted()
            sha1 = header.sha1
        case "cue", "gdi":
            let files = [url] + CHDConversion.tracks(of: url)
            format = ext == "cue" ? "CUE/BIN" : "GDI"
            tracks = files.count - 1
            bytes = files.reduce(0) { $0 + MediaFolder.fileSize($1) }
        case "iso", "cdi", "pbp", "cso", "zso":
            format = ext.uppercased()
            bytes = MediaFolder.fileSize(url)
        default:
            return nil
        }
    }

    var formatText: String {
        var parts = [format]
        switch kind {
        case .cd: parts.append(String(localized: "CD"))
        case .gdrom: parts.append(String(localized: "GD-ROM"))
        case .dvd: parts.append(String(localized: "DVD"))
        default: break
        }
        if discs > 1 { parts.append(String(localized: "\(discs) discs")) }
        if let tracks, tracks > 1 { parts.append(String(localized: "\(tracks) tracks")) }
        return parts.joined(separator: " · ")
    }

    var sizeText: String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        guard let logicalBytes, logicalBytes > 0 else { return size }
        let original = ByteCountFormatter.string(fromByteCount: logicalBytes, countStyle: .file)
        let percent = Int((Double(bytes) / Double(logicalBytes) * 100).rounded())
        return String(localized: "\(size), \(percent)% of \(original)")
    }

    /// What a CHD turns back into.
    var originalFormat: String {
        switch kind {
        case .gdrom: "GDI"
        case .dvd: "ISO"
        default: "CUE/BIN"
        }
    }

    private static func codecName(_ code: String) -> String {
        switch code {
        case "cdlz", "lzma": "LZMA"
        case "cdzl", "zlib": "Deflate"
        case "cdzs", "zstd": "Zstandard"
        case "cdfl", "flac": String(localized: "FLAC (audio)")
        case "huff": "Huffman"
        default: code
        }
    }
}
