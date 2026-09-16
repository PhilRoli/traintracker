// Sources/TrainTracker/TrainFetcher.swift
import Foundation

final class TrainFetcher {
    private let client: any OeBBClientProtocol
    private static let offsets: [TimeInterval] = {
        let wideOffsets: [TimeInterval] = [-21600, -14400] // -6h, -4h
        let quarterHourOffsets: [TimeInterval] = stride(from: -7200, through: 900, by: 900)
            .map { TimeInterval($0) }
        return wideOffsets + quarterHourOffsets
    }()

    // Refresh-token cache — all access is sequential via StatusBarController's timer
    private var cachedRefreshToken: String?
    private var cachedConfigKey: String?
    private var cachedOptions: [TrainOption] = []

    init(client: any OeBBClientProtocol = OeBBClient()) {
        self.client = client
    }

    // MARK: - Main entry point

    func fetch(config: AppConfig) async -> TrainStatus {
        guard let from = config.fromStation, let destination = config.toStation else {
            invalidateCache()
            return .noConfig
        }

        let now = Date()
        let configKey = "\(from.id)|\(destination.id)|\(config.viaStation?.id ?? "")"
            + "|\(config.trainNumber ?? "")|\(config.secondLegTrainNumber ?? "")"
        if configKey != cachedConfigKey {
            invalidateCache()
            cachedConfigKey = configKey
        }

        if let token = cachedRefreshToken, let trainNumber = config.trainNumber {
            if let trainData = await tryRefresh(
                token: token, trainNumber: trainNumber, secondLegTrainNumber: config.secondLegTrainNumber, now: now
            ) {
                return .tracking(trainData, cachedOptions)
            }
            // tryRefresh cleared the token on failure; fall through to full fetch
        }

        let journeys = await fetchAllJourneys(
            fromId: from.id,
            toId: destination.id,
            viaId: config.viaStation?.id,
            now: now
        )
        let options = buildOptions(from: journeys)
        cachedOptions = options

        guard let trainNumber = config.trainNumber else {
            return .pickTrain(options)
        }
        guard let (trainData, token) = findTrainWithToken(
            named: trainNumber, secondLegTrainNumber: config.secondLegTrainNumber, in: journeys, now: now
        ) else {
            if let secondLegTrainNumber = config.secondLegTrainNumber,
               journeys.contains(where: { Self.namedLegs(in: $0)?.leg0.line?.name == trainNumber }) {
                return .error(
                    "Missed connection — \(secondLegTrainNumber) not found after \(trainNumber). "
                        + "Use Switch Train to reselect.",
                    options
                )
            }
            return .error("\(trainNumber) not found — use Switch Train to reselect", options)
        }
        if let newToken = token { cachedRefreshToken = newToken }
        return .tracking(trainData, options)
    }

    private func tryRefresh(
        token: String, trainNumber: String, secondLegTrainNumber: String?, now: Date
    ) async -> TrainData? {
        guard let journey = try? await client.refreshJourney(token: token) else {
            cachedRefreshToken = nil
            return nil
        }
        guard let (leg0, leg1) = Self.namedLegs(in: journey), leg0.line?.name == trainNumber else {
            cachedRefreshToken = nil
            return nil
        }
        if let secondLegTrainNumber {
            guard leg1?.line?.name == secondLegTrainNumber else {
                cachedRefreshToken = nil
                return nil
            }
        }
        guard let trainData = buildTrainData(
            leg0: leg0, leg1: secondLegTrainNumber != nil ? leg1 : nil, now: now
        ) else {
            cachedRefreshToken = nil
            return nil
        }
        cachedRefreshToken = journey.refreshToken ?? token
        return trainData
    }

    private func findTrainWithToken(
        named trainNumber: String,
        secondLegTrainNumber: String?,
        in journeys: [APIJourney],
        now: Date
    ) -> (TrainData, String?)? {
        for journey in journeys {
            guard let (leg0, leg1) = Self.namedLegs(in: journey), leg0.line?.name == trainNumber else { continue }
            if let secondLegTrainNumber {
                guard leg1?.line?.name == secondLegTrainNumber else { continue }
            }
            guard let trainData = buildTrainData(
                leg0: leg0, leg1: secondLegTrainNumber != nil ? leg1 : nil, now: now
            ) else { continue }
            return (trainData, journey.refreshToken)
        }
        return nil
    }

    private func invalidateCache() {
        cachedRefreshToken = nil
        cachedConfigKey = nil
        cachedOptions = []
    }

    // MARK: - Concurrent journey fetch

    private func fetchAllJourneys(fromId: String, toId: String, viaId: String?, now: Date) async -> [APIJourney] {
        await withTaskGroup(of: [APIJourney].self) { group in
            for offset in Self.offsets {
                let dep = now.addingTimeInterval(offset)
                group.addTask { [self] in
                    (try? await client.fetchJourneys(fromId: fromId, toId: toId, departure: dep, viaId: viaId)) ?? []
                }
            }
            var all: [APIJourney] = []
            for await batch in group { all.append(contentsOf: batch) }
            return Self.deduplicated(all)
        }
    }

    // MARK: - Deduplication (by trainName + plannedDeparture, exact; leg1 included when present)

    static func deduplicated(_ journeys: [APIJourney]) -> [APIJourney] {
        var seen = Set<String>()
        return journeys.filter { journey in
            guard let (leg0, leg1) = namedLegs(in: journey),
                  let name0 = leg0.line?.name,
                  let dep0 = leg0.plannedDeparture ?? leg0.departure
            else { return false }
            var key = "\(name0)|\(dep0)"
            if let leg1, let name1 = leg1.line?.name, let dep1 = leg1.plannedDeparture ?? leg1.departure {
                key += "|\(name1)|\(dep1)"
            }
            return seen.insert(key).inserted
        }
    }

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

    private static func namedLegs(in journey: APIJourney) -> (leg0: APILeg, leg1: APILeg?)? {
        let named = journey.legs.filter { $0.line?.name != nil }
        guard let leg0 = named.first else { return nil }
        return (leg0, named.count > 1 ? named[1] : nil)
    }

    private static func legSummary(_ leg: APILeg) -> TrainLegSummary? {
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

    private func buildTrainData(leg0: APILeg, leg1: APILeg?, now: Date) -> TrainData? {
        guard let leg1 else { return buildTrainData(leg: leg0, now: now) }
        let leg0RtArrival = Self.parseDate(leg0.plannedArrival ?? leg0.arrival)
            .map { $0.addingTimeInterval(TimeInterval(leg0.arrivalDelay ?? 0)) }
        if let leg0RtArrival, now >= leg0RtArrival {
            return buildTrainData(leg: leg1, now: now)
        }
        return buildTrainData(leg: leg0, now: now, nextLeg: Self.legSummary(leg1))
    }

    // MARK: - Build TrainData from a leg

    private func buildTrainData(leg: APILeg, now: Date, nextLeg: TrainLegSummary? = nil) -> TrainData? {
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}
