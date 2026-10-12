import Foundation
import Testing
@testable import AtticScraping

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
            _ = try await client.fetchGameInfo(title: "Mario", platformID: 7, credentials: TheGamesDBCredentials(apiKey: ""))
        }
    }

    @Test func successfulResponseMapsToGameInfo() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in
            (200, #"{"data": {"games": [{"id": 1, "game_title": "Mario"}]}}"#)
        }
        let client = makeClient()
        let info = try await client.fetchGameInfo(title: "Mario (USA)", platformID: 7, credentials: credentials)
        #expect(info.title == "Mario")
    }

    @Test func requestStripsReleaseTagsAndIncludesExpectedParameters() async throws {
        TheGamesDBStubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            guard request.url?.path.hasSuffix("/ByGameName") == true else { return (200, "{}") }
            #expect(query.contains("apikey=test-key"))
            #expect(query.contains("filter%5Bplatform%5D=7") || query.contains("filter[platform]=7"))
            #expect(query.contains("name=Mario") || query.contains("name=Mario%20"))
            return (200, #"{"data": {"games": [{"id": 1, "game_title": "Mario"}]}}"#)
        }
        let client = makeClient()
        _ = try await client.fetchGameInfo(title: "Mario (USA) (En,Fr)", platformID: 7, credentials: credentials)
    }

    @Test func noMatchThrowsNoMatch() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (200, #"{"data": {"games": []}}"#) }
        let client = makeClient()
        await #expect(throws: TheGamesDBError.noMatch) {
            _ = try await client.fetchGameInfo(title: "Unknown", platformID: 7, credentials: credentials)
        }
    }

    @Test func unauthorizedStatusThrowsCredentialsRejectedOrQuotaExceeded() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (401, #"{"message": "invalid api key"}"#) }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(title: "Mario", platformID: 7, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch TheGamesDBError.credentialsRejectedOrQuotaExceeded {
            // expected
        }
    }

    @Test func serverErrorThrowsNetwork() async throws {
        TheGamesDBStubURLProtocol.handler = { _ in (500, "server error") }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(title: "Mario", platformID: 7, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch TheGamesDBError.network {
            // expected
        }
    }
}

@Suite struct TheGamesDBSearchNameTests {
    @Test func stripsTagsAndKeepsTheFirstOfDualTitles() {
        #expect(TheGamesDBClient.searchName(fromTitle: "Super Metroid (USA)") == "Super Metroid")
        #expect(TheGamesDBClient.searchName(fromTitle: "Chrono Trigger (Japan) (En,Fr,De)") == "Chrono Trigger")
        #expect(TheGamesDBClient.searchName(fromTitle: "10-Yard Fight [!]") == "10-Yard Fight")
        #expect(TheGamesDBClient.searchName(fromTitle: "Super Mario Bros. 3") == "Super Mario Bros. 3")
        #expect(TheGamesDBClient.searchName(fromTitle: "3 Count Bout / Fire Suplex") == "3 Count Bout")
    }
}

@Suite(.serialized) struct TheGamesDBNameLookupTests {
    private func makeClient(cacheURL: URL? = nil) -> TheGamesDBClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TheGamesDBNamesStubURLProtocol.self]
        return TheGamesDBClient(session: URLSession(configuration: config), namesCacheURL: cacheURL)
    }

    private static let gameResponse = #"{"data": {"count": 1, "games": [{"id": 1, "game_title": "Sonic the Hedgehog", "genres": [1, 8], "developers": [1296], "publishers": [1]}]}}"#

    private static func respond(to request: URLRequest) -> (Int, String) {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/Genres") {
            return (200, #"{"data": {"count": 2, "genres": {"1": {"id": 1, "name": "Action"}, "8": {"id": 8, "name": "Platform"}}}}"#)
        }
        if path.hasSuffix("/Developers") {
            return (200, #"{"data": {"count": 1, "developers": {"1296": {"id": 1296, "name": "Sega"}}}}"#)
        }
        if path.hasSuffix("/Publishers") {
            return (200, #"{"data": {"count": 1, "publishers": {"1": {"id": 1, "name": "Sega of America"}}}}"#)
        }
        return (200, gameResponse)
    }

    @Test func resolvesGenreDeveloperAndPublisherNames() async throws {
        TheGamesDBNamesStubURLProtocol.handler = Self.respond
        let info = try await makeClient().fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: TheGamesDBCredentials(apiKey: "k"))
        #expect(info.genre == "Action, Platform")
        #expect(info.developer == "Sega")
        #expect(info.publisher == "Sega of America")
    }

    @Test func namesAreCachedOnDiskAndReused() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appending(path: "tgdb-names-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        TheGamesDBNamesStubURLProtocol.handler = Self.respond
        _ = try await makeClient(cacheURL: cacheURL).fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: TheGamesDBCredentials(apiKey: "k"))
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        // A new client (a later launch) answers from the file: the list
        // endpoints now fail, yet the names still resolve.
        TheGamesDBNamesStubURLProtocol.handler = { request in
            (request.url?.path ?? "").hasSuffix("/ByGameName") ? (200, Self.gameResponse) : (500, "down")
        }
        let info = try await makeClient(cacheURL: cacheURL).fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: TheGamesDBCredentials(apiKey: "k"))
        #expect(info.developer == "Sega")
    }

    @Test func screenshotIsFetchedOnlyWhenAskedFor() async throws {
        TheGamesDBNamesStubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/Games/Images") {
                return (200, #"{"data": {"count": 2, "base_url": {"original": "https://cdn.thegamesdb.net/images/original/"}, "images": {"1": [{"id": 9, "type": "titlescreen", "filename": "titlescreen/1-1.jpg"}, {"id": 10, "type": "screenshot", "filename": "screenshot/1-1.jpg"}]}}}"#)
            }
            return Self.respond(to: request)
        }
        let credentials = TheGamesDBCredentials(apiKey: "k")
        let with = try await makeClient().fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: credentials, wantsScreenshot: true)
        #expect(with.screenshotURL == URL(string: "https://cdn.thegamesdb.net/images/original/screenshot/1-1.jpg"))
        let without = try await makeClient().fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: credentials, wantsScreenshot: false)
        #expect(without.screenshotURL == nil)
    }

    @Test func failingNameListsStillReturnTheGame() async throws {
        TheGamesDBNamesStubURLProtocol.handler = { request in
            (request.url?.path ?? "").hasSuffix("/ByGameName") ? (200, Self.gameResponse) : (500, "down")
        }
        let info = try await makeClient().fetchGameInfo(title: "Sonic the Hedgehog", platformID: 18, credentials: TheGamesDBCredentials(apiKey: "k"))
        #expect(info.title == "Sonic the Hedgehog")
        #expect(info.genre == nil)
    }
}

final class TheGamesDBNamesStubURLProtocol: URLProtocol, @unchecked Sendable {
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
