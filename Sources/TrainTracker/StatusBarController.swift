// Sources/TrainTracker/StatusBarController.swift
import AppKit
import Network

protocol TrainFetching {
    func fetch(config: AppConfig) async -> TrainStatus
}

extension TrainFetcher: TrainFetching {}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    let menu = NSMenu()
    private var refreshTimer: Timer?
    private var titleTimer: Timer?
    let configStore: AppConfigStore
    private let fetcher: any TrainFetching
    private var consecutiveErrors = 0
    private var lastGoodStatus: TrainStatus = .noConfig   // shown during transient errors
    var displayStatus: TrainStatus = .noConfig
    var lastUpdated: Date?
    var prefsController: PreferencesWindowController?
    private let notificationManager: NotificationManager
    private var isRefreshing = false
    private var refreshRequestedWhileBusy = false
    private var lastRouteKey: String?
    private let pathMonitor = NWPathMonitor()
    private var wasOnline = true

    init(
        configStore: AppConfigStore = .shared,
        fetcher: any TrainFetching = TrainFetcher(),
        notificationManager: NotificationManager? = nil,
        autostart: Bool = true
    ) {
        self.configStore = configStore
        self.fetcher = fetcher
        self.notificationManager = notificationManager ?? NotificationManager()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "Train"
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        guard autostart else { return }
        startTitleTimer()
        observeWakeAndNetwork()
        Task { await refresh() }
    }

    // MARK: - Wake / network

    private func observeWakeAndNetwork() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                // Refresh only on offline → online, since the scheduled refresh covers steady state
                if online && !self.wasOnline { await self.refresh() }
                self.wasOnline = online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "traintracker.network-path"))
    }

    // MARK: - Timers

    /// Seconds until the next fetch, or nil when polling should pause (nothing to track, or already arrived).
    nonisolated static func refreshInterval(for status: TrainStatus, now: Date = Date()) -> TimeInterval? {
        switch status {
        case .noConfig:
            return nil
        case .pickTrain:
            return 120
        case .error:
            return 60
        case .tracking(let trainData, _):
            let rtArr = trainData.scheduledArrival.addingTimeInterval(TimeInterval(trainData.arrivalDelaySecs))
            if rtArr <= now { return nil }
            if trainData.isEnRoute { return 30 }
            let rtDep = trainData.scheduledDeparture.addingTimeInterval(TimeInterval(trainData.departureDelaySecs))
            return rtDep.timeIntervalSince(now) > 30 * 60 ? 120 : 30
        }
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let interval = Self.refreshInterval(for: displayStatus) else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = interval / 10   // lets the system coalesce wakeups
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Re-renders the title between fetches so countdowns don't lag by a whole refresh interval.
    private func startTitleTimer() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    var titleForTesting: String { statusItem.button?.title ?? "" }

    private func updateTitle() {
        let title = Self.titleString(for: displayStatus, consecutiveErrors: consecutiveErrors)
        statusItem.button?.title = title
        if case .tracking = displayStatus {
            configStore.setStatusLine(title)
        } else {
            configStore.setStatusLine(nil)
        }
    }

    // MARK: - Refresh

    /// Serialized: a call during an in-flight refresh queues exactly one re-run with the latest config.
    func refresh() async {
        if isRefreshing {
            refreshRequestedWhileBusy = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshRequestedWhileBusy = false
            await performRefresh()
        } while refreshRequestedWhileBusy
    }

    /// Drops stale state from a previous route/train so it can't flash after switching.
    private func resetStateIfRouteChanged(_ config: AppConfig) {
        let routeKey = [config.fromStation?.id, config.viaStation?.id, config.toStation?.id,
                        config.trainNumber, config.secondLegTrainNumber].map { $0 ?? "" }.joined(separator: "|")
        guard routeKey != lastRouteKey else { return }
        lastRouteKey = routeKey
        consecutiveErrors = 0
        lastGoodStatus = .noConfig
    }

    private func performRefresh() async {
        let config = configStore.load()

        resetStateIfRouteChanged(config)

        let status = await fetcher.fetch(config: config)

        if case .error = status {
            consecutiveErrors += 1
        } else {
            consecutiveErrors = 0
            lastGoodStatus = status
        }

        // Show last good data for transient errors; show error UI after 2 consecutive failures
        displayStatus = consecutiveErrors >= 2 ? status : lastGoodStatus
        lastUpdated = Date()
        updateTitle()
        rebuildMenu()
        scheduleNextRefresh()

        if case .tracking(let trainData, _) = displayStatus {
            notificationManager.process(trainData, settings: config.notifications)
        }
    }

    // MARK: - Title string (static for testability)

    private nonisolated static let trainNoSuffix = #/\s*\(Train-No\.[^)]*\)/#

    nonisolated static func titleString(for status: TrainStatus, consecutiveErrors: Int, now: Date = Date()) -> String {
        switch status {
        case .noConfig, .pickTrain:
            return "🚂"
        case .error:
            return consecutiveErrors >= 2 ? "🚂 (!)" : "🚂"
        case .tracking(let trainData, _):
            let shortName = trainData.trainName.replacing(trainNoSuffix, with: "")
            let emoji = trainTypeEmoji(trainData.trainName)
            let rtArr = trainData.scheduledArrival.addingTimeInterval(TimeInterval(trainData.arrivalDelaySecs))
            let rtDep = trainData.scheduledDeparture.addingTimeInterval(TimeInterval(trainData.departureDelaySecs))

            if rtArr <= now {
                return "\(emoji) \(shortName) Arrived"
            } else if trainData.isEnRoute {
                let minsLeft = minutesRoundedUp(rtArr.timeIntervalSince(now))
                let delay = formatDelay(trainData.arrivalDelaySecs)
                return delay.isEmpty
                    ? "\(emoji) \(shortName) \(minsLeft)m"
                    : "\(emoji) \(shortName) \(minsLeft)m \(delay)"
            } else {
                let mins = minutesRoundedUp(rtDep.timeIntervalSince(now))
                return "\(emoji) \(shortName) in \(mins)m"
            }
        }
    }

    /// Rounds up so a countdown never reads "0m" for the whole final minute.
    private nonisolated static func minutesRoundedUp(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds / 60).rounded(.up)))
    }

    // MARK: - Train type emoji

    nonisolated static func trainTypeEmoji(_ name: String) -> String {
        let upper = name.uppercased()
        if upper.hasPrefix("RJX") { return "⚡" }
        if upper.hasPrefix("RJ") { return "🚄" }
        if upper.hasPrefix("WB") { return "🟦" }
        if upper.hasPrefix("ICE") || upper.hasPrefix("IC") || upper.hasPrefix("EC") { return "🚆" }
        if upper.hasPrefix("REX") { return "🚂" }
        if upper.hasPrefix("EN") || upper.hasPrefix("NJ") { return "🌙" }
        if upper.lowercased().hasPrefix("bus") { return "🚌" }
        if upper.hasPrefix("S"), let second = upper.dropFirst().first, second.isNumber { return "🚇" }
        return "🚊"
    }

    // MARK: - Formatting helpers

    private nonisolated static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    nonisolated static func formatHHMM(_ date: Date, delaySecs: Int) -> String {
        let adjusted = date.addingTimeInterval(TimeInterval(delaySecs))
        return Self.timeFormatter.string(from: adjusted)
    }

    nonisolated static func formatDelay(_ secs: Int) -> String {
        guard secs != 0 else { return "" }
        let mins = (abs(secs) + 59) / 60
        return secs > 0 ? "+\(mins)m" : "-\(mins)m"
    }
}
