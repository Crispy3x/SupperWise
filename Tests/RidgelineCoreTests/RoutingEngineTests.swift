import XCTest
@testable import RidgelineCore

/// Simple 1-D world: time is the longitude difference x 1000, so expected values are easy to check by hand.
private struct LineProvider: DriveTimeProvider {
    func seconds(from: Coordinate, to: Coordinate) -> Double { abs(from.longitude - to.longitude) * 1000 }
}

private func stop(_ name: String, _ lon: Double, priority: Int = 3, service: Double = 10, deadline: Double? = nil) -> Stop {
    Stop(id: UUID(), name: name, coordinate: Coordinate(latitude: 0, longitude: lon), priority: priority,
         serviceMinutes: service, deadlineSeconds: deadline)
}

final class RouteOptimizerTests: XCTestCase {
    private let start = Coordinate(latitude: 0, longitude: 5)

    func testTwoOptBeatsNearestNext() {
        let stops = [stop("4", 4), stop("6", 6), stop("0", 0), stop("10", 10)]
        let nn = RouteOptimizer.nearestNext(stops, from: start, provider: LineProvider())
        let nnCost = RouteOptimizer.pathCost(start: start, stops: nn, provider: LineProvider())
        XCTAssertEqual(nnCost, 17_000, accuracy: 0.001)
        let result = RouteOptimizer.optimize(stops: stops, start: start, provider: LineProvider())
        XCTAssertEqual(result.totalDriveSeconds, 15_000, accuracy: 0.001)
        XCTAssertLessThan(result.totalDriveSeconds, nnCost)
    }

    func testOptimizerNeverWorseThanNearestNextOnRandomInstances() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let stops = (0..<12).map { i in stop("s\(i)", Double.random(in: 0...100, using: &rng)) }
            let nn = RouteOptimizer.nearestNext(stops, from: start, provider: LineProvider())
            let opt = RouteOptimizer.optimize(stops: stops, start: start, provider: LineProvider())
            XCTAssertLessThanOrEqual(opt.totalDriveSeconds,
                                     RouteOptimizer.pathCost(start: start, stops: nn, provider: LineProvider()) + 1e-6)
            XCTAssertEqual(Set(opt.stops.map(\.id)), Set(stops.map(\.id)))
        }
    }

    func testPriorityTiersStayStrict() {
        let stops = [stop("low-near", 5.1, priority: 3), stop("hi-far", 50, priority: 1),
                     stop("mid", 20, priority: 2), stop("hi-far2", 48, priority: 1)]
        let result = RouteOptimizer.optimize(stops: stops, start: start, provider: LineProvider())
        XCTAssertEqual(result.stops.map(\.priority), [1, 1, 2, 3])
    }

    func testFrozenPrefixKeepsOrderAndStart() {
        let a = stop("a", 90), b = stop("b", 80), c = stop("c", 1), d = stop("d", 2)
        let result = RouteOptimizer.optimize(stops: [a, b, c, d], start: start, frozenPrefix: 2, provider: LineProvider())
        XCTAssertEqual(Array(result.stops.prefix(2)).map(\.name), ["a", "b"])
        XCTAssertEqual(result.stops.map(\.name), ["a", "b", "d", "c"])
    }

    func testDeadlinesReportedNotForced() {
        // Starts at 5; stop at 15 is 10,000 s away. Deadline 5,000 s cannot be met.
        let late = stop("late", 15, deadline: 5_000)
        let ok = stop("ok", 6, deadline: 5_000)
        let result = RouteOptimizer.optimize(stops: [late, ok], start: start, provider: LineProvider())
        XCTAssertEqual(result.lateStopIDs, [late.id])
        XCTAssertEqual(result.stops.count, 2)
    }

    func testServiceTimeFactorDelaysLaterArrivals() {
        let stops = [stop("a", 6, service: 10), stop("b", 7, service: 10)]
        let normal = RouteOptimizer.optimize(stops: stops, start: start, provider: LineProvider(), serviceTimeFactor: 1)
        let snowy = RouteOptimizer.optimize(stops: stops, start: start, provider: LineProvider(), serviceTimeFactor: 2)
        XCTAssertEqual(snowy.planned[1].arrivalOffsetSeconds - normal.planned[1].arrivalOffsetSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(snowy.stops.first?.serviceMinutes, 10)   // original stop values are returned
    }

    func testEmptyAndSingleStop() {
        XCTAssertTrue(RouteOptimizer.optimize(stops: [], start: start, provider: LineProvider()).planned.isEmpty)
        XCTAssertEqual(RouteOptimizer.optimize(stops: [stop("x", 9)], start: start, provider: LineProvider()).planned.count, 1)
    }

    func testCrewAssignmentCoversEveryStopOnceAndBalances() {
        let depot = Coordinate(latitude: 45, longitude: -93)
        let stops = (0..<30).map { i -> Stop in
            let a = Double(i) / 30 * 2 * Double.pi
            return Stop(id: UUID(), name: "s\(i)", coordinate: Coordinate(latitude: 45 + 0.05 * sin(a), longitude: -93 + 0.05 * cos(a)),
                        serviceMinutes: 10)
        }
        let groups = RouteOptimizer.assignToCrews(stops: stops, depot: depot, crewCount: 3)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.flatMap { $0 }.count, 30)
        XCTAssertEqual(Set(groups.flatMap { $0 }.map(\.id)).count, 30)
        for g in groups { XCTAssertEqual(g.count, 10) }
    }

    func testCrewAssignmentEdgeCases() {
        let depot = Coordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(RouteOptimizer.assignToCrews(stops: [], depot: depot, crewCount: 2).count, 2)
        let one = [stop("x", 1)]
        XCTAssertEqual(RouteOptimizer.assignToCrews(stops: one, depot: depot, crewCount: 0).flatMap { $0 }.count, 1)
        XCTAssertEqual(RouteOptimizer.assignToCrews(stops: one, depot: depot, crewCount: 5).flatMap { $0 }.count, 1)
    }
}

