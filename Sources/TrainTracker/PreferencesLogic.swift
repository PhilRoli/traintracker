// Sources/TrainTracker/PreferencesLogic.swift
import Foundation

/// The four minute-based notification settings, each shown as a single popup in Preferences.
enum ReminderKind: CaseIterable {
    case departure, delay, arrival, transfer

    var label: String {
        switch self {
        case .departure: return "Departure"
        case .delay: return "Delay alert"
        case .arrival: return "Arrival"
        case .transfer: return "Transfer"
        }
    }

    func itemTitle(minutes: Int) -> String {
        switch self {
        case .delay: return "\(minutes)+ min late"
        case .departure, .arrival, .transfer: return "\(minutes) min before"
        }
    }

    func isEnabled(in settings: NotificationSettings) -> Bool {
        switch self {
        case .departure: return settings.departureReminderEnabled
        case .delay: return settings.delayAlertEnabled
        case .arrival: return settings.arrivalReminderEnabled
        case .transfer: return settings.transferReminderEnabled
        }
    }

    func minutes(in settings: NotificationSettings) -> Int {
        switch self {
        case .departure: return settings.departureReminderMinutes
        case .delay: return settings.delayAlertThresholdMinutes
        case .arrival: return settings.arrivalReminderMinutes
        case .transfer: return settings.transferReminderMinutes
        }
    }

    func apply(enabled: Bool, minutes: Int, to settings: inout NotificationSettings) {
        switch self {
        case .departure:
            settings.departureReminderEnabled = enabled
            settings.departureReminderMinutes = minutes
        case .delay:
            settings.delayAlertEnabled = enabled
            settings.delayAlertThresholdMinutes = minutes
        case .arrival:
            settings.arrivalReminderEnabled = enabled
            settings.arrivalReminderMinutes = minutes
        case .transfer:
            settings.transferReminderEnabled = enabled
            settings.transferReminderMinutes = minutes
        }
    }
}

enum PreferencesLogic {
    static let minuteChoices = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    static let minuteRange = 1...120

    /// The standard choices plus `value`, so a value imported from a config file is never silently replaced.
    static func choices(including value: Int) -> [Int] {
        Array(Set(minuteChoices + [value])).sorted()
    }

    /// Applies a route selection: remembers it as a saved route and drops the tracked train if the route changed.
    static func applyingRoute(
        to config: AppConfig, from: Station?, via: Station?, to destination: Station?
    ) -> AppConfig {
        var config = config
        let changed = config.fromStation != from || config.viaStation != via || config.toStation != destination
        config.fromStation = from
        config.viaStation = via
        config.toStation = destination
        if let from, let destination {
            let route = SavedRoute(from: from, toStation: destination, viaStation: via)
            if !config.savedRoutes.contains(route) { config.savedRoutes.append(route) }
        }
        if changed {
            config.trainNumber = nil
            config.secondLegTrainNumber = nil
        }
        return config
    }

    /// Clamps imported minute values into a sane range.
    static func sanitized(_ config: AppConfig) -> AppConfig {
        var config = config
        for kind in ReminderKind.allCases {
            let minutes = kind.minutes(in: config.notifications)
            let clamped = min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
            let enabled = kind.isEnabled(in: config.notifications)
            kind.apply(enabled: enabled, minutes: clamped, to: &config.notifications)
        }
        return config
    }
}
