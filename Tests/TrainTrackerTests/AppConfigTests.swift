// Tests/TrainTrackerTests/AppConfigTests.swift
import XCTest
@testable import TrainTracker

final class AppConfigTests: XCTestCase {
    var store: AppConfigStore!

    override func setUp() {
        // Use a unique suite name per test run to avoid cross-test pollution
        store = AppConfigStore(suiteName: "test-\(UUID().uuidString)")
    }

    func test_defaultConfigIsEmpty() {
        let config = store.load()
        XCTAssertNil(config.fromStation)
        XCTAssertNil(config.toStation)
        XCTAssertNil(config.trainNumber)
        XCTAssertTrue(config.savedRoutes.isEmpty)
    }

    func test_saveAndLoadRoundtrip() {
        var config = AppConfig()
        config.fromStation = Station(name: "Linz/Donau Hbf", id: "8100013")
        config.toStation = Station(name: "Salzburg Hbf", id: "8100002")
        config.trainNumber = "WB 912"
        config.savedRoutes = [SavedRoute(
            from: Station(name: "Linz/Donau Hbf", id: "8100013"),
            to: Station(name: "Salzburg Hbf", id: "8100002")
        )]

        store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.fromStation?.id, "8100013")
        XCTAssertEqual(loaded.fromStation?.name, "Linz/Donau Hbf")
        XCTAssertEqual(loaded.toStation?.id, "8100002")
        XCTAssertEqual(loaded.trainNumber, "WB 912")
        XCTAssertEqual(loaded.savedRoutes.count, 1)
        XCTAssertEqual(loaded.savedRoutes[0].from.id, "8100013")
    }

    func test_saveAndLoadWithNilTrainNumber() {
        var config = AppConfig()
        config.fromStation = Station(name: "Wien Hbf", id: "8103000")
        config.toStation = Station(name: "Linz/Donau Hbf", id: "8100013")
        config.trainNumber = nil

        store.save(config)
        let loaded = store.load()

        XCTAssertNil(loaded.trainNumber)
        XCTAssertEqual(loaded.fromStation?.id, "8103000")
    }

    func test_notificationSettings_defaultValues() {
        let settings = NotificationSettings()
        XCTAssertTrue(settings.departureReminderEnabled)
        XCTAssertEqual(settings.departureReminderMinutes, 10)
        XCTAssertTrue(settings.delayAlertEnabled)
        XCTAssertEqual(settings.delayAlertThresholdMinutes, 10)
        XCTAssertTrue(settings.platformChangeEnabled)
    }

    func test_notificationSettings_roundtrip() throws {
        var settings = NotificationSettings()
        settings.departureReminderMinutes = 7
        settings.delayAlertThresholdMinutes = 15
        settings.platformChangeEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)

        XCTAssertEqual(decoded.departureReminderMinutes, 7)
        XCTAssertEqual(decoded.delayAlertThresholdMinutes, 15)
        XCTAssertFalse(decoded.platformChangeEnabled)
    }

    func test_appConfig_notificationsDefaultsOnMissingKey() throws {
        // Simulate a stored config that predates NotificationSettings (no "notifications" key)
        let legacyJSON = """
        {"fromStation":{"name":"Linz/Donau Hbf","id":"8100013"},
         "toStation":{"name":"Salzburg Hbf","id":"8100002"},
         "trainNumber":"WB 912","savedRoutes":[]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: legacyJSON)
        XCTAssertTrue(config.notifications.departureReminderEnabled)
        XCTAssertEqual(config.notifications.departureReminderMinutes, 10)
    }
}
