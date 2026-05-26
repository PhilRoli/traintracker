# TrainTracker Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add journey refresh-token caching (1 API call instead of 5 on repeat ticks), a "Switch Route…" menu bar submenu, and delete support for saved routes in Preferences.

**Architecture:** `OeBBClient` gains a `refreshJourney(token:)` method and a shared protocol for testability. `TrainFetcher` caches the journey's `refreshToken` after each full fetch and uses a single refresh call on subsequent ticks, falling back to the full batch on error. `StatusBarController` adds a "Switch Route…" submenu that writes to `AppConfigStore`. `PreferencesWindowController` gains a "–" button and Delete-key handler on the saved-routes table.

**Tech Stack:** Swift 5.9+, AppKit, XCTest, `URLSession`, `UserDefaults`

---

## File Map

| File | Role |
|---|---|
| `Sources/TrainTracker/Models.swift` | Add `refreshToken` field + `APIJourneyResponse` wrapper |
| `Sources/TrainTracker/OeBBClient.swift` | Add `OeBBClientProtocol`, `refreshJourneyURL`, `refreshJourney` |
| `Sources/TrainTracker/TrainFetcher.swift` | Protocol-typed client, refresh-token cache, `tryRefresh`, `findTrainWithToken` |
| `Sources/TrainTracker/StatusBarController.swift` | `selectRoute` action, `addRouteOptions` helper, updated `buildMenu` |
| `Sources/TrainTracker/PreferencesWindowController.swift` | Drop "Load" column, add "–" button + Delete key, fix `saveAndClose` |
| `Tests/TrainTrackerTests/OeBBClientTests.swift` | Test for `refreshJourneyURL` |
| `Tests/TrainTrackerTests/TrainFetcherTests.swift` | `MockOeBBClient`, three new refresh-path tests |

---

## Task 1: Refresh token in API models and URL builder

**Files:**
- Modify: `Sources/TrainTracker/Models.swift`
- Modify: `Sources/TrainTracker/OeBBClient.swift`
- Modify: `Tests/TrainTrackerTests/OeBBClientTests.swift`

- [ ] **Step 1: Write the failing URL test**

Add to `Tests/TrainTrackerTests/OeBBClientTests.swift` after the last existing test:

```swift
func test_refreshJourneyURL() {
    let url = OeBBClient.refreshJourneyURL(token: "abc123")
    XCTAssertNotNil(url)
    XCTAssertTrue(url!.absoluteString.contains("/journeys/abc123"))
    XCTAssertTrue(url!.absoluteString.contains("stopovers=true"))
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
swift test --filter OeBBClientTests/test_refreshJourneyURL 2>&1 | tail -20
```

Expected: compile error — `refreshJourneyURL` does not exist yet.

- [ ] **Step 3: Add `refreshToken` to `APIJourney` and `APIJourneyResponse`**

In `Sources/TrainTracker/Models.swift`, replace the `APIJourney` struct:

```swift
struct APIJourney: Codable {
    let legs: [APILeg]
    let refreshToken: String?
}
```

Add `APIJourneyResponse` directly after `APIJourneysResponse`:

```swift
struct APIJourneyResponse: Codable {
    let journey: APIJourney
}
```

- [ ] **Step 4: Add `refreshJourneyURL` and `refreshJourney` to `OeBBClient`**

In `Sources/TrainTracker/OeBBClient.swift`, add after `journeysURL`:

```swift
static func refreshJourneyURL(token: String) -> URL? {
    guard let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
    var components = URLComponents(string: "\(baseURL)/journeys/\(encoded)")
    components?.queryItems = [URLQueryItem(name: "stopovers", value: "true")]
    return components?.url
}
```

Add after `fetchJourneys`:

```swift
func refreshJourney(token: String) async throws -> APIJourney {
    guard let url = Self.refreshJourneyURL(token: token) else { throw OeBBError.invalidURL }
    let (data, response) = try await session.data(from: url)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw OeBBError.httpError(http.statusCode)
    }
    return try JSONDecoder().decode(APIJourneyResponse.self, from: data).journey
}
```

- [ ] **Step 5: Run test to confirm it passes**

```bash
swift test --filter OeBBClientTests/test_refreshJourneyURL 2>&1 | tail -10
```

Expected: `Test Suite 'OeBBClientTests' passed`

