# Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add macOS push notifications for departure reminders, delay alerts, and platform changes, with user-configurable thresholds in the Preferences panel.

**Architecture:** A new `NotificationManager` receives `TrainData` after each refresh, compares against stored state, and fires `UNUserNotificationCenter` notifications for crossing events. A `NotificationScheduler` protocol enables spy injection in tests. `AppConfig` gains a `NotificationSettings` sub-struct alongside existing config.

**Tech Stack:** Swift 5.9, AppKit, UserNotifications framework (macOS 13+), XCTest

---

### Task 1: Add `NotificationSettings` to `AppConfig`

**Files:**
- Modify: `Sources/TrainTracker/AppConfig.swift`
- Modify: `Tests/TrainTrackerTests/AppConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TrainTrackerTests/AppConfigTests.swift` (inside the `AppConfigTests` class, below existing tests):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter AppConfigTests 2>&1 | tail -20
```

Expected: compile errors — `NotificationSettings` is not yet defined.

- [ ] **Step 3: Add `NotificationSettings` and `notifications` field**

In `Sources/TrainTracker/AppConfig.swift`, add the struct above `AppConfigStore` and add the field to `AppConfig`:

```swift
struct NotificationSettings: Codable {
    var departureReminderEnabled: Bool  = true
    var departureReminderMinutes: Int   = 10
    var delayAlertEnabled: Bool         = true
    var delayAlertThresholdMinutes: Int = 10
    var platformChangeEnabled: Bool     = true
}
```

In `AppConfig`, add one property (the struct's defaults make it backward-compatible with stored JSON that lacks the key):

```swift
struct AppConfig: Codable {
    var fromStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var savedRoutes: [SavedRoute]
    var notifications: NotificationSettings = NotificationSettings()

    init() { savedRoutes = [] }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter AppConfigTests 2>&1 | tail -20
```

Expected: all `AppConfigTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/AppConfig.swift Tests/TrainTrackerTests/AppConfigTests.swift
git commit -m "feat: add NotificationSettings to AppConfig"
```

---

### Task 2: `NotificationScheduler` protocol and test spy

**Files:**
- Create: `Sources/TrainTracker/NotificationManager.swift` (protocol only for now)
- Create: `Tests/TrainTrackerTests/NotificationManagerTests.swift` (spy + empty test class)

- [ ] **Step 1: Create `NotificationManager.swift` with the protocol**

```swift
// Sources/TrainTracker/NotificationManager.swift
import UserNotifications
import Foundation

protocol NotificationScheduler {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationScheduler {}

@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler

    init(scheduler: NotificationScheduler = UNUserNotificationCenter.current()) {
        self.scheduler = scheduler
    }

    func process(_ data: TrainData, settings: NotificationSettings) {
        // implementation in subsequent tasks
    }
}
```

- [ ] **Step 2: Create `NotificationManagerTests.swift` with spy and helpers**

```swift
// Tests/TrainTrackerTests/NotificationManagerTests.swift
import XCTest
import UserNotifications
@testable import TrainTracker

// MARK: - Spy

final class NotificationSpy: NotificationScheduler {
    struct Posted {
        let identifier: String
        let title: String
        let body: String
    }
    private(set) var posted: [Posted] = []

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        posted.append(Posted(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body
        ))
        completionHandler?(nil)
    }
}

// MARK: - Tests

@MainActor
final class NotificationManagerTests: XCTestCase {

    // MARK: - Helpers

    func makeManager() -> (NotificationManager, NotificationSpy) {
        let spy = NotificationSpy()
        let manager = NotificationManager(scheduler: spy)
        return (manager, spy)
    }

    func makeTrainData(
        trainName: String = "WB 912",
        fromName: String = "Linz/Donau Hbf",
        toName: String = "Salzburg Hbf",
        scheduledDeparture: Date = Date().addingTimeInterval(3600),
        scheduledArrival: Date = Date().addingTimeInterval(7200),
        departureDelaySecs: Int = 0,
        arrivalDelaySecs: Int = 0,
        departurePlatform: String? = nil,
        arrivalPlatform: String? = nil,
        isEnRoute: Bool = false
    ) -> TrainData {
        TrainData(
            trainName: trainName,
            fromName: fromName,
            toName: toName,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            departureDelaySecs: departureDelaySecs,
            arrivalDelaySecs: arrivalDelaySecs,
            departurePlatform: departurePlatform,
            arrivalPlatform: arrivalPlatform,
            stopovers: [],
            isEnRoute: isEnRoute
        )
    }
}
```

- [ ] **Step 3: Verify it compiles and runs (no tests yet)**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -20
```

