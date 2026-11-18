import Foundation

/// Hand-off to Apple Maps or Google Maps for turn-by-turn. Our app decides the order; the maps app navigates.
public enum NavigationLinks {
    /// One leg in Apple Maps (the driver's "next stop"). Apple Maps links reliably take one destination.
    public static func appleMaps(to destination: Coordinate, from origin: Coordinate? = nil) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        var items: [URLQueryItem] = []
        if let o = origin { items.append(URLQueryItem(name: "saddr", value: "\(o.latitude),\(o.longitude)")) }
        items.append(URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"))
        items.append(URLQueryItem(name: "dirflg", value: "d"))
        c?.queryItems = items
        return c?.url
    }

    /// Whole route in Google Maps. A link holds a limited number of waypoints (about 9), so long routes become
    /// several links, each starting where the last ended.
    public static func googleMaps(stops: [Coordinate], origin: Coordinate? = nil, maxWaypoints: Int = 9) -> [URL] {
        guard !stops.isEmpty else { return [] }
        let perLink = max(maxWaypoints, 0) + 1   // waypoints plus the destination
        var urls: [URL] = []
        var start = origin
        var index = 0
        while index < stops.count {
            let chunk = Array(stops[index..<min(index + perLink, stops.count)])
            var c = URLComponents(string: "https://www.google.com/maps/dir/")!
            var items = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "travelmode", value: "driving")]
            if let s = start { items.append(URLQueryItem(name: "origin", value: "\(s.latitude),\(s.longitude)")) }
            let dest = chunk.last!
            items.append(URLQueryItem(name: "destination", value: "\(dest.latitude),\(dest.longitude)"))
            let waypoints = chunk.dropLast().map { "\($0.latitude),\($0.longitude)" }
            if !waypoints.isEmpty { items.append(URLQueryItem(name: "waypoints", value: waypoints.joined(separator: "|"))) }
            c.queryItems = items
            if let url = c.url { urls.append(url) }
            start = dest
            index += perLink
        }
        return urls
    }
}
