import Foundation

public struct RoutePlanResult: Equatable, Sendable {
    public let planned: [PlannedStop]
    /// Stops whose estimated arrival is after their deadline.
    public let lateStopIDs: [UUID]
    public var totalDriveSeconds: Double { RouteSequencer.totalDriveSeconds(planned) }
    public var stops: [Stop] { planned.map(\.stop) }
}

/// Route ordering with these rules, in this order of importance:
/// 1. Stops in the frozen prefix never move (drivers are already committed).
/// 2. Priority tiers are strict: all priority-1 sites before priority 2, and so on.
/// 3. Inside a tier, order to minimise drive time: nearest-next, then 2-opt improvement.
/// Deadlines are checked and reported, not forced, so the dispatcher decides what to do about late stops.
public enum RouteOptimizer {
    /// - Parameter end: where the truck finishes (back at the yard, or another address). When set, the drive there counts
    ///   toward the cost, so the last tier ends near the finish. Nil keeps the old open-ended route.
    public static func optimize(stops: [Stop], start: Coordinate, frozenPrefix: Int = 0, provider: DriveTimeProvider,
                                serviceTimeFactor: Double = 1, maxPasses: Int = 50, end: Coordinate? = nil) -> RoutePlanResult {
        let frozenCount = min(max(frozenPrefix, 0), stops.count)
        var ordered = Array(stops.prefix(frozenCount))
        var here = ordered.last?.coordinate ?? start
        let rest = Array(stops.dropFirst(frozenCount))

        let tiers = Set(rest.map(\.priority)).sorted()
        for (n, tier) in tiers.enumerated() {
            let block = rest.filter { $0.priority == tier }
            let seq = nearestNext(block, from: here, provider: provider)
            // Only the last tier drives on to the finish.
            let improved = twoOpt(seq, from: here, provider: provider, maxPasses: maxPasses, end: n == tiers.count - 1 ? end : nil)
            ordered += improved
            here = improved.last?.coordinate ?? here
        }

        var scaled = ordered
        for i in scaled.indices { scaled[i].serviceMinutes *= max(serviceTimeFactor, 0) }
        let planned = RouteSequencer.plan(stops: scaled, start: start, provider: provider)
        let late = planned.filter { p in p.stop.deadlineSeconds.map { p.arrivalOffsetSeconds > $0 } ?? false }.map { $0.stop.id }
        // Return the original (unscaled) stop values, with timings that include the scaled service time.
        let restored = zip(planned, ordered).map { PlannedStop(stop: $1, driveSeconds: $0.driveSeconds, arrivalOffsetSeconds: $0.arrivalOffsetSeconds) }
        return RoutePlanResult(planned: restored, lateStopIDs: late)
    }

    /// Drive seconds from `start` through `stops` in order, plus the drive on to `end` when one is given.
    public static func pathCost(start: Coordinate, stops: [Stop], provider: DriveTimeProvider, end: Coordinate? = nil) -> Double {
        var cost = 0.0
        var here = start
        for s in stops {
            cost += provider.seconds(from: here, to: s.coordinate)
            here = s.coordinate
        }
        if let end, !stops.isEmpty { cost += provider.seconds(from: here, to: end) }
        return cost
    }

    static func nearestNext(_ block: [Stop], from start: Coordinate, provider: DriveTimeProvider) -> [Stop] {
        var remaining = block
        var out: [Stop] = []
        var here = start
        while !remaining.isEmpty {
            var bestIndex = 0
            var bestTime = Double.infinity
            for (i, s) in remaining.enumerated() {
                let t = provider.seconds(from: here, to: s.coordinate)
                if t < bestTime { bestTime = t; bestIndex = i }
            }
            let next = remaining.remove(at: bestIndex)
            out.append(next)
            here = next.coordinate
        }
        return out
    }

    /// Reverses segments while that shortens the open path from a fixed start. Never makes a route longer.
    /// With an `end`, the drive to the finish is part of the cost, so even two stops can swap.
    static func twoOpt(_ seq: [Stop], from start: Coordinate, provider: DriveTimeProvider, maxPasses: Int, end: Coordinate? = nil) -> [Stop] {
        guard seq.count >= (end == nil ? 3 : 2) else { return seq }
        var best = seq
        var bestCost = pathCost(start: start, stops: best, provider: provider, end: end)
        var pass = 0
        var improved = true
        while improved && pass < maxPasses {
            improved = false
            pass += 1
            for i in 0..<(best.count - 1) {
                for j in (i + 1)..<best.count {
                    var candidate = best
                    candidate[i...j].reverse()
                    let c = pathCost(start: start, stops: candidate, provider: provider, end: end)
                    if c < bestCost - 1e-9 {
                        best = candidate
                        bestCost = c
                        improved = true
                    }
                }
            }
        }
        return best
    }

