import Foundation
import ProcessKit

/// The EmuMovies file server over FTP with TLS, through macOS's `curl`
/// (URLSession no longer speaks FTP). The login goes to curl on its
/// standard input, never on its command line, where any process could
/// read it.
public struct EmuMoviesServer: Sendable {
    public enum Host: String, CaseIterable, Sendable {
        /// The main server, in the USA.
        case usa = "files.emumovies.com"
        /// Its copy in Europe.
        case europe = "files2.emumovies.com"
    }

    public enum Failure: Error, Equatable {
        /// The username or password was refused.
        case login
        /// Anything else curl reports, with its message.
        case transfer(String)
        case cancelled
    }

    public let host: Host
    let username: String
    let password: String
    var curl = URL(fileURLWithPath: "/usr/bin/curl")

    public init(host: Host, username: String, password: String) {
        self.host = host
        self.username = username
        self.password = password
    }

    /// What's in a folder (`path` ends with a slash).
    public func list(_ path: String) async throws -> [EmuMovies.Entry] {
        let listing = String(decoding: try await run([url(path)], output: nil), as: UTF8.self)
        let entries = EmuMovies.entries(inListing: listing)
        // A listing in a form Attic doesn't know, rather than an empty folder.
        if entries.isEmpty, let line = listing.split(whereSeparator: \.isNewline).first {
            throw Failure.transfer("Unreadable listing: \(line.prefix(120))")
        }
        return entries
    }

    /// Whether the login works.
    public func checkLogin() async throws {
        _ = try await run([url("/")], output: nil)
    }

    /// Downloads `path` to `destination`, carrying on from what's already
    /// there. `progress` gets the bytes written so far, about twice a second.
    public func download(_ path: String, to destination: URL, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                progress(Int64(size))
            }
        }
        defer { watcher.cancel() }
        _ = try await run(["--continue-at", "-", url(path)], output: destination)
    }

    func url(_ path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "ftp://\(host.rawValue)\(encoded)"
    }

    /// The config curl reads from its standard input: the login, quoted.
    func config() -> String {
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "user = \(quoted(username + ":" + password))\n"
    }

    private func run(_ arguments: [String], output: URL?) async throws -> Data {
        // --globoff: names hold brackets, which curl would read as ranges.
        let arguments = ["--silent", "--show-error", "--fail", "--globoff", "--ssl-reqd",
                         "--connect-timeout", "30", "--speed-limit", "1024", "--speed-time", "60",
                         "--config", "-"]
            + (output.map { ["--output", $0.path] } ?? []) + arguments
        let result: Shell.Output
        do {
            result = try await Shell.run(curl.path, arguments, options: Shell.Options(input: .data(Data(config().utf8))))
        } catch is CancellationError {
            throw Failure.cancelled
        } catch {
            throw Failure.transfer(error.localizedDescription)
        }
        switch result.status {
        case 0: return result.stdout
        case _ where result.signal != nil: throw Failure.cancelled
        // 67: login denied. 9: the server refused the folder, which it
        // also does to a refused login.
        case 67: throw Failure.login
        default: throw Failure.transfer(result.errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
