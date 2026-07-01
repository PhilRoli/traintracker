// Sources/TrainTracker/TrainFetcher.swift
import Foundation

final class TrainFetcher {
    private let client: any OeBBClientProtocol
    private static let offsets: [TimeInterval] =
        [-6 * 3600, -4 * 3600] + stride(from: -120 * 60, through: 15 * 60, by: 15 * 60).map(TimeInterval.init)

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
        let configKey = "\(from.id)|\(destination.id)|\(config.trainNumber ?? "")"
        if configKey != cachedConfigKey {
            invalidateCache()
            cachedConfigKey = configKey
        }

        if let token = cachedRefreshToken, let trainNumber = config.trainNumber {
            if let trainData = await tryRefresh(token: token, trainNumber: trainNumber, now: now) {
                return .tracking(trainData, cachedOptions)
            }
            // tryRefresh cleared the token on failure; fall through to full fetch
        }

        let journeys = await fetchAllJourneys(fromId: from.id, toId: destination.id, now: now)
        let options = buildOptions(from: journeys)
        cachedOptions = options

        guard let trainNumber = config.trainNumber else {
            return .pickTrain(options)
        }
        guard let (trainData, token) = findTrainWithToken(named: trainNumber, in: journeys, now: now) else {
            return .error("\(trainNumber) not found — use Switch Train to reselect", options)
        }
        if let newToken = token { cachedRefreshToken = newToken }
        return .tracking(trainData, options)
    }

    private func tryRefresh(token: String, trainNumber: String, now: Date) async -> TrainData? {
        guard let journey = try? await client.refreshJourney(token: token) else {
            cachedRefreshToken = nil
            return nil
        }
        guard let leg = journey.legs.first(where: { $0.line?.name == trainNumber }),
              let trainData = buildTrainData(leg: leg, now: now)
        else {
            cachedRefreshToken = nil
            return nil
        }
        cachedRefreshToken = journey.refreshToken ?? token
        return trainData
    }

    private func findTrainWithToken(
        named trainNumber: String,
        in journeys: [APIJourney],
        now: Date
    ) -> (TrainData, String?)? {
        for journey in journeys {
            guard let leg = journey.legs.first(where: { $0.line?.name == trainNumber }),
                  let trainData = buildTrainData(leg: leg, now: now) else { continue }
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

    // MARK: - Build train option list

    func buildOptions(from journeys: [APIJourney], now: Date = Date()) -> [TrainOption] {
        var seenNames = Set<String>()
        var options: [TrainOption] = []

        for journey in journeys {
            guard let leg = journey.legs.first(where: { $0.line?.name != nil }),
                  let name = leg.line?.name, !name.isEmpty,
                  let schDep = Self.parseDate(leg.plannedDeparture ?? leg.departure),
                  let schArr = Self.parseDate(leg.plannedArrival ?? leg.arrival),
                  seenNames.insert(name).inserted
            else { continue }

            let rtArr = schArr.addingTimeInterval(TimeInterval(leg.arrivalDelay ?? 0))
            // Grace period handles trains delayed beyond scheduled arrival with no real-time data
            guard rtArr > now.addingTimeInterval(-30 * 60) else { continue }

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
        findTrainWithToken(named: trainNumber, in: journeys, now: now)?.0
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
