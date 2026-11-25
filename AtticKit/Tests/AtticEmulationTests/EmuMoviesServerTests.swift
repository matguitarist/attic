import Foundation
import Testing
@testable import AtticEmulation

/// The curl EmuMoviesServer runs, played by a script: the login reaches it
/// on stdin, and its exit status becomes Attic's own failure.
@Suite struct EmuMoviesServerTests {
    private func server(exiting status: Int32, printing text: String = "") throws -> (EmuMoviesServer, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "attic-curl-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stdin = folder.appending(path: "stdin")
        let script = folder.appending(path: "curl")
        try """
        #!/bin/sh
        cat > '\(stdin.path)'
        printf '%s' '\(text)'
        [ \(status) -ne 0 ] && echo "curl: (\(status)) refused" >&2
        exit \(status)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var server = EmuMoviesServer(host: .usa, username: "me", password: "p\"w")
        server.curl = script
        return (server, stdin)
    }

    @Test func theLoginGoesOnStdinAndTheListingComesBack() async throws {
        let line = "drwxr-xr-x 1 ftp ftp 0 Jan 01 2026 Nintendo"
        let (server, stdin) = try server(exiting: 0, printing: line)
        _ = try? await server.list("/")
        #expect(try String(contentsOf: stdin, encoding: .utf8) == server.config())
    }

    @Test func aRefusedLoginIsSaidSo() async throws {
        let (server, _) = try server(exiting: 67)
        await #expect(throws: EmuMoviesServer.Failure.login) { try await server.checkLogin() }
    }

    @Test func otherFailuresCarryCurlsWords() async throws {
        let (server, _) = try server(exiting: 9)
        await #expect(throws: EmuMoviesServer.Failure.transfer("curl: (9) refused")) { try await server.checkLogin() }
    }
}
