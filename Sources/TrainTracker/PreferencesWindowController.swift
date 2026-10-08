// Sources/TrainTracker/PreferencesWindowController.swift
import AppKit
import ServiceManagement

/// Preferences apply live: every control writes to the config store as soon as it changes.
@MainActor
final class PreferencesWindowController: NSWindowController {
    static let contentWidth: CGFloat = 400
    private static let labelWidth: CGFloat = 100

    var onRouteChanged: (() -> Void)?
    var onClose: (() -> Void)?

    let configStore: AppConfigStore
    let loginItemController: LoginItemController
    let client: any OeBBClientProtocol

    // Route state
    enum ActiveField { case from, via, destination, none }
    let fromField = NSTextField()
    let viaField = NSTextField()
    let toField = NSTextField()
    let routeStack = NSStackView()
    let resultsScrollView = NSScrollView()
    let resultsTable = NSTableView()
    let savedRoutesTable = DeletableTableView()
    let deleteRouteButton = NSButton(title: "–", target: nil, action: nil)
    var activeField: ActiveField = .none
    var searchResults: [APILocation] = []
    var searchMessage: String?
    var savedRoutes: [SavedRoute] = []
    var pendingFrom: Station?
    var pendingVia: Station?
    var pendingTo: Station?
    var searchTimer: Timer?
    var searchTask: Task<Void, Never>?

    // Notification controls
    var reminderPopups: [ReminderKind: NSPopUpButton] = [:]
    let platformCheck = NSButton(checkboxWithTitle: "Platform change alert", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let stack = NSStackView()

    init(
        configStore: AppConfigStore = .shared,
        loginItemController: LoginItemController? = nil,
        client: (any OeBBClientProtocol)? = nil
    ) {
        self.configStore = configStore
        self.loginItemController = loginItemController ?? LoginItemController()
        self.client = client ?? OeBBClient()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Train Tracker"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        reloadFromStore()
        window.contentView = stack
        resizeToFit()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func close() {
        super.close()
        onClose?()
    }

    // MARK: - Layout

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        stack.addArrangedSubview(sectionHeader("Route"))
        buildRouteSection()
        stack.addArrangedSubview(sectionHeader("Saved routes"))
        stack.addArrangedSubview(makeSavedRoutesView())
        stack.addArrangedSubview(sectionHeader("Notifications"))
        for kind in ReminderKind.allCases {
            let popup = NSPopUpButton()
            popup.target = self
            popup.action = #selector(notificationsChanged)
            reminderPopups[kind] = popup
            stack.addArrangedSubview(row(kind.label, popup))
        }
        platformCheck.target = self
        platformCheck.action = #selector(notificationsChanged)
        stack.addArrangedSubview(platformCheck)
        stack.addArrangedSubview(sectionHeader("App"))
        loginCheck.target = self
        loginCheck.action = #selector(loginChanged)
        stack.addArrangedSubview(loginCheck)
        let export = NSButton(title: "Export Config…", target: self, action: #selector(exportConfig))
        let importButton = NSButton(title: "Import Config…", target: self, action: #selector(importConfig))
        let transferRow = NSStackView(views: [export, importButton])
        transferRow.spacing = 8
        stack.addArrangedSubview(transferRow)
    }

    private func buildRouteSection() {
        routeStack.orientation = .vertical
        routeStack.alignment = .leading
        routeStack.spacing = 8
        let fields: [(label: String, field: NSTextField)] = [
            ("From", fromField), ("Via", viaField), ("To", toField)
        ]
        fromField.placeholderString = "Search for station…"
        viaField.placeholderString = "Optional transfer station…"
        toField.placeholderString = "Search for station…"
        for entry in fields {
            entry.field.delegate = self
            routeStack.addArrangedSubview(row(entry.label, entry.field))
        }
        configureResultsView()
        stack.addArrangedSubview(routeStack)
    }

    func row(_ label: String, _ control: NSView) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        let row = NSStackView(views: [title, control])
        row.spacing = 8
        row.alignment = .centerY
        if control is NSTextField {
            row.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        return row
    }

    private func sectionHeader(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let header = NSStackView(views: [spacer, label])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 0
        return header
    }

    /// Fits the window to its content, keeping the top-left corner fixed.
    func resizeToFit() {
        guard let window else { return }
        let oldHeight = window.frame.height
        window.setContentSize(NSSize(width: Self.contentWidth + 40, height: stack.fittingSize.height))
        var frame = window.frame
        frame.origin.y += oldHeight - frame.height
        window.setFrame(frame, display: true)
    }

    // MARK: - Loading

    func reloadFromStore() {
        let config = configStore.load()
        pendingFrom = config.fromStation
        pendingVia = config.viaStation
        pendingTo = config.toStation
        savedRoutes = config.savedRoutes
        fromField.stringValue = pendingFrom?.name ?? ""
        viaField.stringValue = pendingVia?.name ?? ""
        toField.stringValue = pendingTo?.name ?? ""
        savedRoutesTable.reloadData()
        for (kind, popup) in reminderPopups {
            populate(popup, kind: kind, settings: config.notifications)
        }
        platformCheck.state = config.notifications.platformChangeEnabled ? .on : .off
        loginCheck.state = loginItemController.isEnabled ? .on : .off
    }

    private func populate(_ popup: NSPopUpButton, kind: ReminderKind, settings: NotificationSettings) {
        let minutes = kind.minutes(in: settings)
        popup.removeAllItems()
        popup.addItem(withTitle: "Off")
        popup.lastItem?.tag = 0
        for choice in PreferencesLogic.choices(including: minutes) {
            popup.addItem(withTitle: kind.itemTitle(minutes: choice))
            popup.lastItem?.tag = choice
        }
        popup.selectItem(withTag: kind.isEnabled(in: settings) ? minutes : 0)
    }

    // MARK: - Live-apply actions

    @objc private func notificationsChanged() {
        var config = configStore.load()
        for (kind, popup) in reminderPopups {
            let tag = popup.selectedItem?.tag ?? 0
            let minutes = tag == 0 ? kind.minutes(in: config.notifications) : tag
            kind.apply(enabled: tag != 0, minutes: minutes, to: &config.notifications)
        }
        config.notifications.platformChangeEnabled = platformCheck.state == .on
        configStore.save(config)
    }

    @objc private func loginChanged() {
        let wantsEnabled = loginCheck.state == .on
        if !loginItemController.setEnabled(wantsEnabled) {
            showAlert(
                title: "Couldn't update login item",
                message: "macOS declined to \(wantsEnabled ? "register" : "unregister") TrainTracker as a login item."
            )
        } else if wantsEnabled && loginItemController.requiresApproval {
            showAlert(
                title: "Approval needed",
                message: "Allow TrainTracker in System Settings → General → Login Items to finish enabling this."
            )
            SMAppService.openSystemSettingsLoginItems()
        }
        loginCheck.state = loginItemController.isEnabled ? .on : .off // reflect what the system actually accepted
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
