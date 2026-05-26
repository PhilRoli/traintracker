// Sources/TrainTracker/NotificationManager.swift
import UserNotifications
import Foundation

protocol NotificationScheduler {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationScheduler {}

@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler
    private var authRequested = false

    private var trackedTrainKey: String? = nil
    private var lastDelaySecs: Int = 0
    private var lastDeparturePlatform: String? = nil
    private var lastArrivalPlatform: String? = nil
    private var departureReminderSentFor: String? = nil

    init(scheduler: NotificationScheduler = UNUserNotificationCenter.current()) {
        self.scheduler = scheduler
    }

    func process(_ data: TrainData, settings: NotificationSettings) {
        requestAuthIfNeeded()

        let key = "\(data.trainName)|\(Int(data.scheduledDeparture.timeIntervalSince1970))"
        if key != trackedTrainKey {
            trackedTrainKey = key
            lastDelaySecs = 0
            lastDeparturePlatform = nil
            lastArrivalPlatform = nil
            departureReminderSentFor = nil
        }

        processDepartureReminder(data: data, settings: settings, key: key)
        processDelayAlert(data: data, settings: settings, key: key)
        processPlatformChange(data: data, settings: settings, key: key)
    }

    private func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        Task { try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func processDepartureReminder(data: TrainData, settings: NotificationSettings, key: String) {
        guard settings.departureReminderEnabled,
              !data.isEnRoute,
              departureReminderSentFor != key
        else { return }

        let rtDep = data.scheduledDeparture.addingTimeInterval(TimeInterval(data.departureDelaySecs))
        let secsUntil = rtDep.timeIntervalSinceNow
        guard secsUntil > 0, secsUntil <= Double(settings.departureReminderMinutes * 60) else { return }

        let content = UNMutableNotificationContent()
        let minsLeft = max(1, Int(secsUntil / 60))
        content.title = "\(data.trainName) departs in \(minsLeft)m"
        content.body = data.departurePlatform
            .map { "Platform \($0) at \(data.fromName)" }
            ?? "From \(data.fromName)"

        post(identifier: "departure-\(key)", content: content)
        departureReminderSentFor = key
    }

    private func processDelayAlert(data: TrainData, settings: NotificationSettings, key: String) {
        defer { lastDelaySecs = data.arrivalDelaySecs }
        guard settings.delayAlertEnabled else { return }
        let threshold = settings.delayAlertThresholdMinutes * 60
        guard data.arrivalDelaySecs >= threshold, lastDelaySecs < threshold else { return }

        let content = UNMutableNotificationContent()
        let mins = (data.arrivalDelaySecs + 59) / 60
        content.title = "\(data.trainName) is now +\(mins)m late"
        content.body = "Arrives at \(data.toName)"
        post(identifier: "delay-\(key)", content: content)
    }

    private func processPlatformChange(data: TrainData, settings: NotificationSettings, key: String) {
        defer {
            lastDeparturePlatform = data.departurePlatform
            lastArrivalPlatform = data.arrivalPlatform
        }
        guard settings.platformChangeEnabled else { return }

        if let prev = lastDeparturePlatform, let curr = data.departurePlatform, prev != curr {
            let content = UNMutableNotificationContent()
            content.title = "\(data.trainName): departure platform changed"
            content.body = "Now departing from platform \(curr)"
            post(identifier: "platform-dep-\(key)", content: content)
        }
        if let prev = lastArrivalPlatform, let curr = data.arrivalPlatform, prev != curr {
            let content = UNMutableNotificationContent()
            content.title = "\(data.trainName): arrival platform changed"
            content.body = "Now arriving at platform \(curr)"
            post(identifier: "platform-arr-\(key)", content: content)
        }
    }

    private func post(identifier: String, content: UNMutableNotificationContent) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        scheduler.add(request, withCompletionHandler: nil)
    }
}
