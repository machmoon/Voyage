import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Simplified sky condition used to theme the window scene on approach.
enum SkyCondition: String, Codable {
    case clear
    case cloudy
    case rain
    case snow

    var spokenDescription: String {
        switch self {
        case .clear: return "clear skies"
        case .cloudy: return "overcast"
        case .rain: return "light rain"
        case .snow: return "snow"
        }
    }
}

/// Fetches destination weather from WeatherKit when available.
/// WeatherKit requires a paid developer entitlement, so every failure
/// path (no entitlement, no network, no Xcode capability) quietly
/// falls back to clear skies.
enum WeatherService {
    static func destinationCondition(for airport: Airport) async -> SkyCondition {
        #if canImport(WeatherKit)
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(
                for: airport.location,
                including: .current
            )
            switch weather.condition {
            case .rain, .drizzle, .heavyRain, .sunShowers, .thunderstorms,
                 .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .hail:
                return .rain
            case .snow, .heavySnow, .flurries, .sleet, .blizzard,
                 .blowingSnow, .freezingDrizzle, .freezingRain, .wintryMix:
                return .snow
            case .cloudy, .mostlyCloudy, .foggy, .haze, .smoky, .blowingDust:
                return .cloudy
            default:
                return .clear
            }
        } catch {
            return .clear
        }
        #else
        return .clear
        #endif
    }
}
