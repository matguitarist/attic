import Foundation
import Testing
@testable import AtticScraping

/// Intercepts all requests so tests never touch the real network — no real
/// devID/devPassword exists to test against yet anyway.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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

@Suite(.serialized) struct ScreenScraperClientTests {
    private func makeClient() -> ScreenScraperClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return ScreenScraperClient(session: URLSession(configuration: config))
    }

    private let credentials = ScreenScraperCredentials(devID: "test-dev", devPassword: "test-pass", userID: "testuser", userPassword: "testpass")

    @Test func notConfiguredCredentialsThrowBeforeAnyRequest() async throws {
        let client = makeClient()
        let empty = ScreenScraperCredentials(devID: "", devPassword: "")
        await #expect(throws: ScreenScraperError.notConfigured) {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", romSizeBytes: nil, systemeID: 3, credentials: empty)
        }
    }

    @Test func successfulResponseMapsToGameInfo() async throws {
        StubURLProtocol.handler = { _ in
            (200, #"{"response": {"jeu": {"noms": [{"region": "us", "text": "Mario"}]}}}"#)
        }
        let client = makeClient()
        let info = try await client.fetchGameInfo(romFilename: "Mario.nes", romSizeBytes: 40960, systemeID: 3, credentials: credentials)
        #expect(info.title == "Mario")
    }

    @Test func requestIncludesExpectedQueryParameters() async throws {
        StubURLProtocol.handler = { request in
            let url = request.url!
            let query = url.query ?? ""
            #expect(query.contains("devid=test-dev"))
            #expect(query.contains("systemeid=3"))
            #expect(query.contains("ssid=testuser"))
            return (200, #"{"response": {"jeu": {"noms": [{"region": "us", "text": "Mario"}]}}}"#)
        }
        let client = makeClient()
        _ = try await client.fetchGameInfo(romFilename: "Mario.nes", romSizeBytes: nil, systemeID: 3, credentials: credentials)
    }

    @Test func noMatchThrowsNoMatch() async throws {
        StubURLProtocol.handler = { _ in (200, #"{"response": {}}"#) }
        let client = makeClient()
        await #expect(throws: ScreenScraperError.noMatch) {
            _ = try await client.fetchGameInfo(romFilename: "Unknown.nes", romSizeBytes: nil, systemeID: 3, credentials: credentials)
        }
    }

    @Test func plainTextErrorBodyThrowsCredentialsRejectedOrQuotaExceeded() async throws {
        StubURLProtocol.handler = { _ in (200, "Erreur : Login/mot de pass developpeur invalide.") }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", romSizeBytes: nil, systemeID: 3, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch ScreenScraperError.credentialsRejectedOrQuotaExceeded {
            // expected
        }
    }

    @Test func nonSuccessHTTPStatusThrowsNetwork() async throws {
        StubURLProtocol.handler = { _ in (500, "server error") }
        let client = makeClient()
        do {
            _ = try await client.fetchGameInfo(romFilename: "Mario.nes", romSizeBytes: nil, systemeID: 3, credentials: credentials)
            Issue.record("expected an error to be thrown")
        } catch ScreenScraperError.network {
            // expected
        }
    }
}
