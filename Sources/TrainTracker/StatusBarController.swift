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

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Train"
        startTimer()
        Task { await refresh() }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refresh() }
        }
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
    }

    // MARK: - Title string (static for testability)

    nonisolated static func titleString(for status: TrainStatus, consecutiveErrors: Int) -> String {
        switch status {
        case .noConfig, .pickTrain:
            return "Train"
        case .error:
            return consecutiveErrors >= 2 ? "Train (!)" : "Train"
        case .tracking(let td, _):
            let now = Date()
            let rtArr = td.scheduledArrival.addingTimeInterval(TimeInterval(td.arrivalDelaySecs))
            let rtDep = td.scheduledDeparture.addingTimeInterval(TimeInterval(td.departureDelaySecs))

            if rtArr <= now {
                return "\(td.trainName)  Arrived"
            } else if td.isEnRoute {
                let timeStr = formatHHMM(td.scheduledArrival, delaySecs: td.arrivalDelaySecs)
                let delay = formatDelay(td.arrivalDelaySecs)
                return delay.isEmpty
                    ? "\(td.trainName)  arr \(timeStr)"
                    : "\(td.trainName)  arr \(timeStr) \(delay)"
            } else {
                let mins = max(0, Int(rtDep.timeIntervalSince(now) / 60))
                return "\(td.trainName)  in \(mins)m"
            }
        }
    }

    // MARK: - Formatting helpers

    nonisolated static func formatHHMM(_ date: Date, delaySecs: Int) -> String {
        let rt = date.addingTimeInterval(TimeInterval(delaySecs))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: rt)
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
        menu.addItem(disabled("\(td.trainName)  \(td.fromName) → \(td.toName)"))

        let dep = Self.formatHHMM(td.scheduledDeparture, delaySecs: td.departureDelaySecs)
        let arr = Self.formatHHMM(td.scheduledArrival, delaySecs: td.arrivalDelaySecs)
        let dd = Self.formatDelay(td.departureDelaySecs)
        let ad = Self.formatDelay(td.arrivalDelaySecs)
        let depStr = dd.isEmpty ? dep : "\(dep) \(dd)"
        let arrStr = ad.isEmpty ? arr : "\(arr) \(ad)"
        menu.addItem(disabled("Dep: \(depStr)   Arr: \(arrStr)"))

        if let dp = td.departurePlatform, let ap = td.arrivalPlatform {
            menu.addItem(disabled("Platform: \(dp) → \(ap)"))
        }
    }

    private func addStopovers(_ stopovers: [StopoverInfo], to menu: NSMenu) {
        for sv in stopovers {
            let timeStr = sv.scheduledArrival
                .map { Self.formatHHMM($0, delaySecs: sv.arrivalDelaySecs) } ?? ""
            let prefix = sv.isNext ? "> " : "  "
            let item = NSMenuItem(title: "\(prefix)\(sv.name)  \(timeStr)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            if sv.passed {
                item.attributedTitle = NSAttributedString(
                    string: "\(prefix)\(sv.name)  \(timeStr)",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            menu.addItem(item)
        }
    }

    private func addTrainOptions(_ options: [TrainOption], to menu: NSMenu, currentTrain: String?) {
        for opt in options {
            let dep = Self.formatHHMM(opt.scheduledDeparture, delaySecs: opt.departureDelaySecs)
            let arr = Self.formatHHMM(opt.scheduledArrival, delaySecs: opt.arrivalDelaySecs)
            let item = NSMenuItem(
                title: "\(opt.name)  \(dep) → \(arr)",
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