    /// Splits stops across crews: sweep around the depot, then cut into groups with roughly equal work.
    public static func assignToCrews(stops: [Stop], depot: Coordinate, crewCount: Int) -> [[Stop]] {
        let k = max(crewCount, 1)
        guard !stops.isEmpty else { return Array(repeating: [], count: k) }
        let sorted = stops.sorted {
            let a = angle($0.coordinate, depot), b = angle($1.coordinate, depot)
            if a != b { return a < b }
            return ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString)
        }
        let work = sorted.map { $0.serviceMinutes + 1 }
        let total = work.reduce(0, +)
        var groups = [[Stop]](repeating: [], count: k)
        var before = 0.0
        for (stop, w) in zip(sorted, work) {
            let g = min(k - 1, Int(((before + w / 2) / total) * Double(k)))
            groups[g].append(stop)
            before += w
        }
        return groups
    }

    private static func angle(_ c: Coordinate, _ depot: Coordinate) -> Double {
        let dx = (c.longitude - depot.longitude) * cos(depot.latitude * .pi / 180)
        let dy = c.latitude - depot.latitude
        return atan2(dy, dx)
    }
}

/// Live ETA for a single leg, for example Apple MapKit on the device. Used to refresh only the next few legs.
public protocol ETASource: Sendable {
    func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double
}

public enum LegRefiner {
    /// ETAs for the first `count` legs of a route. A failed leg is `nil` so the caller keeps its estimate.
    public static func refine(stops: [Stop], start: Coordinate, count: Int, source: ETASource) async -> [Double?] {
        var out: [Double?] = []
        var here = start
        for s in stops.prefix(max(count, 0)) {
            out.append(try? await source.etaSeconds(from: here, to: s.coordinate))
            here = s.coordinate
        }
        return out
    }
}

/// The whole pipeline: drive times from the best available source, adjusted for weather and for what
/// your trucks actually did, then ordered by the optimizer.
public struct RoutePlanner: Sendable {
    public var matrixSource: MatrixSource
    public var model: ConditionsModel

    public init(matrixSource: MatrixSource = ProviderMatrixSource(), model: ConditionsModel = ConditionsModel()) {
        self.matrixSource = matrixSource
        self.model = model
    }

    /// - Parameters:
    ///   - observedSpeedFactor: from `SpeedCalibrator.observedFactor`, blended into the model's guess.
    ///   - end: where the route finishes, if it matters (see `RouteOptimizer.optimize`).
    public func plan(stops: [Stop], start: Coordinate, conditions: WeatherConditions = .clear, frozenPrefix: Int = 0,
                     observedSpeedFactor: Double? = nil, end: Coordinate? = nil) async -> RoutePlanResult {
        var points = [start] + stops.map(\.coordinate)
        if let end, end != start { points.append(end) }
        let provider = await driveTimes(for: points, conditions: conditions, observedSpeedFactor: observedSpeedFactor)
        return RouteOptimizer.optimize(stops: stops, start: start, frozenPrefix: frozenPrefix, provider: provider,
                                       serviceTimeFactor: model.serviceTimeFactor(conditions), end: end)
    }

    /// Drive times between `points` (yard first) from the best available source, adjusted for weather. Pairs outside
    /// `points` fall back to the offline estimate, so the result can also time a route the user reorders by hand.
    public func driveTimes(for points: [Coordinate], conditions: WeatherConditions = .clear,
                           observedSpeedFactor: Double? = nil) async -> DriveTimeProvider {
        let matrix = (try? await matrixSource.matrix(for: points))
            ?? DriveTimeMatrix(points: points, seconds: points.map { a in points.map { b in a == b ? 0 : HaversineDriveTime().seconds(from: a, to: b) } })
        let speed = SpeedCalibrator.blend(model: model.speedFactor(conditions), observed: observedSpeedFactor)
        return StormAdjustedDriveTime(base: MatrixProvider(matrix: matrix), speedFactor: speed)
    }
}
