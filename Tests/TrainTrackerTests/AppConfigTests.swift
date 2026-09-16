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
            toStation: Station(name: "Salzburg Hbf", id: "8100002")
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
        XCTAssertTrue(settings.arrivalReminderEnabled)
        XCTAssertEqual(settings.arrivalReminderMinutes, 10)
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

    func test_notificationSettings_decodesMissingArrivalKeys() throws {
        // Simulates a NotificationSettings blob saved before the arrival reminder fields existed.
        let legacyJSON = """
        {"departureReminderEnabled":true,"departureReminderMinutes":10,
         "delayAlertEnabled":true,"delayAlertThresholdMinutes":10,
         "platformChangeEnabled":true}
        """
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.arrivalReminderEnabled)
        XCTAssertEqual(decoded.arrivalReminderMinutes, 10)
    }

    func test_appConfig_notificationsDefaultsOnMissingKey() throws {
        // Simulate a stored config that predates NotificationSettings (no "notifications" key)
        let legacyJSON = """
        {"fromStation":{"name":"Linz/Donau Hbf","id":"8100013"},
         "toStation":{"name":"Salzburg Hbf","id":"8100002"},
         "trainNumber":"WB 912","savedRoutes":[]}
        """
        let legacyData = Data(legacyJSON.utf8)

        let config = try JSONDecoder().decode(AppConfig.self, from: legacyData)
        XCTAssertTrue(config.notifications.departureReminderEnabled)
        XCTAssertEqual(config.notifications.departureReminderMinutes, 10)
    }

    func test_setStatusLine_writesString() {
        store.setStatusLine("⚡ RJX 12m")
        let value = UserDefaults(suiteName: store.suiteName)?.string(forKey: "statusLine")
        XCTAssertEqual(value, "⚡ RJX 12m")
    }

    func test_setStatusLine_clearsWhenNil() {
        store.setStatusLine("⚡ RJX 12m")
        store.setStatusLine(nil)
        let value = UserDefaults(suiteName: store.suiteName)?.string(forKey: "statusLine")
        XCTAssertNil(value)
    }

    func test_saveAndLoadRoundtrip_withViaAndSecondLeg() {
        var config = AppConfig()
        config.fromStation = Station(name: "Linz Hbf", id: "8100013")
        config.viaStation = Station(name: "Wien Meidling", id: "8100523")
        config.toStation = Station(name: "Wiener Neustadt Hbf", id: "8100108")
        config.trainNumber = "RJX 60"
        config.secondLegTrainNumber = "REX 1234"

        store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.viaStation?.id, "8100523")
        XCTAssertEqual(loaded.secondLegTrainNumber, "REX 1234")
    }

    func test_appConfig_viaFieldsDefaultNilOnLegacyConfig() throws {
        // Simulate a stored config saved before via-routes existed (no viaStation/secondLegTrainNumber keys)
        let legacyJSON = """
        {"fromStation":{"name":"Linz/Donau Hbf","id":"8100013"},
         "toStation":{"name":"Salzburg Hbf","id":"8100002"},
         "trainNumber":"WB 912","savedRoutes":[]}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(config.viaStation)
        XCTAssertNil(config.secondLegTrainNumber)
    }

    func test_savedRoute_displayName_includesVia() {
        let route = SavedRoute(
            from: Station(name: "Linz Hbf", id: "8100013"),
            toStation: Station(name: "Wiener Neustadt Hbf", id: "8100108"),
            viaStation: Station(name: "Wien Meidling", id: "8100523")
        )
        XCTAssertEqual(route.displayName, "Linz Hbf → Wien Meidling → Wiener Neustadt Hbf")
    }

    func test_savedRoute_displayName_withoutVia() {
        let route = SavedRoute(
            from: Station(name: "Linz Hbf", id: "8100013"),
            toStation: Station(name: "Salzburg Hbf", id: "8100002")
        )
        XCTAssertEqual(route.displayName, "Linz Hbf → Salzburg Hbf")
    }

    func test_notificationSettings_defaultValues_includesTransferReminder() {
        let settings = NotificationSettings()
        XCTAssertTrue(settings.transferReminderEnabled)
        XCTAssertEqual(settings.transferReminderMinutes, 10)
    }

    func test_notificationSettings_decodesMissingTransferKeys() throws {
        // Simulates a NotificationSettings blob saved before the transfer reminder existed.
        let legacyJSON = """
        {"departureReminderEnabled":true,"departureReminderMinutes":10,
         "delayAlertEnabled":true,"delayAlertThresholdMinutes":10,
         "platformChangeEnabled":true,"arrivalReminderEnabled":true,"arrivalReminderMinutes":10}
        """
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.transferReminderEnabled)
        XCTAssertEqual(decoded.transferReminderMinutes, 10)
    }
}
