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
        case .clear: return 0.15
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

/// Real current weather for an airport. Tries WeatherKit first (needs the
/// paid entitlement), then falls back to Open-Meteo — free, no API key —
/// so real-world weather works on any build. Final fallback: clear.
enum WeatherService {
    static func destinationCondition(for airport: Airport) async -> SkyCondition {
        await condition(for: airport)
    }

    static func condition(for airport: Airport) async -> SkyCondition {
        // Unit tests must stay offline and deterministic.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .clear
        }
        #if canImport(WeatherKit)
        if let condition = await weatherKitCondition(for: airport) {
            return condition
        }
        #endif
        if let condition = await openMeteoCondition(for: airport) {
            return condition
        }
        return .clear
    }

    // MARK: WeatherKit

    #if canImport(WeatherKit)
    private static func weatherKitCondition(for airport: Airport) async -> SkyCondition? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(
                for: airport.location,
                including: .current
            )
            switch weather.condition {
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
        } catch {
            return nil // No entitlement / no network — try Open-Meteo.
        }
    }
    #endif

    // MARK: Open-Meteo

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let weatherCode: Int
            let cloudCover: Int?

            enum CodingKeys: String, CodingKey {
                case weatherCode = "weather_code"
                case cloudCover = "cloud_cover"
            }
        }
        let current: Current
    }

    private static func openMeteoCondition(for airport: Airport) async -> SkyCondition? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", airport.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", airport.longitude)),
            URLQueryItem(name: "current", value: "weather_code,cloud_cover"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return condition(forWMOCode: decoded.current.weatherCode,
                             cloudCover: decoded.current.cloudCover)
        } catch {
            return nil
        }
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
}
