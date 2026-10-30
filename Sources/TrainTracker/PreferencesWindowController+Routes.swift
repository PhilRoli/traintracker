// Sources/TrainTracker/PreferencesWindowController+Routes.swift
import AppKit

// MARK: - Results list + saved routes

extension PreferencesWindowController {
    func configureResultsView() {
        resultsTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        resultsTable.headerView = nil
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.action = #selector(resultRowClicked)
        resultsScrollView.documentView = resultsTable
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .bezelBorder
        resultsScrollView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        resultsScrollView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        resultsScrollView.isHidden = true
        routeStack.addArrangedSubview(resultsScrollView)
    }

    func makeSavedRoutesView() -> NSView {
        savedRoutesTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route")))
        savedRoutesTable.headerView = nil
        savedRoutesTable.dataSource = self
        savedRoutesTable.delegate = self
        savedRoutesTable.target = self
        savedRoutesTable.action = #selector(savedRouteRowClicked)
        savedRoutesTable.onDelete = { [weak self] in self?.deleteSelectedRoute() }
        savedRoutesTable.registerForDraggedTypes([Self.rowDragType])
        savedRoutesTable.draggingDestinationFeedbackStyle = .gap

        let scroll = NSScrollView()
        scroll.documentView = savedRoutesTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical) // soaks up extra window height

        addHeaderButton.target = self
        addHeaderButton.action = #selector(addHeader)
        addHeaderButton.bezelStyle = .rounded
        addHeaderButton.toolTip = "Add a named header to group routes. Drag rows to reorder."

        let container = NSStackView(views: [scroll, addHeaderButton])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        return container
    }

    func makeSaveRouteRow() -> NSView {
        saveRouteButton.target = self
        saveRouteButton.action = #selector(commitRoute)
        saveRouteButton.bezelStyle = .rounded
        saveRouteButton.keyEquivalent = "\r"
        saveRouteButton.isEnabled = false
        saveStatusLabel.textColor = .secondaryLabelColor
        saveStatusLabel.font = .systemFont(ofSize: 11)
        let row = NSStackView(views: [saveRouteButton, saveStatusLabel])
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    /// Enabled only when both ends are picked and the pair differs from the active route.
    func updateSaveButton() {
        let config = configStore.load()
        let differs = pendingFrom != config.fromStation || pendingVia != config.viaStation
            || pendingTo != config.toStation
        saveRouteButton.isEnabled = pendingFrom != nil && pendingTo != nil && differs
    }

    private func showSaveStatus(_ text: String) {
        saveStatusLabel.stringValue = text
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveStatusLabel.stringValue = "" }
        }
    }

    // MARK: - Showing results

    func showResults(below field: NSTextField) {
        guard let fieldRow = field.superview else { return }
        routeStack.removeArrangedSubview(resultsScrollView)
        resultsScrollView.removeFromSuperview()
        let rows = routeStack.arrangedSubviews
        let index = rows.firstIndex(of: fieldRow).map { $0 + 1 } ?? rows.count
        routeStack.insertArrangedSubview(resultsScrollView, at: index)
        resultsScrollView.isHidden = false
        resizeToFit()
    }

    func hideResults() {
        searchResults = []
        searchMessage = nil
        resultsTable.reloadData()
        guard !resultsScrollView.isHidden else { return }
        resultsScrollView.isHidden = true
        resizeToFit()
    }

    private var activeTextField: NSTextField? {
        switch activeField {
        case .from: return fromField
        case .via: return viaField
        case .destination: return toField
        case .none: return nil
        }
    }

    // MARK: - Debounced search

    func scheduleSearch(query: String) {
        searchTimer?.invalidate()
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            hideResults()
            return
        }
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.searchTask = Task { await self?.performSearch(query: trimmed) }
            }
        }
    }

    private func performSearch(query: String) async {
        let results: [APILocation]
        do {
            results = try await client.searchStations(query: query)
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchMessage = "Search failed — check your connection"
            presentResults()
            return
        }
        guard !Task.isCancelled else { return }
        searchResults = results.filter { $0.type == "stop" || $0.type == nil }
        searchMessage = searchResults.isEmpty ? "No stations found" : nil
        presentResults()
    }

    private func presentResults() {
        resultsTable.reloadData()
        if let field = activeTextField { showResults(below: field) }
    }

    // MARK: - Actions

    @objc func resultRowClicked() {
        let row = resultsTable.clickedRow
        guard row >= 0, row < searchResults.count else { return }
        let location = searchResults[row]
        let station = Station(name: location.name, id: location.id)
        switch activeField {
        case .from:
            pendingFrom = station
            fromField.stringValue = station.name
        case .via:
            pendingVia = station
            viaField.stringValue = station.name
        case .destination:
            pendingTo = station
            toField.stringValue = station.name
        case .none:
            return
        }
        activeField = .none
        hideResults()
        updateSaveButton()
    }

    @objc func savedRouteRowClicked() {
        let row = savedRoutesTable.clickedRow
        guard row >= 0, row < savedEntries.count, case .route(let route) = savedEntries[row] else { return }
        pendingFrom = route.from
        pendingVia = route.viaStation
        pendingTo = route.toStation
        fromField.stringValue = route.from.name
        viaField.stringValue = route.viaStation?.name ?? ""
        toField.stringValue = route.toStation.name
        activeField = .none
        hideResults()
        updateSaveButton()
    }

    @objc func deleteSelectedRoute() {
        removeRoute(at: savedRoutesTable.selectedRow)
    }

    @objc func removeRouteClicked(_ sender: NSButton) {
        removeRoute(at: savedRoutesTable.row(for: sender))
    }

    private func removeRoute(at row: Int) {
        guard row >= 0, row < savedEntries.count else { return }
        savedEntries.remove(at: row)
        persistEntries()
    }

    @objc func addHeader() {
        savedEntries.append(.header("New header"))
        persistEntries()
        let row = savedEntries.count - 1
        savedRoutesTable.scrollRowToVisible(row)
        let field = (savedRoutesTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSStackView)?
            .views.compactMap { $0 as? NSTextField }.first
        if let field { window?.makeFirstResponder(field) }
    }

    /// Writes the list order and headers back; the active route and train are left alone.
    private func persistEntries() {
        var config = configStore.load()
        config.savedEntries = savedEntries
        configStore.save(config)
        savedRoutesTable.reloadData()
    }

    private func renameHeader(at row: Int, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard row >= 0, row < savedEntries.count, case .header(let old) = savedEntries[row] else { return }
        savedEntries[row] = .header(trimmed.isEmpty ? old : trimmed)
        persistEntries()
    }

    /// Saves the picked route, makes it the active one, and tells the menu bar to refetch if it changed.
    @objc func commitRoute() {
        guard pendingFrom != nil, pendingTo != nil else { return }
        let old = configStore.load()
        let updated = PreferencesLogic.applyingRoute(to: old, from: pendingFrom, via: pendingVia, to: pendingTo)
        configStore.save(updated)
        let isNew = updated.savedEntries.count > old.savedEntries.count
        savedEntries = updated.savedEntries
        savedRoutesTable.reloadData()
        let activeIndex = savedEntries.lastIndex { entry in
            if case .route(let route) = entry { return route.matches(updated) }
            return false
        }
        if let index = activeIndex {
            savedRoutesTable.selectRowIndexes([index], byExtendingSelection: false)
            savedRoutesTable.scrollRowToVisible(index)
        }
        updateSaveButton()
        showSaveStatus(isNew ? "Saved ✓" : "Now using this route ✓")
        let changed = old.fromStation != updated.fromStation || old.viaStation != updated.viaStation
            || old.toStation != updated.toStation
        if changed { onRouteChanged?() }
    }
}

