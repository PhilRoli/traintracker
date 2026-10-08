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
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    private var titleTimer: Timer?
    private let configStore: AppConfigStore
    private let fetcher: any TrainFetching
    private var consecutiveErrors = 0
    private var lastGoodStatus: TrainStatus = .noConfig   // shown during transient errors
    private var displayStatus: TrainStatus = .noConfig
    private var lastUpdated: Date?
    private var prefsController: PreferencesWindowController?
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

    private func performRefresh() async {
        let config = configStore.load()

        // Drop stale state from a previous route/train so it can't flash after switching
        let routeKey = [config.fromStation?.id, config.viaStation?.id, config.toStation?.id,
                        config.trainNumber, config.secondLegTrainNumber].map { $0 ?? "" }.joined(separator: "|")
        if routeKey != lastRouteKey {
            lastRouteKey = routeKey
            consecutiveErrors = 0
            lastGoodStatus = .noConfig
        }

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

// MARK: - Menu building

extension StatusBarController {
    private func makeRouteSubmenu(config: AppConfig) -> NSMenuItem {
        let item = NSMenuItem(title: "Switch Route…", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        var currentRoute: SavedRoute?
        if let from = config.fromStation, let destination = config.toStation {
            currentRoute = config.savedRoutes.first {
                $0.from == from && $0.toStation == destination && $0.viaStation == config.viaStation
            }
        }
        addRouteOptions(config.savedRoutes, to: sub, currentRoute: currentRoute)
        item.submenu = sub
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// Rebuilds the items of the single status menu in place, so an open menu is never swapped out.
    private func rebuildMenu() {
        let fresh = buildMenu(for: displayStatus)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    private func buildMenu(for status: TrainStatus) -> NSMenu {
        let config = configStore.load()
        let menu = NSMenu()

        switch status {
        case .noConfig:
            menu.addItem(disabled("Open Preferences to get started"))

        case .pickTrain(let options):
            menu.addItem(disabled("Pick your train:"))
            menu.addItem(.separator())
            addTrainOptions(options, to: menu, currentTrain: nil, currentSecondLeg: nil)
            menu.addItem(.separator())
            menu.addItem(makeRouteSubmenu(config: config))

        case .tracking(let trainData, let options):
            addTrackingHeader(trainData, to: menu)
            if !trainData.stopovers.isEmpty {
                menu.addItem(.separator())
                addStopovers(trainData.stopovers, to: menu)
            }
            menu.addItem(.separator())
            let switchItem = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
            let switchSub = NSMenu()
            addTrainOptions(
                options,
                to: switchSub,
                currentTrain: config.trainNumber,
                currentSecondLeg: config.secondLegTrainNumber
            )
            switchItem.submenu = switchSub
            menu.addItem(switchItem)
            menu.addItem(action("Deselect Train", #selector(deselectTrain), key: ""))
            menu.addItem(makeRouteSubmenu(config: config))

        case .error(let msg, let options):
            menu.addItem(disabled(msg))
            menu.addItem(.separator())
            let switchItem = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
            let switchSub = NSMenu()
            addTrainOptions(options, to: switchSub, currentTrain: nil, currentSecondLeg: nil)
            switchItem.submenu = switchSub
            menu.addItem(switchItem)
            if config.trainNumber != nil {
                menu.addItem(action("Deselect Train", #selector(deselectTrain), key: ""))
            }
            menu.addItem(makeRouteSubmenu(config: config))
        }

        menu.addItem(.separator())
        if let lastUpdated {
            menu.addItem(disabled("Updated \(Self.formatHHMM(lastUpdated, delaySecs: 0))"))
        }
        menu.addItem(action("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(action("Refresh", #selector(manualRefresh), key: "r"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func addTrackingHeader(_ trainData: TrainData, to menu: NSMenu) {
        let emoji = Self.trainTypeEmoji(trainData.trainName)
        menu.addItem(disabled("\(emoji) \(trainData.trainName) \(trainData.fromName) → \(trainData.toName)"))

        let dep = Self.formatHHMM(trainData.scheduledDeparture, delaySecs: trainData.departureDelaySecs)
        let arr = Self.formatHHMM(trainData.scheduledArrival, delaySecs: trainData.arrivalDelaySecs)
        let depDelay = Self.formatDelay(trainData.departureDelaySecs)
        let arrDelay = Self.formatDelay(trainData.arrivalDelaySecs)
        let depStr = depDelay.isEmpty ? dep : "\(dep) \(depDelay)"
        let arrStr = arrDelay.isEmpty ? arr : "\(arr) \(arrDelay)"
        menu.addItem(disabled("Dep: \(depStr) Arr: \(arrStr)"))

        if let depPlatform = trainData.departurePlatform, let arrPlatform = trainData.arrivalPlatform {
            menu.addItem(disabled("Platform: \(depPlatform) → \(arrPlatform)"))
        }

        if let nextLeg = trainData.nextLeg {
            let nextEmoji = Self.trainTypeEmoji(nextLeg.trainName)
            let nextDep = Self.formatHHMM(nextLeg.scheduledDeparture, delaySecs: nextLeg.departureDelaySecs)
            let platformStr = nextLeg.departurePlatform.map { ", platform \($0)" } ?? ""
            let nextLine = "→ then \(nextEmoji) \(nextLeg.trainName) to \(nextLeg.toName)\(platformStr) (\(nextDep))"
            menu.addItem(disabled(nextLine))
        }
    }

    private func addStopovers(_ stopovers: [StopoverInfo], to menu: NSMenu) {
        for stopover in stopovers {
            let timeStr = stopover.scheduledArrival
                .map { Self.formatHHMM($0, delaySecs: stopover.arrivalDelaySecs) } ?? ""
            let icon = stopover.passed ? "✓" : (stopover.isNext ? "📍" : "○")
            let delay = Self.formatDelay(stopover.arrivalDelaySecs)
            let label = delay.isEmpty
                ? "\(icon) \(stopover.name) (\(timeStr))"
                : "\(icon) \(stopover.name) (\(timeStr) \(delay))"
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if stopover.passed {
                item.attributedTitle = NSAttributedString(
                    string: label,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            menu.addItem(item)
        }
    }

    private func addRouteOptions(_ routes: [SavedRoute], to menu: NSMenu, currentRoute: SavedRoute?) {
        for route in routes {
            let item = NSMenuItem(
                title: route.displayName,
                action: #selector(selectRoute(_:)),
                keyEquivalent: ""
            )
            item.representedObject = route
            item.target = self
            if route == currentRoute { item.state = .on }
            menu.addItem(item)
        }
        if routes.isEmpty {
            menu.addItem(disabled("No saved routes"))
        }
    }

    private func addTrainOptions(
        _ options: [TrainOption],
        to menu: NSMenu,
        currentTrain: String?,
        currentSecondLeg: String?
    ) {
        for opt in options {
            let emoji = Self.trainTypeEmoji(opt.name)
            let dep = Self.formatHHMM(opt.scheduledDeparture, delaySecs: opt.departureDelaySecs)
            let arr = Self.formatHHMM(opt.scheduledArrival, delaySecs: opt.arrivalDelaySecs)
            let title: String
            if let secondLegName = opt.secondLegName {
                let secondEmoji = Self.trainTypeEmoji(secondLegName)
                title = "\(emoji) \(opt.name) → \(secondEmoji) \(secondLegName)  \(dep) → \(arr)"
            } else {
                title = "\(emoji) \(opt.name) \(dep) → \(arr)"
            }
            let item = NSMenuItem(title: title, action: #selector(selectTrain(_:)), keyEquivalent: "")
            item.representedObject = opt
            item.target = self
            if opt.name == currentTrain && opt.secondLegName == currentSecondLeg { item.state = .on }
            menu.addItem(item)
        }
        if options.isEmpty {
            menu.addItem(disabled("No trains found — tap Refresh"))
        }
    }

    // MARK: - Menu helpers

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }
}

// MARK: - Actions

extension StatusBarController {
    @objc private func selectTrain(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? TrainOption else { return }
        var config = configStore.load()
        config.trainNumber = option.name
        config.secondLegTrainNumber = option.secondLegName
        configStore.save(config)
        Task { await refresh() }
    }

    @objc private func deselectTrain() {
        var config = configStore.load()
        config.trainNumber = nil
        config.secondLegTrainNumber = nil
        configStore.save(config)
        Task { await refresh() }
    }

    @objc private func selectRoute(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? SavedRoute else { return }
        var config = configStore.load()
        config.fromStation = route.from
        config.viaStation = route.viaStation
        config.toStation = route.toStation
        config.trainNumber = nil
        config.secondLegTrainNumber = nil
        configStore.save(config)
        Task { await refresh() }
    }

    @objc private func openPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController()
            prefsController?.onClose = { [weak self] in
                self?.prefsController = nil
                Task { await self?.refresh() }
            }
        }
        prefsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func manualRefresh() {
        Task { await refresh() }
    }
}
