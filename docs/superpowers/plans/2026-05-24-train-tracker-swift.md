# TrainTracker Swift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app in Swift that tracks the user's current Austrian train, showing countdown-to-arrival in the title bar and intermediate stops in the dropdown menu.

**Architecture:** Swift Package Manager executable (no Xcode project required) using AppKit + URLSession with zero third-party dependencies. Four concurrent API calls at time offsets -6h, -4h, -2h, now find the user's train every 30 seconds. Station IDs are stored at setup time — never resolved at runtime — eliminating the "station not found" failure mode.

**Tech Stack:** Swift 5.9+, AppKit, URLSession, XCTest, UserDefaults, `https://oebb.macistry.com/api`

---

## File Map

| File | Responsibility |
|---|---|
| `Package.swift` | SPM manifest, macOS 13 target, test target |
| `Sources/TrainTracker/main.swift` | Entry point: launch NSApplication, set `.accessory` policy |
| `Sources/TrainTracker/AppDelegate.swift` | Create StatusBarController on launch |
| `Sources/TrainTracker/Models.swift` | Codable API response types + internal display types (`TrainStatus`, `TrainData`, etc.) |
| `Sources/TrainTracker/AppConfig.swift` | `AppConfig` struct + `AppConfigStore` (UserDefaults persistence) |
| `Sources/TrainTracker/OeBBClient.swift` | URLSession wrapper: `searchStations` + `fetchJourneys` |
| `Sources/TrainTracker/TrainFetcher.swift` | Business logic: concurrent fetch, deduplication, train matching, stopover building |
| `Sources/TrainTracker/StatusBarController.swift` | `NSStatusItem`, 30s timer, menu building, title formatting, menu action handlers |
| `Sources/TrainTracker/PreferencesWindowController.swift` | Programmatic `NSPanel`, station search UI, saved routes |
| `Tests/TrainTrackerTests/ModelsTests.swift` | JSON decoding tests |
| `Tests/TrainTrackerTests/AppConfigTests.swift` | Save/load roundtrip tests |
| `Tests/TrainTrackerTests/TrainFetcherTests.swift` | Deduplication, option building, train matching, date parsing |
| `Tests/TrainTrackerTests/StatusBarControllerTests.swift` | Title string formatting for all states |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/TrainTracker/main.swift`
- Create: `Sources/TrainTracker/AppDelegate.swift`

- [ ] **Step 1: Verify working directory and init git**

```bash
cd /Users/philipp/Development/traintracker
git init
echo ".build/" > .gitignore
echo "*.o" >> .gitignore
echo "*.d" >> .gitignore
```

- [ ] **Step 2: Create Package.swift**

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "TrainTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TrainTracker",
            path: "Sources/TrainTracker"
        ),
        .testTarget(
            name: "TrainTrackerTests",
            dependencies: ["TrainTracker"],
            path: "Tests/TrainTrackerTests"
        )
    ]
)
```

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p Sources/TrainTracker Tests/TrainTrackerTests
```

- [ ] **Step 4: Create main.swift**

```swift
// Sources/TrainTracker/main.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Create AppDelegate.swift (stub)**

```swift
// Sources/TrainTracker/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}
```

- [ ] **Step 6: Verify the project compiles**

`StatusBarController` does not exist yet — create a temporary stub so the build passes:

```swift
// Sources/TrainTracker/StatusBarController.swift  (temporary stub)
import AppKit

@MainActor
final class StatusBarController {
    init() {}
}
```

Run:
```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/ .gitignore
git commit -m "feat: scaffold Swift Package Manager project"
```

---

## Task 2: Data Models

**Files:**
- Create: `Sources/TrainTracker/Models.swift`
- Create: `Tests/TrainTrackerTests/ModelsTests.swift`

- [ ] **Step 1: Write the failing decode test**

```swift
// Tests/TrainTrackerTests/ModelsTests.swift
import XCTest
@testable import TrainTracker

final class ModelsTests: XCTestCase {
    func test_decodeJourneysResponse() throws {
        let json = """
        {
          "journeys": [{
            "legs": [{
              "origin": {"id":"8100013","name":"Linz/Donau Hbf"},
              "destination": {"id":"8100002","name":"Salzburg Hbf"},
              "plannedDeparture": "2026-05-24T12:56:00+02:00",
              "plannedArrival": "2026-05-24T14:08:00+02:00",
              "departureDelay": 0,
              "arrivalDelay": 180,
              "departurePlatform": "3",
              "arrivalPlatform": "5",
              "line": {"name":"WB 912","product":"interregional"},
              "stopovers": [
                {"stop":{"id":"1","name":"Linz/Donau Hbf"},
                 "plannedDeparture":"2026-05-24T12:56:00+02:00"},
                {"stop":{"id":"2","name":"Attnang-Puchheim"},
                 "plannedArrival":"2026-05-24T13:28:00+02:00"},
                {"stop":{"id":"3","name":"Salzburg Hbf"},
                 "plannedArrival":"2026-05-24T14:08:00+02:00"}
              ]
            }]
          }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(APIJourneysResponse.self, from: json)
        XCTAssertEqual(response.journeys.count, 1)
        let leg = response.journeys[0].legs[0]
        XCTAssertEqual(leg.line?.name, "WB 912")
        XCTAssertEqual(leg.origin.name, "Linz/Donau Hbf")
        XCTAssertEqual(leg.arrivalDelay, 180)
        XCTAssertEqual(leg.departurePlatform, "3")
        XCTAssertEqual(leg.stopovers?.count, 3)
    }

    func test_decodeLocationsResponse() throws {
        let json = """
        [
          {"id":"8100013","name":"Linz/Donau Hbf","type":"stop"},
          {"id":"1140101","name":"Linz/Donau","type":"station"}
        ]
        """.data(using: .utf8)!

        let locations = try JSONDecoder().decode([APILocation].self, from: json)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].id, "8100013")
        XCTAssertEqual(locations[0].type, "stop")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ModelsTests 2>&1 | tail -10
```
Expected: error — `APIJourneysResponse`, `APILocation` not found.

