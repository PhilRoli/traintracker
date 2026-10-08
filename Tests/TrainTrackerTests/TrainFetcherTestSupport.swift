// Tests/TrainTrackerTests/TrainFetcherTestSupport.swift
import XCTest
@testable import TrainTracker

// MARK: - Helpers

extension XCTestCase {
    func makeJourney(
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

    func makeConfig(fromId: String = "1", toId: String = "2", trainNumber: String? = nil) -> AppConfig {
        var config = AppConfig()
        config.fromStation = Station(name: "From", id: fromId)
        config.toStation = Station(name: "To", id: toId)
        config.trainNumber = trainNumber
        return config
    }

    func makeStopover(name: String, arr: String? = nil, dep: String? = nil) -> APIStopover {
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

    func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - MockOeBBClient (internal — also used by TrainFetcherViaTests.swift)

actor MockOeBBClient: OeBBClientProtocol {
    private(set) var journeysToReturn: [APIJourney] = []
    private(set) var refreshToReturn: APIJourney?
    private(set) var refreshError: Error?
    private(set) var fetchError: Error?
    private(set) var fetchJourneysCallCount = 0
    private(set) var refreshJourneyCallCount = 0
    private(set) var lastViaId: String?

    func setup(journeys: [APIJourney] = [], refresh: APIJourney? = nil, error: Error? = nil) {
        self.journeysToReturn = journeys
        self.refreshToReturn = refresh
        self.refreshError = error
    }
    func setFetchError(_ error: Error?) {
        self.fetchError = error
    }
    func setRefreshError(_ error: Error?) {
        self.refreshError = error
    }
    func searchStations(query: String) async throws -> [APILocation] { [] }

    func fetchJourneys(fromId: String, toId: String, departure: Date, viaId: String?) async throws -> [APIJourney] {
        fetchJourneysCallCount += 1
        lastViaId = viaId
        if let fetchError { throw fetchError }
        return journeysToReturn
    }

    func refreshJourney(token: String) async throws -> APIJourney {
        refreshJourneyCallCount += 1
        if let error = refreshError { throw error }
        return refreshToReturn!
    }
}
