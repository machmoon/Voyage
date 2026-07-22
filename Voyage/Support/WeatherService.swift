import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Simplified sky condition used to theme the window scene.
enum SkyCondition: String, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case storm
    case snow

    var spokenDescription: String {
        switch self {
        case .clear: return "clear skies"
        case .partlyCloudy: return "a few clouds"
        case .cloudy: return "overcast"
        case .fog: return "fog"
        case .rain: return "light rain"
        case .storm: return "thunderstorms"
        case .snow: return "snow"
        }
    }

    /// 0…1 how much cloud the window scene should draw.
    var cloudAmount: Double {
        switch self {
        case .clear: return 0
        case .partlyCloudy: return 0.45
        case .cloudy, .fog: return 0.95
        case .rain, .storm: return 0.9
        case .snow: return 0.85
        }
    }

    var isPrecipitating: Bool {
        self == .rain || self == .storm || self == .snow
    }
}

/// Real current weather for an airport or route coordinate. WeatherKit is
/// always attempted first, then Open-Meteo, and finally a clear deterministic
/// fallback. Unit tests short-circuit before any provider is touched.
enum WeatherService {
    nonisolated static let maximumRouteWeatherSamples = 5

    typealias CoordinateSnapshotProvider = @Sendable (
        _ coordinate: CLLocationCoordinate2D,
        _ identifier: String
    ) async -> WeatherSnapshot

    static func destinationCondition(for airport: Airport) async -> SkyCondition {
        await condition(for: airport)
    }