- [ ] **Step 6: Confirm existing OeBBClient tests still pass**

```bash
swift test --filter OeBBClientTests 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TrainTracker/Models.swift Sources/TrainTracker/OeBBClient.swift Tests/TrainTrackerTests/OeBBClientTests.swift
git commit -m "feat: add refreshToken to APIJourney and refreshJourney to OeBBClient"
```

---

## Task 2: OeBBClientProtocol and TrainFetcher protocol adoption

**Files:**
- Modify: `Sources/TrainTracker/OeBBClient.swift`
- Modify: `Sources/TrainTracker/TrainFetcher.swift`

No new tests in this task — existing tests verify correctness after the refactor.

- [ ] **Step 1: Define `OeBBClientProtocol` in `OeBBClient.swift`**

Add at the top of `Sources/TrainTracker/OeBBClient.swift`, before `enum OeBBError`:

```swift
protocol OeBBClientProtocol {
    func searchStations(query: String) async throws -> [APILocation]
    func fetchJourneys(fromId: String, toId: String, departure: Date) async throws -> [APIJourney]
    func refreshJourney(token: String) async throws -> APIJourney
}
```

Then mark `OeBBClient` as conforming. Replace the class declaration line:

```swift
final class OeBBClient: OeBBClientProtocol {
```

- [ ] **Step 2: Update `TrainFetcher` to use the protocol type**

In `Sources/TrainTracker/TrainFetcher.swift`, replace the property and init:

```swift
final class TrainFetcher {
    private let client: any OeBBClientProtocol
    private static let offsets: [TimeInterval] = [-6 * 3600, -4 * 3600, -2 * 3600, -1800, 0]

    init(client: any OeBBClientProtocol = OeBBClient()) {
        self.client = client
    }
```

- [ ] **Step 3: Run all existing tests to confirm nothing broke**

```bash
swift test 2>&1 | tail -20
```

Expected: all existing tests pass (zero failures).

- [ ] **Step 4: Commit**

```bash
git add Sources/TrainTracker/OeBBClient.swift Sources/TrainTracker/TrainFetcher.swift
git commit -m "refactor: introduce OeBBClientProtocol for testable TrainFetcher injection"
```

---

## Task 3: Journey refresh-token caching in TrainFetcher

**Files:**
- Modify: `Sources/TrainTracker/TrainFetcher.swift`
- Modify: `Tests/TrainTrackerTests/TrainFetcherTests.swift`

- [ ] **Step 1: Add `MockOeBBClient` and test helpers to `TrainFetcherTests.swift`**

Add after the last existing helper in `Tests/TrainTrackerTests/TrainFetcherTests.swift`:

```swift
// MARK: - MockOeBBClient

private final class MockOeBBClient: OeBBClientProtocol {
    var journeysToReturn: [APIJourney] = []
    var refreshToReturn: APIJourney?
    var refreshError: Error?
    var fetchJourneysCallCount = 0
    var refreshJourneyCallCount = 0

    func searchStations(query: String) async throws -> [APILocation] { [] }

    func fetchJourneys(fromId: String, toId: String, departure: Date) async throws -> [APIJourney] {
        fetchJourneysCallCount += 1
        return journeysToReturn
    }

    func refreshJourney(token: String) async throws -> APIJourney {
        refreshJourneyCallCount += 1
        if let error = refreshError { throw error }
        return refreshToReturn!
    }
}
```

Also update the existing `makeJourney` helper to accept an optional `refreshToken` (add a default parameter):

```swift
private func makeJourney(
    trainName: String,
    plannedDep: String,
    plannedArr: String = "2026-05-24T14:08:00+02:00",
    refreshToken: String? = nil
) -> APIJourney {
    let leg = APILeg(
        origin: APIStop(id: "1", name: "From"),
        destination: APIStop(id: "2", name: "To"),
        departure: plannedDep,
        plannedDeparture: plannedDep,
        arrival: plannedArr,
        plannedArrival: plannedArr,
        departureDelay: 0,
        arrivalDelay: 0,
        line: APILine(name: trainName, product: "interregional"),
        departurePlatform: nil,
        arrivalPlatform: nil,
        stopovers: nil
    )
    return APIJourney(legs: [leg], refreshToken: refreshToken)
}
```

