// Sources/TrainTracker/AppDelegate.swift
import AppKit
import MenuBarKit
import UserNotifications

/// Accessory apps have no visible menu bar; without these items text fields can't use ⌘C/⌘V/⌘X/⌘A.
@MainActor
func installMainMenu() {
    NSApp.mainMenu = MainMenu.make(appName: "TrainTracker")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private let configStore: AppConfigStore

    init(configStore: AppConfigStore = .shared) {
        self.configStore = configStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        UNUserNotificationCenter.current().delegate = self
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        configStore.setStatusLine(nil)
    }

    // Menu bar apps count as foreground, so without this macOS would suppress the banners
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