Expected: `Executed 0 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Sources/TrainTracker/NotificationManager.swift Tests/TrainTrackerTests/NotificationManagerTests.swift
git commit -m "feat: add NotificationScheduler protocol and test spy"
```

---

### Task 3: Departure reminder

**Files:**
- Modify: `Tests/TrainTrackerTests/NotificationManagerTests.swift`
- Modify: `Sources/TrainTracker/NotificationManager.swift`

- [ ] **Step 1: Write failing tests**

Add inside `NotificationManagerTests` (after the helpers):

```swift
// MARK: - Departure reminder

func test_departureReminder_firesWhenWithinWindow() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.departureReminderMinutes = 10

    // Train departs in 8 minutes (within 10m window)
    let data = makeTrainData(
        scheduledDeparture: Date().addingTimeInterval(8 * 60),
        isEnRoute: false
    )

    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 1)
    XCTAssertTrue(spy.posted[0].identifier.hasPrefix("departure-"))
    XCTAssertTrue(spy.posted[0].title.contains("WB 912"))
    XCTAssertTrue(spy.posted[0].title.contains("departs"))
}

func test_departureReminder_doesNotFireOutsideWindow() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.departureReminderMinutes = 10

    // Train departs in 15 minutes (outside 10m window)
    let data = makeTrainData(
        scheduledDeparture: Date().addingTimeInterval(15 * 60),
        isEnRoute: false
    )

    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

func test_departureReminder_doesNotFireWhenEnRoute() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()

    let data = makeTrainData(
        scheduledDeparture: Date().addingTimeInterval(5 * 60),
        isEnRoute: true
    )

    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

func test_departureReminder_doesNotFireTwiceForSameTrain() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()
    let departure = Date().addingTimeInterval(5 * 60)
    let data = makeTrainData(scheduledDeparture: departure, isEnRoute: false)

    manager.process(data, settings: settings)
    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 1)
}

func test_departureReminder_doesNotFireWhenDisabled() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.departureReminderEnabled = false

    let data = makeTrainData(
        scheduledDeparture: Date().addingTimeInterval(5 * 60),
        isEnRoute: false
    )

    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

func test_departureReminder_includesPlatformInBodyWhenAvailable() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()

    let data = makeTrainData(
        scheduledDeparture: Date().addingTimeInterval(5 * 60),
        departurePlatform: "3",
        isEnRoute: false
    )

    manager.process(data, settings: settings)

    XCTAssertEqual(spy.posted.count, 1)
    XCTAssertTrue(spy.posted[0].body.contains("3"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -30
```

Expected: failures — `process` does nothing yet.

- [ ] **Step 3: Implement departure reminder**

Replace the `process` method in `NotificationManager.swift` and add the supporting private state and methods:

