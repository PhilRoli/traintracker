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
    let loginItemController = LoginItemController()
    private var launchAtLoginCheckbox: NSButton!

    var departureReminderCheckbox: NSButton!
    var departureReminderField: NSTextField!
    var delayAlertCheckbox: NSButton!
    var delayAlertField: NSTextField!
    var platformChangeCheckbox: NSButton!
    var arrivalReminderCheckbox: NSButton!
    var arrivalReminderField: NSTextField!
    var pendingNotifications: NotificationSettings = NotificationSettings()

    enum ActiveField { case from, destination, none }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Train Tracker"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 560)
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

    // MARK: - Layout

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 20
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        let sections = [
            makeRouteSection(),
            makeSavedRoutesSection(),
            makeNotificationsSection(),
            makeAppSection()
        ]
        for section in sections {
            mainStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            // Without this, NSStackView can silently set isHidden = true on whichever
            // arranged subview it picks when the stack can't fit everything at the
            // window's minimum size — and it does NOT un-hide the view later even if
            // the window is resized back up. Pinning every top-level section to
            // .mustHold makes that auto-hide behavior impossible, so shrinking the
            // window can only make the layout visually tight, never make a section
            // vanish (permanently or otherwise).
            mainStack.setVisibilityPriority(.mustHold, for: section)
        }

        setupResultsOverlay(in: contentView)
    }

    private func makeRouteSection() -> NSView {
        let fromField = makeTextField(placeholder: "Search for station…")
        fromField.stringValue = pendingFrom?.name ?? ""
        fromField.delegate = self
        self.fromField = fromField
        let fromRow = makeLabeledFieldRow(label: "From:", field: fromField)

        let toField = makeTextField(placeholder: "Search for station…")
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        self.toField = toField
        let toRow = makeLabeledFieldRow(label: "To:", field: toField)

        let section = NSStackView(views: [fromRow, toRow])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for row in [fromRow, toRow] {
            row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    private func makeLabeledFieldRow(label text: String, field: NSTextField) -> NSView {
        let label = makeLabel(text)
        label.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func setupResultsOverlay(in contentView: NSView) {
        resultsScrollView = NSScrollView()
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .bezelBorder
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
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

        NSLayoutConstraint.activate([
            resultsScrollView.topAnchor.constraint(equalTo: toField.bottomAnchor, constant: 4),
            resultsScrollView.leadingAnchor.constraint(equalTo: toField.leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: toField.trailingAnchor),
            resultsScrollView.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    private func makeSavedRoutesSection() -> NSView {
        let label = makeSectionLabel("Saved routes")
        let deleteBtn = NSButton(title: "–", target: self, action: #selector(deleteSelectedRoute))
        deleteBtn.bezelStyle = .smallSquare
        deleteBtn.isEnabled = false
        deleteRouteButton = deleteBtn

        let spacer = NSView()
        let headerRow = NSStackView(views: [label, spacer, deleteBtn])
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        deleteBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let savedScrollView = NSScrollView()
        savedScrollView.hasVerticalScroller = true
        savedScrollView.borderType = .bezelBorder
        savedScrollView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        let deletable = DeletableTableView()
        deletable.onDelete = { [weak self] in self?.deleteSelectedRoute() }
        savedRoutesTable = deletable
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        nameCol.title = "Route"
        savedRoutesTable.addTableColumn(nameCol)
        savedRoutesTable.headerView = nil
        savedRoutesTable.dataSource = self
        savedRoutesTable.delegate = self
        savedRoutesTable.action = #selector(savedRouteRowClicked)
        savedRoutesTable.target = self
        savedScrollView.documentView = savedRoutesTable

        let section = NSStackView(views: [makeSeparator(), headerRow, savedScrollView])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for view in [headerRow, savedScrollView] {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    private func makeNotificationsSection() -> NSView {
        let label = makeSectionLabel("Notifications")

        departureReminderCheckbox = NSButton(
            checkboxWithTitle: "Departure reminder",
            target: self, action: #selector(notifCheckboxChanged(_:))
        )
        departureReminderCheckbox.state = pendingNotifications.departureReminderEnabled ? .on : .off
        departureReminderField = makeNumberField()
        departureReminderField.integerValue = pendingNotifications.departureReminderMinutes
        departureReminderField.isEnabled = pendingNotifications.departureReminderEnabled
        let departureRow = makeNotificationRow(
            checkbox: departureReminderCheckbox, field: departureReminderField, suffix: "minutes before"
        )

        delayAlertCheckbox = NSButton(
            checkboxWithTitle: "Delay alert when",
            target: self, action: #selector(notifCheckboxChanged(_:))
        )
        delayAlertCheckbox.state = pendingNotifications.delayAlertEnabled ? .on : .off
        delayAlertField = makeNumberField()
        delayAlertField.integerValue = pendingNotifications.delayAlertThresholdMinutes
        delayAlertField.isEnabled = pendingNotifications.delayAlertEnabled
        let delayRow = makeNotificationRow(
            checkbox: delayAlertCheckbox, field: delayAlertField, suffix: "+ minutes late"
        )

        arrivalReminderCheckbox = NSButton(
            checkboxWithTitle: "Arrival reminder",
            target: self, action: #selector(notifCheckboxChanged(_:))
        )
        arrivalReminderCheckbox.state = pendingNotifications.arrivalReminderEnabled ? .on : .off
        arrivalReminderField = makeNumberField()
        arrivalReminderField.integerValue = pendingNotifications.arrivalReminderMinutes
        arrivalReminderField.isEnabled = pendingNotifications.arrivalReminderEnabled
        let arrivalRow = makeNotificationRow(
            checkbox: arrivalReminderCheckbox, field: arrivalReminderField, suffix: "minutes before"
        )

        platformChangeCheckbox = NSButton(
            checkboxWithTitle: "Platform change alert",
            target: self, action: #selector(notifCheckboxChanged(_:))
        )
        platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off

        let section = NSStackView(views: [
            makeSeparator(), label, departureRow, delayRow, arrivalRow, platformChangeCheckbox
        ])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for row in [departureRow, delayRow, arrivalRow] {
            row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    private func makeNotificationRow(checkbox: NSButton, field: NSTextField, suffix: String) -> NSView {
        checkbox.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        checkbox.widthAnchor.constraint(equalToConstant: 170).isActive = true
        field.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let suffixLabel = makeLabel(suffix)
        let row = NSStackView(views: [checkbox, field, suffixLabel])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func makeAppSection() -> NSView {
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self, action: #selector(launchAtLoginChanged(_:))
        )
        launchAtLoginCheckbox.state = loginItemController.isEnabled ? .on : .off

        let exportBtn = NSButton(title: "Export Config…", target: self, action: #selector(exportConfig))
        exportBtn.bezelStyle = .rounded
        let importBtn = NSButton(title: "Import Config…", target: self, action: #selector(importConfig))
        importBtn.bezelStyle = .rounded
        let transferRow = NSStackView(views: [exportBtn, importBtn])
        transferRow.orientation = .horizontal
        transferRow.spacing = 8

        let saveBtn = NSButton(title: "Save & Close", target: self, action: #selector(saveAndClose))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        let saveSpacer = NSView()
        let saveRow = NSStackView(views: [saveSpacer, saveBtn])
        saveRow.orientation = .horizontal
        saveRow.distribution = .fill

        let section = NSStackView(views: [makeSeparator(), launchAtLoginCheckbox, transferRow, saveRow])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        saveRow.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
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

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = makeLabel(text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
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

class DeletableTableView: NSTableView {
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