- [ ] **Step 3: Write Models.swift**

```swift
// Sources/TrainTracker/Models.swift
import Foundation

// MARK: - API Response Types

struct APILocation: Codable {
    let id: String
    let name: String
    let type: String?
}

struct APIStop: Codable {
    let id: String
    let name: String
}

struct APILine: Codable {
    let name: String?
    let product: String?
}

struct APIStopover: Codable {
    let stop: APIStop
    let arrival: String?
    let plannedArrival: String?
    let departure: String?
    let plannedDeparture: String?
    let arrivalDelay: Int?
    let departureDelay: Int?
}

struct APILeg: Codable {
    let origin: APIStop
    let destination: APIStop
    let departure: String?
    let plannedDeparture: String?
    let arrival: String?
    let plannedArrival: String?
    let departureDelay: Int?
    let arrivalDelay: Int?
    let line: APILine?
    let departurePlatform: String?
    let arrivalPlatform: String?
    let stopovers: [APIStopover]?
}

struct APIJourney: Codable {
    let legs: [APILeg]
}

struct APIJourneysResponse: Codable {
    let journeys: [APIJourney]
}

// MARK: - Internal Display Types

enum TrainStatus {
    case noConfig
    case pickTrain([TrainOption])
    case tracking(TrainData, [TrainOption])   // second arg: available trains for Switch Train submenu
    case error(String)
}

struct TrainData {
    let trainName: String
    let fromName: String
    let toName: String
    let scheduledDeparture: Date
    let scheduledArrival: Date
    let departureDelaySecs: Int
    let arrivalDelaySecs: Int
    let departurePlatform: String?
    let arrivalPlatform: String?
    let stopovers: [StopoverInfo]
    let isEnRoute: Bool
}

struct StopoverInfo {
    let name: String
    let scheduledArrival: Date?
    let arrivalDelaySecs: Int
    let passed: Bool
    let isNext: Bool
}

struct TrainOption {
    let name: String
    let scheduledDeparture: Date
    let scheduledArrival: Date
    let departureDelaySecs: Int
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ModelsTests 2>&1 | tail -5
```
Expected: `Test Suite 'ModelsTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/Models.swift Tests/TrainTrackerTests/ModelsTests.swift
git commit -m "feat: add API response and display models"
```

---

## Task 3: Configuration Persistence

**Files:**
- Create: `Sources/TrainTracker/AppConfig.swift`
- Create: `Tests/TrainTrackerTests/AppConfigTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
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
            to: Station(name: "Salzburg Hbf", id: "8100002")
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
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AppConfigTests 2>&1 | tail -10
```
Expected: error — `AppConfig`, `AppConfigStore`, `Station`, `SavedRoute` not found.

- [ ] **Step 3: Write AppConfig.swift**

```swift
// Sources/TrainTracker/AppConfig.swift
import Foundation

struct Station: Codable, Equatable {
    var name: String   // display only
    var id: String     // used for all API calls
}

struct SavedRoute: Codable, Equatable {
    var from: Station
    var to: Station

    var displayName: String { "\(from.name) → \(to.name)" }
}

struct AppConfig: Codable {
    var fromStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var savedRoutes: [SavedRoute]

    init() { savedRoutes = [] }
}

final class AppConfigStore {
    static let shared = AppConfigStore()

    private let key = "config"
    private let defaults: UserDefaults

    init(suiteName: String = "traintracker") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func load() -> AppConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    func save(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter AppConfigTests 2>&1 | tail -5
```
Expected: `Test Suite 'AppConfigTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/AppConfig.swift Tests/TrainTrackerTests/AppConfigTests.swift
git commit -m "feat: add configuration persistence with UserDefaults"
```

---

## Task 4: API Client

**Files:**
- Create: `Sources/TrainTracker/OeBBClient.swift`
- Create: `Tests/TrainTrackerTests/OeBBClientTests.swift`

- [ ] **Step 1: Write failing tests (URL construction only — no network)**

```swift
// Tests/TrainTrackerTests/OeBBClientTests.swift
import XCTest
@testable import TrainTracker

final class OeBBClientTests: XCTestCase {
    func test_searchStationsURL() {
        let url = OeBBClient.locationsURL(query: "Linz Hbf")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("oebb.macistry.com"))
        XCTAssertTrue(url!.absoluteString.contains("locations"))
        XCTAssertTrue(url!.absoluteString.contains("Linz"))
    }

    func test_searchStationsURL_encodesSpecialChars() {
        let url = OeBBClient.locationsURL(query: "St. Pölten Hbf")
        XCTAssertNotNil(url)
        // space and ö must be percent-encoded
        XCTAssertFalse(url!.absoluteString.contains(" "))
        XCTAssertFalse(url!.absoluteString.contains("ö"))
    }

    func test_journeysURL() {
        let dep = Date(timeIntervalSince1970: 1_716_548_160) // fixed timestamp
        let url = OeBBClient.journeysURL(fromId: "8100013", toId: "8100002", departure: dep)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("from=8100013"))
        XCTAssertTrue(url!.absoluteString.contains("to=8100002"))
        XCTAssertTrue(url!.absoluteString.contains("stopovers=true"))
        XCTAssertTrue(url!.absoluteString.contains("results=12"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter OeBBClientTests 2>&1 | tail -10
```
Expected: error — `OeBBClient` not found.

