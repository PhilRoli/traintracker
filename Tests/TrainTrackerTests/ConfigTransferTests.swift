import XCTest
@testable import TrainTracker

final class ConfigTransferTests: XCTestCase {
    func test_exportThenImport_roundTrips() throws {
        var config = AppConfig()
        config.fromStation = Station(name: "Linz/Donau Hbf", id: "8100013")
        config.toStation = Station(name: "Salzburg Hbf", id: "8100002")
        config.trainNumber = "WB 912"
        config.savedRoutes = [SavedRoute(
            from: Station(name: "Linz/Donau Hbf", id: "8100013"),
            toStation: Station(name: "Salzburg Hbf", id: "8100002")
        )]
        config.notifications.departureReminderMinutes = 5

        let data = try ConfigTransfer.exportData(config)
        let imported = try ConfigTransfer.importConfig(from: data)

        XCTAssertEqual(imported.fromStation?.id, "8100013")
        XCTAssertEqual(imported.toStation?.id, "8100002")
        XCTAssertEqual(imported.trainNumber, "WB 912")
        XCTAssertEqual(imported.savedRoutes.count, 1)
        XCTAssertEqual(imported.savedRoutes[0].from.id, "8100013")
        XCTAssertEqual(imported.notifications.departureReminderMinutes, 5)
    }

    func test_importConfig_invalidJSON_throws() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try ConfigTransfer.importConfig(from: data))
    }
}
