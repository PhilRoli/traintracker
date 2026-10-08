// Tests/TrainTrackerTests/TrainFetcherCachingTests.swift
import XCTest
@testable import TrainTracker

final class TrainFetcherCachingTests: XCTestCase {
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
        await mock.setup(journeys: [journey], refresh: journey)

        let fetcher = TrainFetcher(client: mock)
        let config = makeConfig(trainNumber: "WB 912")

        // First fetch: full batch
        _ = await fetcher.fetch(config: config)
        let fetchCount1 = await mock.fetchJourneysCallCount
        let refreshCount1 = await mock.refreshJourneyCallCount
        XCTAssertEqual(fetchCount1, 12)
        XCTAssertEqual(refreshCount1, 0)

        // Second fetch: refresh path used, no new full-batch calls
        _ = await fetcher.fetch(config: config)
        let fetchCount2 = await mock.fetchJourneysCallCount
        let refreshCount2 = await mock.refreshJourneyCallCount
        XCTAssertEqual(fetchCount2, 12, "Full batch should not fire again")
        XCTAssertEqual(refreshCount2, 1)
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
        await mock.setup(journeys: [journey])

        let fetcher = TrainFetcher(client: mock)
        let config = makeConfig(trainNumber: "WB 912")

        // First fetch: caches the token
        _ = await fetcher.fetch(config: config)
        let fetchCount1 = await mock.fetchJourneysCallCount
        XCTAssertEqual(fetchCount1, 12)

        // Make refresh fail
        await mock.setRefreshError(OeBBError.httpError(404))

        // Second fetch: refresh tried once, then full batch again
        _ = await fetcher.fetch(config: config)
        let refreshCount2 = await mock.refreshJourneyCallCount
        let fetchCount2 = await mock.fetchJourneysCallCount
        XCTAssertEqual(refreshCount2, 1)
        XCTAssertEqual(fetchCount2, 24, "Full batch should fire after refresh failure")
    }

    func test_transientRefreshErrorKeepsTokenAndReportsUnreachable() async {
        let mock = MockOeBBClient()
        let now = Date()
        let journey = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-600)),
            plannedArr: iso8601(now.addingTimeInterval(3600)),
            refreshToken: "tok-abc"
        )
        await mock.setup(journeys: [journey], refresh: journey)
        let fetcher = TrainFetcher(client: mock)
        let config = makeConfig(trainNumber: "WB 912")
        _ = await fetcher.fetch(config: config)

        await mock.setRefreshError(URLError(.notConnectedToInternet))
        let status = await fetcher.fetch(config: config)
        guard case .error(let message, _) = status else { return XCTFail("expected .error, got \(status)") }
        XCTAssertEqual(message, TrainFetcher.unreachableMessage)
        let fetchCount = await mock.fetchJourneysCallCount
        XCTAssertEqual(fetchCount, 12, "Transient failure must not trigger a full refetch")

        await mock.setRefreshError(nil)
        let recovered = await fetcher.fetch(config: config)
        guard case .tracking = recovered else { return XCTFail("expected .tracking, got \(recovered)") }
        let refreshCount = await mock.refreshJourneyCallCount
        XCTAssertEqual(refreshCount, 2, "Token should survive the transient failure")
    }

    func test_allJourneyRequestsFailing_reportsUnreachable() async {
        let mock = MockOeBBClient()
        await mock.setFetchError(URLError(.notConnectedToInternet))
        let status = await TrainFetcher(client: mock).fetch(config: makeConfig())
        guard case .error(let message, _) = status else { return XCTFail("expected .error, got \(status)") }
        XCTAssertEqual(message, TrainFetcher.unreachableMessage)
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
        await mock.setup(journeys: [journey], refresh: journey)

        let fetcher = TrainFetcher(client: mock)
        let config = makeConfig(trainNumber: "WB 912")

        // Prime the cache
        _ = await fetcher.fetch(config: config)
        let fetchCount1 = await mock.fetchJourneysCallCount
        XCTAssertEqual(fetchCount1, 12)

        // Switch to a different train — cache must be invalidated
        let newConfig = makeConfig(trainNumber: "RJX 100")
        _ = await fetcher.fetch(config: newConfig)
        let refreshCount2 = await mock.refreshJourneyCallCount
        let fetchCount2 = await mock.fetchJourneysCallCount
        XCTAssertEqual(refreshCount2, 0, "Should not use stale token for a different train")
        XCTAssertEqual(fetchCount2, 24, "Must do a full batch for the new config")
    }

    func test_refreshTokenUpdatedAfterSuccessfulRefresh() async {
        let mock = MockOeBBClient()
        let now = Date()
        let firstJourney = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-600)),
            plannedArr: iso8601(now.addingTimeInterval(3600)),
            refreshToken: "tok-first"
        )
        let secondJourney = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-600)),
            plannedArr: iso8601(now.addingTimeInterval(3600)),
            refreshToken: "tok-second"
        )
        await mock.setup(journeys: [firstJourney], refresh: secondJourney)

        let fetcher = TrainFetcher(client: mock)
        let config = makeConfig(trainNumber: "WB 912")

        // First fetch: caches tok-first
        _ = await fetcher.fetch(config: config)
        let fetchCount1 = await mock.fetchJourneysCallCount
        XCTAssertEqual(fetchCount1, 12)

        // Second fetch: refresh succeeds, should update to tok-second
        _ = await fetcher.fetch(config: config)
        let refreshCount2 = await mock.refreshJourneyCallCount
        XCTAssertEqual(refreshCount2, 1)

        // Third fetch: must use the new tok-second token (not the old tok-first)
        // If the token wasn't updated, this would use tok-first which the API no longer honours
        _ = await fetcher.fetch(config: config)
        let refreshCount3 = await mock.refreshJourneyCallCount
        let fetchCount3 = await mock.fetchJourneysCallCount
        XCTAssertEqual(refreshCount3, 2, "Third fetch must use the rotated token")
        XCTAssertEqual(fetchCount3, 12, "No fallback to full batch expected")
    }
    func test_fetch_passesViaIdFromConfigToClient() async {
        let mock = MockOeBBClient()
        let now = Date()
        let journey = makeJourney(
            trainName: "RJX 60",
            plannedDep: iso8601(now.addingTimeInterval(-600)),
            plannedArr: iso8601(now.addingTimeInterval(3600))
        )
        await mock.setup(journeys: [journey])
        var config = makeConfig(trainNumber: "RJX 60")
        config.viaStation = Station(name: "Wien Meidling", id: "8100523")
        _ = await TrainFetcher(client: mock).fetch(config: config)
        let lastViaId = await mock.lastViaId
        XCTAssertEqual(lastViaId, "8100523")
    }
}
