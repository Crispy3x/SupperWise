import XCTest
@testable import RidgelineCore

final class RoutingTests: XCTestCase {
    // Points roughly along a line east of the start, about 1.1 km per 0.01 degrees of longitude at lat 45.
    private let start = Coordinate(latitude: 45, longitude: -93)
    private func stop(_ name: String, lonOffset: Double, priority: Int = 3) -> Stop {
        Stop(id: UUID(), name: name, coordinate: Coordinate(latitude: 45, longitude: -93 + lonOffset), priority: priority)
    }
    private let provider = HaversineDriveTime()

    func testHaversineKnownDistance() {
        // One degree of latitude is about 111.2 km.
        let d = Geo.distanceMeters(Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(d, 111_195, accuracy: 300)
        XCTAssertEqual(Geo.distanceMeters(start, start), 0, accuracy: 0.001)
    }

    func testNearestNeighborWithinSamePriority() {
        let far = stop("far", lonOffset: 0.05)
        let near = stop("near", lonOffset: 0.01)
        let mid = stop("mid", lonOffset: 0.03)
        let ordered = RouteSequencer.resequence(stops: [far, near, mid], start: start, provider: provider)
        XCTAssertEqual(ordered.map(\.name), ["near", "mid", "far"])
    }

    func testPriorityBeatsDistance() {
        let hospitalFar = stop("hospital", lonOffset: 0.08, priority: 1)
        let drivewayNear = stop("driveway", lonOffset: 0.01, priority: 3)
        let ordered = RouteSequencer.resequence(stops: [drivewayNear, hospitalFar], start: start, provider: provider)
        XCTAssertEqual(ordered.map(\.name), ["hospital", "driveway"])
    }

    func testFrozenPrefixNeverMoves() {
        let a = stop("a", lonOffset: 0.09)
        let b = stop("b", lonOffset: 0.07)
        let c = stop("c", lonOffset: 0.01)
        let d = stop("d", lonOffset: 0.02)
        let ordered = RouteSequencer.resequence(stops: [a, b, c, d], start: start, frozenPrefix: 2, provider: provider)
        XCTAssertEqual(Array(ordered.prefix(2)).map(\.name), ["a", "b"])
        // After b (lon .07) the nearest remaining is d (.02) vs c (.01): both ~equal distance steps; c is 0.06 away, d 0.05 away.
        XCTAssertEqual(ordered.map(\.name), ["a", "b", "d", "c"])
    }

    func testFrozenPrefixLargerThanCountIsSafe() {
        let a = stop("a", lonOffset: 0.01)
        XCTAssertEqual(RouteSequencer.resequence(stops: [a], start: start, frozenPrefix: 10, provider: provider).count, 1)
        XCTAssertTrue(RouteSequencer.resequence(stops: [], start: start, provider: provider).isEmpty)
    }

    func testResequenceIsDeterministicAndKeepsAllStops() {
        let stops = (1...12).map { stop("s\($0)", lonOffset: Double($0 % 5) * 0.01, priority: ($0 % 3) + 1) }
        let one = RouteSequencer.resequence(stops: stops, start: start, provider: provider)
        let two = RouteSequencer.resequence(stops: stops, start: start, provider: provider)
        XCTAssertEqual(one, two)
        XCTAssertEqual(Set(one.map(\.id)), Set(stops.map(\.id)))
    }

    func testStormSpeedFactorSlowsDriving() {
        let a = start
        let b = Coordinate(latitude: 45, longitude: -92.9)
        let normal = provider.seconds(from: a, to: b)
        let storm = StormAdjustedDriveTime(base: provider, speedFactor: 0.5).seconds(from: a, to: b)
        XCTAssertEqual(storm, normal * 2, accuracy: 0.001)
    }

    func testPlanAccumulatesDriveAndServiceTime() {
        let s1 = Stop(id: UUID(), name: "one", coordinate: Coordinate(latitude: 45, longitude: -92.99), serviceMinutes: 10)
        let s2 = Stop(id: UUID(), name: "two", coordinate: Coordinate(latitude: 45, longitude: -92.98), serviceMinutes: 5)
        let planned = RouteSequencer.plan(stops: [s1, s2], start: start, provider: provider)
        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned[0].arrivalOffsetSeconds, planned[0].driveSeconds, accuracy: 0.001)
        XCTAssertEqual(planned[1].arrivalOffsetSeconds,
                       planned[0].driveSeconds + 600 + planned[1].driveSeconds, accuracy: 0.001)
        XCTAssertGreaterThan(RouteSequencer.totalDriveSeconds(planned), 0)
    }
}

final class StormAndSchedulingTests: XCTestCase {
    private func site(_ trigger: Double, priority: Int, _ address: String) -> Site {
        Site(customerID: UUID(), address: address, priority: priority, triggerInches: trigger)
    }

    func testTriggerEvaluatorOrdersByPriorityThenTrigger() {
        let sites = [site(2, priority: 3, "C"), site(1, priority: 1, "A"), site(4, priority: 1, "B"), site(6, priority: 1, "D")]
        let hit = TriggerEvaluator.sitesToServe(sites: sites, inches: 4)
        XCTAssertEqual(hit.map(\.address), ["A", "B", "C"])
    }

    func testNearTriggerWarning() {
        let sites = [site(5, priority: 1, "A"), site(8, priority: 1, "B")]
        let near = TriggerEvaluator.sitesNearTrigger(sites: sites, inches: 4, within: 1.5)
        XCTAssertEqual(near.map(\.address), ["A"])
    }

    func testStormUsesActualOverForecast() {
        var storm = StormEvent(name: "Dec 3", start: Date(timeIntervalSince1970: 0), forecastInches: 4)
        XCTAssertEqual(storm.effectiveInches, 4)
        storm.actualInches = 7
        XCTAssertEqual(storm.effectiveInches, 7)
    }

    func testBulkMoveRoutesToCrewAndWeekday() {
        let crewA = UUID(), crewB = UUID()
        let r1 = Route(name: "North", crewID: crewA, weekday: 2)
        let r2 = Route(name: "South", crewID: crewA, weekday: 2)
        let r3 = Route(name: "East", crewID: crewA, weekday: 2)
        let moved = RouteBook.move([r1, r2, r3], ids: [r1.id, r2.id], toCrew: crewB)
        XCTAssertEqual(moved.map(\.crewID), [crewB, crewB, crewA])
        let days = RouteBook.move(moved, ids: [r2.id], toWeekday: 5)
        XCTAssertEqual(days.map(\.weekday), [2, 5, 2])
    }

    func testSwapCrews() {
        let a = UUID(), b = UUID(), c = UUID()
        let routes = [Route(name: "1", crewID: a), Route(name: "2", crewID: b), Route(name: "3", crewID: c)]
        XCTAssertEqual(RouteBook.swapCrews(routes, a, b).map(\.crewID), [b, a, c])
    }

    func testMoveSitesRemovesFromOldRouteAndDoesNotDuplicate() {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        let r1 = Route(name: "A", stopSiteIDs: [s1, s2])
        let r2 = Route(name: "B", stopSiteIDs: [s3])
        let moved = RouteBook.moveSites([r1, r2], siteIDs: [s2, s2, s1], toRoute: r2.id)
        XCTAssertEqual(moved[0].stopSiteIDs, [])
        XCTAssertEqual(moved[1].stopSiteIDs, [s3, s2, s1])
    }
}
