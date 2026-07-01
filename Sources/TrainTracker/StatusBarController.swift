// Sources/TrainTracker/StatusBarController.swift
import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private let fetcher = TrainFetcher()
    private var consecutiveErrors = 0
    private var lastGoodStatus: TrainStatus = .noConfig   // shown during transient errors
    private var prefsController: PreferencesWindowController?
    private let notificationManager = NotificationManager()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Train"
        startTimer()
        Task { await refresh() }
    }

    // MARK: - Timer

    private func startTimer() {
        let newTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    // MARK: - Refresh

    func refresh() async {
        let config = AppConfigStore.shared.load()
        let status = await fetcher.fetch(config: config)

        if case .error = status {
            consecutiveErrors += 1
        } else {
            consecutiveErrors = 0
            lastGoodStatus = status
        }

        // Show last good data for transient errors; show error UI after 2 consecutive failures
        let displayStatus: TrainStatus = consecutiveErrors >= 2 ? status : lastGoodStatus
        let title = Self.titleString(for: displayStatus, consecutiveErrors: consecutiveErrors)
        statusItem.button?.title = title
        statusItem.menu = buildMenu(for: displayStatus)
        if case .tracking = displayStatus {
            AppConfigStore.shared.setStatusLine(title)
        } else {
            AppConfigStore.shared.setStatusLine(nil)
        }

        if case .tracking(let trainData, _) = displayStatus {
            notificationManager.process(trainData, settings: config.notifications)
        }
    }

    // MARK: - Title string (static for testability)

    nonisolated static func titleString(for status: TrainStatus, consecutiveErrors: Int, now: Date = Date()) -> String {
        switch status {
        case .noConfig, .pickTrain:
            return "🚂"
        case .error:
            return consecutiveErrors >= 2 ? "🚂 (!)" : "🚂"
        case .tracking(let trainData, _):
            let shortName = trainData.trainName.replacing(#/\s*\(Train-No\.[^)]*\)/#, with: "")
            let emoji = trainTypeEmoji(trainData.trainName)
            let rtArr = trainData.scheduledArrival.addingTimeInterval(TimeInterval(trainData.arrivalDelaySecs))
            let rtDep = trainData.scheduledDeparture.addingTimeInterval(TimeInterval(trainData.departureDelaySecs))

            if rtArr <= now {
                return "\(emoji) \(shortName) Arrived"
            } else if trainData.isEnRoute {
                let minsLeft = max(0, Int(rtArr.timeIntervalSince(now) / 60))
                let delay = formatDelay(trainData.arrivalDelaySecs)
                return delay.isEmpty
                    ? "\(emoji) \(shortName) \(minsLeft)m"
                    : "\(emoji) \(shortName) \(minsLeft)m \(delay)"
            } else {
                let mins = max(0, Int(rtDep.timeIntervalSince(now) / 60))
                return "\(emoji) \(shortName) in \(mins)m"
            }
        }
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
            currentRoute = config.savedRoutes.first { $0.from == from && $0.toStation == destination }
        }
        addRouteOptions(config.savedRoutes, to: sub, currentRoute: currentRoute)
        item.submenu = sub
        return item
    }

    private func buildMenu(for status: TrainStatus) -> NSMenu {
        let config = AppConfigStore.shared.load()
        let menu = NSMenu()

        switch status {
        case .noConfig:
            menu.addItem(disabled("Open Preferences to get started"))

        case .pickTrain(let options):
            menu.addItem(disabled("Pick your train:"))
            menu.addItem(.separator())
            addTrainOptions(options, to: menu, currentTrain: nil)
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
            addTrainOptions(options, to: switchSub, currentTrain: trainData.trainName)
            switchItem.submenu = switchSub
            menu.addItem(switchItem)
            menu.addItem(action("Deselect Train", #selector(deselectTrain), key: ""))
            menu.addItem(makeRouteSubmenu(config: config))

        case .error(let msg, let options):
            menu.addItem(disabled(msg))
            menu.addItem(.separator())
            let switchItem = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
            let switchSub = NSMenu()
            addTrainOptions(options, to: switchSub, currentTrain: nil)
            switchItem.submenu = switchSub
            menu.addItem(switchItem)
            menu.addItem(makeRouteSubmenu(config: config))
        }

        menu.addItem(.separator())
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

    private func addTrainOptions(_ options: [TrainOption], to menu: NSMenu, currentTrain: String?) {
        for opt in options {
            let emoji = Self.trainTypeEmoji(opt.name)
            let dep = Self.formatHHMM(opt.scheduledDeparture, delaySecs: opt.departureDelaySecs)
            let arr = Self.formatHHMM(opt.scheduledArrival, delaySecs: opt.arrivalDelaySecs)
            let item = NSMenuItem(
                title: "\(emoji) \(opt.name) \(dep) → \(arr)",
                action: #selector(selectTrain(_:)),
                keyEquivalent: ""
            )
            item.representedObject = opt.name
            item.target = self
            if opt.name == currentTrain { item.state = .on }
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
        guard let name = sender.representedObject as? String else { return }
        var config = AppConfigStore.shared.load()
        config.trainNumber = name
        AppConfigStore.shared.save(config)
        Task { await refresh() }
    }

    @objc private func deselectTrain() {
        var config = AppConfigStore.shared.load()
        config.trainNumber = nil
        AppConfigStore.shared.save(config)
        Task { await refresh() }
    }

    @objc private func selectRoute(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? SavedRoute else { return }
        var config = AppConfigStore.shared.load()
        config.fromStation = route.from
        config.toStation = route.toStation
        config.trainNumber = nil
        AppConfigStore.shared.save(config)
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
