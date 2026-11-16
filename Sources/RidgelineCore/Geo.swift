import Foundation

public struct Coordinate: Equatable, Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    /// Great-circle distance in meters (haversine).
    public static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// Source of drive times. Swap in a traffic-aware provider (Valhalla, Google, Mapbox) later.
public protocol DriveTimeProvider: Sendable {
    func seconds(from: Coordinate, to: Coordinate) -> Double
}

/// Offline fallback: straight-line distance, a road factor and an average speed.
public struct HaversineDriveTime: DriveTimeProvider {
    public var averageMph: Double
    public var roadFactor: Double
    public init(averageMph: Double = 25, roadFactor: Double = 1.3) {
        self.averageMph = averageMph
        self.roadFactor = roadFactor
    }
    public func seconds(from: Coordinate, to: Coordinate) -> Double {
        let meters = Geo.distanceMeters(from, to) * roadFactor
        return meters / (averageMph * 0.44704)
    }
}

/// Slows any provider down for storm conditions. `speedFactor` 0.5 means twice as slow.
public struct StormAdjustedDriveTime: DriveTimeProvider {
    public let base: DriveTimeProvider
    public let speedFactor: Double
    public init(base: DriveTimeProvider, speedFactor: Double) {
        self.base = base
        self.speedFactor = max(speedFactor, 0.1)
    }
    public func seconds(from: Coordinate, to: Coordinate) -> Double {
        base.seconds(from: from, to: to) / speedFactor
    }
}
