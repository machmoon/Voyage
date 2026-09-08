import CoreLocation
import XCTest
@testable import Voyage

final class FlightEnvironmentWeatherTests: XCTestCase {
    func testOpenMeteoURLRequestsEveryRichCurrentFieldInKnots() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903)
        let url = try XCTUnwrap(WeatherService.openMeteoURL(at: coordinate))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(query["latitude"], "39.7392")
        XCTAssertEqual(query["longitude"], "-104.9903")
        XCTAssertEqual(query["wind_speed_unit"], "kn")
        XCTAssertEqual(query["temperature_unit"], "celsius")
        XCTAssertEqual(query["timezone"], "UTC")

        let variables = Set(try XCTUnwrap(query["current"]).split(separator: ",").map(String.init))
        XCTAssertEqual(variables, [
            "temperature_2m",
            "weather_code",
            "cloud_cover",
            "wind_speed_10m",
            "wind_direction_10m",
            "visibility",
        ])
    }

    func testOpenMeteoFixtureDecodesRichSnapshot() throws {
        let data = Data(
            """
            {
              "current": {
                "time": "2026-07-21T18:45",
                "temperature_2m": 14.6,
                "weather_code": 2,
                "cloud_cover": 52,
                "wind_speed_10m": 17.6,
                "wind_direction_10m": 281.4,
                "visibility": 16093.44
              }
            }
            """.utf8
        )

        let snapshot = try WeatherService.decodeOpenMeteoSnapshot(
            data,
            identifier: " ROCKIES-50 "
        )

        XCTAssertEqual(snapshot.airportCode, "ROCKIES-50")
        XCTAssertEqual(snapshot.condition, .partlyCloudy)
        XCTAssertEqual(snapshot.windDirectionDegrees, 281)
        XCTAssertEqual(snapshot.windSpeedKnots, 18)
        XCTAssertEqual(snapshot.visibilityMiles ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(snapshot.temperatureCelsius ?? 0, 14.6, accuracy: 0.0001)
        XCTAssertNil(snapshot.cloudBaseFeet)
        XCTAssertEqual(snapshot.source, "Open-Meteo")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(calendar.component(.hour, from: snapshot.observedAt), 18)
        XCTAssertEqual(calendar.component(.minute, from: snapshot.observedAt), 45)
    }

    func testOpenMeteoDecoderNormalizesWindAndUsesFallbackDate() throws {
        let fallbackDate = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(
            """
            {
              "current": {
                "weather_code": 0,
                "cloud_cover": 88,
                "wind_speed_10m": 0.4,
                "wind_direction_10m": -10,
                "visibility": 8046.72
              }
            }
            """.utf8
        )

        let snapshot = try WeatherService.decodeOpenMeteoSnapshot(
            data,
            identifier: "",
            fallbackObservedAt: fallbackDate
        )

        XCTAssertEqual(snapshot.airportCode, "ROUTE")
        XCTAssertEqual(snapshot.observedAt, fallbackDate)
        XCTAssertEqual(snapshot.condition, .cloudy)
        XCTAssertEqual(snapshot.windDirectionDegrees, 350)
        XCTAssertEqual(snapshot.windSpeedKnots, 0)
        XCTAssertEqual(snapshot.visibilityMiles ?? 0, 5, accuracy: 0.0001)
    }

    func testCoordinateSnapshotIsOfflineAndDeterministicUnderXCTest() async {
        let snapshot = await WeatherService.snapshot(
            at: CLLocationCoordinate2D(latitude: 39.1, longitude: -106.2),
            identifier: "ROCKIES-50"
        )

        XCTAssertEqual(snapshot.airportCode, "ROCKIES-50")
        XCTAssertEqual(snapshot.condition, .clear)
        XCTAssertEqual(snapshot.source, "on-device fallback")
        XCTAssertNil(snapshot.windDirectionDegrees)
        XCTAssertNil(snapshot.visibilityMiles)
    }

    func testInjectedRouteFreezeClampsCountAndRestoresGeographicOrder() async {
        let leg = FlightLeg(
            origin: Airport.byCode("SFO"),
            destination: Airport.byCode("JFK"),
            duration: 5 * 3600,
            flightNumber: "VOY 424"
        )
        let frozenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let provider: WeatherService.CoordinateSnapshotProvider = { coordinate, identifier in
            // Reverse-ish delays ensure completion order differs from route order.
            let delay = UInt64(max(0, Int((180 + coordinate.longitude).rounded())))
            try? await Task.sleep(for: .milliseconds(delay))
            return WeatherSnapshot(
                airportCode: identifier,
                observedAt: frozenAt,
                condition: .clear,
                windDirectionDegrees: nil,
                windSpeedKnots: nil,
                visibilityMiles: 10,
                cloudBaseFeet: nil,
                temperatureCelsius: nil,
                source: "fixture"
            )
        }

        let environment = await WeatherService.freezeEnvironment(
            for: leg,
            frozenAt: frozenAt,
            routeSampleCount: WeatherService.maximumRouteWeatherSamples + 20,
            timeout: .seconds(1),
            using: provider
        )

        XCTAssertEqual(environment.frozenAt, frozenAt)
        XCTAssertEqual(environment.departureWeather?.airportCode, "SFO")
        XCTAssertEqual(environment.arrivalWeather?.airportCode, "JFK")
        XCTAssertEqual(environment.routeWeather.count, WeatherService.maximumRouteWeatherSamples)
        XCTAssertEqual(
            environment.routeWeather.map(\.airportCode),
            ["ROUTE-01", "ROUTE-02", "ROUTE-03", "ROUTE-04", "ROUTE-05"]
        )
    }

    func testInjectedRouteFreezeTimesOutToDeterministicFallback() async {
        let leg = FlightLeg(
            origin: Airport.byCode("SFO"),
            destination: Airport.byCode("LAX"),
            duration: 90 * 60,
            flightNumber: "VOY 1175"
        )
        let frozenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let provider: WeatherService.CoordinateSnapshotProvider = { _, identifier in
            try? await Task.sleep(for: .seconds(10))
            return WeatherSnapshot(
                airportCode: identifier,
                observedAt: frozenAt,
                condition: .storm,
                windDirectionDegrees: 180,
                windSpeedKnots: 50,
                visibilityMiles: 1,
                cloudBaseFeet: 500,
                temperatureCelsius: 10,
                source: "late fixture"
            )
        }

        let environment = await WeatherService.freezeEnvironment(
            for: leg,
            frozenAt: frozenAt,
            routeSampleCount: 3,
            timeout: .milliseconds(5),
            using: provider
        )

        XCTAssertEqual(environment, .fallback(for: leg, frozenAt: frozenAt))
    }
}