    static func condition(for airport: Airport) async -> SkyCondition {
        // Unit tests must stay offline and deterministic.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .clear
        }
        return await snapshot(
            at: airport.coordinate,
            identifier: airport.code
        ).condition
    }

    static func snapshot(for airport: Airport) async -> WeatherSnapshot {
        // Keep this guard at the public boundary: unit tests must never touch
        // WeatherKit, Open-Meteo, or the optional Voyage worker.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .fallback(for: airport)
        }
        return await snapshot(at: airport.coordinate, identifier: airport.code)
    }

    /// Fetches weather at a non-airport route point. The identifier is persisted
    /// in WeatherSnapshot.airportCode so synthetic samples remain inspectable.
    static func snapshot(
        at coordinate: CLLocationCoordinate2D,
        identifier: String = "ROUTE"
    ) async -> WeatherSnapshot {
        // Unit tests must stay offline and deterministic.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return fallbackSnapshot(identifier: identifier)
        }

        let resolvedIdentifier = normalizedIdentifier(identifier)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return fallbackSnapshot(identifier: resolvedIdentifier)
        }

        #if canImport(WeatherKit)
        if let weatherKit = await weatherKitSnapshot(
            at: coordinate,
            identifier: resolvedIdentifier
        ) {
            return weatherKit
        }
        #endif

        if let openMeteo = await openMeteoSnapshot(
            at: coordinate,
            identifier: resolvedIdentifier
        ) {
            return openMeteo
        }

        return fallbackSnapshot(identifier: resolvedIdentifier)
    }

    /// Freezes a bounded set of weather samples for one leg. Three evenly
    /// spaced interior samples are enough to vary atmosphere over long routes;
    /// callers may request fewer or up to `maximumRouteWeatherSamples`.
    static func freezeEnvironment(
        for leg: FlightLeg,
        frozenAt: Date,
        routeSampleCount: Int = 3,
        timeout: Duration = .seconds(3)
    ) async -> FlightEnvironmentSnapshot {
        // This exact process guard keeps the entire batch offline in XCTest,
        // including any future provider added below the public snapshot API.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .fallback(for: leg, frozenAt: frozenAt)
        }

        return await freezeEnvironment(
            for: leg,
            frozenAt: frozenAt,
            routeSampleCount: routeSampleCount,
            timeout: timeout,
            using: { coordinate, identifier in
                await snapshot(at: coordinate, identifier: identifier)
            }
        )
    }

    /// Injectable seam used by deterministic tests. Production callers should
    /// use the overload above so the XCTest network guard cannot be bypassed.
    static func freezeEnvironment(
        for leg: FlightLeg,
        frozenAt: Date,
        routeSampleCount: Int = 3,
        timeout: Duration = .seconds(3),
        using snapshotProvider: @escaping CoordinateSnapshotProvider
    ) async -> FlightEnvironmentSnapshot {
        let requests = environmentRequests(for: leg, routeSampleCount: routeSampleCount)
        guard timeout > .zero else {
            return .fallback(for: leg, frozenAt: frozenAt)
        }

        let frozen = await withTaskGroup(of: FlightEnvironmentSnapshot?.self) { group in
            group.addTask {
                await collectEnvironment(
                    requests: requests,
                    frozenAt: frozenAt,
                    using: snapshotProvider
                )
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return nil
                } catch {
                    return nil
                }
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        return frozen ?? .fallback(for: leg, frozenAt: frozenAt)
    }

    // MARK: WeatherKit

    #if canImport(WeatherKit)
    private static func weatherKitSnapshot(
        at coordinate: CLLocationCoordinate2D,
        identifier: String
    ) async -> WeatherSnapshot? {
        do {
            let current = try await WeatherKit.WeatherService.shared.weather(
                for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                including: .current
            )
            return WeatherSnapshot(
                airportCode: identifier,
                observedAt: current.date,
                condition: condition(for: current.condition),
                windDirectionDegrees: normalizedDegrees(current.wind.direction.converted(to: .degrees).value),
                windSpeedKnots: roundedInt(current.wind.speed.converted(to: .knots).value),
                visibilityMiles: finiteValue(current.visibility.converted(to: .miles).value),
                cloudBaseFeet: nil,
                temperatureCelsius: finiteValue(current.temperature.converted(to: .celsius).value),
                source: "WeatherKit"
            )
        } catch {
            return nil // No entitlement / no network — try Open-Meteo.
        }
    }

    private static func condition(for weatherCondition: WeatherCondition) -> SkyCondition {
        switch weatherCondition {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hail:
            return .storm
        case .rain, .drizzle, .heavyRain, .sunShowers:
            return .rain
        case .snow, .heavySnow, .flurries, .sleet, .blizzard,
             .blowingSnow, .freezingDrizzle, .freezingRain, .wintryMix:
            return .snow
        case .foggy, .haze, .smoky:
            return .fog
        case .cloudy, .mostlyCloudy, .blowingDust:
            return .cloudy
        case .partlyCloudy, .mostlyClear:
            return .partlyCloudy
        default:
            return .clear
        }
    }
    #endif

    // MARK: Open-Meteo

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let time: String?
            let temperatureCelsius: Double?
            let weatherCode: Int
            let cloudCover: Int?
            let windSpeedKnots: Double?
            let windDirectionDegrees: Double?
            let visibilityMeters: Double?

            enum CodingKeys: String, CodingKey {
                case time
                case temperatureCelsius = "temperature_2m"
                case weatherCode = "weather_code"
                case cloudCover = "cloud_cover"
                case windSpeedKnots = "wind_speed_10m"
                case windDirectionDegrees = "wind_direction_10m"
                case visibilityMeters = "visibility"
            }
        }

        let current: Current
    }

    static func openMeteoURL(at coordinate: CLLocationCoordinate2D) -> URL? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,visibility"
            ),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return components.url
    }

    private static func openMeteoSnapshot(
        at coordinate: CLLocationCoordinate2D,
        identifier: String
    ) async -> WeatherSnapshot? {
        guard let url = openMeteoURL(at: coordinate) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try decodeOpenMeteoSnapshot(data, identifier: identifier)
        } catch {
            return nil
        }
    }

    /// Internal for fixture-based tests; keeping decoding separate from URLSession
    /// prevents tests from weakening the process-wide offline guard.
    static func decodeOpenMeteoSnapshot(
        _ data: Data,
        identifier: String,
        fallbackObservedAt: Date = .now
    ) throws -> WeatherSnapshot {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = decoded.current
        let visibilityMiles = current.visibilityMeters.flatMap(finiteValue).map { $0 / 1_609.344 }
        return WeatherSnapshot(
            airportCode: normalizedIdentifier(identifier),
            observedAt: openMeteoDate(current.time) ?? fallbackObservedAt,
            condition: condition(forWMOCode: current.weatherCode, cloudCover: current.cloudCover),
            windDirectionDegrees: current.windDirectionDegrees.flatMap(normalizedDegrees),
            windSpeedKnots: current.windSpeedKnots.flatMap(roundedInt),
            visibilityMiles: visibilityMiles,
            cloudBaseFeet: nil,
            temperatureCelsius: current.temperatureCelsius.flatMap(finiteValue),
            source: "Open-Meteo"
        )
    }

    /// Maps a WMO weather interpretation code (Open-Meteo's `weather_code`)
    /// to a SkyCondition. Exposed for unit testing.
    static func condition(forWMOCode code: Int, cloudCover: Int? = nil) -> SkyCondition {
        switch code {
        case 0:
            // "Clear" per code, but heavy cloud cover reads as clouds.
            if let cover = cloudCover, cover >= 70 { return .cloudy }
            return .clear
        case 1: return (cloudCover ?? 0) >= 70 ? .cloudy : .clear
        case 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...57, 61...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .clear
        }
    }

    // MARK: Route freeze

    private struct EnvironmentRequest: Sendable {
        let index: Int
        let coordinate: CLLocationCoordinate2D
        let identifier: String
    }

    private static func environmentRequests(
        for leg: FlightLeg,
        routeSampleCount: Int
    ) -> [EnvironmentRequest] {
        let count = min(max(0, routeSampleCount), maximumRouteWeatherSamples)
        var requests = [
            EnvironmentRequest(index: 0, coordinate: leg.origin.coordinate, identifier: leg.origin.code)
        ]
        if count > 0 {
            requests += (1...count).map { index in
                let progress = Double(index) / Double(count + 1)
                return EnvironmentRequest(
                    index: index,
                    coordinate: GreatCircle.point(
                        from: leg.origin.coordinate,
                        to: leg.destination.coordinate,
                        fraction: progress
                    ),
                    identifier: String(format: "ROUTE-%02d", index)
                )
            }
        }
        requests.append(
            EnvironmentRequest(
                index: count + 1,
                coordinate: leg.destination.coordinate,
                identifier: leg.destination.code
            )
        )
        return requests
    }

    private static func collectEnvironment(
        requests: [EnvironmentRequest],
        frozenAt: Date,
        using snapshotProvider: @escaping CoordinateSnapshotProvider
    ) async -> FlightEnvironmentSnapshot {
        let results = await withTaskGroup(of: (Int, WeatherSnapshot).self) { group in
            for request in requests {
                group.addTask {
                    let snapshot = await snapshotProvider(request.coordinate, request.identifier)
                    return (request.index, snapshot)
                }
            }

            var collected: [(Int, WeatherSnapshot)] = []
            collected.reserveCapacity(requests.count)
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return FlightEnvironmentSnapshot(
            frozenAt: frozenAt,
            departureWeather: results.first,
            arrivalWeather: results.last,
            routeWeather: results.count > 2 ? Array(results.dropFirst().dropLast()) : []
        )
    }

    // MARK: Helpers

    private static func fallbackSnapshot(
        identifier: String,
        observedAt: Date = .now
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            airportCode: normalizedIdentifier(identifier),
            observedAt: observedAt,
            condition: .clear,
            windDirectionDegrees: nil,
            windSpeedKnots: nil,
            visibilityMiles: nil,
            cloudBaseFeet: nil,
            temperatureCelsius: nil,
            source: "on-device fallback"
        )
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ROUTE" : trimmed
    }

    private static func finiteValue(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static func roundedInt(_ value: Double) -> Int? {
        finiteValue(value).map { Int($0.rounded()) }
    }

    private static func normalizedDegrees(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = Int(value.rounded()).quotientAndRemainder(dividingBy: 360).remainder
        return rounded < 0 ? rounded + 360 : rounded
    }

    private static func openMeteoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let internetFormatter = ISO8601DateFormatter()
        if let date = internetFormatter.date(from: value) { return date }
        if let date = internetFormatter.date(from: value + "Z") { return date }
        if let date = internetFormatter.date(from: value + ":00Z") { return date }

        let minuteFormatter = DateFormatter()
        minuteFormatter.calendar = Calendar(identifier: .gregorian)
        minuteFormatter.locale = Locale(identifier: "en_US_POSIX")
        minuteFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        minuteFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return minuteFormatter.date(from: value)
    }
}
