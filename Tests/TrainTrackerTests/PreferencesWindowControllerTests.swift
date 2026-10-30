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

    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { sub -> [NSTextField] in
            let nested = textFields(in: sub)
            if let field = sub as? NSTextField { return [field] + nested }
            return nested
        }
    }

    func test_showsVersionLineInsideTheWindow() throws {
        let (controller, _) = makeController()
        let content = try XCTUnwrap(controller.window?.contentView)
        let version = try XCTUnwrap(textFields(in: content).first {
            $0.stringValue.hasPrefix("Version") || $0.stringValue == "Development build"
        })
        content.layoutSubtreeIfNeeded()
        XCTAssertTrue(content.bounds.insetBy(dx: -1, dy: -1).contains(version.convert(version.bounds, to: content)))
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

    func test_pickingStationsDoesNotSaveUntilSaveAndUse() {
        let (controller, store) = makeController()
        controller.pendingFrom = linz
        controller.pendingTo = salzburg
        controller.updateSaveButton()

        XCTAssertTrue(controller.saveRouteButton.isEnabled)
        XCTAssertNil(store.load().toStation)

        controller.saveRouteButton.performClick(nil)
        XCTAssertEqual(store.load().toStation, salzburg)
        XCTAssertFalse(controller.saveRouteButton.isEnabled, "nothing left to save")
        XCTAssertEqual(controller.saveStatusLabel.stringValue, "Saved ✓")
    }

    func test_removeButtonDeletesItsRoute() {
        var config = AppConfig()
        config.savedEntries = [.route(SavedRoute(from: linz, toStation: salzburg))]
        let (controller, store) = makeController(config: config)

        let cell = controller.savedRoutesTable.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let remove = (cell as? NSStackView)?.views.compactMap { $0 as? NSButton }.first
        XCTAssertNotNil(remove)
        controller.removeRouteClicked(remove!)
        XCTAssertTrue(store.load().savedRoutes.isEmpty)
    }

    func test_addHeaderAppendsAndPersistsWithoutTouchingRoutes() {
        var config = AppConfig()
        let route = SavedRoute(from: linz, toStation: salzburg)
        config.savedEntries = [.route(route), .header("Linz")]
        let (controller, store) = makeController(config: config)

        controller.addHeader()
        XCTAssertEqual(store.load().savedEntries.count, 3)
        XCTAssertEqual(store.load().savedEntries.last, .header("New header"))
        XCTAssertEqual(store.load().savedRoutes, [route])
    }
}
