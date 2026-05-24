// Tests/TrainTrackerTests/StatusBarControllerTests.swift
import XCTest
@testable import TrainTracker

final class StatusBarControllerTests: XCTestCase {
    func test_titleForNoConfig() {
        let title = StatusBarController.titleString(for: .noConfig, consecutiveErrors: 0)
        XCTAssertEqual(title, "🚂")
    }

    func test_titleForPickTrain() {
        let title = StatusBarController.titleString(for: .pickTrain([]), consecutiveErrors: 0)
        XCTAssertEqual(title, "🚂")
    }

    func test_titleForErrorAfterTwoFailures() {
        let title = StatusBarController.titleString(for: .error("oops"), consecutiveErrors: 2)
        XCTAssertEqual(title, "🚂 (!)")
    }

    func test_titleWaitingToDepartShowsCountdown() {
        let now = Date()
        let dep = now.addingTimeInterval(12 * 60)  // departs in 12 minutes
        let arr = now.addingTimeInterval(90 * 60)
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, depDelay: 0, isEnRoute: false)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 in 12m")
    }

    func test_titleEnRouteOnTime() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)  // departed 30 min ago
        let arr = now.addingTimeInterval(72 * 60)   // arrives at now + 72 min → HH:MM
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 72m")
    }

    func test_titleEnRouteDelayed() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)
        let arr = now.addingTimeInterval(72 * 60)
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 180, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0, now: now)
        // rtArr = arr + 180s = now + 72*60 + 180 = now + 4500s → 75 minutes
        XCTAssertEqual(title, "🟦 WB 912 75m +3m")
    }

    func test_titleArrived() {
        let now = Date()
        let dep = now.addingTimeInterval(-120 * 60)
        let arr = now.addingTimeInterval(-10 * 60)   // arrived 10 min ago
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 Arrived")
    }

    // MARK: - trainTypeEmoji

    func test_trainTypeEmoji() {
        XCTAssertEqual(StatusBarController.trainTypeEmoji("RJX 100"), "⚡")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("RJ 200"),  "🚄")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("WB 912"),  "🟦")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("ICE 50"),  "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("IC 50"),   "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("EC 50"),   "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("REX 3"),   "🚂")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("EN 414"),  "🌙")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("NJ 414"),  "🌙")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("S1"),      "🚇")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("Bus 100"), "🚌")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("R 3456"),  "🚊")
    }

    // MARK: - Helpers

    private func makeTrainData(
        name: String, dep: Date, arr: Date,
        depDelay: Int = 0, arrDelay: Int = 0, isEnRoute: Bool = false
    ) -> TrainData {
        TrainData(
            trainName: name, fromName: "A", toName: "B",
            scheduledDeparture: dep, scheduledArrival: arr,
            departureDelaySecs: depDelay, arrivalDelaySecs: arrDelay,
            departurePlatform: nil, arrivalPlatform: nil,
            stopovers: [], isEnRoute: isEnRoute
        )
    }
}
