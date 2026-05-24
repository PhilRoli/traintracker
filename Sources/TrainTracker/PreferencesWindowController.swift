// Sources/TrainTracker/PreferencesWindowController.swift
import AppKit

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
    private let client = OeBBClient()

    private enum ActiveField { case from, to, none }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
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
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // From row
        let fromLabel = makeLabel("From:")
        fromLabel.frame = NSRect(x: 16, y: 272, width: 50, height: 20)
        cv.addSubview(fromLabel)

        fromField = makeTextField(placeholder: "Search for station…")
        fromField.frame = NSRect(x: 70, y: 268, width: 314, height: 24)
        fromField.stringValue = pendingFrom?.name ?? ""
        fromField.delegate = self
        cv.addSubview(fromField)

        // To row
        let toLabel = makeLabel("To:")
        toLabel.frame = NSRect(x: 16, y: 240, width: 50, height: 20)
        cv.addSubview(toLabel)

        toField = makeTextField(placeholder: "Search for station…")
        toField.frame = NSRect(x: 70, y: 236, width: 314, height: 24)
        toField.stringValue = pendingTo?.name ?? ""
        toField.delegate = self
        cv.addSubview(toField)

        // Search results table (hidden until there are results)
        resultsScrollView = NSScrollView(frame: NSRect(x: 70, y: 152, width: 314, height: 76))
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
        routesLabel.frame = NSRect(x: 16, y: 128, width: 120, height: 20)
        cv.addSubview(routesLabel)

        // Saved routes table
        let savedScrollView = NSScrollView(frame: NSRect(x: 16, y: 44, width: 368, height: 76))
        savedScrollView.hasVerticalScroller = true
        savedScrollView.borderType = .bezelBorder
        savedRoutesTable = NSTableView()
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        nameCol.title = "Route"
        nameCol.width = 260
        let loadCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("load"))
        loadCol.title = ""
        loadCol.width = 60
        savedRoutesTable.addTableColumn(nameCol)
        savedRoutesTable.addTableColumn(loadCol)
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
            self?.searchTask = Task { [weak self] in await self?.performSearch(query: query) }
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

    @objc private func saveAndClose() {
        var config = AppConfigStore.shared.load()
        // Check for station change BEFORE overwriting the stored values
        let stationsChanged = config.fromStation != pendingFrom || config.toStation != pendingTo
        config.fromStation = pendingFrom
        config.toStation = pendingTo
        if let f = pendingFrom, let t = pendingTo {
            let route = SavedRoute(from: f, to: t)
            if !config.savedRoutes.contains(route) {
                config.savedRoutes.append(route)
            }
        }
        if stationsChanged { config.trainNumber = nil }
        AppConfigStore.shared.save(config)
        close()
    }

    override func close() {
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.font = NSFont.systemFont(ofSize: 13)
        if tableView === resultsTable {
            cell.stringValue = searchResults[row].name
        } else {
            let id = tableColumn?.identifier.rawValue
            cell.stringValue = id == "route" ? savedRoutes[row].displayName : "Load"
            if id == "load" { cell.textColor = .linkColor }
        }
        return cell
    }
}
