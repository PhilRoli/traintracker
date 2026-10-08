// Tests/TrainTrackerTests/StatusBarControllerTests.swift
import XCTest
import UserNotifications
@testable import TrainTracker

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func test_titleForNoConfig() {
        let title = StatusBarController.titleString(for: .noConfig, consecutiveErrors: 0)
        XCTAssertEqual(title, "🚂")
    }

    func test_titleForPickTrain() {
        let title = StatusBarController.titleString(for: .pickTrain([]), consecutiveErrors: 0)
        XCTAssertEqual(title, "🚂")
    }

    func test_titleForErrorAfterTwoFailures() {
        let title = StatusBarController.titleString(for: .error("oops", []), consecutiveErrors: 2)
        XCTAssertEqual(title, "🚂 (!)")
    }

    func test_titleWaitingToDepartShowsCountdown() {
        let now = Date()
        let dep = now.addingTimeInterval(12 * 60)  // departs in 12 minutes
        let arr = now.addingTimeInterval(90 * 60)
        let trainData = makeTrainData(name: "WB 912", dep: dep, arr: arr, depDelay: 0, isEnRoute: false)

        let title = StatusBarController.titleString(for: .tracking(trainData, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 in 12m")
    }

    func test_titleEnRouteOnTime() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)  // departed 30 min ago
        let arr = now.addingTimeInterval(72 * 60)   // arrives at now + 72 min → HH:MM
        let trainData = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(trainData, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 72m")
    }

    func test_titleEnRouteDelayed() {
        let now = Date()
        let dep = now.addingTimeInterval(-30 * 60)
        let arr = now.addingTimeInterval(72 * 60)
        let trainData = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 180, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(trainData, []), consecutiveErrors: 0, now: now)
        // rtArr = arr + 180s = now + 72*60 + 180 = now + 4500s → 75 minutes
        XCTAssertEqual(title, "🟦 WB 912 75m +3m")
    }

    func test_titleArrived() {
        let now = Date()
        let dep = now.addingTimeInterval(-120 * 60)
        let arr = now.addingTimeInterval(-10 * 60)   // arrived 10 min ago
        let trainData = makeTrainData(name: "WB 912", dep: dep, arr: arr, arrDelay: 0, isEnRoute: true)

        let title = StatusBarController.titleString(for: .tracking(trainData, []), consecutiveErrors: 0, now: now)
        XCTAssertEqual(title, "🟦 WB 912 Arrived")
    }

    // MARK: - trainTypeEmoji

    func test_trainTypeEmoji() {
        XCTAssertEqual(StatusBarController.trainTypeEmoji("RJX 100"), "⚡")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("RJ 200"), "🚄")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("WB 912"), "🟦")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("ICE 50"), "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("IC 50"), "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("EC 50"), "🚆")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("REX 3"), "🚂")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("EN 414"), "🌙")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("NJ 414"), "🌙")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("S1"), "🚇")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("Bus 100"), "🚌")
        XCTAssertEqual(StatusBarController.trainTypeEmoji("R 3456"), "🚊")
    }

    // MARK: - refreshInterval

    func test_refreshInterval_noConfigPauses() {
        XCTAssertNil(StatusBarController.refreshInterval(for: .noConfig))
    }

    func test_refreshInterval_arrivedPauses() {
        let now = Date()
        let data = makeTrainData(name: "WB 912", dep: now.addingTimeInterval(-7200),
                                 arr: now.addingTimeInterval(-60), isEnRoute: true)
        XCTAssertNil(StatusBarController.refreshInterval(for: .tracking(data, []), now: now))
    }

    func test_refreshInterval_farFromDepartureIsSlow_enRouteIsFast() {
        let now = Date()
        let far = makeTrainData(name: "WB 912", dep: now.addingTimeInterval(3 * 3600),
                                arr: now.addingTimeInterval(5 * 3600))
        XCTAssertEqual(StatusBarController.refreshInterval(for: .tracking(far, []), now: now), 120)
        let enRoute = makeTrainData(name: "WB 912", dep: now.addingTimeInterval(-600),
                                    arr: now.addingTimeInterval(3600), isEnRoute: true)
        XCTAssertEqual(StatusBarController.refreshInterval(for: .tracking(enRoute, []), now: now), 30)
    }

    func test_countdownRoundsUpInFinalMinute() {
        let now = Date()
        let data = makeTrainData(name: "WB 912", dep: now.addingTimeInterval(20),
                                 arr: now.addingTimeInterval(3600))
        XCTAssertEqual(StatusBarController.titleString(for: .tracking(data, []), consecutiveErrors: 0, now: now),
                       "🟦 WB 912 in 1m")
    }

    // MARK: - refresh() state handling

    func test_refresh_showsLastGoodStatusForFirstError_thenErrorUI() async {
        let store = AppConfigStore(suiteName: "test-\(UUID().uuidString)")
        var config = AppConfig()
        config.fromStation = Station(name: "A", id: "1")
        config.toStation = Station(name: "B", id: "2")
        store.save(config)

        let now = Date()
        let good = makeTrainData(name: "WB 912", dep: now.addingTimeInterval(-600),
                                 arr: now.addingTimeInterval(3600), isEnRoute: true)
        let fetcher = ScriptedFetcher(results: [
            .tracking(good, []), .error("down", []), .error("down", [])
        ])
        let controller = StatusBarController(
            configStore: store, fetcher: fetcher, notificationManager: NotificationManager(scheduler: NoopScheduler()),
            autostart: false
        )

        await controller.refresh()
        XCTAssertEqual(controller.titleForTesting, "🟦 WB 912 60m")
        await controller.refresh()
        XCTAssertEqual(controller.titleForTesting, "🟦 WB 912 60m", "first error keeps last good data")
        await controller.refresh()
        XCTAssertEqual(controller.titleForTesting, "🚂 (!)")
    }

    func test_refresh_overlappingCallsCoalesce() async {
        let store = AppConfigStore(suiteName: "test-\(UUID().uuidString)")
        let fetcher = ScriptedFetcher(results: [.noConfig], delayNanos: 50_000_000)
        let controller = StatusBarController(
            configStore: store, fetcher: fetcher, notificationManager: NotificationManager(scheduler: NoopScheduler()),
            autostart: false
        )
        async let first: Void = controller.refresh()
        async let second: Void = controller.refresh()
        async let third: Void = controller.refresh()
        _ = await (first, second, third)
        XCTAssertEqual(fetcher.callCount, 2, "one in-flight run plus a single queued re-run")
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

private final class NoopScheduler: NotificationScheduler {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    ) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}

@MainActor
private final class ScriptedFetcher: TrainFetching {
    private var results: [TrainStatus]
    private let delayNanos: UInt64
    private(set) var callCount = 0

    init(results: [TrainStatus], delayNanos: UInt64 = 0) {
        self.results = results
        self.delayNanos = delayNanos
    }

    func fetch(config: AppConfig) async -> TrainStatus {
        callCount += 1
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}