// MARK: - NSTextFieldDelegate

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fromField {
            activeField = .from
        } else if field === viaField {
            activeField = .via
        } else if field === toField {
            activeField = .destination
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, [fromField, viaField, toField].contains(field) else { return }
        if field === viaField, field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            pendingVia = nil
            updateSaveButton()
        }
        scheduleSearch(query: field.stringValue)
    }

    /// Typed-but-unpicked text isn't a station; snap the field back to what is actually saved.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fromField {
            field.stringValue = pendingFrom?.name ?? ""
        } else if field === viaField {
            field.stringValue = pendingVia?.name ?? ""
        } else if field === toField {
            field.stringValue = pendingTo?.name ?? ""
        } else {
            let row = savedRoutesTable.row(for: field)
            renameHeader(at: row, to: field.stringValue)
        }
    }
}

// MARK: - NSTableViewDataSource + NSTableViewDelegate

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === resultsTable else { return savedEntries.count }
        return searchResults.isEmpty && searchMessage != nil ? 1 : searchResults.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        if tableView === resultsTable {
            if searchResults.isEmpty, let searchMessage {
                cell.stringValue = searchMessage
                cell.textColor = .secondaryLabelColor
            } else {
                cell.stringValue = searchResults[row].name
            }
        } else {
            return savedEntryCell(for: savedEntries[row])
        }
        return cell
    }

    private func savedEntryCell(for entry: SavedEntry) -> NSView {
        let label: NSTextField
        switch entry {
        case .route(let route):
            let active = route.matches(configStore.load())
            label = NSTextField(labelWithString: (active ? "✓ " : "") + route.displayName)
        case .header(let title):
            label = NSTextField(string: title)
            label.isEditable = true
            label.isBordered = false
            label.drawsBackground = false
            label.focusRingType = .none
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.delegate = self
        }
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let remove = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
                ?? NSImage(),
            target: self, action: #selector(removeRouteClicked)
        )
        remove.isBordered = false
        remove.contentTintColor = .tertiaryLabelColor
        remove.toolTip = "Remove"
        let cell = NSStackView(views: [label, remove])
        cell.spacing = 6
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 4)
        return cell
    }

    // MARK: Drag to reorder

    static let rowDragType = NSPasteboard.PasteboardType("com.philipp.TrainTracker.savedEntryRow")

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard tableView === savedRoutesTable else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard tableView === savedRoutesTable else { return [] }
        if operation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo,
        row: Int, dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard tableView === savedRoutesTable,
              let text = info.draggingPasteboard.string(forType: Self.rowDragType),
              let source = Int(text), source >= 0, source < savedEntries.count else { return false }
        let moved = savedEntries.remove(at: source)
        let destination = min(max(source < row ? row - 1 : row, 0), savedEntries.count)
        savedEntries.insert(moved, at: destination)
        persistEntries()
        tableView.selectRowIndexes([destination], byExtendingSelection: false)
        return true
    }
}
