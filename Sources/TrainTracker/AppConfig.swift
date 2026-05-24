// Sources/TrainTracker/AppConfig.swift
import Foundation

struct Station: Codable, Equatable {
    var name: String   // display only
    var id: String     // used for all API calls
}

struct SavedRoute: Codable, Equatable {
    var from: Station
    var to: Station

    var displayName: String { "\(from.name) → \(to.name)" }
}

struct AppConfig: Codable {
    var fromStation: Station?
    var toStation: Station?
    var trainNumber: String?
    var savedRoutes: [SavedRoute]

    init() { savedRoutes = [] }
}

final class AppConfigStore {
    static let shared = AppConfigStore()

    private let key = "config"
    private let defaults: UserDefaults

    init(suiteName: String = "traintracker") {
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
}