- [ ] **Step 3: Write OeBBClient.swift**

```swift
// Sources/TrainTracker/OeBBClient.swift
import Foundation

enum OeBBError: Error {
    case invalidURL
    case httpError(Int)
}

final class OeBBClient {
    static let baseURL = "https://oebb.macistry.com/api"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - URL constructors (static for testability)

    static func locationsURL(query: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/locations")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "results", value: "8")
        ]
        return components?.url
    }

    static func journeysURL(fromId: String, toId: String, departure: Date) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let depString = formatter.string(from: departure)
        var components = URLComponents(string: "\(baseURL)/journeys")
        components?.queryItems = [
            URLQueryItem(name: "from", value: fromId),
            URLQueryItem(name: "to", value: toId),
            URLQueryItem(name: "departure", value: depString),
            URLQueryItem(name: "results", value: "12"),
            URLQueryItem(name: "stopovers", value: "true")
        ]
        return components?.url
    }

    // MARK: - Network calls

    func searchStations(query: String) async throws -> [APILocation] {
        guard let url = Self.locationsURL(query: query) else { throw OeBBError.invalidURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OeBBError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode([APILocation].self, from: data)
    }

    func fetchJourneys(fromId: String, toId: String, departure: Date) async throws -> [APIJourney] {
        guard let url = Self.journeysURL(fromId: fromId, toId: toId, departure: departure) else {
            throw OeBBError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OeBBError.httpError(http.statusCode)
        }
        let resp = try JSONDecoder().decode(APIJourneysResponse.self, from: data)
        return resp.journeys
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter OeBBClientTests 2>&1 | tail -5
```
Expected: `Test Suite 'OeBBClientTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/OeBBClient.swift Tests/TrainTrackerTests/OeBBClientTests.swift
git commit -m "feat: add OeBB API client (URLSession wrapper)"
```

---

## Task 5: Train Fetcher (Core Business Logic)

