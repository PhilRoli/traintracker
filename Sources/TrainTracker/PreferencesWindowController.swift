// Sources/TrainTracker/PreferencesWindowController.swift (temporary stub — will be replaced in Task 7)
import AppKit

final class PreferencesWindowController: NSWindowController {
    var onClose: (() -> Void)?

    convenience init() {
        self.init(window: nil)
    }
}
