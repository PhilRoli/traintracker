// Sources/TrainTracker/TrainFetcher+Building.swift
import Foundation

extension TrainFetcher {
    // MARK: - Build train option list

    func buildOptions(from journeys: [APIJourney], now: Date = Date()) -> [TrainOption] {
        var seenKeys = Set<String>()
        var options: [TrainOption] = []

        for journey in journeys {
            guard let (leg0, leg1) = Self.namedLegs(in: journey),
                  let name0 = leg0.line?.name, !name0.isEmpty,
                  let schDep = Self.parseDate(leg0.plannedDeparture ?? leg0.departure)
            else { continue }

            let name1 = leg1?.line?.name
            let key = [name0, name1].compactMap { $0 }.joined(separator: " → ")
            guard seenKeys.insert(key).inserted else { continue }

            let finalLeg = leg1 ?? leg0
            guard let schArr = Self.parseDate(finalLeg.plannedArrival ?? finalLeg.arrival) else { continue }

            let rtArr = schArr.addingTimeInterval(TimeInterval(finalLeg.arrivalDelay ?? 0))
            // Grace period handles trains delayed beyond scheduled arrival with no real-time data
            guard rtArr > now.addingTimeInterval(-30 * 60) else { continue }

            options.append(TrainOption(
                name: name0,
                scheduledDeparture: schDep,
                scheduledArrival: schArr,
                departureDelaySecs: leg0.departureDelay ?? 0,
                arrivalDelaySecs: finalLeg.arrivalDelay ?? 0,
                secondLegName: name1
            ))
        }
        return options.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    // MARK: - Find specific train by exact name

    func findTrain(
        named trainNumber: String,
        secondLegTrainNumber: String? = nil,
        in journeys: [APIJourney],
        now: Date
    ) -> TrainData? {
        findTrainWithToken(named: trainNumber, secondLegTrainNumber: secondLegTrainNumber, in: journeys, now: now)?.0
    }

    // MARK: - Two-leg (via) helpers

    static func namedLegs(in journey: APIJourney) -> (leg0: APILeg, leg1: APILeg?)? {
        let named = journey.legs.filter { $0.line?.name != nil }
        guard let leg0 = named.first else { return nil }
        return (leg0, named.count > 1 ? named[1] : nil)
    }

    static func legSummary(_ leg: APILeg) -> TrainLegSummary? {
        guard let name = leg.line?.name,
              let schDep = parseDate(leg.plannedDeparture ?? leg.departure),
              let schArr = parseDate(leg.plannedArrival ?? leg.arrival)
        else { return nil }
        return TrainLegSummary(
            trainName: name,
            fromName: leg.origin.name,
            toName: leg.destination.name,
            scheduledDeparture: schDep,
            scheduledArrival: schArr,
            departureDelaySecs: leg.departureDelay ?? 0,
            arrivalDelaySecs: leg.arrivalDelay ?? 0,
            departurePlatform: leg.departurePlatform,
            arrivalPlatform: leg.arrivalPlatform
        )
    }

    func buildTrainData(leg0: APILeg, leg1: APILeg?, now: Date) -> TrainData? {
        guard let leg1 else { return buildTrainData(leg: leg0, now: now) }
        let leg0RtArrival = Self.parseDate(leg0.plannedArrival ?? leg0.arrival)
            .map { $0.addingTimeInterval(TimeInterval(leg0.arrivalDelay ?? 0)) }
        if let leg0RtArrival, now >= leg0RtArrival {
            return buildTrainData(leg: leg1, now: now)
        }
        return buildTrainData(leg: leg0, now: now, nextLeg: Self.legSummary(leg1))
    }

    // MARK: - Build TrainData from a leg

    func buildTrainData(leg: APILeg, now: Date, nextLeg: TrainLegSummary? = nil) -> TrainData? {
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
            isEnRoute: rtDep <= now,
            nextLeg: nextLeg
        )
    }

    // MARK: - Build stopover list (strips origin + destination)

    func buildStopovers(stopovers: [APIStopover], now: Date) -> [StopoverInfo] {
        guard stopovers.count > 2 else { return [] }
        let middle = Array(stopovers.dropFirst().dropLast())

        // Find the index of the first upcoming stop
        let nextIdx = middle.firstIndex { stopover in
            let stopoverTime = Self.parseDate(stopover.arrival ?? stopover.plannedArrival)
                    ?? Self.parseDate(stopover.departure ?? stopover.plannedDeparture)
            return (stopoverTime ?? .distantPast) > now
        }

        return middle.enumerated().map { (idx, stopover) in
            StopoverInfo(
                name: stopover.stop.name,
                scheduledArrival: Self.parseDate(stopover.plannedArrival ?? stopover.arrival),
                arrivalDelaySecs: stopover.arrivalDelay ?? stopover.departureDelay ?? 0,
                passed: nextIdx.map { idx < $0 } ?? true,
                isNext: nextIdx == idx
            )
        }
    }

    // MARK: - Date parsing

    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        return plainFormatter.date(from: dateString) ?? fractionalFormatter.date(from: dateString)
    }

    // ISO8601DateFormatter is thread-safe; shared instances avoid allocating one per parsed date
    private nonisolated(unsafe) static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
