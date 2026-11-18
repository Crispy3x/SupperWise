import XCTest
@testable import RidgelineCore

/// A fake maps service: the true drive time is `factor` times the straight-line estimate, and it counts requests.
private final class FakeMaps: ETASource, @unchecked Sendable {
    let factor: Double
    var failAfter: Int?
    var alwaysFail = false
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    init(factor: Double) { self.factor = factor }

    func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double {
        lock.lock(); count += 1; let n = count; lock.unlock()
        if alwaysFail { throw RoutingError.badResponse("throttled") }
        if let failAfter, n > failAfter { throw RoutingError.badResponse("throttled") }
        return HaversineDriveTime().seconds(from: from, to: to) * factor
    }
}

private final class ReportBox: @unchecked Sendable {
    var report: SampledReport?
}

final class SampledMatrixTests: XCTestCase {
    private func points(_ n: Int) -> [Coordinate] {
        (0..<n).map { Coordinate(latitude: 45 + Double($0 % 5) * 0.01, longitude: -93 + Double($0 / 5) * 0.012) }
    }

    func testMeasuredPairsAreUsedAndOthersScaledByTheObservedRatio() async throws {
        let maps = FakeMaps(factor: 2)
        let pts = points(12)
        let source = SampledMatrixSource(etaSource: maps, neighbors: 2, pauseSeconds: 0)
        let m = try await source.matrix(for: pts)
        XCTAssertTrue(m.isValid)
        let est = HaversineDriveTime()
        // Because the fake is exactly 2x the estimate, measured and scaled pairs agree everywhere.
        for i in 0..<pts.count { for j in 0..<pts.count where i != j {
            XCTAssertEqual(m.seconds[i][j], est.seconds(from: pts[i], to: pts[j]) * 2, accuracy: 0.01)
        } }
        XCTAssertEqual(m.seconds[3][3], 0)
    }

    func testRequestCountIsFarBelowAFullMatrixAndRespectsTheCap() async throws {
        let maps = FakeMaps(factor: 1.5)
        let n = 25
        let m = try await SampledMatrixSource(etaSource: maps, neighbors: 3, maxMeasurements: 80, pauseSeconds: 0).matrix(for: points(n))
        XCTAssertTrue(m.isValid)
        XCTAssertLessThanOrEqual(maps.calls, 80)
        XCTAssertLessThan(maps.calls, n * (n - 1) / 4)       // far fewer than the 600 a full matrix would need
        let uncapped = FakeMaps(factor: 1.5)
        _ = try await SampledMatrixSource(etaSource: uncapped, neighbors: 3, maxMeasurements: 10_000, pauseSeconds: 0).matrix(for: points(n))
        XCTAssertLessThanOrEqual(uncapped.calls, (n - 1) + n * 3)   // yard to each stop, plus 3 neighbours each
    }

    func testYardToEveryStopIsMeasuredFirst() async throws {
        let pts = points(8)
        let est = pts.map { a in pts.map { b in a == b ? 0 : HaversineDriveTime().seconds(from: a, to: b) } }
        let pairs = SampledMatrixSource.pairsToMeasure(points: pts, estimate: est, neighbors: 2, limit: 100)
        XCTAssertEqual(Array(pairs.prefix(7)).map { $0.1 }, Array(1..<8))
        XCTAssertTrue(pairs.prefix(7).allSatisfy { $0.0 == 0 })
        XCTAssertEqual(Set(pairs.map { $0.0 * 8 + $0.1 }).count, pairs.count)     // no pair twice
        XCTAssertTrue(SampledMatrixSource.pairsToMeasure(points: pts, estimate: est, neighbors: 2, limit: 3).count == 3)
    }

    func testThrottlingStopsAskingAndFinishesWithEstimates() async throws {
        let maps = FakeMaps(factor: 3)
        maps.alwaysFail = true
        let box = ReportBox()
        let source = SampledMatrixSource(etaSource: maps, neighbors: 3, concurrency: 2, pauseSeconds: 0, maxFailedChunks: 2,
                                         onReport: { box.report = $0 })
        let pts = points(20)
        let m = try await source.matrix(for: pts)
        XCTAssertTrue(m.isValid)
        XCTAssertEqual(maps.calls, 4)                          // two failed chunks of two, then it gave up
        XCTAssertEqual(box.report?.stoppedEarly, true)
        XCTAssertEqual(box.report?.measured, 0)
        XCTAssertEqual(m.seconds[0][1], HaversineDriveTime().seconds(from: pts[0], to: pts[1]), accuracy: 0.01)   // pure estimate
    }

    func testPartialFailureKeepsWhatWasMeasured() async throws {
        let maps = FakeMaps(factor: 2)
        maps.failAfter = 10
        let box = ReportBox()
        let m = try await SampledMatrixSource(etaSource: maps, neighbors: 3, concurrency: 1, pauseSeconds: 0, maxFailedChunks: 3,
                                              onReport: { box.report = $0 }).matrix(for: points(15))
        XCTAssertTrue(m.isValid)
        XCTAssertEqual(box.report?.measured, 10)
        XCTAssertEqual(box.report?.stoppedEarly, true)
        XCTAssertEqual(box.report!.scale, 2, accuracy: 0.001)      // still learned the 2x from what it did measure
    }