**Files:**
- Create: `Sources/TrainTracker/TrainFetcher.swift`
- Create: `Tests/TrainTrackerTests/TrainFetcherTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/TrainTrackerTests/TrainFetcherTests.swift
import XCTest
@testable import TrainTracker

final class TrainFetcherTests: XCTestCase {
    let fetcher = TrainFetcher(client: OeBBClient())

    // MARK: - parseDate

    func test_parseDate_validISO8601WithOffset() {
        let date = TrainFetcher.parseDate("2026-05-24T12:56:00+02:00")
        XCTAssertNotNil(date)
        // Verify the absolute timestamp: 12:56 CEST = 10:56 UTC
        let cal = Calendar(identifier: .gregorian)
        var utc = TimeZone(identifier: "UTC")!
        var components = cal.dateComponents(in: utc, from: date!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 56)
    }

    func test_parseDate_nilForEmpty() {
        XCTAssertNil(TrainFetcher.parseDate(nil))
        XCTAssertNil(TrainFetcher.parseDate(""))
        XCTAssertNil(TrainFetcher.parseDate("not-a-date"))
    }

    // MARK: - deduplicated

    func test_deduplicated_removesJourneysWithSameTrainAndDeparture() {
        let journey = makeJourney(trainName: "WB 912", plannedDep: "2026-05-24T12:56:00+02:00")
        let duplicate = makeJourney(trainName: "WB 912", plannedDep: "2026-05-24T12:56:00+02:00")
        let different = makeJourney(trainName: "WB 914", plannedDep: "2026-05-24T13:56:00+02:00")

        let result = TrainFetcher.deduplicated([journey, duplicate, different])
        XCTAssertEqual(result.count, 2)
    }

    func test_deduplicated_keepsSameTrainDifferentDeparture() {
        let morning = makeJourney(trainName: "WB 912", plannedDep: "2026-05-24T08:56:00+02:00")
        let afternoon = makeJourney(trainName: "WB 912", plannedDep: "2026-05-24T12:56:00+02:00")

        let result = TrainFetcher.deduplicated([morning, afternoon])
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - buildOptions (no arrival time filter)

    func test_buildOptions_includesArrivedTrains() {
        // Train that arrived 2 hours ago — must still appear in options
        let now = Date()
        let departed = now.addingTimeInterval(-4 * 3600)
        let arrived = now.addingTimeInterval(-2 * 3600)
        let journey = makeJourney(
            trainName: "WB 910",
            plannedDep: iso8601(departed),
            plannedArr: iso8601(arrived)
        )

        let options = fetcher.buildOptions(from: [journey])
        XCTAssertEqual(options.count, 1, "Arrived train must still appear so user can select mid-journey")
        XCTAssertEqual(options[0].name, "WB 910")
    }

    func test_buildOptions_sortedByDeparture() {
        let now = Date()
        let j1 = makeJourney(trainName: "WB 914", plannedDep: iso8601(now.addingTimeInterval(3600)),
                             plannedArr: iso8601(now.addingTimeInterval(7200)))
        let j2 = makeJourney(trainName: "WB 912", plannedDep: iso8601(now.addingTimeInterval(-3600)),
                             plannedArr: iso8601(now.addingTimeInterval(600)))

        let options = fetcher.buildOptions(from: [j1, j2])
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].name, "WB 912")   // earlier departure first
        XCTAssertEqual(options[1].name, "WB 914")
    }

    // MARK: - findTrain

    func test_findTrain_exactNameMatch() {
        let now = Date()
        let j = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-3600)),
            plannedArr: iso8601(now.addingTimeInterval(3600))
        )

        let result = fetcher.findTrain(named: "WB 912", in: [j], now: now)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.trainName, "WB 912")
    }

    func test_findTrain_returnsNilForNoMatch() {
        let now = Date()
        let j = makeJourney(trainName: "WB 912", plannedDep: iso8601(now), plannedArr: iso8601(now.addingTimeInterval(3600)))

        let result = fetcher.findTrain(named: "RJX 860", in: [j], now: now)
        XCTAssertNil(result)
    }

    func test_findTrain_setsIsEnRouteCorrectly() {
        let now = Date()
        // departed 30 minutes ago
        let j = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-1800)),
            plannedArr: iso8601(now.addingTimeInterval(3600))
        )

        let result = fetcher.findTrain(named: "WB 912", in: [j], now: now)
        XCTAssertEqual(result?.isEnRoute, true)
    }

    // MARK: - buildStopovers

    func test_buildStopovers_marksPassedAndNextStop() {
        let now = Date()
        let past = now.addingTimeInterval(-600)
        let future1 = now.addingTimeInterval(600)
        let future2 = now.addingTimeInterval(1200)

        // stopovers: origin, passed-intermediate, next-intermediate, destination
        let stopovers: [APIStopover] = [
            makeStopover(name: "Origin", dep: iso8601(now.addingTimeInterval(-3600))),
            makeStopover(name: "Passed Stop", arr: iso8601(past)),
            makeStopover(name: "Next Stop", arr: iso8601(future1)),
            makeStopover(name: "Future Stop", arr: iso8601(future2)),
            makeStopover(name: "Destination", arr: iso8601(now.addingTimeInterval(3600)))
        ]

        let result = fetcher.buildStopovers(stopovers: stopovers, now: now)
        // origin and destination are stripped: 3 intermediate stops remain
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].passed,   "Passed Stop should be marked passed")
        XCTAssertFalse(result[0].isNext,  "Passed Stop should not be next")
        XCTAssertFalse(result[1].passed,  "Next Stop should not be passed")
        XCTAssertTrue(result[1].isNext,   "Next Stop should be marked next")
        XCTAssertFalse(result[2].passed,  "Future Stop should not be passed")
        XCTAssertFalse(result[2].isNext,  "Future Stop should not be next")
    }

    // MARK: - Helpers

    private func makeJourney(
        trainName: String,
        plannedDep: String,
        plannedArr: String = "2026-05-24T14:08:00+02:00"
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
        return APIJourney(legs: [leg])
    }

    private func makeStopover(name: String, arr: String? = nil, dep: String? = nil) -> APIStopover {
        APIStopover(
            stop: APIStop(id: name, name: name),
            arrival: arr,
            plannedArrival: arr,
            departure: dep,
            plannedDeparture: dep,
            arrivalDelay: nil,
            departureDelay: nil
        )
    }

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter TrainFetcherTests 2>&1 | tail -10
```
Expected: error — `TrainFetcher` not found.

- [ ] **Step 3: Write TrainFetcher.swift**

