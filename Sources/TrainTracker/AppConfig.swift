// Sources/TrainTracker/AppConfig.swift
import Foundation

struct Station: Codable, Equatable {
    var name: String   // display only
    var id: String     // used for all API calls
}

struct SavedRoute: Codable, Equatable {
    var from: Station
    var toStation: Station

    private enum CodingKeys: String, CodingKey {
        case from
        case toStation = "to"
    }

    var displayName: String { "\(from.name) → \(toStation.name)" }
}

struct NotificationSettings: Codable {
    var departureReminderEnabled: Bool
    var departureReminderMinutes: Int
    var delayAlertEnabled: Bool
    var delayAlertThresholdMinutes: Int
    var platformChangeEnabled: Bool
    var arrivalReminderEnabled: Bool
    var arrivalReminderMinutes: Int

    init(
        departureReminderEnabled: Bool = true,
        departureReminderMinutes: Int = 10,
        delayAlertEnabled: Bool = true,
        delayAlertThresholdMinutes: Int = 10,
        platformChangeEnabled: Bool = true,
        arrivalReminderEnabled: Bool = true,
        arrivalReminderMinutes: Int = 10
    ) {
        self.departureReminderEnabled = departureReminderEnabled
        self.departureReminderMinutes = departureReminderMinutes
        self.delayAlertEnabled = delayAlertEnabled
        self.delayAlertThresholdMinutes = delayAlertThresholdMinutes
        self.platformChangeEnabled = platformChangeEnabled
        self.arrivalReminderEnabled = arrivalReminderEnabled
        self.arrivalReminderMinutes = arrivalReminderMinutes
    }

    enum CodingKeys: String, CodingKey {
        case departureReminderEnabled
        case departureReminderMinutes
        case delayAlertEnabled
        case delayAlertThresholdMinutes
        case platformChangeEnabled
        case arrivalReminderEnabled
        case arrivalReminderMinutes
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
    }
}

struct AppConfig: Codable {
    var fromStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var savedRoutes: [SavedRoute]
    var notifications: NotificationSettings = NotificationSettings()

    init() { savedRoutes = [] }

    enum CodingKeys: String, CodingKey {
        case fromStation
        case toStation
        case trainNumber
        case savedRoutes
        case notifications
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromStation = try container.decodeIfPresent(Station.self, forKey: .fromStation)
        toStation = try container.decodeIfPresent(Station.self, forKey: .toStation)
        trainNumber = try container.decodeIfPresent(String.self, forKey: .trainNumber)
        savedRoutes = try container.decode([SavedRoute].self, forKey: .savedRoutes)
        notifications = try container.decodeIfPresent(
            NotificationSettings.self,
            forKey: .notifications
        ) ?? NotificationSettings()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fromStation, forKey: .fromStation)
        try container.encodeIfPresent(toStation, forKey: .toStation)
        try container.encodeIfPresent(trainNumber, forKey: .trainNumber)
        try container.encode(savedRoutes, forKey: .savedRoutes)
        try container.encode(notifications, forKey: .notifications)
    }
}

final class AppConfigStore {
    static let shared = AppConfigStore()

    private let key = "config"
    private let defaults: UserDefaults
    let suiteName: String

    init(suiteName: String = "traintracker") {
        self.suiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func load() -> AppConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
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