    func testReportAndEdgeCases() async throws {
        let maps = FakeMaps(factor: 1)
        let box = ReportBox()
        let m = try await SampledMatrixSource(etaSource: maps, neighbors: 1, pauseSeconds: 0, onReport: { box.report = $0 }).matrix(for: points(4))
        XCTAssertEqual(box.report?.totalPairs, 12)
        XCTAssertEqual(box.report?.stoppedEarly, false)
        XCTAssertTrue(m.isValid)
        let one = try await SampledMatrixSource(etaSource: maps).matrix(for: points(1))
        XCTAssertEqual(one.seconds, [[0]])
        let none = try await SampledMatrixSource(etaSource: maps).matrix(for: [])
        XCTAssertTrue(none.seconds.isEmpty)
    }

    func testBadAnswersAreIgnored() async throws {
        struct Junk: ETASource { func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double { .nan } }
        let m = try await SampledMatrixSource(etaSource: Junk(), pauseSeconds: 0).matrix(for: points(6))
        XCTAssertTrue(m.isValid)
    }

    func testPlannerWorksThroughTheSampledSource() async {
        let maps = FakeMaps(factor: 2)
        let planner = RoutePlanner(matrixSource: SampledMatrixSource(etaSource: maps, neighbors: 2, pauseSeconds: 0))
        let pts = points(6)
        let stops = pts.dropFirst().map { Stop(id: UUID(), name: "s", coordinate: $0, priority: 1, serviceMinutes: 0) }
        let slow = await planner.plan(stops: Array(stops), start: pts[0], conditions: .clear)
        let fast = await RoutePlanner(matrixSource: SampledMatrixSource(etaSource: FakeMaps(factor: 1), neighbors: 2, pauseSeconds: 0))
            .plan(stops: Array(stops), start: pts[0], conditions: .clear)
        XCTAssertEqual(slow.stops.count, 5)
        XCTAssertGreaterThan(slow.totalDriveSeconds, fast.totalDriveSeconds)
    }
}

final class SampledCancellationTests: XCTestCase {
    private final class SlowMaps: ETASource, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        private func bump() { lock.lock(); count += 1; lock.unlock() }
        func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double {
            bump()
            try? await Task.sleep(nanoseconds: 20_000_000)
            return 100
        }
    }

    func testCancelledPlanningStopsAskingAppleEarly() async {
        let maps = SlowMaps()
        let pts = (0..<20).map { Coordinate(latitude: 45 + Double($0) * 0.01, longitude: -93) }
        let source = SampledMatrixSource(etaSource: maps, neighbors: 3, maxMeasurements: 150, concurrency: 2, pauseSeconds: 0)
        let task = Task { try await source.matrix(for: pts) }
        try? await Task.sleep(nanoseconds: 70_000_000)
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(maps.calls, 30)         // without the check it would run on to about 80 requests
    }
}

final class CachedETATests: XCTestCase {
    func testSecondAskIsFreeUntilItExpires() async throws {
        let maps = FakeMaps(factor: 1)
        let clock = ClockBox()
        let cache = CachedETASource(base: maps, ttl: 600, now: { clock.now })
        let a = Coordinate(latitude: 45, longitude: -93), b = Coordinate(latitude: 45.01, longitude: -93)
        let first = try await cache.etaSeconds(from: a, to: b)
        let second = try await cache.etaSeconds(from: a, to: b)
        XCTAssertEqual(first, second)
        XCTAssertEqual(maps.calls, 1)
        _ = try await cache.etaSeconds(from: b, to: a)               // other direction is a different leg
        XCTAssertEqual(maps.calls, 2)
        clock.advance(601)
        _ = try await cache.etaSeconds(from: a, to: b)
        XCTAssertEqual(maps.calls, 3)                                // expired, asked again
        cache.clear()
        _ = try await cache.etaSeconds(from: a, to: b)
        XCTAssertEqual(maps.calls, 4)
    }

    func testFailuresAreNotRemembered() async throws {
        let maps = FakeMaps(factor: 1)
        maps.alwaysFail = true
        let cache = CachedETASource(base: maps)
        let a = Coordinate(latitude: 1, longitude: 1), b = Coordinate(latitude: 2, longitude: 2)
        do { _ = try await cache.etaSeconds(from: a, to: b); XCTFail() } catch {}
        maps.alwaysFail = false
        _ = try await cache.etaSeconds(from: a, to: b)
        XCTAssertEqual(maps.calls, 2)
    }

    func testCacheSizeIsBounded() async throws {
        let maps = FakeMaps(factor: 1)
        let cache = CachedETASource(base: maps, maxEntries: 5)
        for i in 0..<20 {
            _ = try await cache.etaSeconds(from: Coordinate(latitude: Double(i), longitude: 0), to: Coordinate(latitude: Double(i) + 0.5, longitude: 0))
        }
        XCTAssertEqual(maps.calls, 20)       // still correct, and it did not grow without limit
    }
}

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ s: TimeInterval) { lock.lock(); date = date.addingTimeInterval(s); lock.unlock() }
}