```swift
// Sources/TrainTracker/TrainFetcher.swift
import Foundation

final class TrainFetcher {
    private let client: OeBBClient
    private static let offsets: [TimeInterval] = [-6 * 3600, -4 * 3600, -2 * 3600, 0]

    init(client: OeBBClient = OeBBClient()) {
        self.client = client
    }

    // MARK: - Main entry point

    func fetch(config: AppConfig) async -> TrainStatus {
        guard let from = config.fromStation, let to = config.toStation else {
            return .noConfig
        }
        let now = Date()
        let journeys = await fetchAllJourneys(fromId: from.id, toId: to.id, now: now)
        let options = buildOptions(from: journeys)

        guard let trainNumber = config.trainNumber else {
            return .pickTrain(options)
        }
        guard let match = findTrain(named: trainNumber, in: journeys, now: now) else {
            return .error("\(trainNumber) not found — use Switch Train to reselect")
        }
        return .tracking(match, options)
    }

    // MARK: - Concurrent journey fetch

    private func fetchAllJourneys(fromId: String, toId: String, now: Date) async -> [APIJourney] {
        await withTaskGroup(of: [APIJourney].self) { group in
            for offset in Self.offsets {
                let dep = now.addingTimeInterval(offset)
                group.addTask { [self] in
                    (try? await client.fetchJourneys(fromId: fromId, toId: toId, departure: dep)) ?? []
                }
            }
            var all: [APIJourney] = []
            for await batch in group { all.append(contentsOf: batch) }
            return Self.deduplicated(all)
        }
    }

    // MARK: - Deduplication (by trainName + plannedDeparture, exact)

    static func deduplicated(_ journeys: [APIJourney]) -> [APIJourney] {
        var seen = Set<String>()
        return journeys.filter { journey in
            guard let leg = journey.legs.first(where: { $0.line?.name != nil }),
                  let name = leg.line?.name,
                  let dep = leg.plannedDeparture ?? leg.departure
            else { return false }
            return seen.insert("\(name)|\(dep)").inserted
        }
    }

    // MARK: - Build train option list (no arrival time filter — fixes problem B)

    func buildOptions(from journeys: [APIJourney]) -> [TrainOption] {
        var seenNames = Set<String>()
        var options: [TrainOption] = []

        for journey in journeys {
            guard let leg = journey.legs.first(where: { $0.line?.name != nil }),
                  let name = leg.line?.name, !name.isEmpty,
                  let schDep = Self.parseDate(leg.plannedDeparture ?? leg.departure),
                  let schArr = Self.parseDate(leg.plannedArrival ?? leg.arrival),
                  seenNames.insert(name).inserted
            else { continue }

            options.append(TrainOption(
                name: name,
                scheduledDeparture: schDep,
                scheduledArrival: schArr,
                departureDelaySecs: leg.departureDelay ?? 0
            ))
        }
        return options.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    // MARK: - Find specific train by exact name

    func findTrain(named trainNumber: String, in journeys: [APIJourney], now: Date) -> TrainData? {
        for journey in journeys {
            guard let leg = journey.legs.first(where: { $0.line?.name == trainNumber }) else { continue }
            return buildTrainData(leg: leg, now: now)
        }
        return nil
    }

    // MARK: - Build TrainData from a leg

    private func buildTrainData(leg: APILeg, now: Date) -> TrainData? {
        guard let name = leg.line?.name,
              let schDep = Self.parseDate(leg.plannedDeparture ?? leg.departure),
              let schArr = Self.parseDate(leg.plannedArrival ?? leg.arrival)
        else { return nil }

        let depDelay = leg.departureDelay ?? 0
        let rtDep = schDep.addingTimeInterval(TimeInterval(depDelay))

        return TrainData(
            trainName: name,
            fromName: leg.origin.name,
            toName: leg.destination.name,
            scheduledDeparture: schDep,
            scheduledArrival: schArr,
            departureDelaySecs: depDelay,
            arrivalDelaySecs: leg.arrivalDelay ?? 0,
            departurePlatform: leg.departurePlatform,
            arrivalPlatform: leg.arrivalPlatform,
            stopovers: buildStopovers(stopovers: leg.stopovers ?? [], now: now),
            isEnRoute: rtDep <= now
        )
    }

    // MARK: - Build stopover list (strips origin + destination)

    func buildStopovers(stopovers: [APIStopover], now: Date) -> [StopoverInfo] {
        guard stopovers.count > 2 else { return [] }
        let middle = Array(stopovers.dropFirst().dropLast())

        // Find the index of the first upcoming stop
        let nextIdx = middle.firstIndex { sv in
            let t = Self.parseDate(sv.arrival ?? sv.plannedArrival)
                    ?? Self.parseDate(sv.departure ?? sv.plannedDeparture)
            return (t ?? .distantPast) > now
        }

        return middle.enumerated().map { (i, sv) in
            StopoverInfo(
                name: sv.stop.name,
                scheduledArrival: Self.parseDate(sv.plannedArrival ?? sv.arrival),
                arrivalDelaySecs: sv.arrivalDelay ?? sv.departureDelay ?? 0,
                passed: nextIdx.map { i < $0 } ?? true,
                isNext: nextIdx == i
            )
        }
    }

    // MARK: - Date parsing

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter TrainFetcherTests 2>&1 | tail -8
```
Expected: `Test Suite 'TrainFetcherTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/TrainFetcher.swift Tests/TrainTrackerTests/TrainFetcherTests.swift
git commit -m "feat: add train fetcher with concurrent search and exact-match deduplication"
```

---

## Task 6: Status Bar — Title Formatting

**Files:**
- Replace: `Sources/TrainTracker/StatusBarController.swift` (was a stub)
- Create: `Tests/TrainTrackerTests/StatusBarControllerTests.swift`

- [ ] **Step 1: Write failing tests for title formatting**

```swift
// Tests/TrainTrackerTests/StatusBarControllerTests.swift
import XCTest
@testable import TrainTracker

final class StatusBarControllerTests: XCTestCase {
    func test_titleForNoConfig() {
        let title = StatusBarController.titleString(for: .noConfig, consecutiveErrors: 0)
        XCTAssertEqual(title, "Train")
    }

    func test_titleForPickTrain() {
        let title = StatusBarController.titleString(for: .pickTrain([]), consecutiveErrors: 0)
        XCTAssertEqual(title, "Train")
    }

    func test_titleForErrorAfterTwoFailures() {
        let title = StatusBarController.titleString(for: .error("oops"), consecutiveErrors: 2)
        XCTAssertEqual(title, "Train (!)")
    }

    func test_titleWaitingToDepartShowsCountdown() {
        let now = Date()
        let dep = now.addingTimeInterval(12 * 60)  // departs in 12 minutes
        let arr = now.addingTimeInterval(90 * 60)
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, depDelay: 0, isEnRoute: false)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0)
        XCTAssertEqual(title, "WB 912  in 12m")
    }

    func test_titleEnRouteOnTime() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)  // departed 30 min ago
        let arr = now.addingTimeInterval(72 * 60)   // arrives at now + 72 min → HH:MM
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let expected = "WB 912  arr \(f.string(from: arr))"
        XCTAssertEqual(title, expected)
    }

    func test_titleEnRouteDelayed() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)
        let arr = now.addingTimeInterval(72 * 60)
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 180, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let rtArr = arr.addingTimeInterval(180)
        let expected = "WB 912  arr \(f.string(from: rtArr)) +3m"
        XCTAssertEqual(title, expected)
    }

    func test_titleArrived() {
        let now = Date()
        let dep = now.addingTimeInterval(-120 * 60)
        let arr = now.addingTimeInterval(-10 * 60)   // arrived 10 min ago
        let td = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(td, []), consecutiveErrors: 0)
        XCTAssertEqual(title, "WB 912  Arrived")
    }

    // MARK: - Helpers

    private func makeTrainData(
        name: String, dep: Date, arr: Date,
        depDelay: Int = 0, arrDelay: Int = 0, isEnRoute: Bool = false
    ) -> TrainData {
        TrainData(
            trainName: name, fromName: "A", toName: "B",
            scheduledDeparture: dep, scheduledArrival: arr,
            departureDelaySecs: depDelay, arrivalDelaySecs: arrDelay,
            departurePlatform: nil, arrivalPlatform: nil,
            stopovers: [], isEnRoute: isEnRoute
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter StatusBarControllerTests 2>&1 | tail -10
```
Expected: error — `StatusBarController.titleString` not found (stub has no such method).

