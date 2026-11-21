import CoreLocation
import Foundation

/// Real local weather from Open-Meteo (free, no key). Refreshed every 15 minutes at most.
nonisolated struct LiveWeather: Sendable, Equatable {
    let condition: WeatherCondition
    let temperature: Double
    let windSpeed: Double
    let code: Int
    let fetchedAt: Date

    var summary: String {
        let temp = "\(Int(temperature.rounded()))°"
        switch code {
        case 0: return "Clear · \(temp)"
        case 1, 2: return "Partly cloudy · \(temp)"
        case 3: return "Overcast · \(temp)"
        case 45, 48: return "Fog · \(temp)"
        case 51...57: return "Drizzle · \(temp)"
        case 61...67, 80...82: return "Rain · \(temp)"
        case 71...77, 85, 86: return "Snow · \(temp)"
        case 95...99: return "Thunderstorm · \(temp)"
        default: return temp
        }
    }
}

nonisolated enum WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let weather_code: Int?
            let precipitation: Double?
            let cloud_cover: Double?
            let wind_speed_10m: Double?
        }
        let current: Current
    }

    static func fetch(at c: CLLocationCoordinate2D) async throws -> LiveWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", c.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,precipitation,cloud_cover,wind_speed_10m"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let current = try JSONDecoder().decode(Response.self, from: data).current
        let code = current.weather_code ?? 0
        let rainy = (current.precipitation ?? 0) > 0.05 || (51...67).contains(code) || (80...82).contains(code) || code >= 95
        let condition: WeatherCondition = rainy ? .rain : ((current.cloud_cover ?? 0) > 65 || code == 3 || code == 45 || code == 48 ? .cloudy : .clear)
        return LiveWeather(
            condition: condition,
            temperature: current.temperature_2m ?? 0,
            windSpeed: current.wind_speed_10m ?? 0,
            code: code,
            fetchedAt: .now
        )
    }
}
