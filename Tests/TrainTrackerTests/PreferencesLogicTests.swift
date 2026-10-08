// Tests/TrainTrackerTests/PreferencesLogicTests.swift
import XCTest
@testable import TrainTracker

final class PreferencesLogicTests: XCTestCase {
    private let linz = Station(name: "Linz/Donau Hbf", id: "1")
    private let salzburg = Station(name: "Salzburg Hbf", id: "2")
    private let wien = Station(name: "Wien Hbf", id: "3")

    func test_applyingRoute_savesNewRouteAndClearsTrain() {
        var config = AppConfig()
        config.trainNumber = "WB 912"
        let result = PreferencesLogic.applyingRoute(to: config, from: linz, via: nil, to: salzburg)
        XCTAssertEqual(result.savedRoutes, [SavedRoute(from: linz, toStation: salzburg, viaStation: nil)])
        XCTAssertNil(result.trainNumber)
    }

    func test_applyingRoute_sameRouteKeepsTrainAndDoesNotDuplicate() {
        var config = AppConfig()
        config.fromStation = linz
        config.toStation = salzburg
        config.trainNumber = "WB 912"
        config.savedRoutes = [SavedRoute(from: linz, toStation: salzburg, viaStation: nil)]
        let result = PreferencesLogic.applyingRoute(to: config, from: linz, via: nil, to: salzburg)
        XCTAssertEqual(result.savedRoutes.count, 1)
        XCTAssertEqual(result.trainNumber, "WB 912")
    }

    func test_applyingRoute_addingViaIsADifferentRoute() {
        var config = AppConfig()
        config.fromStation = linz
        config.toStation = salzburg
        config.trainNumber = "WB 912"
        let result = PreferencesLogic.applyingRoute(to: config, from: linz, via: wien, to: salzburg)
        XCTAssertEqual(result.viaStation, wien)
        XCTAssertNil(result.trainNumber)
        XCTAssertEqual(result.savedRoutes.first?.viaStation, wien)
    }

    func test_choices_includesCustomValueInOrder() {
        XCTAssertEqual(PreferencesLogic.choices(including: 7), [1, 2, 3, 5, 7, 10, 15, 20, 30, 45, 60])
        XCTAssertEqual(PreferencesLogic.choices(including: 10), PreferencesLogic.minuteChoices)
    }

    func test_sanitized_clampsOutOfRangeMinutes() {
        var config = AppConfig()
        config.notifications.departureReminderMinutes = -5
        config.notifications.delayAlertThresholdMinutes = 5_000
        let result = PreferencesLogic.sanitized(config)
        XCTAssertEqual(result.notifications.departureReminderMinutes, 1)
        XCTAssertEqual(result.notifications.delayAlertThresholdMinutes, 120)
    }

    func test_reminderKind_applyRoundTrips() {
        var settings = NotificationSettings()
        for kind in ReminderKind.allCases {
            kind.apply(enabled: false, minutes: 15, to: &settings)
            XCTAssertFalse(kind.isEnabled(in: settings))
            XCTAssertEqual(kind.minutes(in: settings), 15)
        }
    }
}