final class ConditionsTests: XCTestCase {
    func testClearWeatherIsNeutral() {
        let m = ConditionsModel()
        XCTAssertEqual(m.speedFactor(.clear), 1, accuracy: 1e-9)
        XCTAssertEqual(m.serviceTimeFactor(.clear), 1, accuracy: 1e-9)
    }

    func testMoreSnowIsSlowerAndLongerButBounded() {
        let m = ConditionsModel()
        var lastSpeed = 2.0
        var lastService = 0.0
        for inches in stride(from: 0.0, through: 40.0, by: 2.0) {
            let c = WeatherConditions(snowfallRateInPerHour: 1.5, accumulationInches: inches, temperatureF: 20, windMph: 30, visibilityMiles: 0.5)
            let s = m.speedFactor(c), t = m.serviceTimeFactor(c)
            XCTAssertLessThanOrEqual(s, lastSpeed)
            XCTAssertGreaterThanOrEqual(t, lastService)
            XCTAssertGreaterThanOrEqual(s, m.minSpeedFactor)
            XCTAssertLessThanOrEqual(t, m.maxServiceTimeFactor)
            lastSpeed = s; lastService = t
        }
        XCTAssertEqual(lastSpeed, m.minSpeedFactor, accuracy: 1e-9)
    }

    func testKnownScenario() {
        // 4 in on the ground, falling 0.5 in/hr at 30F (icy band), light wind, good visibility.
        let c = WeatherConditions(snowfallRateInPerHour: 0.5, accumulationInches: 4, temperatureF: 30, windMph: 10)
        XCTAssertEqual(ConditionsModel().speedFactor(c), 1 - (0.14 + 0.08), accuracy: 1e-9)
        XCTAssertEqual(ConditionsModel().serviceTimeFactor(c), 1.4, accuracy: 1e-9)
    }

    func testCalibratorUsesMedianAndNeedsEnoughData() {
        let few = (0..<4).map { _ in SpeedCalibrator.Observation(expectedSeconds: 100, actualSeconds: 200) }
        XCTAssertNil(SpeedCalibrator.observedFactor(few))
        var many = (0..<5).map { _ in SpeedCalibrator.Observation(expectedSeconds: 100, actualSeconds: 200) }  // ratio 0.5
        many.append(SpeedCalibrator.Observation(expectedSeconds: 100, actualSeconds: 10))                       // outlier 10
        XCTAssertEqual(SpeedCalibrator.observedFactor(many)!, 0.5, accuracy: 1e-9)
    }

