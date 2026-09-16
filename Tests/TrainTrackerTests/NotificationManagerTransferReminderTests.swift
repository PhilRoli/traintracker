// Tests/TrainTrackerTests/NotificationManagerTransferReminderTests.swift
import XCTest
import UserNotifications
@testable import TrainTracker

@MainActor
final class NotificationManagerTransferReminderTests: XCTestCase {

    private func makeNextLeg(departurePlatform: String? = "3") -> TrainLegSummary {
        TrainLegSummary(
            trainName: "REX 1234",
            fromName: "Wien Meidling",
            toName: "Wiener Neustadt Hbf",
            scheduledDeparture: Date().addingTimeInterval(15 * 60),
            scheduledArrival: Date().addingTimeInterval(45 * 60),
            departureDelaySecs: 0,
            arrivalDelaySecs: 0,
            departurePlatform: departurePlatform,
            arrivalPlatform: nil
        )
    }

    func test_transferReminder_firesWhenWithinWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false
        settings.transferReminderMinutes = 10

        let data = makeTrainData(
            toName: "Wien Meidling",
            scheduledArrival: Date().addingTimeInterval(8 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].identifier.hasPrefix("transfer-"))
        XCTAssertTrue(spy.posted[0].title.contains("Wien Meidling"))
        XCTAssertTrue(spy.posted[0].body.contains("REX 1234"))
    }

    func test_transferReminder_doesNotFireOutsideWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false
        settings.transferReminderMinutes = 10

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(15 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_transferReminder_doesNotFireWhenNextLegIsNil() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true,
            nextLeg: nil
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_transferReminder_doesNotFireWhenDisabled() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false
        settings.transferReminderEnabled = false

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_transferReminder_doesNotFireTwiceForSameLeg() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false
        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )

        manager.process(data, settings: settings)
        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
    }

    func test_transferReminder_fallsBackToNoPlatformWording() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg(departurePlatform: nil)
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertFalse(spy.posted[0].body.contains("platform"))
        XCTAssertTrue(spy.posted[0].body.contains("REX 1234"))
    }

    func test_stateReset_transferReminderCanFireAgainForDifferentTrip() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false

        let data1 = makeTrainData(
            trainName: "RJX 60",
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )
        manager.process(data1, settings: settings)
        XCTAssertEqual(spy.posted.count, 1)

        let data2 = makeTrainData(
            trainName: "RJX 62",
            scheduledArrival: Date().addingTimeInterval(7 * 60),
            isEnRoute: true,
            nextLeg: makeNextLeg()
        )
        manager.process(data2, settings: settings)
        XCTAssertEqual(spy.posted.count, 2)
    }
}
