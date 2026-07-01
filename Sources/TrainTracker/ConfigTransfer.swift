import Foundation

enum ConfigTransfer {
    static func exportData(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    static func importConfig(from data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
