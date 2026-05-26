// Sources/TrainTracker/PreferencesWindowController.swift
import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private var fromField: NSTextField!
    private var toField: NSTextField!
    private var resultsTable: NSTableView!
    private var resultsScrollView: NSScrollView!
    private var savedRoutesTable: NSTableView!

    private var activeField: ActiveField = .none
    private var searchResults: [APILocation] = []
    private var savedRoutes: [SavedRoute] = []
    private var pendingFrom: Station?
    private var pendingTo: Station?
    private var searchTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var deleteRouteButton: NSButton!
    private let client = OeBBClient()

    private var departureReminderCheckbox: NSButton!
    private var departureReminderField: NSTextField!
    private var delayAlertCheckbox: NSButton!
    private var delayAlertField: NSTextField!
    private var platformChangeCheckbox: NSButton!
    private var pendingNotifications: NotificationSettings = NotificationSettings()

    private enum ActiveField { case from, to, none }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Train Tracker"
        panel.isReleasedWhenClosed = false
        panel.center()
        self.init(window: panel)
        loadCurrentConfig()
        setupUI()
    }

    private func loadCurrentConfig() {
        let config = AppConfigStore.shared.load()
        pendingFrom = config.fromStation
        pendingTo = config.toStation
        savedRoutes = config.savedRoutes
        pendingNotifications = config.notifications
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // From row
        let fromLabel = makeLabel("From:")
        fromLabel.frame = NSRect(x: 16, y: 392, width: 50, height: 20)
        cv.addSubview(fromLabel)

        fromField = makeTextField(placeholder: "Search for station…")
        fromField.frame = NSRect(x: 70, y: 388, width: 314, height: 24)
        fromField.stringValue = pendingFrom?.name ?? ""
        fromField.delegate = self
        cv.addSubview(fromField)

        // To row
        let toLabel = makeLabel("To:")
        toLabel.frame = NSRect(x: 16, y: 360, width: 50, height: 20)
        cv.addSubview(toLabel)

        toField = makeTextField(placeholder: "Search for station…")
        toField.frame = NSRect(x: 70, y: 356, width: 314, height: 24)
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        cv.addSubview(toField)

        // Search results table (hidden until there are results)
        resultsScrollView = NSScrollView(frame: NSRect(x: 70, y: 272, width: 314, height: 76))
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .bezelBorder
        resultsTable = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Station"
        resultsTable.addTableColumn(col)
        resultsTable.headerView = nil
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.action = #selector(resultRowClicked)
        resultsTable.target = self
        resultsScrollView.documentView = resultsTable
        resultsScrollView.isHidden = true
        cv.addSubview(resultsScrollView)

        // Saved routes label
        let routesLabel = makeLabel("Saved routes:")
        routesLabel.frame = NSRect(x: 16, y: 248, width: 120, height: 20)
        cv.addSubview(routesLabel)

        // "–" delete button aligned with the label
        let deleteBtn = NSButton(title: "–", target: self, action: #selector(deleteSelectedRoute))
        deleteBtn.bezelStyle = .smallSquare
        deleteBtn.frame = NSRect(x: 352, y: 244, width: 32, height: 24)
        deleteBtn.isEnabled = false
        cv.addSubview(deleteBtn)
        deleteRouteButton = deleteBtn

        // Saved routes table (single column, full-width)
        let savedScrollView = NSScrollView(frame: NSRect(x: 16, y: 164, width: 368, height: 76))
        savedScrollView.hasVerticalScroller = true
        savedScrollView.borderType = .bezelBorder
        let deletable = DeletableTableView()
        deletable.onDelete = { [weak self] in self?.deleteSelectedRoute() }
        savedRoutesTable = deletable
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        nameCol.title = "Route"
        nameCol.width = 350
        savedRoutesTable.addTableColumn(nameCol)
        savedRoutesTable.headerView = nil
        savedRoutesTable.dataSource = self
        savedRoutesTable.delegate = self
        savedRoutesTable.action = #selector(savedRouteRowClicked)
        savedRoutesTable.target = self
        savedScrollView.documentView = savedRoutesTable
        cv.addSubview(savedScrollView)

        // Save & Close button
        let saveBtn = NSButton(title: "Save & Close", target: self, action: #selector(saveAndClose))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 284, y: 8, width: 100, height: 28)
        cv.addSubview(saveBtn)

        // Notifications section separator
        let notifSeparator = NSBox()
        notifSeparator.boxType = .separator
        notifSeparator.frame = NSRect(x: 16, y: 156, width: 368, height: 1)
        cv.addSubview(notifSeparator)

        // Section label
        let notifLabel = makeLabel("Notifications")
        notifLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        notifLabel.frame = NSRect(x: 16, y: 136, width: 200, height: 18)
        cv.addSubview(notifLabel)

        // Departure reminder row
        departureReminderCheckbox = NSButton(checkboxWithTitle: "Departure reminder", target: self, action: #selector(notifCheckboxChanged(_:)))
        departureReminderCheckbox.frame = NSRect(x: 16, y: 110, width: 170, height: 20)
        departureReminderCheckbox.state = pendingNotifications.departureReminderEnabled ? .on : .off
        cv.addSubview(departureReminderCheckbox)

        departureReminderField = makeNumberField()
        departureReminderField.frame = NSRect(x: 192, y: 110, width: 40, height: 20)
        departureReminderField.integerValue = pendingNotifications.departureReminderMinutes
        departureReminderField.isEnabled = pendingNotifications.departureReminderEnabled
        cv.addSubview(departureReminderField)

        let depMinLabel = makeLabel("minutes before")
        depMinLabel.frame = NSRect(x: 238, y: 110, width: 120, height: 20)
        cv.addSubview(depMinLabel)

        // Delay alert row
        delayAlertCheckbox = NSButton(checkboxWithTitle: "Delay alert when", target: self, action: #selector(notifCheckboxChanged(_:)))
        delayAlertCheckbox.frame = NSRect(x: 16, y: 82, width: 160, height: 20)
        delayAlertCheckbox.state = pendingNotifications.delayAlertEnabled ? .on : .off
        cv.addSubview(delayAlertCheckbox)

        delayAlertField = makeNumberField()
        delayAlertField.frame = NSRect(x: 192, y: 82, width: 40, height: 20)
        delayAlertField.integerValue = pendingNotifications.delayAlertThresholdMinutes
        delayAlertField.isEnabled = pendingNotifications.delayAlertEnabled
        cv.addSubview(delayAlertField)

        let delayMinLabel = makeLabel("+ minutes late")
        delayMinLabel.frame = NSRect(x: 238, y: 82, width: 120, height: 20)
        cv.addSubview(delayMinLabel)

        // Platform change row
        platformChangeCheckbox = NSButton(checkboxWithTitle: "Platform change alert", target: self, action: #selector(notifCheckboxChanged(_:)))
        platformChangeCheckbox.frame = NSRect(x: 16, y: 54, width: 220, height: 20)
        platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off
        cv.addSubview(platformChangeCheckbox)
    }

    // MARK: - Debounced search

    private func scheduleSearch(query: String) {
        searchTimer?.invalidate()
        guard !query.isEmpty else {
            searchResults = []
            resultsTable.reloadData()
            resultsScrollView.isHidden = true
            return
        }
        searchTask?.cancel()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.searchTask = Task { await self?.performSearch(query: query) }
            }
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        guard !Task.isCancelled else { return }
        guard let results = try? await client.searchStations(query: query) else { return }
        guard !Task.isCancelled else { return }
        searchResults = results.filter { $0.type == "stop" || $0.type == nil }
        resultsTable.reloadData()
        resultsScrollView.isHidden = searchResults.isEmpty
    }

    // MARK: - Actions

    @objc private func resultRowClicked() {
        let row = resultsTable.clickedRow
        guard row >= 0, row < searchResults.count else { return }
        let location = searchResults[row]
        let station = Station(name: location.name, id: location.id)
        switch activeField {
        case .from:
            pendingFrom = station
            fromField.stringValue = station.name
        case .to:
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

    @objc private func savedRouteRowClicked() {
        let row = savedRoutesTable.clickedRow
        guard row >= 0, row < savedRoutes.count else { return }
        let route = savedRoutes[row]
        pendingFrom = route.from
        pendingTo = route.to
        fromField.stringValue = route.from.name
        toField.stringValue = route.to.name
        searchResults = []
        resultsTable.reloadData()
        resultsScrollView.isHidden = true
        activeField = .none
    }

    @objc private func deleteSelectedRoute() {
        let row = savedRoutesTable.selectedRow
        guard row >= 0, row < savedRoutes.count else { return }
        savedRoutes.remove(at: row)
        savedRoutesTable.reloadData()
        deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
    }

    @objc private func notifCheckboxChanged(_ sender: NSButton) {
        departureReminderField.isEnabled = departureReminderCheckbox.state == .on
        delayAlertField.isEnabled = delayAlertCheckbox.state == .on
    }

    @objc private func saveAndClose() {
        var config = AppConfigStore.shared.load()
        let stationsChanged = config.fromStation != pendingFrom || config.toStation != pendingTo
        config.fromStation = pendingFrom
        config.toStation = pendingTo
        var routes = savedRoutes
        if let f = pendingFrom, let t = pendingTo {
            let route = SavedRoute(from: f, to: t)
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

    @MainActor override func close() {
        super.close()
        onClose?()
    }

    // MARK: - UI helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13)
        return f
    }

    private func makeTextField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.font = NSFont.systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        return f
    }

    private func makeNumberField() -> NSTextField {
        let f = NSTextField()
        f.font = NSFont.systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        f.alignment = .center
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 120
        f.formatter = formatter
        return f
    }
}

// MARK: - NSTextFieldDelegate

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fromField { activeField = .from }
        else if field === toField { activeField = .to }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        scheduleSearch(query: field.stringValue)
    }
}

// MARK: - NSTableViewDataSource + NSTableViewDelegate

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === resultsTable ? searchResults.count : savedRoutes.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === savedRoutesTable else { return }
        deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.font = NSFont.systemFont(ofSize: 13)
        if tableView === resultsTable {
            cell.stringValue = searchResults[row].name
        } else {
            cell.stringValue = savedRoutes[row].displayName
        }
        return cell
    }
}

// MARK: - DeletableTableView

private class DeletableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // keyCode 51 = Delete (backspace), 117 = Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
