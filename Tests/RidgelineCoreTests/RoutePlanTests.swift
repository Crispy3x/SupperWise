import XCTest
@testable import RidgelineCore

/// One minute of driving per unit of longitude (or latitude), so the numbers in these tests are exact.
private struct MinutesPerUnit: DriveTimeProvider {
    func seconds(from a: Coordinate, to b: Coordinate) -> Double {
        (abs(a.longitude - b.longitude) + abs(a.latitude - b.latitude)) * 60
    }
}

final class RoutePlanTests: XCTestCase {
    private let provider = MinutesPerUnit()
    private let origin = Coordinate(latitude: 0, longitude: 0)
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let day = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC

    private func at(_ lon: Double) -> Coordinate { Coordinate(latitude: 0, longitude: lon) }
    private func stop(_ name: String, _ lon: Double, minutes: Double = 0) -> Stop {
        Stop(id: UUID(), name: name, coordinate: at(lon), serviceMinutes: minutes)
    }
    private func clock(_ date: Date) -> String {
        let c = utc.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    private func startTime(hour: Int, minute: Int = 0) -> Date {
        utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: finish point

    func testFinishPointChangesTheOrderWhenItShould() {
        let a = stop("A", 2), b = stop("B", -3)
        // Open-ended: A (2 min) then B (5 more) beats B then A.
        XCTAssertEqual(RouteOptimizer.optimize(stops: [a, b], start: origin, provider: provider).stops.map(\.name), ["A", "B"])
        // Finishing far east: B first, then A on the way to the finish (8 + 8) beats A, B, then back east (7 + 13).
        let east = RouteOptimizer.optimize(stops: [a, b], start: origin, provider: provider, end: at(10))
        XCTAssertEqual(east.stops.map(\.name), ["B", "A"])
        // Finishing far west keeps A first.
        XCTAssertEqual(RouteOptimizer.optimize(stops: [a, b], start: origin, provider: provider, end: at(-10)).stops.map(\.name), ["A", "B"])
    }

    func testPathCostCountsTheFinishOnlyWhenGiven() {
        let stops = [stop("A", 2), stop("B", 5)]
        XCTAssertEqual(RouteOptimizer.pathCost(start: origin, stops: stops, provider: provider), 300, accuracy: 1e-9)
        XCTAssertEqual(RouteOptimizer.pathCost(start: origin, stops: stops, provider: provider, end: origin), 600, accuracy: 1e-9)
        XCTAssertEqual(RouteOptimizer.pathCost(start: origin, stops: [], provider: provider, end: at(9)), 0)
    }

    func testDayPlannerOptimizesTowardTheFinish() {
        let a = stop("A", 2), b = stop("B", -3)
        let plan = RouteDayPlanner.optimize(stops: [a, b], start: origin, end: at(10), startTime: startTime(hour: 8), breakRule: nil, provider: provider)
        XCTAssertEqual(plan.stops.map(\.stop.name), ["B", "A"])
        XCTAssertEqual(plan.finishDriveSeconds, 8 * 60, accuracy: 1e-9)
        XCTAssertEqual(plan.result.stops.map(\.name), ["B", "A"])
    }

    // MARK: break, clock times and totals

    private var threeHourStops: [Stop] { [stop("S1", 10, minutes: 60), stop("S2", 20, minutes: 60), stop("S3", 30, minutes: 60)] }

    func testBreakIsTakenAfterTheStopThatPassesTheThreshold() {
        let plan = RouteDayPlanner.timeline(order: threeHourStops, start: origin, end: nil, startTime: startTime(hour: 8),
                                            breakRule: RouteBreak(minutes: 30, afterHours: 1), provider: provider)
        // S1: drive 10, work 60 -> 70 minutes of work, past one hour, so the break comes before S2.
        XCTAssertEqual(plan.stops.map { clock($0.arrival) }, ["8:10", "9:50", "11:00"])
        XCTAssertEqual(plan.stops.map(\.breakBefore), [false, true, false])
        XCTAssertEqual(plan.breakStart.map(clock), "9:10")
        XCTAssertEqual(clock(plan.endTime), "12:00")
        XCTAssertEqual(plan.totalSeconds, 4 * 3600, accuracy: 1e-9)   // 30 drive + 180 on site + 30 break
        XCTAssertEqual(RouteText.summary(plan), "4h · 3 stops")
    }

    func testLaterThresholdMovesTheBreakAndNoBreakAfterTheLastStop() {
        let later = RouteDayPlanner.timeline(order: threeHourStops, start: origin, end: nil, startTime: startTime(hour: 8),
                                             breakRule: RouteBreak(minutes: 30, afterHours: 2), provider: provider)
        XCTAssertEqual(later.stops.map(\.breakBefore), [false, false, true])
        XCTAssertEqual(clock(later.stops[2].arrival), "11:00")   // 10:20 leave S2, 30 min break, 10 min drive

        let never = RouteDayPlanner.timeline(order: threeHourStops, start: origin, end: nil, startTime: startTime(hour: 8),
                                             breakRule: RouteBreak(minutes: 30, afterHours: 3.5), provider: provider)
        XCTAssertNil(never.breakStart)
        XCTAssertEqual(never.breakSeconds, 0)
        XCTAssertEqual(never.totalSeconds, 3.5 * 3600, accuracy: 1e-9)
    }

    func testClockTimesAndTotalsWithReturnToStart() {
        var d = AppData()
        d.routeSettings.startMinutes = 9 * 60 + 9
        let start = d.routeStartTime(on: day, calendar: utc)
        XCTAssertEqual(clock(start), "9:09")
        let stops = [stop("S1", 10, minutes: 20), stop("S2", 20, minutes: 20), stop("S3", 30, minutes: 20)]
        let plan = RouteDayPlanner.timeline(order: stops, start: origin, end: origin, startTime: start, breakRule: nil, provider: provider)
        XCTAssertEqual(plan.stops.map { clock($0.arrival) }, ["9:19", "9:49", "10:19"])
        XCTAssertEqual(plan.stops.map { clock($0.departure) }, ["9:39", "10:09", "10:39"])
        XCTAssertEqual(plan.finishDriveSeconds, 30 * 60, accuracy: 1e-9)
        XCTAssertEqual(plan.driveSeconds, 60 * 60, accuracy: 1e-9)
        XCTAssertEqual(plan.serviceSeconds, 60 * 60, accuracy: 1e-9)
        XCTAssertEqual(clock(plan.endTime), "11:09")
        XCTAssertEqual(plan.stopCount, 3)
        XCTAssertEqual(RouteText.summary(plan), "2h · 3 stops")
    }

    func testFinishSettings() {
        var d = AppData()
        d.depot = at(1)
        XCTAssertEqual(d.routeStartCoordinate, at(1))
        XCTAssertEqual(d.routeFinishCoordinate(start: d.routeStartCoordinate), at(1))      // return to start by default
        d.routeSettings.finishKind = .endAtLastStop
        XCTAssertNil(d.routeFinishCoordinate(start: d.routeStartCoordinate))
        d.routeSettings.finishKind = .custom
        d.routeSettings.finishCoordinate = at(7)
        XCTAssertEqual(d.routeFinishCoordinate(start: d.routeStartCoordinate), at(7))
        d.routeSettings.startKind = .custom
        d.routeSettings.startCoordinate = at(4)
        XCTAssertEqual(d.routeStartCoordinate, at(4))
    }

    func testTextHelpers() {
        XCTAssertEqual(RouteText.duration(332 * 60), "5h 32m")
        XCTAssertEqual(RouteText.duration(45 * 60), "45m")
        XCTAssertEqual(RouteText.duration(120 * 60), "2h")
        XCTAssertEqual(RouteText.addressLines("12 Main St, Burlington, VT 05401").street, "12 Main St")
        XCTAssertEqual(RouteText.addressLines("12 Main St, Burlington, VT 05401").rest, "Burlington, VT 05401")
        XCTAssertEqual(RouteText.addressLines("Yard").rest, "")
        XCTAssertEqual(RouteText.initials("Maple Street Dental"), "MS")
        XCTAssertEqual(RouteText.initials(""), "")
    }

    // MARK: ad-hoc stops and manual order

    /// A client with one site on the map and a job on `day`.
    private func dataWithJob() throws -> (data: AppData, job: Job) {
        var d = AppData()
        let c = Customer(name: "Maple Dental")
        d.customers.append(c)
        let site = Site(customerID: c.id, address: "1 Maple St, Town", latitude: 0, longitude: 3)
        d.sites.append(site)
        let job = try d.addJob(title: "Plow", kind: .snowPlowing, customerID: c.id, siteID: site.id, start: day, durationMinutes: 30, now: day)
        return (d, job)
    }

    func testAdHocStopsAreIncludedOnTheirDayOnly() throws {
        let made = try dataWithJob()
        var d = made.data
        let job = made.job
        let dump = try d.addAdHocStop(address: "Town dump", coordinate: at(5), on: day, note: "Drop the trailer", now: day, calendar: utc)
        _ = try d.addAdHocStop(address: "Salt yard", coordinate: at(6), on: day.addingTimeInterval(86_400), now: day, calendar: utc)
        XCTAssertEqual(dump.serviceMinutes, 20)                                     // the default time per stop
        XCTAssertEqual(d.routeStops(on: day, calendar: utc).map(\.id), [job.id])   // client jobs only, as before
        XCTAssertEqual(d.plannerStops(on: day, calendar: utc).map(\.id), [job.id, dump.id])
        XCTAssertEqual(d.plannerStops(on: day, calendar: utc).last?.serviceMinutes, 20)
        XCTAssertThrowsError(try d.addAdHocStop(address: "  ", coordinate: at(1), on: day, now: day, calendar: utc))

        try d.updateAdHocStop(id: dump.id, serviceMinutes: 45, note: "Two loads")
        XCTAssertEqual(d.plannerStops(on: day, calendar: utc).last?.serviceMinutes, 45)
        try d.removeAdHocStop(id: dump.id)
        XCTAssertEqual(d.plannerStops(on: day, calendar: utc).map(\.id), [job.id])
    }

    func testEmployeesSeeOnlyTheirOwnAdHocStops() throws {
        var d = try dataWithJob().data
        let owners = try d.addAdHocStop(address: "Owner errand", coordinate: at(5), on: day, now: day, calendar: utc)
        let member = TeamMember(name: "Sam", role: .crewMember, createdAt: day)
        d.team.append(member)
        d.session = AppSession(role: .employee, memberID: member.id, startedAt: day)
        let mine = try d.addAdHocStop(address: "Fuel", coordinate: at(2), on: day, now: day, calendar: utc)
        XCTAssertEqual(mine.createdBy, member.id)
        XCTAssertEqual(d.plannerStops(on: day, calendar: utc).map(\.id), [mine.id])   // the job is not assigned to Sam
        d.session = nil
        XCTAssertEqual(Set(d.adHocStops(on: day, calendar: utc).map(\.id)), [owners.id, mine.id])
    }

    func testManualOrderIsKeptUntilOptimizedAgain() throws {
        let made = try dataWithJob()
        var d = made.data
        let job = made.job
        let a = try d.addAdHocStop(address: "A", coordinate: at(1), on: day, now: day, calendar: utc)
        d.setRouteOrder([a.id, job.id], on: day, optimized: false, calendar: utc)
        XCTAssertEqual(d.orderedPlannerStops(on: day, calendar: utc).map(\.id), [a.id, job.id])
        XCTAssertEqual(d.routeOrder(on: day, calendar: utc)?.optimized, false)

        // A stop added later goes at the end; the dragged order stays.
        let b = try d.addAdHocStop(address: "B", coordinate: at(9), on: day, now: day, calendar: utc)
        XCTAssertEqual(d.orderedPlannerStops(on: day, calendar: utc).map(\.id), [a.id, job.id, b.id])

        // Removing a stop drops it from the order.
        try d.removeAdHocStop(id: a.id)
        XCTAssertEqual(d.orderedPlannerStops(on: day, calendar: utc).map(\.id), [job.id, b.id])

        // Optimize replaces the order for that day only.
        d.setRouteOrder([b.id, job.id], on: day, optimized: true, calendar: utc)
        XCTAssertEqual(d.routeOrders.count, 1)
        XCTAssertEqual(d.routeOrder(on: day, calendar: utc)?.optimized, true)
        XCTAssertNil(d.routeOrder(on: day.addingTimeInterval(86_400), calendar: utc))
    }

    func testApplyOrderSkipsMissingAndDuplicateIDs() {
        let a = stop("A", 1), b = stop("B", 2), c = stop("C", 3)
        let out = RouteDayPlanner.apply(order: [c.id, UUID(), c.id, a.id], to: [a, b, c])
        XCTAssertEqual(out.map(\.name), ["C", "A", "B"])
    }

    func testOldDaysArePrunedWhenAStopIsAdded() throws {
        var d = AppData()
        let old = day.addingTimeInterval(-40 * 86_400)
        _ = try d.addAdHocStop(address: "Old", coordinate: at(1), on: old, now: old, calendar: utc)
        d.setRouteOrder([], on: old, optimized: true, calendar: utc)
        _ = try d.addAdHocStop(address: "New", coordinate: at(1), on: day, now: day, calendar: utc)
        XCTAssertEqual(d.adHocStops.map(\.address), ["New"])
        XCTAssertTrue(d.routeOrders.isEmpty)
    }

    func testServiceMinutesForAJob() throws {
        let made = try dataWithJob()
        var d = made.data
        let job = made.job
        try d.setJobServiceMinutes(25, id: job.id)
        XCTAssertEqual(d.routeStops(on: day, calendar: utc).first?.serviceMinutes, 25)
        XCTAssertThrowsError(try d.setJobServiceMinutes(25, id: UUID()))
    }

    // MARK: saved files

    func testOldSavedFilesStillLoad() throws {
        let old = try FileStore.decoder.decode(AppData.self, from: Data(#"{"schemaVersion":1,"companyName":"Old Co"}"#.utf8))
        XCTAssertEqual(old.routeSettings, RouteSettings())
        XCTAssertTrue(old.adHocStops.isEmpty)
        XCTAssertTrue(old.routeOrders.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(RouteSettings.self, from: Data("{}".utf8)), RouteSettings())
        // An unknown finish choice from a newer version falls back instead of failing the whole file.
        let newer = try JSONDecoder().decode(RouteSettings.self, from: Data(#"{"finishKind":"teleport","startMinutes":480}"#.utf8))
        XCTAssertEqual(newer.finishKind, .returnToStart)
        XCTAssertEqual(newer.startMinutes, 480)
    }

    func testRouteDataRoundTrips() throws {
        let made = try dataWithJob()
        var d = made.data
        let job = made.job
        var s = RouteSettings()
        s.startKind = .custom
        s.startAddress = "9 Shop Rd"
        s.startCoordinate = at(2)
        s.finishKind = .custom
        s.finishCoordinate = at(8)
        s.defaultBreak = RouteBreak(minutes: 45, afterHours: 3)
        s.defaultServiceMinutes = 15
        d.setRouteSettings(s)
        let a = try d.addAdHocStop(address: "Dump", coordinate: at(4), on: day, now: day, calendar: utc)
        d.setRouteOrder([a.id, job.id], on: day, optimized: false, calendar: utc)
        let back = try FileStore.decoder.decode(AppData.self, from: FileStore.encoder.encode(d))
        XCTAssertEqual(back.routeSettings, d.routeSettings)
        XCTAssertEqual(back.adHocStops, d.adHocStops)
        XCTAssertEqual(back.routeOrders, d.routeOrders)
        XCTAssertEqual(back.adHocStops.first?.serviceMinutes, 15)
    }

    func testSettingsAreCleaned() {
        var s = RouteSettings()
        s.startMinutes = 5000
        s.defaultServiceMinutes = 0
        s.defaultBreak = RouteBreak(minutes: 1, afterHours: 40)
        let c = s.cleaned()
        XCTAssertEqual(c.startMinutes, 24 * 60 - 1)
        XCTAssertEqual(c.defaultServiceMinutes, 1)
        XCTAssertEqual(c.defaultBreak, RouteBreak(minutes: 5, afterHours: 12))
    }
}
