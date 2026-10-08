// Sources/TrainTracker/PreferencesWindowController+Transfer.swift
import AppKit
import UniformTypeIdentifiers

extension PreferencesWindowController {
    @objc func exportConfig() {
        guard let data = try? ConfigTransfer.exportData(configStore.load()) else {
            showAlert(title: "Export failed", message: "Couldn't encode the current configuration.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "traintracker-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            showAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    @objc func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported: AppConfig
        do {
            imported = PreferencesLogic.sanitized(try ConfigTransfer.importConfig(from: Data(contentsOf: url)))
        } catch {
            showAlert(title: "Import failed", message: "Couldn't read that file as a valid TrainTracker config.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Replace current configuration?"
        alert.informativeText = "Your stations, saved routes and notification settings will be replaced "
            + "by the contents of \(url.lastPathComponent)."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        configStore.save(imported)
        reloadFromStore()
        onRouteChanged?()
    }
}
