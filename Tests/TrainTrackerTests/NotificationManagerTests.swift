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
}
