// Sources/TrainTracker/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let configStore: AppConfigStore

    init(configStore: AppConfigStore = .shared) {
        self.configStore = configStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        configStore.setStatusLine(nil)
    }
}