Add `makeConfig` helper after `makeJourney`:

```swift
private func makeConfig(fromId: String = "1", toId: String = "2", trainNumber: String? = nil) -> AppConfig {
    var config = AppConfig()
    config.fromStation = Station(name: "From", id: fromId)
    config.toStation = Station(name: "To", id: toId)
    config.trainNumber = trainNumber
    return config
}
```

- [ ] **Step 2: Write three failing refresh-path tests**

Add these tests to the `TrainFetcherTests` class (after `test_findTrain_isNotEnRouteBeforeDeparture`):

```swift
// MARK: - Refresh token caching

func test_refreshTokenCachedAfterFullFetch_usedOnNextCall() async {
    let mock = MockOeBBClient()
    let now = Date()
    let journey = makeJourney(
        trainName: "WB 912",
        plannedDep: iso8601(now.addingTimeInterval(-600)),
        plannedArr: iso8601(now.addingTimeInterval(3600)),
        refreshToken: "tok-abc"
    )
    mock.journeysToReturn = [journey]
    mock.refreshToReturn = journey

    let fetcher = TrainFetcher(client: mock)
    let config = makeConfig(trainNumber: "WB 912")

    // First fetch: full batch (5 offsets)
    _ = await fetcher.fetch(config: config)
    XCTAssertEqual(mock.fetchJourneysCallCount, 5)
    XCTAssertEqual(mock.refreshJourneyCallCount, 0)

    // Second fetch: refresh path used, no new full-batch calls
    _ = await fetcher.fetch(config: config)
    XCTAssertEqual(mock.fetchJourneysCallCount, 5, "Full batch should not fire again")
    XCTAssertEqual(mock.refreshJourneyCallCount, 1)
}

func test_fallsBackToFullFetchWhenRefreshFails() async {
    let mock = MockOeBBClient()
    let now = Date()
    let journey = makeJourney(
        trainName: "WB 912",
        plannedDep: iso8601(now.addingTimeInterval(-600)),
        plannedArr: iso8601(now.addingTimeInterval(3600)),
        refreshToken: "tok-abc"
    )
    mock.journeysToReturn = [journey]

    let fetcher = TrainFetcher(client: mock)
    let config = makeConfig(trainNumber: "WB 912")

    // First fetch: caches the token
    _ = await fetcher.fetch(config: config)
    XCTAssertEqual(mock.fetchJourneysCallCount, 5)

    // Make refresh fail
    mock.refreshError = OeBBError.httpError(404)

    // Second fetch: refresh tried once, then full batch again
    _ = await fetcher.fetch(config: config)
    XCTAssertEqual(mock.refreshJourneyCallCount, 1)
    XCTAssertEqual(mock.fetchJourneysCallCount, 10, "Full batch should fire after refresh failure")
}

func test_cacheInvalidatedOnConfigChange() async {
    let mock = MockOeBBClient()
    let now = Date()
    let journey = makeJourney(
        trainName: "WB 912",
        plannedDep: iso8601(now.addingTimeInterval(-600)),
        plannedArr: iso8601(now.addingTimeInterval(3600)),
        refreshToken: "tok-abc"
    )
    mock.journeysToReturn = [journey]
    mock.refreshToReturn = journey

    let fetcher = TrainFetcher(client: mock)
    let config = makeConfig(trainNumber: "WB 912")

    // Prime the cache
    _ = await fetcher.fetch(config: config)
    XCTAssertEqual(mock.fetchJourneysCallCount, 5)

    // Switch to a different train — cache must be invalidated
    let newConfig = makeConfig(trainNumber: "RJX 100")
    _ = await fetcher.fetch(config: newConfig)
    XCTAssertEqual(mock.refreshJourneyCallCount, 0, "Should not use stale token for a different train")
    XCTAssertEqual(mock.fetchJourneysCallCount, 10, "Must do a full batch for the new config")
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
swift test --filter TrainFetcherTests/test_refreshToken 2>&1 | tail -20
swift test --filter TrainFetcherTests/test_fallsBack 2>&1 | tail -20
swift test --filter TrainFetcherTests/test_cacheInvalidated 2>&1 | tail -20
```

Expected: compile errors or assertion failures — caching logic not yet implemented.

- [ ] **Step 4: Add cache properties to `TrainFetcher`**

