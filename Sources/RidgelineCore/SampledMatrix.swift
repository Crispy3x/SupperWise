import Foundation

/// Counts what a sampled matrix actually measured, so the app can say so plainly.
public struct SampledReport: Equatable, Sendable {
    /// Pairs the maps service answered.
    public var measured: Int
    /// Pairs asked for.
    public var attempted: Int
    /// All pairs in the matrix (the rest are estimated).
    public var totalPairs: Int
    /// How much slower (above 1) or faster (below 1) the measured drives were than the straight-line estimate.
    public var scale: Double
    /// True when it stopped asking because the service kept failing (for example throttling).
    public var stoppedEarly: Bool
}

/// Builds a full drive-time matrix from a service that can only answer one leg at a time (Apple MapKit).
///
/// A full matrix of n points needs about n squared requests, which would be throttled. So this asks only for the
/// legs that matter most: from the yard to every stop, and from each stop to its few nearest neighbours. It then
/// scales the straight-line estimate for every other pair by how the measured legs compared. If the service starts
/// failing it stops asking and finishes with estimates, so planning never breaks.
public struct SampledMatrixSource: MatrixSource {
    public let etaSource: ETASource
    public let neighbors: Int
    public let maxMeasurements: Int
    public let concurrency: Int
    public let pauseSeconds: Double
    public let maxFailedChunks: Int
    public let fallback: DriveTimeProvider
    public let onReport: (@Sendable (SampledReport) -> Void)?

    public init(etaSource: ETASource, neighbors: Int = 3, maxMeasurements: Int = 150, concurrency: Int = 3,
                pauseSeconds: Double = 0.2, maxFailedChunks: Int = 2, fallback: DriveTimeProvider = HaversineDriveTime(),
                onReport: (@Sendable (SampledReport) -> Void)? = nil) {
        self.etaSource = etaSource
        self.neighbors = max(neighbors, 0)
        self.maxMeasurements = max(maxMeasurements, 0)
        self.concurrency = max(concurrency, 1)
        self.pauseSeconds = max(pauseSeconds, 0)
        self.maxFailedChunks = max(maxFailedChunks, 1)
        self.fallback = fallback
        self.onReport = onReport
    }

    /// The pairs to measure, most useful first: yard to every stop, then each stop to its nearest neighbours.
    static func pairsToMeasure(points: [Coordinate], estimate: [[Double]], neighbors: Int, limit: Int) -> [(Int, Int)] {
        let n = points.count
        var seen = Set<Int>()
        var out: [(Int, Int)] = []
        func add(_ i: Int, _ j: Int) {
            guard i != j, seen.insert(i * n + j).inserted else { return }
            out.append((i, j))
        }
        for j in 1..<max(n, 1) { add(0, j) }
        var near: [(Double, Int, Int)] = []
        for i in 0..<n {
            let order = (0..<n).filter { $0 != i }.sorted { (estimate[i][$0], $0) < (estimate[i][$1], $1) }
            for j in order.prefix(neighbors) { near.append((estimate[i][j], i, j)) }
        }
        for (_, i, j) in near.sorted(by: { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }) { add(i, j) }
        return Array(out.prefix(limit))
    }

    public func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        let n = points.count
        guard n >= 2 else { return DriveTimeMatrix(points: points, seconds: points.map { _ in [0.0] }) }
        let estimate = points.map { a in points.map { b in a == b ? 0 : fallback.seconds(from: a, to: b) } }
        let pairs = Self.pairsToMeasure(points: points, estimate: estimate, neighbors: neighbors, limit: maxMeasurements)

        var measured: [Int: Double] = [:]
        var failedChunks = 0
        var attempted = 0
        var stoppedEarly = false
        var index = 0
        while index < pairs.count {
            if Task.isCancelled { stoppedEarly = true; break }       // the caller moved on, so stop spending requests
            let chunk = Array(pairs[index..<min(index + concurrency, pairs.count)])
            index += chunk.count
            attempted += chunk.count
            let results = await withTaskGroup(of: (Int, Double?).self) { group -> [(Int, Double?)] in
                for (i, j) in chunk {
                    group.addTask {
                        let v = try? await etaSource.etaSeconds(from: points[i], to: points[j])
                        return (i * n + j, v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
                    }
                }
                var all: [(Int, Double?)] = []
                for await r in group { all.append(r) }
                return all
            }
            var anyOK = false
            for (key, value) in results { if let value { measured[key] = value; anyOK = true } }
            if anyOK { failedChunks = 0 } else { failedChunks += 1 }
            if failedChunks >= maxFailedChunks { stoppedEarly = true; break }
            if pauseSeconds > 0, index < pairs.count { try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000)) }
        }

        let ratios = measured.compactMap { key, value -> Double? in
            let e = estimate[key / n][key % n]
            return e > 0 ? value / e : nil
        }.sorted()
        var scale = 1.0
        if !ratios.isEmpty {
            let mid = ratios.count / 2
            scale = min(max(ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2, 0.3), 5)
        }
        let seconds = (0..<n).map { i in
            (0..<n).map { j -> Double in
                if i == j { return 0 }
                return measured[i * n + j] ?? estimate[i][j] * scale
            }
        }
        onReport?(SampledReport(measured: measured.count, attempted: attempted, totalPairs: n * (n - 1), scale: scale, stoppedEarly: stoppedEarly))
        return DriveTimeMatrix(points: points, seconds: seconds)
    }
}

/// Remembers answers for a short time, in memory only. Apple's terms allow Map Data to be kept only on a
/// temporary and limited basis, so nothing is written to disk and entries expire quickly. Planning again after
/// only the weather changed then costs no new requests.
public final class CachedETASource: ETASource, @unchecked Sendable {
    private struct Key: Hashable { let a: Coordinate; let b: Coordinate }
    private let base: ETASource
    private let ttl: TimeInterval
    private let maxEntries: Int
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var store: [Key: (value: Double, at: Date)] = [:]

    public init(base: ETASource, ttl: TimeInterval = 600, maxEntries: Int = 2000, now: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.ttl = ttl
        self.maxEntries = maxEntries
        self.now = now
    }

    private func rounded(_ c: Coordinate) -> Coordinate {
        Coordinate(latitude: (c.latitude * 100_000).rounded() / 100_000, longitude: (c.longitude * 100_000).rounded() / 100_000)
    }

    // Locking lives in plain (non-async) helpers so it never spans an await.
    private func lookup(_ key: Key, at t: Date) -> Double? {
        lock.lock(); defer { lock.unlock() }
        if let hit = store[key], t.timeIntervalSince(hit.at) < ttl { return hit.value }
        return nil
    }

    private func insert(_ value: Double, for key: Key, at t: Date) {
        lock.lock(); defer { lock.unlock() }
        if store.count >= maxEntries { store = store.filter { t.timeIntervalSince($0.value.at) < ttl } }
        if store.count >= maxEntries { store.removeAll() }
        store[key] = (value, t)
    }

    public func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double {
        let key = Key(a: rounded(from), b: rounded(to))
        let t = now()
        if let cached = lookup(key, at: t) { return cached }
        let value = try await base.etaSeconds(from: from, to: to)
        insert(value, for: key, at: t)
        return value
    }

    /// Forgets everything (for example when the app goes to the background).
    public func clear() { lock.lock(); store.removeAll(); lock.unlock() }
}

public enum RoutingProvider: String, Codable, CaseIterable, Sendable {
    /// Apple Maps on this device (free, no key).
    case appleMaps
    /// The routing server that uses Google (needs setup and costs money).
    case server
    /// Straight-line estimates only.
    case offline
}
