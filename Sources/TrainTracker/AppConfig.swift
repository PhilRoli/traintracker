// Sources/TrainTracker/AppConfig.swift
import Foundation

struct Station: Codable, Equatable {
    var name: String   // display only
    var id: String     // used for all API calls
}

struct SavedRoute: Codable, Equatable {
    var from: Station
    var toStation: Station
    var viaStation: Station?

    private enum CodingKeys: String, CodingKey {
        case from
        case toStation = "to"
        case viaStation
    }

    /// Whether this route is the one `config` currently tracks.
    func matches(_ config: AppConfig) -> Bool {
        config.fromStation == from && config.viaStation == viaStation && config.toStation == toStation
    }

    var displayName: String {
        if let viaStation {
            return "\(from.name) → \(viaStation.name) → \(toStation.name)"
        }
        return "\(from.name) → \(toStation.name)"
    }
}

/// One line of the saved-routes list: a route, or a named header that groups the routes below it.
enum SavedEntry: Codable, Equatable {
    case route(SavedRoute)
    case header(String)

    private enum CodingKeys: String, CodingKey { case header }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let title = try container.decodeIfPresent(String.self, forKey: .header) {
            self = .header(title)
        } else {
            self = .route(try SavedRoute(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .route(let route):
            try route.encode(to: encoder)
        case .header(let title):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .header)
        }
    }
}

struct NotificationSettings: Codable {
    var departureReminderEnabled: Bool
    var departureReminderMinutes: Int
    var delayAlertEnabled: Bool
    var delayAlertThresholdMinutes: Int
    var platformChangeEnabled: Bool
    var arrivalReminderEnabled: Bool
    var arrivalReminderMinutes: Int
    var transferReminderEnabled: Bool
    var transferReminderMinutes: Int

    init(
        departureReminderEnabled: Bool = true,
        departureReminderMinutes: Int = 10,
        delayAlertEnabled: Bool = true,
        delayAlertThresholdMinutes: Int = 10,
        platformChangeEnabled: Bool = true,
        arrivalReminderEnabled: Bool = true,
        arrivalReminderMinutes: Int = 10,
        transferReminderEnabled: Bool = true,
        transferReminderMinutes: Int = 10
    ) {
        self.departureReminderEnabled = departureReminderEnabled
        self.departureReminderMinutes = departureReminderMinutes
        self.delayAlertEnabled = delayAlertEnabled
        self.delayAlertThresholdMinutes = delayAlertThresholdMinutes
        self.platformChangeEnabled = platformChangeEnabled
        self.arrivalReminderEnabled = arrivalReminderEnabled
        self.arrivalReminderMinutes = arrivalReminderMinutes
        self.transferReminderEnabled = transferReminderEnabled
        self.transferReminderMinutes = transferReminderMinutes
    }

    enum CodingKeys: String, CodingKey {
        case departureReminderEnabled
        case departureReminderMinutes
        case delayAlertEnabled
        case delayAlertThresholdMinutes
        case platformChangeEnabled
        case arrivalReminderEnabled
        case arrivalReminderMinutes
        case transferReminderEnabled
        case transferReminderMinutes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        departureReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .departureReminderEnabled) ?? true
        departureReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .departureReminderMinutes) ?? 10
        delayAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .delayAlertEnabled) ?? true
        delayAlertThresholdMinutes = try container.decodeIfPresent(Int.self, forKey: .delayAlertThresholdMinutes) ?? 10
        platformChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .platformChangeEnabled) ?? true
        arrivalReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .arrivalReminderEnabled) ?? true
        arrivalReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .arrivalReminderMinutes) ?? 10
        transferReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .transferReminderEnabled) ?? true
        transferReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .transferReminderMinutes) ?? 10
    }
}

struct AppConfig: Codable {
    var fromStation: Station?
    var viaStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var secondLegTrainNumber: String?
    /// Routes and headers in display order; stored under the `savedRoutes` key, so older configs still load.
    var savedEntries: [SavedEntry]
    var savedRoutes: [SavedRoute] {
        savedEntries.compactMap { if case .route(let route) = $0 { return route } else { return nil } }
    }
    var notifications: NotificationSettings = NotificationSettings()

    init() { savedEntries = [] }

    enum CodingKeys: String, CodingKey {
        case fromStation
        case viaStation
        case toStation
        case trainNumber
        case secondLegTrainNumber
        case savedRoutes
        case notifications
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromStation = try container.decodeIfPresent(Station.self, forKey: .fromStation)
        viaStation = try container.decodeIfPresent(Station.self, forKey: .viaStation)
        toStation = try container.decodeIfPresent(Station.self, forKey: .toStation)
        trainNumber = try container.decodeIfPresent(String.self, forKey: .trainNumber)
        secondLegTrainNumber = try container.decodeIfPresent(String.self, forKey: .secondLegTrainNumber)
        savedEntries = try container.decodeIfPresent([SavedEntry].self, forKey: .savedRoutes) ?? []
        notifications = try container.decodeIfPresent(
            NotificationSettings.self,
            forKey: .notifications
        ) ?? NotificationSettings()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fromStation, forKey: .fromStation)
        try container.encodeIfPresent(viaStation, forKey: .viaStation)
        try container.encodeIfPresent(toStation, forKey: .toStation)
        try container.encodeIfPresent(trainNumber, forKey: .trainNumber)
        try container.encodeIfPresent(secondLegTrainNumber, forKey: .secondLegTrainNumber)
        try container.encode(savedEntries, forKey: .savedRoutes)
        try container.encode(notifications, forKey: .notifications)
    }
}

final class AppConfigStore {
    static let shared = AppConfigStore()

    private let key = "config"
    private let corruptBackupKey = "config.corruptBackup"
    private let defaults: UserDefaults
    let suiteName: String

    init(suiteName: String = "traintracker") {
        self.suiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func load() -> AppConfig {
        guard let data = defaults.data(forKey: key) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            // Keep the unreadable payload so a later save doesn't destroy the user's only copy
            NSLog("TrainTracker: config decode failed (\(error)); backed up raw data")
            defaults.set(data, forKey: corruptBackupKey)
            return AppConfig()
        }
    }

    /// Raw config bytes that failed to decode on the last `load()`, if any.
    func corruptConfigBackup() -> Data? {
        defaults.data(forKey: corruptBackupKey)
    }

    func save(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }

    func setStatusLine(_ line: String?) {
        if let line {
            defaults.set(line, forKey: "statusLine")
        } else {
            defaults.removeObject(forKey: "statusLine")
        }
    }

    func statusLine() -> String? {
        defaults.string(forKey: "statusLine")
    }
}
