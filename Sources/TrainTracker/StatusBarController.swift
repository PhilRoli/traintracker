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
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        statusItem.button?.title = Self.titleString(for: displayStatus, consecutiveErrors: consecutiveErrors)
        statusItem.menu = buildMenu(for: displayStatus)

        if case .tracking(let td, _) = displayStatus {
            notificationManager.process(td, settings: config.notifications)
        }
    }

    // MARK: - Title string (static for testability)

    nonisolated static func titleString(for status: TrainStatus, consecutiveErrors: Int, now: Date = Date()) -> String {
        switch status {
        case .noConfig, .pickTrain:
            return "🚂"
        case .error:
            return consecutiveErrors >= 2 ? "🚂 (!)" : "🚂"
        case .tracking(let td, _):
            let shortName = td.trainName.replacing(#/\s*\(Train-No\.[^)]*\)/#, with: "")
            let emoji = trainTypeEmoji(td.trainName)
            let rtArr = td.scheduledArrival.addingTimeInterval(TimeInterval(td.arrivalDelaySecs))
            let rtDep = td.scheduledDeparture.addingTimeInterval(TimeInterval(td.departureDelaySecs))

            if rtArr <= now {
                return "\(emoji) \(shortName) Arrived"
            } else if td.isEnRoute {
                let minsLeft = max(0, Int(rtArr.timeIntervalSince(now) / 60))
                let delay = formatDelay(td.arrivalDelaySecs)
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
        let u = name.uppercased()
        if u.hasPrefix("RJX") { return "⚡" }
        if u.hasPrefix("RJ")  { return "🚄" }
        if u.hasPrefix("WB")  { return "🟦" }
        if u.hasPrefix("ICE") || u.hasPrefix("IC") || u.hasPrefix("EC") { return "🚆" }
        if u.hasPrefix("REX") { return "🚂" }
        if u.hasPrefix("EN")  || u.hasPrefix("NJ") { return "🌙" }
        if u.lowercased().hasPrefix("bus") { return "🚌" }
        if u.hasPrefix("S"), let second = u.dropFirst().first, second.isNumber { return "🚇" }
        return "🚊"
    }

    // MARK: - Formatting helpers

    private nonisolated static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    nonisolated static func formatHHMM(_ date: Date, delaySecs: Int) -> String {
        let rt = date.addingTimeInterval(TimeInterval(delaySecs))
        return Self.timeFormatter.string(from: rt)
    }

    nonisolated static func formatDelay(_ secs: Int) -> String {
        guard secs != 0 else { return "" }
        let mins = (abs(secs) + 59) / 60
        return secs > 0 ? "+\(mins)m" : "-\(mins)m"
    }

    // MARK: - Menu building

    private func buildMenu(for status: TrainStatus) -> NSMenu {
        let menu = NSMenu()

        switch status {
        case .noConfig:
            menu.addItem(disabled("Open Preferences to get started"))

        case .pickTrain(let options):
            menu.addItem(disabled("Pick your train:"))
            menu.addItem(.separator())
            addTrainOptions(options, to: menu, currentTrain: nil)

        case .tracking(let td, let options):
            addTrackingHeader(td, to: menu)
            if !td.stopovers.isEmpty {
                menu.addItem(.separator())
                addStopovers(td.stopovers, to: menu)
            }
            menu.addItem(.separator())
            let switchItem = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
            let switchSub = NSMenu()
            addTrainOptions(options, to: switchSub, currentTrain: td.trainName)
            switchItem.submenu = switchSub
            menu.addItem(switchItem)

        case .error(let msg):
            menu.addItem(disabled(msg))
        }

        menu.addItem(.separator())
        menu.addItem(action("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(action("Refresh", #selector(manualRefresh), key: "r"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func addTrackingHeader(_ td: TrainData, to menu: NSMenu) {
        let emoji = Self.trainTypeEmoji(td.trainName)
        menu.addItem(disabled("\(emoji) \(td.trainName) \(td.fromName) → \(td.toName)"))

        let dep = Self.formatHHMM(td.scheduledDeparture, delaySecs: td.departureDelaySecs)
        let arr = Self.formatHHMM(td.scheduledArrival, delaySecs: td.arrivalDelaySecs)
        let dd = Self.formatDelay(td.departureDelaySecs)
        let ad = Self.formatDelay(td.arrivalDelaySecs)
        let depStr = dd.isEmpty ? dep : "\(dep) \(dd)"
        let arrStr = ad.isEmpty ? arr : "\(arr) \(ad)"
        menu.addItem(disabled("Dep: \(depStr) Arr: \(arrStr)"))

        if let dp = td.departurePlatform, let ap = td.arrivalPlatform {
            menu.addItem(disabled("Platform: \(dp) → \(ap)"))
        }
    }

    private func addStopovers(_ stopovers: [StopoverInfo], to menu: NSMenu) {
        for sv in stopovers {
            let timeStr = sv.scheduledArrival
                .map { Self.formatHHMM($0, delaySecs: sv.arrivalDelaySecs) } ?? ""
            let icon = sv.passed ? "✓" : (sv.isNext ? "📍" : "○")
            let delay = Self.formatDelay(sv.arrivalDelaySecs)
            let label = delay.isEmpty
                ? "\(icon) \(sv.name) (\(timeStr))"
                : "\(icon) \(sv.name) (\(timeStr) \(delay))"
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if sv.passed {
                item.attributedTitle = NSAttributedString(
                    string: label,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            menu.addItem(item)
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

    // MARK: - Actions

    @objc private func selectTrain(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var config = AppConfigStore.shared.load()
        config.trainNumber = name
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
