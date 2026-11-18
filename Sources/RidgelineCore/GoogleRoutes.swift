import Foundation

/// Request and response handling for Google's Routes API "computeRouteMatrix" (traffic-aware drive times).
///
/// The API key must NOT be inside the app. Call this through your own small server that holds the key, adds
/// the headers below, enforces limits and caches. This file only builds requests and reads responses.
/// Check the current Routes API docs for element limits and Google's terms on caching and on showing results
/// next to a non-Google map before shipping.
public enum GoogleRoutesMatrix {
    public static let endpoint = URL(string: "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix")!
    /// Value for the X-Goog-FieldMask header: only ask for what is used, to keep the price down.
    public static let fieldMask = "originIndex,destinationIndex,duration,condition"
    /// Typical per-request element limit for traffic-aware matrices. Confirm against current documentation.
    public static let defaultMaxElements = 625

    public static func requestBody(origins: [Coordinate], destinations: [Coordinate], departureTime: Date? = nil) throws -> Data {
        func waypoint(_ c: Coordinate) -> [String: Any] {
            ["waypoint": ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]]
        }
        var body: [String: Any] = [
            "origins": origins.map(waypoint),
            "destinations": destinations.map(waypoint),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
        ]
        if let departureTime {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            body["departureTime"] = f.string(from: departureTime)
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Reads the response into seconds[origin][destination]. A missing route is `nil`.
    public static func parse(_ data: Data, originCount: Int, destinationCount: Int) throws -> [[Double?]] {
        guard let raw = try? JSONSerialization.jsonObject(with: data), let items = raw as? [[String: Any]] else {
            throw RoutingError.badResponse("Expected a JSON array of matrix elements")
        }
        var out = [[Double?]](repeating: [Double?](repeating: nil, count: destinationCount), count: originCount)
        for item in items {
            guard let o = item["originIndex"] as? Int, let d = item["destinationIndex"] as? Int,
                  (0..<originCount).contains(o), (0..<destinationCount).contains(d) else {
                throw RoutingError.badResponse("Element index out of range")
            }
            if (item["condition"] as? String) == "ROUTE_NOT_FOUND" { continue }
            if let text = item["duration"] as? String, text.hasSuffix("s"), let secs = Double(text.dropLast()) {
                out[o][d] = secs
            }
        }
        return out
    }

    /// Combines block results into one full matrix. Pairs the API could not route are filled from `fallback`.
    public static func assemble(points: [Coordinate], blocks: [(MatrixChunker.Block, [[Double?]])],
                                fallback: DriveTimeProvider = HaversineDriveTime()) -> DriveTimeMatrix {
        let n = points.count
        var grid = [[Double?]](repeating: [Double?](repeating: nil, count: n), count: n)
        for (block, values) in blocks {
            for (oi, row) in values.enumerated() {
                for (di, v) in row.enumerated() {
                    let o = block.origins.lowerBound + oi
                    let d = block.destinations.lowerBound + di
                    if o < n, d < n { grid[o][d] = v }
                }
            }
        }
        let seconds = (0..<n).map { o in
            (0..<n).map { d -> Double in
                if o == d { return 0 }
                return grid[o][d] ?? fallback.seconds(from: points[o], to: points[d])
            }
        }
        return DriveTimeMatrix(points: points, seconds: seconds)
    }
}
