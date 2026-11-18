import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// National Weather Service (api.weather.gov): free, US only, no key. Parsing here follows the real
/// response shape: values are intervals like "2026-11-17T12:00:00+00:00/PT6H" in mm, degrees C and km/h.

public struct TimedValue: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let value: Double
    public var durationSeconds: Double { end.timeIntervalSince(start) }
}

public enum NWSParsing {
    /// "PT2H", "PT30M", "P1DT12H", "P2D". Months and years are not used by NWS and are rejected.
    public static func parseDuration(_ text: String) -> TimeInterval? {
        guard text.hasPrefix("P") else { return nil }
        var seconds = 0.0
        var number = ""
        var inTime = false
        for ch in text.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { number.append(ch); continue }
            guard let n = Double(number) else { return nil }
            number = ""
            switch (ch, inTime) {
            case ("W", false): seconds += n * 604_800
            case ("D", false): seconds += n * 86_400
            case ("H", true): seconds += n * 3_600
            case ("M", true): seconds += n * 60
            case ("S", true): seconds += n
            default: return nil
            }
        }
        return number.isEmpty && seconds > 0 ? seconds : nil
    }

    public static func parseDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }

    public static func parseInterval(_ text: String) -> (start: Date, end: Date)? {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let start = parseDate(parts[0]), let duration = parseDuration(parts[1]) else { return nil }
        return (start, start.addingTimeInterval(duration))
    }

    /// Reads one series ({"values":[{"validTime":..., "value":...}]}). Null values and bad intervals are skipped.
    static func series(_ properties: [String: Any], _ key: String) -> [TimedValue] {
        guard let block = properties[key] as? [String: Any], let values = block["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { item in
            guard let vt = item["validTime"] as? String, let interval = parseInterval(vt),
                  let v = (item["value"] as? NSNumber)?.doubleValue, v.isFinite else { return nil }
            return TimedValue(start: interval.start, end: interval.end, value: v)
        }
    }
}

public struct WeatherWindowSummary: Equatable, Sendable {
    public var snowfallInches: Double
    public var peakSnowRateInPerHour: Double
    /// Temperature when snow falls hardest, or the coldest temperature in the window if no snow.
    public var temperatureF: Double?
    public var minTemperatureF: Double?
    public var maxWindMph: Double?
    public var maxGustMph: Double?
    public var minVisibilityMiles: Double?

    /// Weather as numbers. The app currently uses only the snowfall total; the rest is available if weather-based routing is ever wanted.
    public var conditions: WeatherConditions {
        WeatherConditions(snowfallRateInPerHour: peakSnowRateInPerHour, accumulationInches: snowfallInches,
                          temperatureF: temperatureF ?? 30, windMph: maxWindMph ?? 0, visibilityMiles: minVisibilityMiles ?? 10)
    }
}

public struct NWSForecast: Equatable, Sendable {
    public var snowfallMM: [TimedValue]
    public var temperatureC: [TimedValue]
    public var windSpeedKmh: [TimedValue]
    public var windGustKmh: [TimedValue]
    public var visibilityM: [TimedValue]

    public init(snowfallMM: [TimedValue], temperatureC: [TimedValue], windSpeedKmh: [TimedValue],
                windGustKmh: [TimedValue], visibilityM: [TimedValue]) {
        self.snowfallMM = snowfallMM
        self.temperatureC = temperatureC
        self.windSpeedKmh = windSpeedKmh
        self.windGustKmh = windGustKmh
        self.visibilityM = visibilityM
    }

    /// Reads the gridpoint response (`/gridpoints/{office}/{x},{y}`).
    public init(gridpointJSON data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["properties"] as? [String: Any] else {
            throw RoutingError.badResponse("Weather response was not readable")
        }
        self.init(snowfallMM: NWSParsing.series(props, "snowfallAmount"),
                  temperatureC: NWSParsing.series(props, "temperature"),
                  windSpeedKmh: NWSParsing.series(props, "windSpeed"),
                  windGustKmh: NWSParsing.series(props, "windGust"),
                  visibilityM: NWSParsing.series(props, "visibility"))
    }

    private static func overlap(_ v: TimedValue, _ from: Date, _ to: Date) -> Double {
        max(0, min(v.end, to).timeIntervalSince(max(v.start, from)))
    }

    private static func value(at t: Date, in series: [TimedValue]) -> Double? {
        series.first { $0.start <= t && t < $0.end }?.value
    }

