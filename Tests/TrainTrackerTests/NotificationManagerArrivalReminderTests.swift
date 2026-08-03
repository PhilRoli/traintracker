// Tests/TrainTrackerTests/NotificationManagerArrivalReminderTests.swift
import XCTest
import UserNotifications
@testable import TrainTracker

@MainActor
final class NotificationManagerArrivalReminderTests: XCTestCase {

    func test_arrivalReminder_firesWhenWithinWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderMinutes = 10

        // Train arrives in 8 minutes (within 10m window)
        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(8 * 60),
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].identifier.hasPrefix("arrival-"))
        XCTAssertTrue(spy.posted[0].title.contains("WB 912"))
        XCTAssertTrue(spy.posted[0].title.contains("arrives"))
    }

    func test_arrivalReminder_doesNotFireOutsideWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderMinutes = 10

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(15 * 60),
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_arrivalReminder_doesNotFireTwiceForSameTrain() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()
        let arrival = Date().addingTimeInterval(5 * 60)
        let data = makeTrainData(scheduledArrival: arrival, isEnRoute: true)

        manager.process(data, settings: settings)
        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
    }

    func test_arrivalReminder_doesNotFireWhenDisabled() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.arrivalReminderEnabled = false

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_arrivalReminder_includesPlatformInBodyWhenAvailable() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            arrivalPlatform: "7",
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].body.contains("7"))
    }

    func test_arrivalReminder_fallsBackToStationNameWhenPlatformUnknown() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()

        let data = makeTrainData(
            scheduledArrival: Date().addingTimeInterval(5 * 60),
            arrivalPlatform: nil,
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].body.contains("Salzburg Hbf"))
    }

    func test_stateReset_arrivalReminderCanFireAgainForNewTrain() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()

        let arr1 = Date().addingTimeInterval(5 * 60)
        manager.process(makeTrainData(trainName: "WB 912", scheduledArrival: arr1, isEnRoute: true), settings: settings)
        XCTAssertEqual(spy.posted.count, 1)

        let arr2 = Date().addingTimeInterval(7 * 60)
        manager.process(makeTrainData(trainName: "WB 914", scheduledArrival: arr2, isEnRoute: true), settings: settings)
        XCTAssertEqual(spy.posted.count, 2)
    }
}
