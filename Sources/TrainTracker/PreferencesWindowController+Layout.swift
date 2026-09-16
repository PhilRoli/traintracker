// Sources/TrainTracker/PreferencesWindowController+Layout.swift
import AppKit

private struct ReminderRow {
    let checkbox: NSButton
    let field: NSTextField
    let row: NSView
}

extension PreferencesWindowController {
    // MARK: - Layout

    func setupUI() {
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

        let routeSection = makeRouteSection()
        // Resist growing vertically so extra window height goes to the Saved
        // Routes table (which has a growth-friendly min-height constraint)
        // rather than pooling as empty space below the To: field.
        routeSection.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let sections = [
            routeSection,
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

        let viaField = makeTextField(placeholder: "Optional transfer station…")
        viaField.stringValue = pendingVia?.name ?? ""
        viaField.delegate = self
        self.viaField = viaField
        let viaRow = makeLabeledFieldRow(label: "Via:", field: viaField)

        let toField = makeTextField(placeholder: "Search for station…")
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        self.toField = toField
        let toRow = makeLabeledFieldRow(label: "To:", field: toField)

        let section = NSStackView(views: [fromRow, viaRow, toRow])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for row in [fromRow, viaRow, toRow] {
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
        savedScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
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

        let departure = makeReminderRow(
            title: "Departure reminder", enabled: pendingNotifications.departureReminderEnabled,
            minutes: pendingNotifications.departureReminderMinutes, suffix: "minutes before"
        )
        departureReminderCheckbox = departure.checkbox
        departureReminderField = departure.field

        let delay = makeReminderRow(
            title: "Delay alert when", enabled: pendingNotifications.delayAlertEnabled,
            minutes: pendingNotifications.delayAlertThresholdMinutes, suffix: "+ minutes late"
        )
        delayAlertCheckbox = delay.checkbox
        delayAlertField = delay.field

        let arrival = makeReminderRow(
            title: "Arrival reminder", enabled: pendingNotifications.arrivalReminderEnabled,
            minutes: pendingNotifications.arrivalReminderMinutes, suffix: "minutes before"
        )
        arrivalReminderCheckbox = arrival.checkbox
        arrivalReminderField = arrival.field

        let transfer = makeReminderRow(
            title: "Transfer reminder", enabled: pendingNotifications.transferReminderEnabled,
            minutes: pendingNotifications.transferReminderMinutes, suffix: "minutes before"
        )
        transferReminderCheckbox = transfer.checkbox
        transferReminderField = transfer.field

        platformChangeCheckbox = NSButton(
            checkboxWithTitle: "Platform change alert",
            target: self, action: #selector(notifCheckboxChanged(_:))
        )
        platformChangeCheckbox.state = pendingNotifications.platformChangeEnabled ? .on : .off

        let section = NSStackView(views: [
            makeSeparator(), label, departure.row, delay.row, arrival.row, transfer.row, platformChangeCheckbox
        ])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for row in [departure.row, delay.row, arrival.row, transfer.row] {
            row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    private func makeReminderRow(
        title: String, enabled: Bool, minutes: Int, suffix: String
    ) -> ReminderRow {
        let checkbox = NSButton(
            checkboxWithTitle: title, target: self, action: #selector(notifCheckboxChanged(_:))
        )
        checkbox.state = enabled ? .on : .off
        let field = makeNumberField()
        field.integerValue = minutes
        field.isEnabled = enabled
        let row = makeNotificationRow(checkbox: checkbox, field: field, suffix: suffix)
        return ReminderRow(checkbox: checkbox, field: field, row: row)
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