In `Sources/TrainTracker/TrainFetcher.swift`, add three private properties after `private static let offsets`:

```swift
// Refresh-token cache — all access is sequential via StatusBarController's timer
private var cachedRefreshToken: String?
private var cachedConfigKey: String?
private var cachedOptions: [TrainOption] = []
```

- [ ] **Step 5: Replace `fetch(config:)` body and add helper methods**

Replace the full `fetch(config:)` method in `TrainFetcher.swift`:

```swift
func fetch(config: AppConfig) async -> TrainStatus {
    guard let from = config.fromStation, let to = config.toStation else {
        invalidateCache()
        return .noConfig
    }

    let now = Date()
    let configKey = "\(from.id)|\(to.id)|\(config.trainNumber ?? "")"
    if configKey != cachedConfigKey {
        invalidateCache()
        cachedConfigKey = configKey
    }

    if let token = cachedRefreshToken, let trainNumber = config.trainNumber {
        if let td = await tryRefresh(token: token, trainNumber: trainNumber, now: now) {
            return .tracking(td, cachedOptions)
        }
        // tryRefresh cleared the token on failure; fall through to full fetch
    }

    let journeys = await fetchAllJourneys(fromId: from.id, toId: to.id, now: now)
    let options = buildOptions(from: journeys)
    cachedOptions = options

    guard let trainNumber = config.trainNumber else {
        return .pickTrain(options)
    }
    guard let (td, token) = findTrainWithToken(named: trainNumber, in: journeys, now: now) else {
        return .error("\(trainNumber) not found — use Switch Train to reselect")
    }
    cachedRefreshToken = token
    return .tracking(td, options)
}
```

Add these three private methods directly after `fetch(config:)`:

```swift
private func tryRefresh(token: String, trainNumber: String, now: Date) async -> TrainData? {
    guard let journey = try? await client.refreshJourney(token: token) else {
        cachedRefreshToken = nil
        return nil
    }
    guard let leg = journey.legs.first(where: { $0.line?.name == trainNumber }),
          let td = buildTrainData(leg: leg, now: now)
    else {
        cachedRefreshToken = nil
        return nil
    }
    return td
}

private func findTrainWithToken(named trainNumber: String, in journeys: [APIJourney], now: Date) -> (TrainData, String?)? {
    for journey in journeys {
        guard let leg = journey.legs.first(where: { $0.line?.name == trainNumber }),
              let td = buildTrainData(leg: leg, now: now) else { continue }
        return (td, journey.refreshToken)
    }
    return nil
}

private func invalidateCache() {
    cachedRefreshToken = nil
    cachedConfigKey = nil
    cachedOptions = []
}
```

Also simplify the existing `findTrain` (public, used by existing tests) to delegate:

```swift
func findTrain(named trainNumber: String, in journeys: [APIJourney], now: Date) -> TrainData? {
    findTrainWithToken(named: trainNumber, in: journeys, now: now)?.0
}
```

- [ ] **Step 6: Run all tests**

```bash
swift test 2>&1 | tail -20
```

