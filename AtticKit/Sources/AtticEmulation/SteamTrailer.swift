import Foundation
import AVFoundation

/// A Steam store trailer saved as one MP4. The store streams trailers
/// only as HLS of fragmented MP4, video and audio apart: each is an init
/// segment and its chunks, which joined end to end make a file of their
/// own, and the two are then copied into one without re-encoding.
public enum SteamTrailer {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// Saves the trailer of `master` (its HLS playlist) at `destination`,
    /// no taller than `maxHeight`.
    public static func save(master: URL, to destination: URL, maxHeight: Int = 720, fetch: Fetch) async throws {
        let playlist = String(decoding: try await fetch(master), as: UTF8.self)
        guard let streams = streams(inMaster: playlist, base: master, maxHeight: maxHeight) else { throw URLError(.cannotParseResponse) }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "Attic-trailer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let video = scratch.appending(path: "video.mp4")
        try await join(streams.video, into: video, fetch: fetch)
        var audio: URL?
        if let audioPlaylist = streams.audio {
            let file = scratch.appending(path: "audio.m4a")
            if (try? await join(audioPlaylist, into: file, fetch: fetch)) != nil { audio = file }
        }
        var output = scratch.appending(path: "trailer.mp4")
        // The video alone, a file already, when the sound won't go in: a
        // preview plays muted anyway.
        let combined: Void? = if audio != nil { try? await combine(video: video, audio: audio, into: output) } else { nil }
        if combined == nil { output = video }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: output, to: destination)
    }

    /// The tallest video stream up to `maxHeight` (else the shortest) and
    /// the audio playlist it goes with.
    static func streams(inMaster text: String, base: URL, maxHeight: Int) -> (video: URL, audio: URL?)? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var variants: [(height: Int, url: URL)] = []
        var audio: URL?
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-X-MEDIA:"), line.contains("TYPE=AUDIO"), let uri = attribute("URI", in: line) {
                audio = URL(string: uri, relativeTo: base)?.absoluteURL
            } else if line.hasPrefix("#EXT-X-STREAM-INF:"),
                      let next = lines.dropFirst(index + 1).first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                      let url = URL(string: next, relativeTo: base)?.absoluteURL {
                let height = attribute("RESOLUTION", in: line)?.split(separator: "x").last.flatMap { Int($0) } ?? 0
                variants.append((height, url))
            }
        }
        let fitting = variants.filter { $0.height <= maxHeight }.max { $0.height < $1.height }
        guard let video = fitting ?? variants.min(by: { $0.height < $1.height }) else { return nil }
        return (video.url, audio)
    }

    /// A media playlist's init segment, then its chunks in order.
    static func segments(inPlaylist text: String, base: URL) -> [URL] {
        var urls: [URL] = []
        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if line.hasPrefix("#EXT-X-MAP:"), let uri = attribute("URI", in: line) {
                urls.insert(contentsOf: [URL(string: uri, relativeTo: base)?.absoluteURL].compactMap { $0 }, at: 0)
            } else if !line.hasPrefix("#"), let url = URL(string: line, relativeTo: base)?.absoluteURL {
                urls.append(url)
            }
        }
        return urls
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: name + "=") else { return nil }
        let rest = line[range.upperBound...]
        if rest.hasPrefix("\"") {
            return rest.dropFirst().split(separator: "\"", maxSplits: 1).first.map(String.init)
        }
        return rest.split(separator: ",", maxSplits: 1).first.map(String.init)
    }

    private static func join(_ playlist: URL, into file: URL, fetch: Fetch) async throws {
        let text = String(decoding: try await fetch(playlist), as: UTF8.self)
        let parts = segments(inPlaylist: text, base: playlist)
        guard parts.count > 1 else { throw URLError(.cannotParseResponse) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        for part in parts {
            try handle.write(contentsOf: try await fetch(part))
        }
    }

    /// The samples of `video` and `audio` copied into one MP4. (An export
    /// session won't take fragmented files as they are.)
    private static func combine(video: URL, audio: URL?, into output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var copies: [SampleCopy] = []
        for (url, type) in [(video, AVMediaType.video), (audio, .audio)] {
            guard let url else { continue }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: type).first else { continue }
            let reader = try AVAssetReader(asset: asset)
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(readerOutput)
            let input = AVAssetWriterInput(mediaType: type, outputSettings: nil,
                                           sourceFormatHint: try await track.load(.formatDescriptions).first)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            copies.append(SampleCopy(reader: reader, output: readerOutput, input: input))
        }
        guard writer.startWriting() else { throw writer.error ?? URLError(.cannotCreateFile) }
        writer.startSession(atSourceTime: .zero)
        // Both at once: the writer waits for each track to keep up with
        // the other.
        await withTaskGroup(of: Void.self) { group in
            for copy in copies { group.addTask { await copy.run() } }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? URLError(.cannotCreateFile) }
    }
}

/// One track's samples, from its reader to the writer's input.
private final class SampleCopy: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput

    init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        (self.reader, self.output, self.input) = (reader, output, input)
    }

    func run() async {
        reader.startReading()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "Attic.SteamTrailer")) { [self] in
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        input.markAsFinished()
                        done.resume()
                        return
                    }
                }
            }
        }
    }
}