```swift
@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler
    private var authRequested = false

    private var trackedTrainKey: String? = nil
    private var lastDelaySecs: Int = 0
    private var lastDeparturePlatform: String? = nil
    private var lastArrivalPlatform: String? = nil
    private var departureReminderSentFor: String? = nil

    init(scheduler: NotificationScheduler = UNUserNotificationCenter.current()) {
        self.scheduler = scheduler
    }

    func process(_ data: TrainData, settings: NotificationSettings) {
        requestAuthIfNeeded()

        let key = "\(data.trainName)|\(Int(data.scheduledDeparture.timeIntervalSince1970))"
        if key != trackedTrainKey {
            trackedTrainKey = key
            lastDelaySecs = 0
            lastDeparturePlatform = nil
            lastArrivalPlatform = nil
            departureReminderSentFor = nil
        }

        processDepartureReminder(data: data, settings: settings, key: key)
        processDelayAlert(data: data, settings: settings, key: key)
        processPlatformChange(data: data, settings: settings, key: key)
    }

    private func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        Task { try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func processDepartureReminder(data: TrainData, settings: NotificationSettings, key: String) {
        guard settings.departureReminderEnabled,
              !data.isEnRoute,
              departureReminderSentFor != key
        else { return }

        let rtDep = data.scheduledDeparture.addingTimeInterval(TimeInterval(data.departureDelaySecs))
        let secsUntil = rtDep.timeIntervalSinceNow
        guard secsUntil > 0, secsUntil <= Double(settings.departureReminderMinutes * 60) else { return }

        let content = UNMutableNotificationContent()
        let minsLeft = max(1, Int(secsUntil / 60))
        content.title = "\(data.trainName) departs in \(minsLeft)m"
        content.body = data.departurePlatform
            .map { "Platform \($0) at \(data.fromName)" }
            ?? "From \(data.fromName)"

        post(identifier: "departure-\(key)", content: content)
        departureReminderSentFor = key
    }

    private func processDelayAlert(data: TrainData, settings: NotificationSettings, key: String) {
        // stub — implemented in Task 4
    }

    private func processPlatformChange(data: TrainData, settings: NotificationSettings, key: String) {
        // stub — implemented in Task 5
    }

    private func post(identifier: String, content: UNMutableNotificationContent) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        scheduler.add(request, withCompletionHandler: nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -30
```

Expected: all departure reminder tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/NotificationManager.swift Tests/TrainTrackerTests/NotificationManagerTests.swift
git commit -m "feat: departure reminder notification"
```

---

### Task 4: Delay alert

**Files:**
- Modify: `Tests/TrainTrackerTests/NotificationManagerTests.swift`
- Modify: `Sources/TrainTracker/NotificationManager.swift`

- [ ] **Step 1: Write failing tests**

Add inside `NotificationManagerTests` (after departure reminder tests):

```swift
// MARK: - Delay alert

func test_delayAlert_firesWhenCrossingThreshold() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.delayAlertThresholdMinutes = 10

    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    // First call: 5 minutes late (below threshold)
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   arrivalDelaySecs: 5 * 60, isEnRoute: true), settings: settings)
    XCTAssertEqual(spy.posted.count, 0)

    // Second call: 12 minutes late (crosses 10m threshold)
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   arrivalDelaySecs: 12 * 60, isEnRoute: true), settings: settings)
    XCTAssertEqual(spy.posted.count, 1)
    XCTAssertTrue(spy.posted[0].identifier.hasPrefix("delay-"))
    XCTAssertTrue(spy.posted[0].title.contains("WB 912"))
    XCTAssertTrue(spy.posted[0].title.contains("+12m"))
}

func test_delayAlert_doesNotFireAgainWhenAlreadyAboveThreshold() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.delayAlertThresholdMinutes = 10

    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    // Cross threshold
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   arrivalDelaySecs: 12 * 60, isEnRoute: true), settings: settings)
    // Delay increases further (still above threshold)
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   arrivalDelaySecs: 18 * 60, isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 1, "Should only fire once when crossing, not on every update above threshold")
}

func test_delayAlert_doesNotFireWhenDisabled() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.delayAlertEnabled = false
    settings.delayAlertThresholdMinutes = 10

    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   arrivalDelaySecs: 15 * 60, isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -30
