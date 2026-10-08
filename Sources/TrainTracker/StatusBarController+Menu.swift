// Sources/TrainTracker/StatusBarController+Menu.swift
import AppKit

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
    func rebuildMenu() {
        let fresh = buildMenu(for: displayStatus)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    private func makeSwitchTrainItem(
        _ options: [TrainOption], currentTrain: String?, currentSecondLeg: String?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "Switch Train…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        addTrainOptions(options, to: submenu, currentTrain: currentTrain, currentSecondLeg: currentSecondLeg)
        item.submenu = submenu
        return item
    }

    func buildMenu(for status: TrainStatus) -> NSMenu {
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
            menu.addItem(makeSwitchTrainItem(
                options, currentTrain: config.trainNumber, currentSecondLeg: config.secondLegTrainNumber
            ))
            menu.addItem(action("Deselect Train", #selector(deselectTrain), key: ""))
            menu.addItem(makeRouteSubmenu(config: config))

        case .error(let msg, let options):
            menu.addItem(disabled(msg))
            menu.addItem(.separator())
            menu.addItem(makeSwitchTrainItem(options, currentTrain: nil, currentSecondLeg: nil))
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
