// Tests/TrainTrackerTests/TrainFetcherViaTests.swift
// Two-leg (via) journey tests — split out of TrainFetcherTests.swift to satisfy
// swiftlint's file_length limit (see commit 1d90e16 for precedent).
import XCTest
@testable import TrainTracker

final class TrainFetcherViaTests: XCTestCase {
    let fetcher = TrainFetcher(client: OeBBClient())

    // MARK: - Two-leg (via) journeys

    func test_findTrain_twoLeg_activeLegIsLeg0BeforeTransfer() {
        let now = Date()
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(-600)), arr: iso8601(now.addingTimeInterval(600))
            ),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(900)), arr: iso8601(now.addingTimeInterval(2400))
            )
        )

        let result = fetcher.findTrain(named: "RJX 60", secondLegTrainNumber: "REX 1234", in: [journey], now: now)
        XCTAssertEqual(result?.trainName, "RJX 60")
        XCTAssertEqual(result?.toName, "Wien Meidling")
        XCTAssertEqual(result?.nextLeg?.trainName, "REX 1234")
        XCTAssertEqual(result?.nextLeg?.toName, "Wiener Neustadt Hbf")
    }

    func test_findTrain_twoLeg_activeLegIsLeg1AfterTransfer() {
        let now = Date()
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(-2400)), arr: iso8601(now.addingTimeInterval(-900))
            ),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(-600)), arr: iso8601(now.addingTimeInterval(900))
            )
        )

        let result = fetcher.findTrain(named: "RJX 60", secondLegTrainNumber: "REX 1234", in: [journey], now: now)
        XCTAssertEqual(result?.trainName, "REX 1234")
        XCTAssertEqual(result?.fromName, "Wien Meidling")
        XCTAssertEqual(result?.toName, "Wiener Neustadt Hbf")
        XCTAssertNil(result?.nextLeg)
    }

    func test_findTrain_twoLeg_requiresSecondLegNameMatch() {
        let now = Date()
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(-600)), arr: iso8601(now.addingTimeInterval(600))
            ),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(900)), arr: iso8601(now.addingTimeInterval(2400))
            )
        )

        let result = fetcher.findTrain(named: "RJX 60", secondLegTrainNumber: "REX 9999", in: [journey], now: now)
        XCTAssertNil(result)
    }

    func test_findTrain_directTripIgnoresSecondLegParamWhenNil() {
        let now = Date()
        let journey = makeJourney(
            trainName: "WB 912",
            plannedDep: iso8601(now.addingTimeInterval(-3600)),
            plannedArr: iso8601(now.addingTimeInterval(3600))
        )
        let result = fetcher.findTrain(named: "WB 912", in: [journey], now: now)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.nextLeg)
    }

    func test_findTrain_naturalTwoLegJourneyIgnoresLeg1WhenNoViaConfigured() {
        // Journey happens to have two named legs (the backend can return this for a plain
        // from→to query even without a via param), but no via-station is configured —
        // secondLegTrainNumber is nil. leg1 must never be surfaced or switched to, even
        // once now is past leg0's real-time arrival.
        let now = Date()
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(-2400)), arr: iso8601(now.addingTimeInterval(-900))
            ),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(-600)), arr: iso8601(now.addingTimeInterval(900))
            )
        )

        let result = fetcher.findTrain(named: "RJX 60", in: [journey], now: now)
        XCTAssertEqual(result?.trainName, "RJX 60")
        XCTAssertNil(result?.nextLeg)
    }

    // MARK: - buildOptions / deduplicated

    func test_buildOptions_twoLeg_computesOverallSpanAndSecondLegName() {
        let now = Date()
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(600)), arr: iso8601(now.addingTimeInterval(1800))
            ),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(2100)), arr: iso8601(now.addingTimeInterval(3600))
            )
        )

        let options = fetcher.buildOptions(from: [journey], now: now)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].name, "RJX 60")
        XCTAssertEqual(options[0].secondLegName, "REX 1234")
        XCTAssertEqual(options[0].scheduledDeparture, TrainFetcher.parseDate(iso8601(now.addingTimeInterval(600))))
        XCTAssertEqual(options[0].scheduledArrival, TrainFetcher.parseDate(iso8601(now.addingTimeInterval(3600))))
    }

    func test_deduplicated_keepsSameLeg0DifferentLeg1() {
        let now = Date()
        let optionA = makeTwoLegJourney(
            leg0: LegSpec(name: "RJX 60", dep: iso8601(now), arr: iso8601(now.addingTimeInterval(1200))),
            leg1: LegSpec(
                name: "REX 1234", dep: iso8601(now.addingTimeInterval(1500)), arr: iso8601(now.addingTimeInterval(2400))
            )
        )
        let optionB = makeTwoLegJourney(
            leg0: LegSpec(name: "RJX 60", dep: iso8601(now), arr: iso8601(now.addingTimeInterval(1200))),
            leg1: LegSpec(
                name: "REX 5678", dep: iso8601(now.addingTimeInterval(1800)), arr: iso8601(now.addingTimeInterval(2700))
            )
        )

        let result = TrainFetcher.deduplicated([optionA, optionB])
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - fetch(config:) missed-connection message

    func test_fetch_missedConnection_returnsSpecificErrorMessage() async {
        let mock = MockOeBBClient()
        let now = Date()
        // Only leg0 ("RJX 60") is available; no journey pairs it with the stored "REX 1234"
        let journey = makeTwoLegJourney(
            leg0: LegSpec(
                name: "RJX 60", dep: iso8601(now.addingTimeInterval(-600)), arr: iso8601(now.addingTimeInterval(600))
            ),
            leg1: LegSpec(
                name: "REX 9999", dep: iso8601(now.addingTimeInterval(900)), arr: iso8601(now.addingTimeInterval(2400))
            )
        )
        await mock.setup(journeys: [journey])

        let fetcher = TrainFetcher(client: mock)
        var config = makeConfig(trainNumber: "RJX 60")
        config.viaStation = Station(name: "Wien Meidling", id: "8100523")
        config.secondLegTrainNumber = "REX 1234"

        let status = await fetcher.fetch(config: config)
        guard case .error(let message, _) = status else {
            return XCTFail("Expected .error, got \(status)")
        }
        XCTAssertTrue(message.contains("Missed connection"))
        XCTAssertTrue(message.contains("REX 1234"))
    }
}

