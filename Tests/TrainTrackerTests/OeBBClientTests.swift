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
        let url = OeBBClient.journeysURL(fromId: "8100013", toId: "8100002", departure: dep)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("from=8100013"))
        XCTAssertTrue(url!.absoluteString.contains("to=8100002"))
        XCTAssertTrue(url!.absoluteString.contains("stopovers=true"))
        XCTAssertTrue(url!.absoluteString.contains("results=12"))
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
