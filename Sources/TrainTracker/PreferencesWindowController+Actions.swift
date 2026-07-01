// Sources/TrainTracker/PreferencesWindowController+Actions.swift
import AppKit
import UniformTypeIdentifiers

// MARK: - Actions

extension PreferencesWindowController {
    @objc func resultRowClicked() {
        let row = resultsTable.clickedRow
        guard row >= 0, row < searchResults.count else { return }
        let location = searchResults[row]
        let station = Station(name: location.name, id: location.id)
        switch activeField {
        case .from:
            pendingFrom = station
            fromField.stringValue = station.name
        case .destination:
            pendingTo = station
            toField.stringValue = station.name
        case .none:
            break
        }
        searchResults = []
        resultsTable.reloadData()
        resultsScrollView.isHidden = true
        activeField = .none
    }

    @objc func savedRouteRowClicked() {
        let row = savedRoutesTable.clickedRow
        guard row >= 0, row < savedRoutes.count else { return }
        let route = savedRoutes[row]
        pendingFrom = route.from
        pendingTo = route.toStation
        fromField.stringValue = route.from.name
        toField.stringValue = route.toStation.name
        searchResults = []
        resultsTable.reloadData()
        resultsScrollView.isHidden = true
        activeField = .none
    }

    @objc func deleteSelectedRoute() {
        let row = savedRoutesTable.selectedRow
        guard row >= 0, row < savedRoutes.count else { return }
        savedRoutes.remove(at: row)
        savedRoutesTable.reloadData()
        deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
    }

    @objc func notifCheckboxChanged(_ sender: NSButton) {
        departureReminderField.isEnabled = departureReminderCheckbox.state == .on
        delayAlertField.isEnabled = delayAlertCheckbox.state == .on
    }

    @objc func saveAndClose() {
        var config = AppConfigStore.shared.load()
        let stationsChanged = config.fromStation != pendingFrom || config.toStation != pendingTo
        config.fromStation = pendingFrom
        config.toStation = pendingTo
        var routes = savedRoutes
        if let fromStation = pendingFrom, let toStation = pendingTo {
            let route = SavedRoute(from: fromStation, toStation: toStation)
            if !routes.contains(route) {
                routes.append(route)
            }
        }
        config.savedRoutes = routes
        if stationsChanged { config.trainNumber = nil }
        config.notifications = NotificationSettings(
            departureReminderEnabled: departureReminderCheckbox.state == .on,
            departureReminderMinutes: max(1, departureReminderField.integerValue),
            delayAlertEnabled: delayAlertCheckbox.state == .on,
            delayAlertThresholdMinutes: max(1, delayAlertField.integerValue),
            platformChangeEnabled: platformChangeCheckbox.state == .on
        )
        AppConfigStore.shared.save(config)
        close()
    }

    @objc func launchAtLoginChanged(_ sender: NSButton) {
        let wantsEnabled = sender.state == .on
        guard loginItemController.setEnabled(wantsEnabled) else {
            sender.state = wantsEnabled ? .off : .on
            showAlert(
                title: "Couldn't update login item",
                message: "macOS declined to \(wantsEnabled ? "register" : "unregister") TrainTracker as a login item."
            )
            return
        }
    }

    @objc func exportConfig() {
        let config = AppConfigStore.shared.load()
        guard let data = try? ConfigTransfer.exportData(config) else {
            showAlert(title: "Export failed", message: "Couldn't encode the current configuration.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "traintracker-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            showAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    @objc func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let config = try ConfigTransfer.importConfig(from: data)
            AppConfigStore.shared.save(config)
            loadCurrentConfig()
            refreshFieldsFromLoadedConfig()
        } catch {
            showAlert(title: "Import failed", message: "Couldn't read that file as a valid TrainTracker config.")
        }
    }

    private func refreshFieldsFromLoadedConfig() {
        fromField.stringValue = pendingFrom?.name ?? ""
        toField.stringValue = pendingTo?.name ?? ""
        savedRoutesTable.reloadData()
        departureReminderCheckbox.state = pendingNotifications.departureReminderEnabled ? .on : .off
        departureReminderField.integerValue = pendingNotifications.departureReminderMinutes
        departureReminderField.isEnabled = pendingNotifications.departureReminderEnabled
        delayAlertCheckbox.state = pendingNotifications.delayAlertEnabled ? .on : .off
        delayAlertField.integerValue = pendingNotifications.delayAlertThresholdMinutes
        delayAlertField.isEnabled = pendingNotifications.delayAlertEnabled
        platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
