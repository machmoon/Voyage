import Foundation

/// Small public Worker client. Voyage deliberately has no flight-data secret;
/// all schedule choices are bundled and this client is used only for no-key weather.
actor VoyageAPIClient {
    static let shared = VoyageAPIClient()

    private struct WeatherEnvelope: Decodable {
        let snapshot: RemoteWeatherSnapshot
    }

    private struct RemoteWeatherSnapshot: Decodable {
        struct Wind: Decodable {
            let direction: Int?
            let speed: Int?
        }

        struct CloudLayer: Decodable {
            let coverage: String
            let altitude: Int
        }

        let metarTime: Date
        let wind: Wind
        let visibility: Double?
        let cloudLayers: [CloudLayer]
        let ceiling: Int?
        let temperature: Double?
        let precipitation: String
        let raw: String?
        let source: String
    }

    private var baseURL: URL? {
        let configured = ProcessInfo.processInfo.environment["VOYAGE_API_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VoyageAPIBaseURL") as? String
        return configured.flatMap(URL.init(string:))
    }

    func weather(for airport: Airport) async -> WeatherSnapshot? {
        guard let baseURL else { return nil }
        let url = baseURL.appending(path: "v1/weather/\(icaoCode(for: airport.code))")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remote = try decoder.decode(WeatherEnvelope.self, from: data).snapshot
            return WeatherSnapshot(
                airportCode: airport.code,
                observedAt: remote.metarTime,
                condition: condition(from: remote),
                windDirectionDegrees: remote.wind.direction,
                windSpeedKnots: remote.wind.speed,
                visibilityMiles: remote.visibility,
                cloudBaseFeet: remote.ceiling ?? remote.cloudLayers.map(\.altitude).min(),
                temperatureCelsius: remote.temperature,
                source: remote.source
            )
        } catch {
            return nil
        }
    }

    private func icaoCode(for airportCode: String) -> String {
        switch airportCode {
        case "BOS": return "KBOS"
        case "JFK": return "KJFK"
        case "MIA": return "KMIA"
        case "SFO": return "KSFO"
        case "LAX": return "KLAX"
        case "YYZ": return "CYYZ"
        case "YVR": return "CYVR"
        case "YQR": return "CYQR"
        default: return airportCode
        }
    }

    private func condition(from snapshot: RemoteWeatherSnapshot) -> SkyCondition {
        let raw = snapshot.raw?.uppercased() ?? ""
        if raw.contains("TS") { return .storm }
        if raw.contains(" SN") || raw.contains(" SG") || raw.contains(" PL") { return .snow }
        if snapshot.precipitation != "none" { return .rain }
        if raw.contains(" FG") || raw.contains(" BR") { return .fog }
        let coverage = Set(snapshot.cloudLayers.map(\.coverage))
        if !coverage.isDisjoint(with: ["BKN", "OVC", "VV"]) { return .cloudy }
        if !coverage.isDisjoint(with: ["FEW", "SCT"]) { return .partlyCloudy }
        return .clear
    }
}
