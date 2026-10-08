// Sources/TrainTracker/AppDelegate.swift
import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private let configStore: AppConfigStore

    init(configStore: AppConfigStore = .shared) {
        self.configStore = configStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
