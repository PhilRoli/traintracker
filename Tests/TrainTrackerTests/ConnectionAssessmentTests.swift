// Tests/TrainTrackerTests/ConnectionAssessmentTests.swift
import XCTest
@testable import TrainTracker

final class ConnectionAssessmentTests: XCTestCase {
    private let arrival = Date(timeIntervalSince1970: 1_800_000_000)

    private func data(
        arrivalDelay: Int, nextDeparture: TimeInterval, nextDelay: Int = 0, reachable: Bool?
    ) -> TrainData {
        let next = TrainLegSummary(
            trainName: "REX 1", fromName: "Wien Meidling", toName: "Bad Vöslau",
            scheduledDeparture: arrival.addingTimeInterval(nextDeparture),
            scheduledArrival: arrival.addingTimeInterval(nextDeparture + 1_800),
            departureDelaySecs: nextDelay, arrivalDelaySecs: 0,
            departurePlatform: nil, arrivalPlatform: nil, reachable: reachable
        )
        return TrainData(
            trainName: "RJX 1", fromName: "Linz", toName: "Wien Meidling",
            scheduledDeparture: arrival.addingTimeInterval(-3_600), scheduledArrival: arrival,
            departureDelaySecs: 0, arrivalDelaySecs: arrivalDelay,
            departurePlatform: nil, arrivalPlatform: nil, stopovers: [], isEnRoute: true, nextLeg: next
        )
    }

    func test_noNextLeg_hasNoConnection() {
        let single = TrainData(
            trainName: "RJX 1", fromName: "A", toName: "B", scheduledDeparture: arrival, scheduledArrival: arrival,
            departureDelaySecs: 0, arrivalDelaySecs: 0, departurePlatform: nil, arrivalPlatform: nil,
            stopovers: [], isEnRoute: false
        )
        XCTAssertNil(single.connection)
    }

    func test_gapUsesRealTimeDelaysOnBothLegs() {
        let connection = data(arrivalDelay: 300, nextDeparture: 900, nextDelay: 120, reachable: true).connection
        XCTAssertEqual(connection?.gapSecs, 720)
        XCTAssertEqual(connection?.text, "✅ Connection OK — 12 min to change")
    }

    func test_upstreamUnreachableOverridesPositiveGap() {
        let connection = data(arrivalDelay: 0, nextDeparture: 240, reachable: false).connection
        XCTAssertEqual(connection?.text, "⚠️ Connection unlikely — only 4 min to change")
    }

    func test_missingReachableFlagFallsBackToGap() {
        XCTAssertEqual(data(arrivalDelay: 0, nextDeparture: 600, reachable: nil).connection?.isLikely, true)
        XCTAssertEqual(data(arrivalDelay: 0, nextDeparture: 30, reachable: nil).connection?.text,
                       "⚠️ Connection unlikely — no time to change")
    }

    func test_negativeGapIsMissed() {
        let connection = data(arrivalDelay: 600, nextDeparture: 300, reachable: true).connection
        XCTAssertEqual(connection?.text, "⚠️ Connection missed — next train leaves 5 min before arrival")
    }
}
