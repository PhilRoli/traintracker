// Tests/TrainTrackerTests/LoginItemControllerTests.swift
import XCTest
@testable import TrainTracker

final class FakeLoginItemManager: LoginItemManaging {
    var isEnabled: Bool = false
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldThrow = false

    struct FakeError: Error {}

    func register() throws {
        registerCallCount += 1
        if shouldThrow { throw FakeError() }
        isEnabled = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if shouldThrow { throw FakeError() }
        isEnabled = false
    }
}

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func test_setEnabled_true_registersAndReturnsTrue() {
        let fake = FakeLoginItemManager()
        let controller = LoginItemController(manager: fake)

        let result = controller.setEnabled(true)

        XCTAssertTrue(result)
        XCTAssertEqual(fake.registerCallCount, 1)
        XCTAssertEqual(fake.unregisterCallCount, 0)
        XCTAssertTrue(controller.isEnabled)
    }

    func test_setEnabled_false_unregistersAndReturnsTrue() {
        let fake = FakeLoginItemManager()
        fake.isEnabled = true
        let controller = LoginItemController(manager: fake)

        let result = controller.setEnabled(false)

        XCTAssertTrue(result)
        XCTAssertEqual(fake.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
    }

    func test_setEnabled_whenManagerThrows_returnsFalseAndLeavesStateUnchanged() {
        let fake = FakeLoginItemManager()
        fake.shouldThrow = true
        let controller = LoginItemController(manager: fake)

        let result = controller.setEnabled(true)

        XCTAssertFalse(result)
        XCTAssertFalse(controller.isEnabled)
    }

    func test_isEnabled_reflectsManagerState() {
        let fake = FakeLoginItemManager()
        fake.isEnabled = true
        let controller = LoginItemController(manager: fake)

        XCTAssertTrue(controller.isEnabled)
    }
}
