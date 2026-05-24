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
    let arrivalDelaySecs: Int
}
