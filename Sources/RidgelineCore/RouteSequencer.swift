import Foundation

public struct Stop: Identifiable, Equatable, Sendable {
    /// The site id.
    public let id: UUID
    public var name: String
    public var coordinate: Coordinate
    /// 1 = most important. All priority-1 stops are served before priority 2, and so on.
    public var priority: Int
    public var serviceMinutes: Double
    /// Latest acceptable arrival, in seconds after the route starts (for example a clinic open at 6am).
    public var deadlineSeconds: Double?

    public init(id: UUID, name: String, coordinate: Coordinate, priority: Int = 3, serviceMinutes: Double = 10,
                deadlineSeconds: Double? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.priority = priority
        self.serviceMinutes = serviceMinutes
        self.deadlineSeconds = deadlineSeconds
    }
}

public struct PlannedStop: Equatable, Sendable {
    public let stop: Stop
    public let driveSeconds: Double
    /// Seconds after route start that the crew arrives.
    public let arrivalOffsetSeconds: Double
}

/// Dispatcher-controlled re-sequencing, not an autopilot: the dispatcher decides how many upcoming
/// stops are frozen, priorities are strict, and the result is deterministic.
public enum RouteSequencer {
    /// - Parameters:
    ///   - frozenPrefix: the first N stops keep their order (drivers already committed to them).
    ///   - start: where the truck is now, used before the first non-frozen stop.
    public static func resequence(stops: [Stop], start: Coordinate, frozenPrefix: Int = 0,
                                  provider: DriveTimeProvider) -> [Stop] {
        let frozenCount = min(max(frozenPrefix, 0), stops.count)
        var result = Array(stops.prefix(frozenCount))
        var remaining = Array(stops.dropFirst(frozenCount))
        var here = result.last?.coordinate ?? start

        while let best = remaining.map(\.priority).min() {
            var bestIndex = 0
            var bestTime = Double.infinity
            for (i, s) in remaining.enumerated() where s.priority == best {
                let t = provider.seconds(from: here, to: s.coordinate)
                if t < bestTime {
                    bestTime = t
                    bestIndex = i
                }
            }
            let chosen = remaining.remove(at: bestIndex)
            result.append(chosen)
            here = chosen.coordinate
        }
        return result
    }

    /// ETA offsets for a route in the given order.
    public static func plan(stops: [Stop], start: Coordinate, provider: DriveTimeProvider) -> [PlannedStop] {
        var out: [PlannedStop] = []
        var here = start
        var clock = 0.0
        for s in stops {
            let drive = provider.seconds(from: here, to: s.coordinate)
            clock += drive
            out.append(PlannedStop(stop: s, driveSeconds: drive, arrivalOffsetSeconds: clock))
            clock += s.serviceMinutes * 60
            here = s.coordinate
        }
        return out
    }

    public static func totalDriveSeconds(_ planned: [PlannedStop]) -> Double {
        planned.reduce(0) { $0 + $1.driveSeconds }
    }
}
