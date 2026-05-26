// Tests/TrainTrackerTests/NotificationManagerTests.swift
import XCTest
import UserNotifications
@testable import TrainTracker

// MARK: - Spy

final class NotificationSpy: NotificationScheduler {
    struct Posted {
        let identifier: String
        let title: String
        let body: String
    }
    private(set) var posted: [Posted] = []

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        posted.append(Posted(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body
        ))
        completionHandler?(nil)
    }
}

// MARK: - Tests

@MainActor
final class NotificationManagerTests: XCTestCase {

    // MARK: - Helpers

    func makeManager() -> (NotificationManager, NotificationSpy) {
        let spy = NotificationSpy()
        let manager = NotificationManager(scheduler: spy)
        return (manager, spy)
    }

    func makeTrainData(
        trainName: String = "WB 912",
        fromName: String = "Linz/Donau Hbf",
        toName: String = "Salzburg Hbf",
        scheduledDeparture: Date = Date().addingTimeInterval(3600),
        scheduledArrival: Date = Date().addingTimeInterval(7200),
        departureDelaySecs: Int = 0,
        arrivalDelaySecs: Int = 0,
        departurePlatform: String? = nil,
        arrivalPlatform: String? = nil,
        isEnRoute: Bool = false
    ) -> TrainData {
        TrainData(
            trainName: trainName,
            fromName: fromName,
            toName: toName,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            departureDelaySecs: departureDelaySecs,
            arrivalDelaySecs: arrivalDelaySecs,
            departurePlatform: departurePlatform,
            arrivalPlatform: arrivalPlatform,
            stopovers: [],
            isEnRoute: isEnRoute
        )
    }

    // MARK: - Departure reminder

    func test_departureReminder_firesWhenWithinWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.departureReminderMinutes = 10

        // Train departs in 8 minutes (within 10m window)
        let data = makeTrainData(
            scheduledDeparture: Date().addingTimeInterval(8 * 60),
            isEnRoute: false
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].identifier.hasPrefix("departure-"))
        XCTAssertTrue(spy.posted[0].title.contains("WB 912"))
        XCTAssertTrue(spy.posted[0].title.contains("departs"))
    }

    func test_departureReminder_doesNotFireOutsideWindow() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.departureReminderMinutes = 10

        // Train departs in 15 minutes (outside 10m window)
        let data = makeTrainData(
            scheduledDeparture: Date().addingTimeInterval(15 * 60),
            isEnRoute: false
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_departureReminder_doesNotFireWhenEnRoute() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()

        let data = makeTrainData(
            scheduledDeparture: Date().addingTimeInterval(5 * 60),
            isEnRoute: true
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_departureReminder_doesNotFireTwiceForSameTrain() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()
        let departure = Date().addingTimeInterval(5 * 60)
        let data = makeTrainData(scheduledDeparture: departure, isEnRoute: false)

        manager.process(data, settings: settings)
        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
    }

    func test_departureReminder_doesNotFireWhenDisabled() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.departureReminderEnabled = false

        let data = makeTrainData(
            scheduledDeparture: Date().addingTimeInterval(5 * 60),
            isEnRoute: false
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }

    func test_departureReminder_includesPlatformInBodyWhenAvailable() {
        let (manager, spy) = makeManager()
        let settings = NotificationSettings()

        let data = makeTrainData(
            scheduledDeparture: Date().addingTimeInterval(5 * 60),
            departurePlatform: "3",
            isEnRoute: false
        )

        manager.process(data, settings: settings)

        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].body.contains("3"))
    }

    // MARK: - Delay alert

    func test_delayAlert_firesWhenCrossingThreshold() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.delayAlertThresholdMinutes = 10

        let dep = Date().addingTimeInterval(-3600)
        let arr = Date().addingTimeInterval(3600)

        // First call: 5 minutes late (below threshold)
        manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                       arrivalDelaySecs: 5 * 60, isEnRoute: true), settings: settings)
        XCTAssertEqual(spy.posted.count, 0)

        // Second call: 12 minutes late (crosses 10m threshold)
        manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                       arrivalDelaySecs: 12 * 60, isEnRoute: true), settings: settings)
        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertTrue(spy.posted[0].identifier.hasPrefix("delay-"))
        XCTAssertTrue(spy.posted[0].title.contains("WB 912"))
        XCTAssertTrue(spy.posted[0].title.contains("+12m"))
    }

    func test_delayAlert_doesNotFireAgainWhenAlreadyAboveThreshold() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.delayAlertThresholdMinutes = 10

        let dep = Date().addingTimeInterval(-3600)
        let arr = Date().addingTimeInterval(3600)

        // Cross threshold
        manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                       arrivalDelaySecs: 12 * 60, isEnRoute: true), settings: settings)
        // Delay increases further (still above threshold)
        manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                       arrivalDelaySecs: 18 * 60, isEnRoute: true), settings: settings)

        XCTAssertEqual(spy.posted.count, 1, "Should only fire once when crossing, not on every update above threshold")
    }

    func test_delayAlert_doesNotFireWhenDisabled() {
        let (manager, spy) = makeManager()
        var settings = NotificationSettings()
        settings.delayAlertEnabled = false
        settings.delayAlertThresholdMinutes = 10

        let dep = Date().addingTimeInterval(-3600)
        let arr = Date().addingTimeInterval(3600)

        manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                       arrivalDelaySecs: 15 * 60, isEnRoute: true), settings: settings)

        XCTAssertEqual(spy.posted.count, 0)
    }
}
