import ServiceManagement

protocol LoginItemManaging {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func register() throws
    func unregister() throws
}

extension LoginItemManaging {
    var requiresApproval: Bool { false }
}

struct SMAppServiceLoginItemManager: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LoginItemController {
    private let manager: LoginItemManaging

    init(manager: LoginItemManaging = SMAppServiceLoginItemManager()) {
        self.manager = manager
    }

    var isEnabled: Bool { manager.isEnabled }

    /// True when macOS registered the item but is waiting for the user to approve it in System Settings.
    var requiresApproval: Bool { manager.requiresApproval }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try manager.register()
            } else {
                try manager.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