    func testBlend() {
        XCTAssertEqual(SpeedCalibrator.blend(model: 0.8, observed: nil), 0.8)
        XCTAssertEqual(SpeedCalibrator.blend(model: 0.8, observed: 0.4, weight: 0.5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(SpeedCalibrator.blend(model: 0.8, observed: 0.4, weight: 5), 0.4, accuracy: 1e-9)
    }
}

final class MatrixAndProviderTests: XCTestCase {
    private func pts(_ n: Int) -> [Coordinate] { (0..<n).map { Coordinate(latitude: 45, longitude: -93 + Double($0) * 0.01) } }

    func testChunkerCoversEveryPairExactlyOnceWithinLimit() {
        let blocks = MatrixChunker.blocks(count: 60, maxElements: 625)
        var seen = Set<[Int]>()
        for b in blocks {
            XCTAssertLessThanOrEqual(b.origins.count * b.destinations.count, 625)
            for o in b.origins { for d in b.destinations { XCTAssertTrue(seen.insert([o, d]).inserted) } }
        }
        XCTAssertEqual(seen.count, 60 * 60)
        XCTAssertTrue(MatrixChunker.blocks(count: 0, maxElements: 100).isEmpty)
    }

    func testGoogleRequestBodyShape() throws {
        let p = pts(2)
        let data = try GoogleRoutesMatrix.requestBody(origins: p, destinations: p, departureTime: Date(timeIntervalSince1970: 2_000_000_000))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["travelMode"] as? String, "DRIVE")
        XCTAssertEqual(json["routingPreference"] as? String, "TRAFFIC_AWARE")
        XCTAssertEqual((json["origins"] as? [Any])?.count, 2)
        XCTAssertNotNil(json["departureTime"])
        let noTime = try JSONSerialization.jsonObject(with: GoogleRoutesMatrix.requestBody(origins: p, destinations: p)) as? [String: Any]
        XCTAssertNil(noTime?["departureTime"])
    }

    func testGoogleParseHandlesMissingRoutes() throws {
        let sample = """
        [{"originIndex":0,"destinationIndex":0,"duration":"0s","condition":"ROUTE_EXISTS"},
         {"originIndex":0,"destinationIndex":1,"duration":"185s","condition":"ROUTE_EXISTS"},
         {"originIndex":1,"destinationIndex":0,"condition":"ROUTE_NOT_FOUND"},
         {"originIndex":1,"destinationIndex":1,"duration":"0s","condition":"ROUTE_EXISTS"}]
        """
        let m = try GoogleRoutesMatrix.parse(Data(sample.utf8), originCount: 2, destinationCount: 2)
        XCTAssertEqual(m[0][1], 185)
        XCTAssertNil(m[1][0])
        XCTAssertThrowsError(try GoogleRoutesMatrix.parse(Data("{}".utf8), originCount: 2, destinationCount: 2))
        XCTAssertThrowsError(try GoogleRoutesMatrix.parse(Data(#"[{"originIndex":9,"destinationIndex":0}]"#.utf8), originCount: 2, destinationCount: 2))
    }

    func testAssembleFillsGapsFromFallback() {
        let p = pts(2)
        let block = MatrixChunker.Block(origins: 0..<2, destinations: 0..<2)
        let values: [[Double?]] = [[0, 185], [nil, 0]]
        let m = GoogleRoutesMatrix.assemble(points: p, blocks: [(block, values)])
        XCTAssertEqual(m.seconds[0][1], 185)
        XCTAssertGreaterThan(m.seconds[1][0], 0)       // filled by the offline estimate
        XCTAssertTrue(m.isValid)
    }

    func testMatrixProviderUsesMatrixThenFallback() {
        let p = pts(2)
        let m = DriveTimeMatrix(points: p, seconds: [[0, 123], [456, 0]])
        let provider = MatrixProvider(matrix: m)
        XCTAssertEqual(provider.seconds(from: p[0], to: p[1]), 123)
        XCTAssertEqual(provider.seconds(from: p[1], to: p[0]), 456)
        let other = Coordinate(latitude: 10, longitude: 10)
        XCTAssertEqual(provider.seconds(from: p[0], to: other), HaversineDriveTime().seconds(from: p[0], to: other))
    }
}

private struct FailingSource: MatrixSource {
    func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix { throw RoutingError.badResponse("down") }
}
private struct JunkSource: MatrixSource {
    func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        DriveTimeMatrix(points: points, seconds: [[Double.nan]])
    }
}
private struct FixedSource: MatrixSource {
    let value: Double
    func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        DriveTimeMatrix(points: points, seconds: points.indices.map { i in points.indices.map { j in i == j ? 0 : value } })
    }
}
private struct FakeETA: ETASource {
    func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double {
        if to.longitude < 0 { throw RoutingError.badResponse("no route") }
        return 100
    }
}

final class RoutePlannerTests: XCTestCase {
    private let start = Coordinate(latitude: 45, longitude: -93)
    private func stops() -> [Stop] {
        [Stop(id: UUID(), name: "a", coordinate: Coordinate(latitude: 45.01, longitude: -93), priority: 1),
         Stop(id: UUID(), name: "b", coordinate: Coordinate(latitude: 45.02, longitude: -93), priority: 1)]
    }

    func testFallbackUsedWhenPrimaryFailsOrReturnsJunk() async throws {
        let pts = [start] + stops().map(\.coordinate)
        let viaFailing = try await FallbackMatrixSource(primary: FailingSource(), secondary: FixedSource(value: 7)).matrix(for: pts)
        XCTAssertEqual(viaFailing.seconds[0][1], 7)
        let viaJunk = try await FallbackMatrixSource(primary: JunkSource(), secondary: FixedSource(value: 9)).matrix(for: pts)
        XCTAssertEqual(viaJunk.seconds[0][1], 9)
        let viaGood = try await FallbackMatrixSource(primary: FixedSource(value: 3), secondary: FixedSource(value: 9)).matrix(for: pts)
        XCTAssertEqual(viaGood.seconds[0][1], 3)
    }

    func testSnowMakesPlannedArrivalsLater() async {
        let planner = RoutePlanner(matrixSource: FixedSource(value: 600))
        let clear = await planner.plan(stops: stops(), start: start, conditions: .clear)
        let snow = await planner.plan(stops: stops(), start: start,
                                      conditions: WeatherConditions(snowfallRateInPerHour: 1.2, accumulationInches: 8, temperatureF: 28))
        XCTAssertGreaterThan(snow.planned[1].arrivalOffsetSeconds, clear.planned[1].arrivalOffsetSeconds)
        XCTAssertGreaterThan(snow.totalDriveSeconds, clear.totalDriveSeconds)
    }

    func testObservedSlowdownPullsEstimateTowardReality() async {
        let planner = RoutePlanner(matrixSource: FixedSource(value: 600))
        let guess = await planner.plan(stops: stops(), start: start, conditions: .clear)
        let calibrated = await planner.plan(stops: stops(), start: start, conditions: .clear, observedSpeedFactor: 0.5)
        XCTAssertGreaterThan(calibrated.totalDriveSeconds, guess.totalDriveSeconds)
    }

    func testPlannerWorksEvenIfEverySourceFails() async {
        let planner = RoutePlanner(matrixSource: FailingSource())
        let r = await planner.plan(stops: stops(), start: start, conditions: .clear)
        XCTAssertEqual(r.planned.count, 2)
        XCTAssertGreaterThan(r.totalDriveSeconds, 0)
    }

    func testLegRefinerReturnsNilForFailedLegs() async {
        let good = Stop(id: UUID(), name: "g", coordinate: Coordinate(latitude: 45, longitude: 5))
        let bad = Stop(id: UUID(), name: "b", coordinate: Coordinate(latitude: 45, longitude: -5))
        let out = await LegRefiner.refine(stops: [good, bad, good], start: start, count: 2, source: FakeETA())
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0], 100)
        XCTAssertNil(out[1])
    }
}