```

Expected: delay alert tests fail.

- [ ] **Step 3: Implement `processDelayAlert`**

Replace the stub in `NotificationManager.swift`:

```swift
private func processDelayAlert(data: TrainData, settings: NotificationSettings, key: String) {
    defer { lastDelaySecs = data.arrivalDelaySecs }
    guard settings.delayAlertEnabled else { return }
    let threshold = settings.delayAlertThresholdMinutes * 60
    guard data.arrivalDelaySecs >= threshold, lastDelaySecs < threshold else { return }

    let content = UNMutableNotificationContent()
    let mins = (data.arrivalDelaySecs + 59) / 60
    content.title = "\(data.trainName) is now +\(mins)m late"
    content.body = "Arrives at \(data.toName)"
    post(identifier: "delay-\(key)", content: content)
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -30
```

Expected: all delay alert tests pass (departure reminder tests still pass too).

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/NotificationManager.swift Tests/TrainTrackerTests/NotificationManagerTests.swift
git commit -m "feat: delay alert notification"
```

---

### Task 5: Platform change and state reset

**Files:**
- Modify: `Tests/TrainTrackerTests/NotificationManagerTests.swift`
- Modify: `Sources/TrainTracker/NotificationManager.swift`

- [ ] **Step 1: Write failing tests**

Add inside `NotificationManagerTests`:

```swift
// MARK: - Platform change

func test_platformChange_firesWhenDeparturePlatformChanges() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()
    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    // First call: platform 3
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)
    XCTAssertEqual(spy.posted.count, 0, "No change on first observation")

    // Second call: platform changed to 4
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "4", isEnRoute: true), settings: settings)
    XCTAssertEqual(spy.posted.count, 1)
    XCTAssertTrue(spy.posted[0].identifier.hasPrefix("platform-dep-"))
    XCTAssertTrue(spy.posted[0].title.contains("departure platform"))
    XCTAssertTrue(spy.posted[0].body.contains("4"))
}

func test_platformChange_doesNotFireOnFirstObservation() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()

    manager.process(makeTrainData(departurePlatform: "3", isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

func test_platformChange_doesNotFireWhenSame() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()
    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

func test_platformChange_doesNotFireWhenDisabled() {
    let (manager, spy) = makeManager()
    var settings = NotificationSettings()
    settings.platformChangeEnabled = false
    let dep = Date().addingTimeInterval(-3600)
    let arr = Date().addingTimeInterval(3600)

    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)
    manager.process(makeTrainData(scheduledDeparture: dep, scheduledArrival: arr,
                                   departurePlatform: "5", isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}

// MARK: - State reset

func test_stateReset_departureReminderCanFireAgainForNewTrain() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()

    // First train: reminder fires
    let dep1 = Date().addingTimeInterval(5 * 60)
    manager.process(makeTrainData(trainName: "WB 912", scheduledDeparture: dep1,
                                   isEnRoute: false), settings: settings)
    XCTAssertEqual(spy.posted.count, 1)

    // Switch to a different train: reminder should fire again
    let dep2 = Date().addingTimeInterval(7 * 60)
    manager.process(makeTrainData(trainName: "WB 914", scheduledDeparture: dep2,
                                   isEnRoute: false), settings: settings)
    XCTAssertEqual(spy.posted.count, 2)
}

func test_stateReset_platformChangeDoesNotFireForNewTrain() {
    let (manager, spy) = makeManager()
    let settings = NotificationSettings()
    let dep1 = Date().addingTimeInterval(-3600)
    let arr1 = Date().addingTimeInterval(3600)
    let dep2 = Date().addingTimeInterval(-1800)
    let arr2 = Date().addingTimeInterval(5400)

    // First train: observe platform 3
    manager.process(makeTrainData(trainName: "WB 912", scheduledDeparture: dep1, scheduledArrival: arr1,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)
    // Switch train: different train also has platform 3 — no change notification expected
    manager.process(makeTrainData(trainName: "WB 914", scheduledDeparture: dep2, scheduledArrival: arr2,
                                   departurePlatform: "3", isEnRoute: true), settings: settings)

    XCTAssertEqual(spy.posted.count, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter NotificationManagerTests 2>&1 | tail -30
```

Expected: platform change and state reset tests fail.

- [ ] **Step 3: Implement `processPlatformChange`**

Replace the stub in `NotificationManager.swift`:

```swift
private func processPlatformChange(data: TrainData, settings: NotificationSettings, key: String) {
    defer {
        lastDeparturePlatform = data.departurePlatform
        lastArrivalPlatform = data.arrivalPlatform
    }
    guard settings.platformChangeEnabled else { return }

    if let prev = lastDeparturePlatform, let curr = data.departurePlatform, prev != curr {
        let content = UNMutableNotificationContent()
        content.title = "\(data.trainName): departure platform changed"
        content.body = "Now departing from platform \(curr)"
        post(identifier: "platform-dep-\(key)", content: content)
    }
    if let prev = lastArrivalPlatform, let curr = data.arrivalPlatform, prev != curr {
        let content = UNMutableNotificationContent()
        content.title = "\(data.trainName): arrival platform changed"
        content.body = "Now arriving at platform \(curr)"
        post(identifier: "platform-arr-\(key)", content: content)
    }
}
```

- [ ] **Step 4: Run all tests to verify they pass**

```bash
swift test 2>&1 | tail -30
```

Expected: all tests pass, including existing tests for `AppConfig`, `TrainFetcher`, `StatusBarController`, and `OeBBClient`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/NotificationManager.swift Tests/TrainTrackerTests/NotificationManagerTests.swift
git commit -m "feat: platform change notification and state reset"
```

---

### Task 6: Preferences panel — notifications section

**Files:**
- Modify: `Sources/TrainTracker/PreferencesWindowController.swift`

No automated tests — verify manually by running the app and opening Preferences.

- [ ] **Step 1: Add new instance variables**

Add these properties to `PreferencesWindowController` (after `private var searchTask`):

```swift
private var departureReminderCheckbox: NSButton!
private var departureReminderField: NSTextField!
private var delayAlertCheckbox: NSButton!
private var delayAlertField: NSTextField!
private var platformChangeCheckbox: NSButton!
private var pendingNotifications: NotificationSettings = NotificationSettings()
```

- [ ] **Step 2: Load notification settings in `loadCurrentConfig()`**

In `loadCurrentConfig()`, add after `savedRoutes = config.savedRoutes`:

```swift
pendingNotifications = config.notifications
```

- [ ] **Step 3: Update panel size and shift existing controls up**

In the `convenience init`, change the content rect height from `320` to `440`:

```swift
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
    ...
)
```

All existing controls must shift up by 120pt to make room for the notifications section. In `setupUI()`, update every `y` coordinate value for the existing controls:

| Control | Old y | New y |
|---|---|---|
| `fromLabel.frame` | 272 | 392 |
| `fromField.frame` | 268 | 388 |
| `toLabel.frame` | 240 | 360 |
| `toField.frame` | 236 | 356 |
| `resultsScrollView` | 152 | 272 |
| `routesLabel.frame` | 128 | 248 |
| `savedScrollView` | 44 | 164 |
| `saveBtn.frame` | 8 | 8 (unchanged) |

- [ ] **Step 4: Add the notifications section to `setupUI()`**

Add the following code at the end of `setupUI()` (after the save button, before the closing brace):

```swift
// Notifications section separator
let notifSeparator = NSBox()
notifSeparator.boxType = .separator
notifSeparator.frame = NSRect(x: 16, y: 156, width: 368, height: 1)
cv.addSubview(notifSeparator)

