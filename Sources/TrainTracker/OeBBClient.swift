// Sources/TrainTracker/OeBBClient.swift
import Foundation

enum OeBBError: Error {
    case invalidURL
    case httpError(Int)
}

final class OeBBClient {
    static let baseURL = "https://oebb.macistry.com/api"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - URL constructors (static for testability)

    static func locationsURL(query: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/locations")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "results", value: "8")
        ]
        return components?.url
    }

    static func journeysURL(fromId: String, toId: String, departure: Date) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let depString = formatter.string(from: departure)
        var components = URLComponents(string: "\(baseURL)/journeys")
        components?.queryItems = [
            URLQueryItem(name: "from", value: fromId),
            URLQueryItem(name: "to", value: toId),
            URLQueryItem(name: "departure", value: depString),
            URLQueryItem(name: "results", value: "12"),
            URLQueryItem(name: "stopovers", value: "true")
        ]
        return components?.url
    }

    static func refreshJourneyURL(token: String) -> URL? {
        guard let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var components = URLComponents(string: "\(baseURL)/journeys/\(encoded)")
        components?.queryItems = [URLQueryItem(name: "stopovers", value: "true")]
        return components?.url
    }

    // MARK: - Network calls

    func searchStations(query: String) async throws -> [APILocation] {
        guard let url = Self.locationsURL(query: query) else { throw OeBBError.invalidURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OeBBError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode([APILocation].self, from: data)
    }

    func fetchJourneys(fromId: String, toId: String, departure: Date) async throws -> [APIJourney] {
        guard let url = Self.journeysURL(fromId: fromId, toId: toId, departure: departure) else {
            throw OeBBError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OeBBError.httpError(http.statusCode)
        }
        let resp = try JSONDecoder().decode(APIJourneysResponse.self, from: data)
        return resp.journeys
    }

    func refreshJourney(token: String) async throws -> APIJourney {
        guard let url = Self.refreshJourneyURL(token: token) else { throw OeBBError.invalidURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OeBBError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(APIJourneyResponse.self, from: data).journey
    }
}
