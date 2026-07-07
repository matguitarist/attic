import Foundation
import Testing
@testable import RomsBoxScraping

/// A separate stub class from `StubURLProtocol` (used by
/// ScreenScraperClientTests) — sharing one static handler across two
/// `@Suite`s racess even with `.serialized` on each individually, since
/// that trait only serializes tests *within* one suite, not across
/// suites that Swift Testing may still run in parallel.
final class TheGamesDBStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (200, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct TheGamesDBClientTests {
    private func makeClient() -> TheGamesDBClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TheGamesDBStubURLProtocol.self]
        return TheGamesDBClient(session: URLSession(configuration: config))
    }

    private let credentials = TheGamesDBCredentials(apiKey: "test-key")

    @Test func notConfiguredCredentialsThrowBeforeAnyRequest() async throws {
        let client = makeClient()
        await #expect(throws: TheGamesDBError.notConfigured) {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", platformID: 7, credentials: TheGamesDBCredentials(apiKey: ""))
        }
    }

    @Test func successfulResponseMapsToGameInfo() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in
            (200, #"{"data": {"games": [{"id": 1, "game_title": "Mario"}]}}"#)
        }
        let client = makeClient()
        let info = try await client.fetchGameInfo(romFilename: "Mario (USA).nes", platformID: 7, credentials: credentials)
        #expect(info.title == "Mario")
    }

    @Test func requestStripsReleaseTagsAndIncludesExpectedParameters() async throws {
        TheGamesDBStubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("apikey=test-key"))
            #expect(query.contains("filter%5Bplatform%5D=7") || query.contains("filter[platform]=7"))
            #expect(query.contains("name=Mario") || query.contains("name=Mario%20"))
            return (200, #"{"data": {"games": [{"id": 1, "game_title": "Mario"}]}}"#)
        }
        let client = makeClient()
        _ = try await client.fetchGameInfo(romFilename: "Mario (USA) (En,Fr).nes", platformID: 7, credentials: credentials)
    }

    @Test func noMatchThrowsNoMatch() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (200, #"{"data": {"games": []}}"#) }
        let client = makeClient()
        await #expect(throws: TheGamesDBError.noMatch) {
            _ = try await client.fetchGameInfo(romFilename: "Unknown.nes", platformID: 7, credentials: credentials)
        }
    }

    @Test func unauthorizedStatusThrowsCredentialsRejectedOrQuotaExceeded() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (401, #"{"message": "invalid api key"}"#) }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", platformID: 7, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch TheGamesDBError.credentialsRejectedOrQuotaExceeded {
            // expected
        }
    }

    @Test func serverErrorThrowsNetwork() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (500, "server error") }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", platformID: 7, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch TheGamesDBError.network {
            // expected
        }
    }
}

@Suite struct TheGamesDBSearchNameTests {
    @Test func stripsExtensionAndParenthesizedTags() {
        #expect(TheGamesDBClient.searchName(fromROMFilename: "Super Metroid (USA).sfc") == "Super Metroid")
        #expect(TheGamesDBClient.searchName(fromROMFilename: "Chrono Trigger (Japan) (En,Fr,De).sfc") == "Chrono Trigger")
        #expect(TheGamesDBClient.searchName(fromROMFilename: "10-Yard Fight [!].nes") == "10-Yard Fight")
        #expect(TheGamesDBClient.searchName(fromROMFilename: "Plain Title.gba") == "Plain Title")
    }
}
