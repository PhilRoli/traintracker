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

        let scroll = NSScrollView()
        scroll.documentView = savedRoutesTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: Self.contentWidth - 34).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true

        deleteRouteButton.target = self
        deleteRouteButton.action = #selector(deleteSelectedRoute)
        deleteRouteButton.bezelStyle = .smallSquare
        deleteRouteButton.isEnabled = false

        let container = NSStackView(views: [scroll, deleteRouteButton])
        container.alignment = .top
        container.spacing = 6
        return container
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

    // MARK: - Actions (live-apply)

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
        commitRoute()
    }

    @objc func savedRouteRowClicked() {
        let row = savedRoutesTable.clickedRow
        guard row >= 0, row < savedRoutes.count else { return }
        let route = savedRoutes[row]
        pendingFrom = route.from
        pendingVia = route.viaStation
        pendingTo = route.toStation
        fromField.stringValue = route.from.name
        viaField.stringValue = route.viaStation?.name ?? ""
        toField.stringValue = route.toStation.name
        activeField = .none
        hideResults()
        commitRoute()
    }

    @objc func deleteSelectedRoute() {
        let row = savedRoutesTable.selectedRow
        guard row >= 0, row < savedRoutes.count else { return }
        var config = configStore.load()
        config.savedRoutes.remove(at: row)
        configStore.save(config)
        savedRoutes = config.savedRoutes
        savedRoutesTable.reloadData()
        deleteRouteButton.isEnabled = false
    }

    /// Persists the selected route once both ends are known, and tells the menu bar to refetch if it changed.
    func commitRoute() {
        guard pendingFrom != nil, pendingTo != nil else { return }
        let old = configStore.load()
        let updated = PreferencesLogic.applyingRoute(to: old, from: pendingFrom, via: pendingVia, to: pendingTo)
        configStore.save(updated)
        savedRoutes = updated.savedRoutes
        savedRoutesTable.reloadData()
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
        guard let field = obj.object as? NSTextField else { return }
        if field === viaField, field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            pendingVia = nil
            commitRoute()
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
        }
    }
}

// MARK: - NSTableViewDataSource + NSTableViewDelegate

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === resultsTable else { return savedRoutes.count }
        return searchResults.isEmpty && searchMessage != nil ? 1 : searchResults.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === savedRoutesTable else { return }
        deleteRouteButton.isEnabled = savedRoutesTable.selectedRow >= 0
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
            cell.stringValue = savedRoutes[row].displayName
        }
        return cell
    }
}
