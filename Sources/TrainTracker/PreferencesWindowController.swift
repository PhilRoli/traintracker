// Sources/TrainTracker/PreferencesWindowController.swift
import AppKit
import UniformTypeIdentifiers

@MainActor
final class PreferencesWindowController: NSWindowController {
    var onClose: (() -> Void)?

    var fromField: NSTextField!
    var toField: NSTextField!
    var resultsTable: NSTableView!
    var resultsScrollView: NSScrollView!
    var savedRoutesTable: NSTableView!

    var activeField: ActiveField = .none
    var searchResults: [APILocation] = []
    var savedRoutes: [SavedRoute] = []
    var pendingFrom: Station?
    var pendingTo: Station?
    private var searchTimer: Timer?
    private var searchTask: Task<Void, Never>?
    var deleteRouteButton: NSButton!
    private let client = OeBBClient()
    var loginItemController = LoginItemController()
    private var launchAtLoginCheckbox: NSButton!

    var departureReminderCheckbox: NSButton!
    var departureReminderField: NSTextField!
    var delayAlertCheckbox: NSButton!
    var delayAlertField: NSTextField!
    var platformChangeCheckbox: NSButton!
    var pendingNotifications: NotificationSettings = NotificationSettings()

    enum ActiveField { case from, destination, none }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 510),
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

    func loadCurrentConfig() {
        let config = AppConfigStore.shared.load()
        pendingFrom = config.fromStation
        pendingTo = config.toStation
        savedRoutes = config.savedRoutes
        pendingNotifications = config.notifications
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        setupFromToFields(in: contentView)
        setupResultsTable(in: contentView)
        setupSavedRoutesSection(in: contentView)
        setupNotificationsSection(in: contentView)
        setupBottomButtons(in: contentView)
    }

    private func setupFromToFields(in contentView: NSView) {
        // From row
        let fromLabel = makeLabel("From:")
        fromLabel.frame = NSRect(x: 16, y: 462, width: 50, height: 20)
        contentView.addSubview(fromLabel)

        fromField = makeTextField(placeholder: "Search for station…")
        fromField.frame = NSRect(x: 70, y: 458, width: 314, height: 24)
        fromField.stringValue = pendingFrom?.name ?? ""
        fromField.delegate = self
        contentView.addSubview(fromField)

        // To row
        let toLabel = makeLabel("To:")
        toLabel.frame = NSRect(x: 16, y: 430, width: 50, height: 20)
        contentView.addSubview(toLabel)

        toField = makeTextField(placeholder: "Search for station…")
        toField.frame = NSRect(x: 70, y: 426, width: 314, height: 24)
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        contentView.addSubview(toField)
    }

    private func setupResultsTable(in contentView: NSView) {
        // Search results table (hidden until there are results)
        resultsScrollView = NSScrollView(frame: NSRect(x: 70, y: 342, width: 314, height: 76))
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
        contentView.addSubview(resultsScrollView)
    }

    private func setupSavedRoutesSection(in contentView: NSView) {
        // Saved routes label
        let routesLabel = makeLabel("Saved routes:")
        routesLabel.frame = NSRect(x: 16, y: 318, width: 120, height: 20)
        contentView.addSubview(routesLabel)

        // "–" delete button aligned with the label
        let deleteBtn = NSButton(title: "–", target: self, action: #selector(deleteSelectedRoute))
        deleteBtn.bezelStyle = .smallSquare
        deleteBtn.frame = NSRect(x: 352, y: 314, width: 32, height: 24)
        deleteBtn.isEnabled = false
        contentView.addSubview(deleteBtn)
        deleteRouteButton = deleteBtn

        // Saved routes table (single column, full-width)
        let savedScrollView = NSScrollView(frame: NSRect(x: 16, y: 234, width: 368, height: 76))
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
        contentView.addSubview(savedScrollView)
    }

    private func setupNotificationsSection(in contentView: NSView) {
        // Notifications section separator
        let notifSeparator = NSBox()
        notifSeparator.boxType = .separator
        notifSeparator.frame = NSRect(x: 16, y: 226, width: 368, height: 1)
        contentView.addSubview(notifSeparator)

        // Section label
        let notifLabel = makeLabel("Notifications")
        notifLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        notifLabel.frame = NSRect(x: 16, y: 206, width: 200, height: 18)
        contentView.addSubview(notifLabel)

        // Departure reminder row
        departureReminderCheckbox = NSButton(
            checkboxWithTitle: "Departure reminder",
            target: self,
            action: #selector(notifCheckboxChanged(_:))
        )
        departureReminderCheckbox.frame = NSRect(x: 16, y: 180, width: 170, height: 20)
        departureReminderCheckbox.state = pendingNotifications.departureReminderEnabled ? .on : .off
        contentView.addSubview(departureReminderCheckbox)

        departureReminderField = makeNumberField()
        departureReminderField.frame = NSRect(x: 192, y: 180, width: 40, height: 20)
        departureReminderField.integerValue = pendingNotifications.departureReminderMinutes
        departureReminderField.isEnabled = pendingNotifications.departureReminderEnabled
        contentView.addSubview(departureReminderField)

        let depMinLabel = makeLabel("minutes before")
        depMinLabel.frame = NSRect(x: 238, y: 180, width: 120, height: 20)
        contentView.addSubview(depMinLabel)

        // Delay alert row
        delayAlertCheckbox = NSButton(
            checkboxWithTitle: "Delay alert when",
            target: self,
            action: #selector(notifCheckboxChanged(_:))
        )
        delayAlertCheckbox.frame = NSRect(x: 16, y: 152, width: 160, height: 20)
        delayAlertCheckbox.state = pendingNotifications.delayAlertEnabled ? .on : .off
        contentView.addSubview(delayAlertCheckbox)

        delayAlertField = makeNumberField()
        delayAlertField.frame = NSRect(x: 192, y: 152, width: 40, height: 20)
        delayAlertField.integerValue = pendingNotifications.delayAlertThresholdMinutes
        delayAlertField.isEnabled = pendingNotifications.delayAlertEnabled
        contentView.addSubview(delayAlertField)

        let delayMinLabel = makeLabel("+ minutes late")
        delayMinLabel.frame = NSRect(x: 238, y: 152, width: 120, height: 20)
        contentView.addSubview(delayMinLabel)

        // Platform change row
        platformChangeCheckbox = NSButton(
            checkboxWithTitle: "Platform change alert",
            target: self,
            action: #selector(notifCheckboxChanged(_:))
        )
        platformChangeCheckbox.frame = NSRect(x: 16, y: 124, width: 220, height: 20)
        platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off
        contentView.addSubview(platformChangeCheckbox)
    }

    private func setupBottomButtons(in contentView: NSView) {
        // Save & Close button
        let saveBtn = NSButton(title: "Save & Close", target: self, action: #selector(saveAndClose))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 284, y: 78, width: 100, height: 28)
        contentView.addSubview(saveBtn)

        // Launch at Login checkbox
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self,
            action: #selector(launchAtLoginChanged(_:))
        )
        launchAtLoginCheckbox.frame = NSRect(x: 16, y: 46, width: 200, height: 20)
        launchAtLoginCheckbox.state = loginItemController.isEnabled ? .on : .off
        contentView.addSubview(launchAtLoginCheckbox)

        // Export / Import config buttons
        let exportBtn = NSButton(title: "Export Config…", target: self, action: #selector(exportConfig))
        exportBtn.bezelStyle = .rounded
        exportBtn.frame = NSRect(x: 16, y: 8, width: 150, height: 28)
        contentView.addSubview(exportBtn)

        let importBtn = NSButton(title: "Import Config…", target: self, action: #selector(importConfig))
        importBtn.bezelStyle = .rounded
        importBtn.frame = NSRect(x: 174, y: 8, width: 150, height: 28)
        contentView.addSubview(importBtn)
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

    @MainActor override func close() {
        super.close()
        onClose?()
    }

    // MARK: - UI helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 13)
        return field
    }

    private func makeTextField(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        return field
    }

    private func makeNumberField() -> NSTextField {
        let field = NSTextField()
        field.font = NSFont.systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 120
        field.formatter = formatter
        return field
    }
}

// MARK: - NSTextFieldDelegate

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fromField {
            activeField = .from
        } else if field === toField {
            activeField = .destination
        }
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
