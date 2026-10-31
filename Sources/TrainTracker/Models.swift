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
    /// Upstream's verdict on whether this leg can still be boarded given the previous leg's real-time data.
    var reachable: Bool?
}

struct APIJourney: Codable {
    let legs: [APILeg]
    let refreshToken: String?
}

struct APIJourneysResponse: Codable {
    let journeys: [APIJourney]
}

struct APIJourneyResponse: Codable {
    let journey: APIJourney
}

// MARK: - Internal Display Types

enum TrainStatus {
    case noConfig
    case pickTrain([TrainOption])
    case tracking(TrainData, [TrainOption])   // second arg: available trains for Switch Train submenu
    case error(String, [TrainOption])
}

struct TrainLegSummary {
    let trainName: String
    let fromName: String
    let toName: String
    let scheduledDeparture: Date
    let scheduledArrival: Date
    let departureDelaySecs: Int
    let arrivalDelaySecs: Int
    let departurePlatform: String?
    let arrivalPlatform: String?
    var reachable: Bool?
}

/// Whether the transfer into the next leg still works, from the real-time gap and upstream's `reachable` flag.
struct ConnectionAssessment: Equatable {
    let gapSecs: Int
    let reachable: Bool?

    var isLikely: Bool { reachable != false && gapSecs >= 60 }

    var text: String {
        let minutes = gapSecs / 60
        if gapSecs < 0 {
            let missedBy = Int((-Double(gapSecs) / 60).rounded(.up))
            return "⚠️ Connection missed — next train leaves \(missedBy) min before arrival"
        }
        if isLikely { return "✅ Connection OK — \(minutes) min to change" }
        let detail = minutes == 0 ? "no time to change" : "only \(minutes) min to change"
        return "⚠️ Connection unlikely — \(detail)"
    }
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
    let nextLeg: TrainLegSummary?

    init(
        trainName: String,
        fromName: String,
        toName: String,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        departureDelaySecs: Int,
        arrivalDelaySecs: Int,
        departurePlatform: String?,
        arrivalPlatform: String?,
        stopovers: [StopoverInfo],
        isEnRoute: Bool,
        nextLeg: TrainLegSummary? = nil
    ) {
        self.trainName = trainName
        self.fromName = fromName
        self.toName = toName
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.departureDelaySecs = departureDelaySecs
        self.arrivalDelaySecs = arrivalDelaySecs
        self.departurePlatform = departurePlatform
        self.arrivalPlatform = arrivalPlatform
        self.stopovers = stopovers
        self.isEnRoute = isEnRoute
        self.nextLeg = nextLeg
    }

    /// Real-time gap between arriving on this leg and the next one leaving; nil without a next leg.
    var connection: ConnectionAssessment? {
        guard let nextLeg else { return nil }
        let arrives = scheduledArrival.addingTimeInterval(TimeInterval(arrivalDelaySecs))
        let departs = nextLeg.scheduledDeparture.addingTimeInterval(TimeInterval(nextLeg.departureDelaySecs))
        return ConnectionAssessment(gapSecs: Int(departs.timeIntervalSince(arrives)), reachable: nextLeg.reachable)
    }
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
    let secondLegName: String?

    init(
        name: String,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        departureDelaySecs: Int,
        arrivalDelaySecs: Int,
        secondLegName: String? = nil
    ) {
        self.name = name
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.departureDelaySecs = departureDelaySecs
        self.arrivalDelaySecs = arrivalDelaySecs
        self.secondLegName = secondLegName
    }
}
