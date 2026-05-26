// Sources/TrainTracker/NotificationManager.swift
import UserNotifications
import Foundation

protocol NotificationScheduler {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationScheduler {}

@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler

    init(scheduler: NotificationScheduler = UNUserNotificationCenter.current()) {
        self.scheduler = scheduler
    }

    func process(_ data: TrainData, settings: NotificationSettings) {
        // implementation in subsequent tasks
    }
}
