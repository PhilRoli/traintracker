// Tests/TrainTrackerTests/DeletableTableViewTests.swift
import XCTest
@testable import TrainTracker

@MainActor
final class DeletableTableViewTests: XCTestCase {
    private func makeKeyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func test_keyDown_deleteKey_firesOnDelete() {
        let tableView = DeletableTableView()
        var fired = false
        tableView.onDelete = { fired = true }

        tableView.keyDown(with: makeKeyEvent(keyCode: 51))

        XCTAssertTrue(fired)
    }

    func test_keyDown_forwardDeleteKey_firesOnDelete() {
        let tableView = DeletableTableView()
        var fired = false
        tableView.onDelete = { fired = true }

        tableView.keyDown(with: makeKeyEvent(keyCode: 117))

        XCTAssertTrue(fired)
    }

    func test_keyDown_otherKey_doesNotFireOnDelete() {
        let tableView = DeletableTableView()
        var fired = false
        tableView.onDelete = { fired = true }

        tableView.keyDown(with: makeKeyEvent(keyCode: 0))  // 'a' key

        XCTAssertFalse(fired)
    }
}