- [ ] **Step 3: Replace stub with full StatusBarController.swift**

```swift
// Sources/TrainTracker/StatusBarController.swift
import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private let fetcher = TrainFetcher()
    private var consecutiveErrors = 0
    private var lastGoodStatus: TrainStatus = .noConfig   // shown during transient errors
    private var prefsController: PreferencesWindowController?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Train"
        startTimer()
        Task { await refresh() }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refresh() }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        let config = AppConfigStore.shared.load()
        let status = await fetcher.fetch(config: config)

        if case .error = status {
            consecutiveErrors += 1
        } else {
            consecutiveErrors = 0
            lastGoodStatus = status
        }

        // Show last good data for transient errors; show error UI after 2 consecutive failures
        let displayStatus: TrainStatus = consecutiveErrors >= 2 ? status : lastGoodStatus
        statusItem.button?.title = Self.titleString(for: displayStatus, consecutiveErrors: consecutiveErrors)
        statusItem.menu = buildMenu(for: displayStatus)
    }

    // MARK: - Title string (static for testability)

    static func titleString(for status: TrainStatus, consecutiveErrors: Int) -> String {
        switch status {
        case .noConfig, .pickTrain:
            return "Train"
        case .error:
            return consecutiveErrors >= 2 ? "Train (!)" : "Train"
        case .tracking(let td, _):
            let now = Date()
            let rtArr = td.scheduledArrival.addingTimeInterval(TimeInterval(td.arrivalDelaySecs))
            let rtDep = td.scheduledDeparture.addingTimeInterval(TimeInterval(td.departureDelaySecs))

            if rtArr <= now {
                return "\(td.trainName)  Arrived"
            } else if td.isEnRoute {
                let timeStr = formatHHMM(td.scheduledArrival, delaySecs: td.arrivalDelaySecs)
                let delay = formatDelay(td.arrivalDelaySecs)
                return delay.isEmpty
                    ? "\(td.trainName)  arr \(timeStr)"
                    : "\(td.trainName)  arr \(timeStr) \(delay)"
            } else {
                let mins = max(0, Int(rtDep.timeIntervalSince(now) / 60))
                return "\(td.trainName)  in \(mins)m"
            }
        }
    }

    // MARK: - Formatting helpers

    static func formatHHMM(_ date: Date, delaySecs: Int) -> String {
        let rt = date.addingTimeInterval(TimeInterval(delaySecs))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: rt)
    }

    static func formatDelay(_ secs: Int) -> String {
        guard secs != 0 else { return "" }
        let mins = (abs(secs) + 59) / 60
        return secs > 0 ? "+\(mins)m" : "-\(mins)m"
    }

    // MARK: - Menu building

    private func buildMenu(for status: TrainStatus) -> NSMenu {
        let menu = NSMenu()

        switch status {
        case .noConfig:
            menu.addItem(disabled("Open Preferences to get started"))

        case .pickTrain(let options):
            menu.addItem(disabled("Pick your train:"))
            menu.addItem(.separator())
            addTrainOptions(options, to: menu, currentTrain: nil)

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

        case .error(let msg):
            menu.addItem(disabled(msg))
        }

        menu.addItem(.separator())
        menu.addItem(action("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(action("Refresh", #selector(manualRefresh), key: "r"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func addTrackingHeader(_ td: TrainData, to menu: NSMenu) {
        menu.addItem(disabled("\(td.trainName)  \(td.fromName) → \(td.toName)"))

        let dep = Self.formatHHMM(td.scheduledDeparture, delaySecs: td.departureDelaySecs)
        let arr = Self.formatHHMM(td.scheduledArrival, delaySecs: td.arrivalDelaySecs)
        let dd = Self.formatDelay(td.departureDelaySecs)
        let ad = Self.formatDelay(td.arrivalDelaySecs)
        let depStr = dd.isEmpty ? dep : "\(dep) \(dd)"
        let arrStr = ad.isEmpty ? arr : "\(arr) \(ad)"
        menu.addItem(disabled("Dep: \(depStr)   Arr: \(arrStr)"))

        if let dp = td.departurePlatform, let ap = td.arrivalPlatform {
            menu.addItem(disabled("Platform: \(dp) → \(ap)"))
        }
    }

    private func addStopovers(_ stopovers: [StopoverInfo], to menu: NSMenu) {
        for sv in stopovers {
            let timeStr = sv.scheduledArrival
                .map { Self.formatHHMM($0, delaySecs: sv.arrivalDelaySecs) } ?? ""
            let prefix = sv.isNext ? "> " : "  "
            let item = NSMenuItem(title: "\(prefix)\(sv.name)  \(timeStr)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            if sv.passed {
                item.attributedTitle = NSAttributedString(
                    string: "\(prefix)\(sv.name)  \(timeStr)",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            menu.addItem(item)
        }
    }

    private func addTrainOptions(_ options: [TrainOption], to menu: NSMenu, currentTrain: String?) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        for opt in options {
            let dep = Self.formatHHMM(opt.scheduledDeparture, delaySecs: opt.departureDelaySecs)
            let arr = f.string(from: opt.scheduledArrival)
            let item = NSMenuItem(
                title: "\(opt.name)  \(dep) → \(arr)",
                action: #selector(selectTrain(_:)),
                keyEquivalent: ""
            )
            item.representedObject = opt.name
            item.target = self
            if opt.name == currentTrain { item.state = .on }
            menu.addItem(item)
        }
        if options.isEmpty {
            menu.addItem(disabled("No trains found — tap Refresh"))
        }
    }

    // MARK: - Menu helpers

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func selectTrain(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var config = AppConfigStore.shared.load()
        config.trainNumber = name
        AppConfigStore.shared.save(config)
        Task { await refresh() }
    }

    @objc private func openPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController()
            prefsController?.onClose = { [weak self] in
                self?.prefsController = nil
                Task { await self?.refresh() }
            }
        }
        prefsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func manualRefresh() {
        Task { await refresh() }
    }
}
```

