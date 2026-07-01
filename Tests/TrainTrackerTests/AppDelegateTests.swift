import XCTest
@testable import TrainTracker

@MainActor
final class AppDelegateTests: XCTestCase {
    func test_applicationWillTerminate_clearsStatusLine() {
        let store = AppConfigStore(suiteName: "test-\(UUID().uuidString)")
        store.setStatusLine("🚆 WB 912 12m")
        XCTAssertNotNil(store.statusLine())

        let delegate = AppDelegate(configStore: store)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertNil(store.statusLine())
    }
}
