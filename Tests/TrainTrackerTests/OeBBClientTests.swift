// Tests/TrainTrackerTests/OeBBClientTests.swift
import XCTest
@testable import TrainTracker

final class OeBBClientTests: XCTestCase {
    func test_searchStationsURL() {
        let url = OeBBClient.locationsURL(query: "Linz Hbf")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("oebb.rolinek.at"))
        XCTAssertTrue(url!.absoluteString.contains("locations"))
        XCTAssertTrue(url!.absoluteString.contains("Linz"))
    }

    func test_searchStationsURL_encodesSpecialChars() {
        let url = OeBBClient.locationsURL(query: "St. Pölten Hbf")
        XCTAssertNotNil(url)
        // space and ö must be percent-encoded
        XCTAssertFalse(url!.absoluteString.contains(" "))
        XCTAssertFalse(url!.absoluteString.contains("ö"))
    }

    func test_journeysURL() {
        let dep = Date(timeIntervalSince1970: 1_716_548_160) // fixed timestamp
        let url = OeBBClient.journeysURL(fromId: "8100013", toId: "8100002", departure: dep, viaId: nil)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("from=8100013"))
        XCTAssertTrue(url!.absoluteString.contains("to=8100002"))
        XCTAssertTrue(url!.absoluteString.contains("stopovers=true"))
        XCTAssertTrue(url!.absoluteString.contains("results=12"))
    }

    func test_journeysURL_includesViaWhenSet() {
        let dep = Date(timeIntervalSince1970: 1_716_548_160)
        let url = OeBBClient.journeysURL(fromId: "8100013", toId: "8100108", departure: dep, viaId: "8100523")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("via=8100523"))
    }

    func test_journeysURL_omitsViaWhenNil() {
        let dep = Date(timeIntervalSince1970: 1_716_548_160)
        let url = OeBBClient.journeysURL(fromId: "8100013", toId: "8100002", departure: dep, viaId: nil)
        XCTAssertNotNil(url)
        XCTAssertFalse(url!.absoluteString.contains("via="))
    }

    func test_refreshJourneyURL() {
        let url = OeBBClient.refreshJourneyURL(token: "abc123")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("/journeys/abc123"))
        XCTAssertTrue(url!.absoluteString.contains("stopovers=true"))
    }

    func test_refreshJourneyURL_encodesSlashInToken() {
        let url = OeBBClient.refreshJourneyURL(token: "tok/abc==")
        XCTAssertNotNil(url)
        XCTAssertFalse(url!.absoluteString.contains("tok/abc"), "Slash in token must be percent-encoded")
        XCTAssertTrue(url!.absoluteString.contains("tok%2Fabc"), "Slash must be encoded as %2F")
    }
}

// MARK: - HTTP behaviour (stubbed transport)

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OeBBClientHTTPTests: XCTestCase {
    private func makeClient() -> OeBBClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return OeBBClient(session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func test_searchStations_decodesLocations() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data(#"[{"id":"1","name":"Linz/Donau Hbf","type":"stop"}]"#.utf8))
        }
        let results = try await makeClient().searchStations(query: "Linz")
        XCTAssertEqual(results.map(\.name), ["Linz/Donau Hbf"])
    }

    func test_searchStations_httpErrorThrows() async {
        StubURLProtocol.handler = { _ in (503, Data()) }
        do {
            _ = try await makeClient().searchStations(query: "Linz")
            XCTFail("expected throw")
        } catch OeBBError.httpError(let code) {
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_refreshJourney_404SurfacesStatusCode() async {
        StubURLProtocol.handler = { _ in (404, Data()) }
        do {
            _ = try await makeClient().refreshJourney(token: "tok")
            XCTFail("expected throw")
        } catch OeBBError.httpError(let code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_fetchJourneys_malformedBodyThrows() async {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        do {
            _ = try await makeClient().fetchJourneys(fromId: "1", toId: "2", departure: Date(), viaId: nil)
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}
