// Tests/TrainTrackerTests/PreferencesWindowControllerTests.swift
import XCTest
@testable import TrainTracker

@MainActor
final class PreferencesWindowControllerTests: XCTestCase {
    private let linz = Station(name: "Linz/Donau Hbf", id: "1")
    private let salzburg = Station(name: "Salzburg Hbf", id: "2")

    private func makeController(config: AppConfig = AppConfig()) -> (PreferencesWindowController, AppConfigStore) {
        let store = AppConfigStore(suiteName: "test-\(UUID().uuidString)")
        store.save(config)
        return (PreferencesWindowController(configStore: store), store)
    }

    func test_loadsExistingConfigIntoControls() {
        var config = AppConfig()
        config.fromStation = linz
        config.toStation = salzburg
        config.notifications.arrivalReminderEnabled = false
        config.notifications.departureReminderMinutes = 7   // not a standard choice
        let (controller, _) = makeController(config: config)

        XCTAssertEqual(controller.fromField.stringValue, "Linz/Donau Hbf")
        XCTAssertEqual(controller.toField.stringValue, "Salzburg Hbf")
        XCTAssertEqual(controller.reminderPopups[.arrival]?.selectedItem?.tag, 0)
        XCTAssertEqual(controller.reminderPopups[.departure]?.selectedItem?.tag, 7)
    }

    func test_changingReminderPopupPersistsImmediately() throws {
        let (controller, store) = makeController()
        let popup = try XCTUnwrap(controller.reminderPopups[.delay])
        popup.selectItem(withTag: 20)
        popup.sendAction(popup.action, to: popup.target)

        let saved = store.load().notifications
        XCTAssertTrue(saved.delayAlertEnabled)
        XCTAssertEqual(saved.delayAlertThresholdMinutes, 20)

        popup.selectItem(withTag: 0)
        popup.sendAction(popup.action, to: popup.target)
        let off = store.load().notifications
        XCTAssertFalse(off.delayAlertEnabled)
        XCTAssertEqual(off.delayAlertThresholdMinutes, 20, "turning a reminder off keeps its minutes")
    }

    func test_commitRoute_savesAndNotifiesOnlyOnChange() {
        let (controller, store) = makeController()
        var notified = 0
        controller.onRouteChanged = { notified += 1 }

        controller.pendingFrom = linz
        controller.commitRoute()
        XCTAssertEqual(notified, 0, "needs both ends")

        controller.pendingTo = salzburg
        controller.commitRoute()
        controller.commitRoute()
        XCTAssertEqual(notified, 1)
        XCTAssertEqual(store.load().toStation, salzburg)
        XCTAssertEqual(store.load().savedRoutes.count, 1)
    }
}
