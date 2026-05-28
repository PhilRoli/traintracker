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
        let utc = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents(in: utc, from: date!)
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

    func test_buildOptions_filtersTrainArrivedLongAgo() {
        let now = Date()
        let journey = makeJourney(
            trainName: "WB 910",
            plannedDep: iso8601(now.addingTimeInterval(-4 * 3600)),
            plannedArr: iso8601(now.addingTimeInterval(-2 * 3600))
        )
        let options = fetcher.buildOptions(from: [journey], now: now)
        XCTAssertEqual(options.count, 0, "Train arrived 2 hours ago should be filtered out")
    }

    func test_buildOptions_keepsDelayedTrainWithNoRealTimeData() {
        // Scheduled arrival passed 20 min ago, but no arrivalDelay from API (e.g. Westbahn)
        // — train is still en route (delayed); grace period keeps it visible
        let now = Date()
        let journey = makeJourney(
            trainName: "WB 931",
            plannedDep: iso8601(now.addingTimeInterval(-2 * 3600)),
            plannedArr: iso8601(now.addingTimeInterval(-20 * 60))
        )
        let options = fetcher.buildOptions(from: [journey], now: now)
        XCTAssertEqual(options.count, 1, "Delayed train past scheduled arrival should still appear")
    }

    func test_buildOptions_sortedByDeparture() {
        let now = Date()
        let j1 = makeJourney(trainName: "WB 914", plannedDep: iso8601(now.addingTimeInterval(3600)),
                             plannedArr: iso8601(now.addingTimeInterval(7200)))
        let j2 = makeJourney(trainName: "WB 912", plannedDep: iso8601(now.addingTimeInterval(-3600)),
                             plannedArr: iso8601(now.addingTimeInterval(600)))

        let options = fetcher.buildOptions(from: [j1, j2], now: now)
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

    func test_findTrain_isNotEnRouteBeforeDeparture() {
        let now = Date()
        // departs in 30 minutes
        let j = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(1800)),
            plannedArr: iso8601(now.addingTimeInterval(5400))
        )

        let result = fetcher.findTrain(named: "WB 912", in: [j], now: now)
        XCTAssertEqual(result?.isEnRoute, false)
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

    private func makeConfig(fromId: String = "1", toId: String = "2", trainNumber: String? = nil) -> AppConfig {
        var config = AppConfig()
        config.fromStation = Station(name: "From", id: fromId)
        config.toStation = Station(name: "To", id: toId)
        config.trainNumber = trainNumber
        return config
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
}

// MARK: - MockOeBBClient

private actor MockOeBBClient: OeBBClientProtocol {
    private(set) var journeysToReturn: [APIJourney] = []
    private(set) var refreshToReturn: APIJourney?
    private(set) var refreshError: Error?
    private(set) var fetchJourneysCallCount = 0
    private(set) var refreshJourneyCallCount = 0

    func setup(journeys: [APIJourney] = [], refresh: APIJourney? = nil, error: Error? = nil) {
        self.journeysToReturn = journeys
        self.refreshToReturn = refresh
        self.refreshError = error
    }

    func setRefreshError(_ error: Error?) {
        self.refreshError = error
    }

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