// Section label
let notifLabel = makeLabel("Notifications")
notifLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
notifLabel.frame = NSRect(x: 16, y: 136, width: 200, height: 18)
cv.addSubview(notifLabel)

// Departure reminder row
departureReminderCheckbox = NSButton(checkboxWithTitle: "Departure reminder", target: self, action: #selector(notifCheckboxChanged(_:)))
departureReminderCheckbox.frame = NSRect(x: 16, y: 110, width: 170, height: 20)
departureReminderCheckbox.state = pendingNotifications.departureReminderEnabled ? .on : .off
cv.addSubview(departureReminderCheckbox)

departureReminderField = makeNumberField()
departureReminderField.frame = NSRect(x: 192, y: 110, width: 40, height: 20)
departureReminderField.integerValue = pendingNotifications.departureReminderMinutes
departureReminderField.isEnabled = pendingNotifications.departureReminderEnabled
cv.addSubview(departureReminderField)

let depMinLabel = makeLabel("minutes before")
depMinLabel.frame = NSRect(x: 238, y: 110, width: 120, height: 20)
cv.addSubview(depMinLabel)

// Delay alert row
delayAlertCheckbox = NSButton(checkboxWithTitle: "Delay alert when", target: self, action: #selector(notifCheckboxChanged(_:)))
delayAlertCheckbox.frame = NSRect(x: 16, y: 82, width: 160, height: 20)
delayAlertCheckbox.state = pendingNotifications.delayAlertEnabled ? .on : .off
cv.addSubview(delayAlertCheckbox)

delayAlertField = makeNumberField()
delayAlertField.frame = NSRect(x: 182, y: 82, width: 40, height: 20)
delayAlertField.integerValue = pendingNotifications.delayAlertThresholdMinutes
delayAlertField.isEnabled = pendingNotifications.delayAlertEnabled
cv.addSubview(delayAlertField)

let delayMinLabel = makeLabel("+ minutes late")
delayMinLabel.frame = NSRect(x: 228, y: 82, width: 130, height: 20)
cv.addSubview(delayMinLabel)

// Platform change row
platformChangeCheckbox = NSButton(checkboxWithTitle: "Platform change alert", target: self, action: #selector(notifCheckboxChanged(_:)))
platformChangeCheckbox.frame = NSRect(x: 16, y: 54, width: 220, height: 20)
platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off
cv.addSubview(platformChangeCheckbox)
```

- [ ] **Step 5: Add `makeNumberField()` helper and `notifCheckboxChanged` action**

Add inside `PreferencesWindowController` (near the other `makeLabel`/`makeTextField` helpers):

```swift
private func makeNumberField() -> NSTextField {
    let f = NSTextField()
    f.font = NSFont.systemFont(ofSize: 13)
    f.bezelStyle = .roundedBezel
    f.alignment = .center
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.minimum = 1
    formatter.maximum = 120
    f.formatter = formatter
    return f
}
```

Add to the `// MARK: - Actions` section:

```swift
@objc private func notifCheckboxChanged(_ sender: NSButton) {
    departureReminderField.isEnabled = departureReminderCheckbox.state == .on
    delayAlertField.isEnabled = delayAlertCheckbox.state == .on
}
```

- [ ] **Step 6: Save notification settings in `saveAndClose()`**

In `saveAndClose()`, add before `AppConfigStore.shared.save(config)`:

```swift
config.notifications = NotificationSettings(
    departureReminderEnabled: departureReminderCheckbox.state == .on,
    departureReminderMinutes: max(1, departureReminderField.integerValue),
    delayAlertEnabled: delayAlertCheckbox.state == .on,
    delayAlertThresholdMinutes: max(1, delayAlertField.integerValue),
    platformChangeEnabled: platformChangeCheckbox.state == .on
)
```

- [ ] **Step 7: Build and verify**

```bash
swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 8: Run the app and verify manually**

```bash
bash rebuild.sh
```

Open Preferences (`Cmd+,` from menu bar). Verify:
- Panel is taller with a "Notifications" section at the bottom
- Three checkboxes are shown, checked by default
- Departure reminder and delay alert each have a number field showing 10
- Unchecking a box disables its number field
- Saving and reopening preserves the values

- [ ] **Step 9: Commit**

```bash
git add Sources/TrainTracker/PreferencesWindowController.swift
git commit -m "feat: notifications settings in Preferences panel"
```

---

### Task 7: Wire `NotificationManager` into `StatusBarController`

**Files:**
- Modify: `Sources/TrainTracker/StatusBarController.swift`

- [ ] **Step 1: Add `NotificationManager` property**

In `StatusBarController`, add after `private var prefsController`:

```swift
private let notificationManager = NotificationManager()
```

- [ ] **Step 2: Call `process` in `refresh()`**

In `StatusBarController.refresh()`, the last lines currently are:

```swift
statusItem.button?.title = Self.titleString(for: displayStatus, consecutiveErrors: consecutiveErrors)
statusItem.menu = buildMenu(for: displayStatus)
```

Add after those two lines:

```swift
if case .tracking(let td, _) = displayStatus {
    notificationManager.process(td, settings: config.notifications)
}
```

- [ ] **Step 3: Build and run all tests**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -20
```

Expected: `Build complete!` and all tests pass.

- [ ] **Step 4: Rebuild and smoke-test**

```bash
bash rebuild.sh
```

Manual smoke test:
1. Configure a route with a train that departs in the next 10 minutes — confirm a "departs in Xm" notification appears
2. If no upcoming departure is handy: open Preferences, set departure reminder to 60 minutes, select a train departing within the hour, verify the notification fires within one 30s refresh cycle

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/StatusBarController.swift
git commit -m "feat: wire NotificationManager into StatusBarController refresh loop"
```