final class NavigationLinksTests: XCTestCase {
    func testAppleMapsLink() throws {
        let url = try XCTUnwrap(NavigationLinks.appleMaps(to: Coordinate(latitude: 45.1, longitude: -93.2),
                                                          from: Coordinate(latitude: 45, longitude: -93)))
        XCTAssertEqual(url.host, "maps.apple.com")
        let q = url.absoluteString
        XCTAssertTrue(q.contains("daddr=45.1,-93.2"))
        XCTAssertTrue(q.contains("saddr=45.0,-93.0"))
        XCTAssertTrue(q.contains("dirflg=d"))
    }

    func testGoogleLinksSplitLongRoutesAndChain() {
        let stops = (0..<25).map { Coordinate(latitude: 45 + Double($0) * 0.01, longitude: -93) }
        let urls = NavigationLinks.googleMaps(stops: stops, origin: Coordinate(latitude: 44.9, longitude: -93))
        XCTAssertEqual(urls.count, 3)
        for u in urls {
            let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let wp = items.first { $0.name == "waypoints" }?.value?.split(separator: "|").count ?? 0
            XCTAssertLessThanOrEqual(wp, 9)
            XCTAssertEqual(items.first { $0.name == "travelmode" }?.value, "driving")
        }
        // Second link starts where the first ended.
        let firstDest = URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "destination" }?.value
        let secondOrigin = URLComponents(url: urls[1], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "origin" }?.value
        XCTAssertEqual(firstDest, secondOrigin)
        XCTAssertTrue(NavigationLinks.googleMaps(stops: []).isEmpty)
    }

    func testSingleStopHasNoWaypoints() {
        let urls = NavigationLinks.googleMaps(stops: [Coordinate(latitude: 1, longitude: 2)])
        XCTAssertEqual(urls.count, 1)
        XCTAssertFalse(urls[0].absoluteString.contains("waypoints"))
    }
}