// MARK: - Helpers

extension TrainFetcherViaTests {
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

    // Groups a leg's train name + times so makeTwoLegJourney stays under
    // swiftlint's function_parameter_count limit.
    private struct LegSpec {
        let name: String
        let dep: String
        let arr: String
    }

    private func makeTwoLegJourney(
        leg0: LegSpec,
        leg1: LegSpec,
        refreshToken: String? = nil
    ) -> APIJourney {
        let leg0Leg = APILeg(
            origin: APIStop(id: "1", name: "Linz Hbf"),
            destination: APIStop(id: "2", name: "Wien Meidling"),
            departure: leg0.dep, plannedDeparture: leg0.dep,
            arrival: leg0.arr, plannedArrival: leg0.arr,
            departureDelay: 0, arrivalDelay: 0,
            line: APILine(name: leg0.name, product: "interregional"),
            departurePlatform: nil, arrivalPlatform: nil, stopovers: nil
        )
        let leg1Leg = APILeg(
            origin: APIStop(id: "2", name: "Wien Meidling"),
            destination: APIStop(id: "3", name: "Wiener Neustadt Hbf"),
            departure: leg1.dep, plannedDeparture: leg1.dep,
            arrival: leg1.arr, plannedArrival: leg1.arr,
            departureDelay: 0, arrivalDelay: 0,
            line: APILine(name: leg1.name, product: "regional"),
            departurePlatform: nil, arrivalPlatform: nil, stopovers: nil
        )
        return APIJourney(legs: [leg0Leg, leg1Leg], refreshToken: refreshToken)
    }

    private func makeConfig(fromId: String = "1", toId: String = "2", trainNumber: String? = nil) -> AppConfig {
        var config = AppConfig()
        config.fromStation = Station(name: "From", id: fromId)
        config.toStation = Station(name: "To", id: toId)
        config.trainNumber = trainNumber
        return config
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
