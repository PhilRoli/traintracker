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
                departureDelaySecs: leg.departureDelay ?? 0,
                arrivalDelaySecs: leg.arrivalDelay ?? 0
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
