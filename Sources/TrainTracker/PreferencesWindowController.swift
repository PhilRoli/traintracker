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
    var launchAtLoginCheckbox: NSButton!

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