- [ ] **Step 4: Run all tests**

```bash
swift test 2>&1 | tail -10
```
Expected: all test suites pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TrainTracker/StatusBarController.swift Tests/TrainTrackerTests/StatusBarControllerTests.swift
git commit -m "feat: add status bar controller with menu building and title formatting"
```

---

## Task 7: Preferences Panel

**Files:**
- Create: `Sources/TrainTracker/PreferencesWindowController.swift`

No unit tests for this task — it is programmatic AppKit UI that is best verified by running the app.

- [ ] **Step 1: Write PreferencesWindowController.swift**

```swift
// Sources/TrainTracker/PreferencesWindowController.swift
import AppKit

final class PreferencesWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private var fromField: NSTextField!
    private var toField: NSTextField!
    private var resultsTable: NSTableView!
    private var resultsScrollView: NSScrollView!
    private var savedRoutesTable: NSTableView!

    private var activeField: ActiveField = .none
    private var searchResults: [APILocation] = []
    private var savedRoutes: [SavedRoute] = []
    private var pendingFrom: Station?
    private var pendingTo: Station?
    private var searchTimer: Timer?
    private let client = OeBBClient()

    private enum ActiveField { case from, to, none }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Train Tracker"
        panel.isReleasedWhenClosed = false
        panel.center()
        self.init(window: panel)
        loadCurrentConfig()
        setupUI()
    }

    private func loadCurrentConfig() {
        let config = AppConfigStore.shared.load()
        pendingFrom = config.fromStation
        pendingTo = config.toStation
        savedRoutes = config.savedRoutes
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // From row
        let fromLabel = makeLabel("From:")
        fromLabel.frame = NSRect(x: 16, y: 272, width: 50, height: 20)
        cv.addSubview(fromLabel)

        fromField = makeTextField(placeholder: "Search for station…")
        fromField.frame = NSRect(x: 70, y: 268, width: 314, height: 24)
        fromField.stringValue = pendingFrom?.name ?? ""
        fromField.delegate = self
        cv.addSubview(fromField)

        // To row
        let toLabel = makeLabel("To:")
        toLabel.frame = NSRect(x: 16, y: 240, width: 50, height: 20)
        cv.addSubview(toLabel)

        toField = makeTextField(placeholder: "Search for station…")
        toField.frame = NSRect(x: 70, y: 236, width: 314, height: 24)
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        cv.addSubview(toField)

        // Search results table (hidden until there are results)
        resultsScrollView = NSScrollView(frame: NSRect(x: 70, y: 152, width: 314, height: 76))
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .bezelBorder
        resultsTable = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Station"
        resultsTable.addTableColumn(col)
        resultsTable.headerView = nil
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.action = #selector(resultRowClicked)
        resultsTable.target = self
        resultsScrollView.documentView = resultsTable
        resultsScrollView.isHidden = true
        cv.addSubview(resultsScrollView)

        // Saved routes label
        let routesLabel = makeLabel("Saved routes:")
        routesLabel.frame = NSRect(x: 16, y: 128, width: 120, height: 20)
        cv.addSubview(routesLabel)

        // Saved routes table
        let savedScrollView = NSScrollView(frame: NSRect(x: 16, y: 44, width: 368, height: 76))
        savedScrollView.hasVerticalScroller = true
        savedScrollView.borderType = .bezelBorder
        savedRoutesTable = NSTableView()
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        nameCol.title = "Route"
        nameCol.width = 260
        let loadCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("load"))
        loadCol.title = ""
        loadCol.width = 60
        savedRoutesTable.addTableColumn(nameCol)
        savedRoutesTable.addTableColumn(loadCol)
        savedRoutesTable.headerView = nil
        savedRoutesTable.dataSource = self
        savedRoutesTable.delegate = self
        savedRoutesTable.action = #selector(savedRouteRowClicked)
        savedRoutesTable.target = self
        savedScrollView.documentView = savedRoutesTable
        cv.addSubview(savedScrollView)

        // Save & Close button
        let saveBtn = NSButton(title: "Save & Close", target: self, action: #selector(saveAndClose))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 284, y: 8, width: 100, height: 28)
        cv.addSubview(saveBtn)
    }

    // MARK: - Debounced search

    private func scheduleSearch(query: String) {
        searchTimer?.invalidate()
        guard !query.isEmpty else {
            searchResults = []
            resultsTable.reloadData()
            resultsScrollView.isHidden = true
            return
        }
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { [weak self] in await self?.performSearch(query: query) }
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        guard let results = try? await client.searchStations(query: query) else { return }
        searchResults = results.filter { $0.type == "stop" || $0.type == nil }
        resultsTable.reloadData()
        resultsScrollView.isHidden = searchResults.isEmpty
    }

    // MARK: - Actions

    @objc private func resultRowClicked() {
        let row = resultsTable.clickedRow
        guard row >= 0, row < searchResults.count else { return }
        let location = searchResults[row]
        let station = Station(name: location.name, id: location.id)
        switch activeField {
        case .from:
            pendingFrom = station
            fromField.stringValue = station.name
        case .to:
            pendingTo = station
            toField.stringValue = station.name
        case .none:
            break
        }
        searchResults = []
        resultsTable.reloadData()
        resultsScrollView.isHidden = true
        activeField = .none
    }

    @objc private func savedRouteRowClicked() {
        let row = savedRoutesTable.clickedRow
        guard row >= 0, row < savedRoutes.count else { return }
        let route = savedRoutes[row]
        pendingFrom = route.from
        pendingTo = route.to
        fromField.stringValue = route.from.name
        toField.stringValue = route.to.name
        searchResults = []
        resultsTable.reloadData()
        resultsScrollView.isHidden = true
    }

    @objc private func saveAndClose() {
        var config = AppConfigStore.shared.load()
        // Check for station change BEFORE overwriting the stored values
        let stationsChanged = config.fromStation != pendingFrom || config.toStation != pendingTo
        config.fromStation = pendingFrom
        config.toStation = pendingTo
        if let f = pendingFrom, let t = pendingTo {
            let route = SavedRoute(from: f, to: t)
            if !config.savedRoutes.contains(route) {
                config.savedRoutes.append(route)
            }
        }
        if stationsChanged { config.trainNumber = nil }
        AppConfigStore.shared.save(config)
        close()
    }

    override func close() {
        super.close()
        onClose?()
    }

    // MARK: - UI helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13)
        return f
    }

    private func makeTextField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.font = NSFont.systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        return f
    }
}