Expected: all tests pass, including the three new refresh-path tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/TrainTracker/TrainFetcher.swift Tests/TrainTrackerTests/TrainFetcherTests.swift
git commit -m "feat: cache journey refresh token for single-call subsequent refreshes"
```

---

## Task 4: Switch Route… submenu in StatusBarController

**Files:**
- Modify: `Sources/TrainTracker/StatusBarController.swift`

No automated tests — verified manually after task 5.

- [ ] **Step 1: Add `selectRoute` action**

In `Sources/TrainTracker/StatusBarController.swift`, add after `selectTrain(_:)`:

```swift
@objc private func selectRoute(_ sender: NSMenuItem) {
    guard let route = sender.representedObject as? SavedRoute else { return }
    var config = AppConfigStore.shared.load()
    config.fromStation = route.from
    config.toStation = route.to
    config.trainNumber = nil
    AppConfigStore.shared.save(config)
    Task { await refresh() }
}
```

- [ ] **Step 2: Add `addRouteOptions` helper**

Add after `addTrainOptions(_:to:currentTrain:)`:

```swift
private func addRouteOptions(_ routes: [SavedRoute], to menu: NSMenu, currentRoute: SavedRoute?) {
    for route in routes {
        let item = NSMenuItem(
            title: route.displayName,
            action: #selector(selectRoute(_:)),
            keyEquivalent: ""
        )
        item.representedObject = route
        item.target = self
        if route == currentRoute { item.state = .on }
        menu.addItem(item)
    }
    if routes.isEmpty {
        menu.addItem(disabled("No saved routes"))
    }
}
```

- [ ] **Step 3: Add a `makeRouteSubmenu` helper and wire it into `buildMenu`**

Add this private helper before `buildMenu`:

```swift
private func makeRouteSubmenu(config: AppConfig) -> NSMenuItem {
    let item = NSMenuItem(title: "Switch Route…", action: nil, keyEquivalent: "")
    let sub = NSMenu()
    var currentRoute: SavedRoute? = nil
    if let from = config.fromStation, let to = config.toStation {
        currentRoute = config.savedRoutes.first { $0.from == from && $0.to == to }
    }
    addRouteOptions(config.savedRoutes, to: sub, currentRoute: currentRoute)
    item.submenu = sub
    return item
}
```

In `buildMenu(for:)`, the method currently loads nothing from config — add `let config = AppConfigStore.shared.load()` at the very top of the method:

```swift
private func buildMenu(for status: TrainStatus) -> NSMenu {
    let config = AppConfigStore.shared.load()
    let menu = NSMenu()
    ...
```

Then in the `.tracking` case, add the submenu after the Switch Train item:

```swift
case .tracking(let td, let options):
    addTrackingHeader(td, to: menu)
    if !td.stopovers.isEmpty {
        menu.addItem(.separator())
        addStopovers(td.stopovers, to: menu)
    }
    menu.addItem(.separator())
    let switchItem = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
    let switchSub = NSMenu()
    addTrainOptions(options, to: switchSub, currentTrain: td.trainName)
    switchItem.submenu = switchSub
    menu.addItem(switchItem)
    menu.addItem(makeRouteSubmenu(config: config))
```

And in the `.pickTrain` case, add it after the train options:

```swift
case .pickTrain(let options):
    menu.addItem(disabled("Pick your train:"))
    menu.addItem(.separator())
    addTrainOptions(options, to: menu, currentTrain: nil)
    menu.addItem(.separator())
    menu.addItem(makeRouteSubmenu(config: config))
```

- [ ] **Step 4: Build the project to confirm no compile errors**

```bash
swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/StatusBarController.swift
git commit -m "feat: add Switch Route submenu to menu bar"
```

---

## Task 5: Delete saved routes in Preferences

**Files:**
- Modify: `Sources/TrainTracker/PreferencesWindowController.swift`

- [ ] **Step 1: Add `DeletableTableView` class**

Add at the very bottom of `Sources/TrainTracker/PreferencesWindowController.swift`, after the last extension:

```swift
// MARK: - DeletableTableView

private class DeletableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // keyCode 51 = Delete (backspace), 117 = Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
```

- [ ] **Step 2: Add `deleteRouteButton` property**

In the `PreferencesWindowController` class body, add after `private var searchTask: Task<Void, Never>?`:

```swift
private var deleteRouteButton: NSButton!
```

- [ ] **Step 3: Replace the saved-routes table setup in `setupUI`**

Find the section in `setupUI` that builds the saved-routes table and replace the NSTableView setup, columns, and scroll view with:

```swift
// Saved routes label
let routesLabel = makeLabel("Saved routes:")
routesLabel.frame = NSRect(x: 16, y: 248, width: 120, height: 20)
cv.addSubview(routesLabel)

// "–" delete button aligned with the label
let deleteBtn = NSButton(title: "–", target: self, action: #selector(deleteSelectedRoute))
deleteBtn.bezelStyle = .smallSquare
deleteBtn.frame = NSRect(x: 352, y: 244, width: 32, height: 24)
deleteBtn.isEnabled = false
cv.addSubview(deleteBtn)
deleteRouteButton = deleteBtn

// Saved routes table (single column, full-width)
let savedScrollView = NSScrollView(frame: NSRect(x: 16, y: 164, width: 368, height: 76))
savedScrollView.hasVerticalScroller = true
savedScrollView.borderType = .bezelBorder
let deletable = DeletableTableView()
deletable.onDelete = { [weak self] in self?.deleteSelectedRoute() }
savedRoutesTable = deletable
let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
nameCol.title = "Route"
nameCol.width = 350
savedRoutesTable.addTableColumn(nameCol)
savedRoutesTable.headerView = nil
savedRoutesTable.dataSource = self
savedRoutesTable.delegate = self
savedRoutesTable.action = #selector(savedRouteRowClicked)
savedRoutesTable.target = self
savedScrollView.documentView = savedRoutesTable
cv.addSubview(savedScrollView)
```

(Remove the old `routesLabel`, `savedScrollView`, `savedRoutesTable`, `nameCol`, and `loadCol` blocks that were there before.)

- [ ] **Step 4: Add `deleteSelectedRoute` action**

Add after `savedRouteRowClicked`:

```swift
@objc private func deleteSelectedRoute() {
    let row = savedRoutesTable.selectedRow
    guard row >= 0, row < savedRoutes.count else { return }
    savedRoutes.remove(at: row)
    savedRoutesTable.reloadData()
    deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
}
```

- [ ] **Step 5: Update `tableViewSelectionDidChange` to enable/disable the button**

In the `NSTableViewDataSource + NSTableViewDelegate` extension, add after `numberOfRows(in:)`:

```swift
func tableViewSelectionDidChange(_ notification: Notification) {
    guard let table = notification.object as? NSTableView, table === savedRoutesTable else { return }
    deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
}
```

- [ ] **Step 6: Remove "Load" column handling from `tableView(_:viewFor:row:)`**

Replace the saved-routes branch of `tableView(_:viewFor:tableColumn:row:)`:

```swift
func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTextField(labelWithString: "")
    cell.font = NSFont.systemFont(ofSize: 13)
    if tableView === resultsTable {
        cell.stringValue = searchResults[row].name
    } else {
        cell.stringValue = savedRoutes[row].displayName
    }
    return cell
}
```

- [ ] **Step 7: Fix `saveAndClose` to persist in-memory deletions**

Replace the route-saving section inside `saveAndClose`:

```swift
// Build saved routes from in-memory list (reflects any deletions), then add current if new
var routes = savedRoutes
if let f = pendingFrom, let t = pendingTo {
    let route = SavedRoute(from: f, to: t)
    if !routes.contains(route) {
        routes.append(route)
    }
}
config.savedRoutes = routes
```

The full updated `saveAndClose` should read:

```swift
@objc private func saveAndClose() {
    var config = AppConfigStore.shared.load()
    let stationsChanged = config.fromStation != pendingFrom || config.toStation != pendingTo
    config.fromStation = pendingFrom
    config.toStation = pendingTo
    var routes = savedRoutes
    if let f = pendingFrom, let t = pendingTo {
        let route = SavedRoute(from: f, to: t)
        if !routes.contains(route) {
            routes.append(route)
        }
    }
    config.savedRoutes = routes
    if stationsChanged { config.trainNumber = nil }
    config.notifications = NotificationSettings(
        departureReminderEnabled: departureReminderCheckbox.state == .on,
        departureReminderMinutes: max(1, departureReminderField.integerValue),
        delayAlertEnabled: delayAlertCheckbox.state == .on,
        delayAlertThresholdMinutes: max(1, delayAlertField.integerValue),
        platformChangeEnabled: platformChangeCheckbox.state == .on
    )
    AppConfigStore.shared.save(config)
    close()
}
```

- [ ] **Step 8: Build and run all tests**

```bash
swift build 2>&1 | tail -20
swift test 2>&1 | tail -20
```

Expected: `Build complete!` and all tests pass.

- [ ] **Step 9: Manual verification**

Run the app (`swift run` or `./rebuild.sh`) and verify:
1. Open Preferences → saved routes table is single-column; clicking a row loads it into the fields
2. Select a row → "–" button enables; clicking "–" removes the row
3. Select a row → press Delete key → row removed
4. Save & Close → deleted routes are gone from persistent storage
5. Menu bar shows "Switch Route…" submenu; selecting a route updates the from/to and clears the train
6. A new 30-second tick uses a single refresh call (check Console for no extra traffic after the first tick)

- [ ] **Step 10: Commit**

```bash
git add Sources/TrainTracker/PreferencesWindowController.swift
git commit -m "feat: add delete button and Delete key for saved routes; drop Load column"
```
