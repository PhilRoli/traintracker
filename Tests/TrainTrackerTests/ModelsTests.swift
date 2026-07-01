// Tests/TrainTrackerTests/ModelsTests.swift
import XCTest
@testable import TrainTracker

final class ModelsTests: XCTestCase {
    func test_decodeJourneysResponse() throws {
        let json = """
        {
          "journeys": [{
            "legs": [{
              "origin": {"id":"8100013","name":"Linz/Donau Hbf"},
              "destination": {"id":"8100002","name":"Salzburg Hbf"},
              "plannedDeparture": "2026-05-24T12:56:00+02:00",
              "plannedArrival": "2026-05-24T14:08:00+02:00",
              "departureDelay": 0,
              "arrivalDelay": 180,
              "departurePlatform": "3",
              "arrivalPlatform": "5",
              "line": {"name":"WB 912","product":"interregional"},
              "stopovers": [
                {"stop":{"id":"1","name":"Linz/Donau Hbf"},
                 "plannedDeparture":"2026-05-24T12:56:00+02:00"},
                {"stop":{"id":"2","name":"Attnang-Puchheim"},
                 "plannedArrival":"2026-05-24T13:28:00+02:00"},
                {"stop":{"id":"3","name":"Salzburg Hbf"},
                 "plannedArrival":"2026-05-24T14:08:00+02:00"}
              ]
            }]
          }]
        }
        """
        let data = Data(json.utf8)

        let response = try JSONDecoder().decode(APIJourneysResponse.self, from: data)
        XCTAssertEqual(response.journeys.count, 1)
        let leg = response.journeys[0].legs[0]
        XCTAssertEqual(leg.line?.name, "WB 912")
        XCTAssertEqual(leg.origin.name, "Linz/Donau Hbf")
        XCTAssertEqual(leg.arrivalDelay, 180)
        XCTAssertEqual(leg.departurePlatform, "3")
        XCTAssertEqual(leg.stopovers?.count, 3)
    }

    func test_decodeLocationsResponse() throws {
        let json = """
        [
          {"id":"8100013","name":"Linz/Donau Hbf","type":"stop"},
          {"id":"1140101","name":"Linz/Donau","type":"station"}
        ]
        """
        let data = Data(json.utf8)

        let locations = try JSONDecoder().decode([APILocation].self, from: data)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].id, "8100013")
        XCTAssertEqual(locations[0].type, "stop")
    }
}