// MARK: - NSTextFieldDelegate

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fromField { activeField = .from }
        else if field === toField { activeField = .to }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        scheduleSearch(query: field.stringValue)
    }
}

// MARK: - NSTableViewDataSource + NSTableViewDelegate

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === resultsTable ? searchResults.count : savedRoutes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.font = NSFont.systemFont(ofSize: 13)
        if tableView === resultsTable {
            cell.stringValue = searchResults[row].name
        } else {
            let id = tableColumn?.identifier.rawValue
            cell.stringValue = id == "route" ? savedRoutes[row].displayName : "Load"
            if id == "load" { cell.textColor = .linkColor }
        }
        return cell
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/TrainTracker/PreferencesWindowController.swift
git commit -m "feat: add programmatic preferences panel with live station search"
```

---

## Task 8: Integration — Wire Up and Smoke Test

**Files:**
- No new files. Verify the whole app runs end-to-end.

- [ ] **Step 1: Run the full test suite**

```bash
swift test 2>&1 | grep -E "(passed|failed|error)"
```
Expected: all test suites show `passed`, zero failures.

- [ ] **Step 2: Build a release binary**

```bash
swift build -c release 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Launch the app and verify the menu bar**

```bash
.build/release/TrainTracker &
```

Expected behaviour:
- No dock icon appears
- Menu bar item shows `Train`
- Clicking it shows "Open Preferences to get started"
- "Preferences…" opens the panel

- [ ] **Step 4: Configure a route in Preferences**

1. Open Preferences from the menu
2. Click the From field, type "Linz" → wait 300ms → results appear
3. Click "Linz/Donau Hbf" in the results
4. Click the To field, type "Salzburg" → wait → results appear
5. Click "Salzburg Hbf"
6. Click "Save & Close"

Expected: menu bar item still shows "Train" (no train number selected yet).

- [ ] **Step 5: Pick your train**

Click the menu bar item — the menu should show a list of trains on the Linz → Salzburg route. Click "WB 912" (or whichever is departing closest to now).

Expected: menu bar title updates to e.g. `WB 912  arr 14:08` or `WB 912  in 12m`.

- [ ] **Step 6: Verify stopovers**

Click the menu bar item while a train is being tracked. Intermediate stops should appear with passed stops greyed out and the next stop prefixed with `>`.

- [ ] **Step 7: Verify Switch Train submenu**

With a train selected, open the menu. "Switch Train…" should show all trains on the route. The current train should have a checkmark. Click a different train to switch.

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "feat: complete TrainTracker Swift menu bar app"
```

---

## Running the App on Login (optional)

To launch automatically at login, create a launchd plist:

```bash
BINARY=$(pwd)/.build/release/TrainTracker
cat > ~/Library/LaunchAgents/com.traintracker.app.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.traintracker.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.traintracker.app.plist
```