    /// Snowfall is shared out in proportion to how much of each forecast interval falls inside the window.
    public func summary(from: Date, to: Date) -> WeatherWindowSummary {
        guard to > from else {
            return WeatherWindowSummary(snowfallInches: 0, peakSnowRateInPerHour: 0)
        }
        var totalMM = 0.0
        var peakRateMMperHr = 0.0
        var peakAt: Date?
        for v in snowfallMM {
            let o = Self.overlap(v, from, to)
            guard o > 0, v.durationSeconds > 0 else { continue }
            totalMM += v.value * (o / v.durationSeconds)
            let rate = v.value / (v.durationSeconds / 3600)
            if rate > peakRateMMperHr { peakRateMMperHr = rate; peakAt = max(v.start, from) }
        }
        let temps = temperatureC.filter { Self.overlap($0, from, to) > 0 }.map(\.value)
        let minTempF = temps.min().map { $0 * 9 / 5 + 32 }
        var tempF = minTempF
        if let t = peakAt, let c = Self.value(at: t, in: temperatureC) { tempF = c * 9 / 5 + 32 }

        func maxMph(_ s: [TimedValue]) -> Double? {
            s.filter { Self.overlap($0, from, to) > 0 }.map(\.value).max().map { $0 / 1.609344 }
        }
        let vis = visibilityM.filter { Self.overlap($0, from, to) > 0 }.map(\.value).min().map { $0 / 1609.344 }
        return WeatherWindowSummary(snowfallInches: totalMM / 25.4, peakSnowRateInPerHour: peakRateMMperHr / 25.4,
                                    temperatureF: tempF, minTemperatureF: minTempF,
                                    maxWindMph: maxMph(windSpeedKmh), maxGustMph: maxMph(windGustKmh),
                                    minVisibilityMiles: vis)
    }
}

public struct WinterAlert: Equatable, Sendable {
    public let event: String
    public let severity: String
    public let headline: String
    public let onset: Date?
    public let ends: Date?
}

public enum NWSAlerts {
    private static let winterWords = ["winter", "snow", "blizzard", "ice storm", "freezing", "sleet", "wind chill", "squall"]

    /// Reads `/alerts/active` and keeps winter-related alerts, most severe first.
    public static func parseWinterAlerts(_ data: Data) throws -> [WinterAlert] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            throw RoutingError.badResponse("Alert response was not readable")
        }
        let rank = ["Extreme": 0, "Severe": 1, "Moderate": 2, "Minor": 3]
        return features.compactMap { f -> WinterAlert? in
            guard let p = f["properties"] as? [String: Any], let event = p["event"] as? String else { return nil }
            let lower = event.lowercased()
            guard winterWords.contains(where: { lower.contains($0) }) else { return nil }
            return WinterAlert(event: event, severity: (p["severity"] as? String) ?? "Unknown",
                               headline: (p["headline"] as? String) ?? event,
                               onset: (p["onset"] as? String).flatMap(NWSParsing.parseDate),
                               ends: ((p["ends"] as? String) ?? (p["expires"] as? String)).flatMap(NWSParsing.parseDate))
        }
        .sorted { (rank[$0.severity] ?? 9, $0.event) < (rank[$1.severity] ?? 9, $1.event) }
    }
}

/// Fetches NWS data. Weather is requested for the depot rounded to about 1 km, not for customer addresses.
/// NWS asks apps to identify themselves: pass a User-Agent with your app name and a contact address.
public struct NWSClient: Sendable {
    public let client: HTTPClient
    public let userAgent: String
    public let baseURL: URL

    public init(client: HTTPClient = URLSessionHTTPClient(), userAgent: String,
                baseURL: URL = URL(string: "https://api.weather.gov")!) {
        self.client = client
        self.userAgent = userAgent
        self.baseURL = baseURL
    }

    static func rounded(_ c: Coordinate) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, status) = try await client.send(request)
        guard status == 200 else { throw RoutingError.badResponse("Weather service returned HTTP \(status)") }
        return data
    }

    public func forecast(near coordinate: Coordinate) async throws -> NWSForecast {
        let pointsURL = baseURL.appendingPathComponent("points/\(Self.rounded(coordinate))")
        let pointsData = try await get(pointsURL)
        guard let root = try? JSONSerialization.jsonObject(with: pointsData) as? [String: Any],
              let props = root["properties"] as? [String: Any],
              let gridString = props["forecastGridData"] as? String,
              let gridURL = URL(string: gridString) else {
            throw RoutingError.badResponse("Weather location lookup was not readable")
        }
        // Only follow links that stay on the weather service.
        guard gridURL.scheme == baseURL.scheme, gridURL.host == baseURL.host else {
            throw RoutingError.badResponse("Weather service sent an unexpected link")
        }
        return try NWSForecast(gridpointJSON: try await get(gridURL))
    }

    public func activeWinterAlerts(near coordinate: Coordinate) async throws -> [WinterAlert] {
        var c = URLComponents(url: baseURL.appendingPathComponent("alerts/active"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "point", value: Self.rounded(coordinate))]
        return try NWSAlerts.parseWinterAlerts(try await get(c.url!))
    }
}
