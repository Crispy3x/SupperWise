import XCTest
@testable import RidgelineCore

final class AutoCheckInTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let base = Coordinate(latitude: 44.9778, longitude: -93.2650)

    /// A point `meters` north of `c`.
    func north(_ c: Coordinate, _ meters: Double) -> Coordinate {
        Coordinate(latitude: c.latitude + meters / 111_320, longitude: c.longitude)
    }

    func fix(_ c: Coordinate, _ seconds: Double, accuracy: Double = 10) -> LocationFix {
        LocationFix(coordinate: c, accuracyMeters: accuracy, timestamp: now.addingTimeInterval(seconds))
    }

    let idA = UUID(), idB = UUID(), idC = UUID()

    func threeStops() -> [CheckInStop] {
        [CheckInStop(id: idA, name: "14 Elm Ave", coordinate: base),
         CheckInStop(id: idB, name: "22 Oak St", coordinate: north(base, 1000), previousStopID: idA, driveSecondsFromPrevious: 360),
         CheckInStop(id: idC, name: "9 Pine Rd", coordinate: north(base, 2000), previousStopID: idB, driveSecondsFromPrevious: 240)]
    }

    /// Feeds fixes and returns every event.
    func feed(_ t: inout ArrivalTracker, _ fixes: [LocationFix]) -> [CheckInEvent] {
        fixes.flatMap { t.ingest($0) }
    }

    /// Parks at A long enough to arrive.
    func arriveAtA(_ t: inout ArrivalTracker) {
        XCTAssertEqual(feed(&t, [fix(north(base, 20), 0), fix(north(base, 25), 45)]), [.arrived(stopID: idA, at: now)])
    }

    // MARK: arrival

    func testArrivesAfter45SecondsWithin60Meters() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(north(base, 30), 0), fix(north(base, 40), 20)]), [])
        XCTAssertNil(t.currentStopID)
        // The arrival time is when the truck first came within range.
        XCTAssertEqual(t.ingest(fix(north(base, 35), 45)), [.arrived(stopID: idA, at: now)])
        XCTAssertEqual(t.currentStopID, idA)
    }

    func testNoArrivalBefore45SecondsOrFartherThan60Meters() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 0), fix(base, 44)]), [])
        var far = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&far, [fix(north(base, 70), 0), fix(north(base, 70), 60), fix(north(base, 70), 120)]), [])
    }

    func testInaccurateFixesAreIgnored() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 0, accuracy: 50), fix(base, 30, accuracy: 80), fix(base, 60, accuracy: -1)]), [])
        XCTAssertNil(t.lastFix)
        // An inaccurate fix in the middle neither counts nor breaks the wait.
        XCTAssertEqual(feed(&t, [fix(base, 100), fix(base, 120, accuracy: 120), fix(base, 145)]), [.arrived(stopID: idA, at: now.addingTimeInterval(100))])
    }

    func testDrivingPastDoesNotArrive() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 0), fix(north(base, 300), 20), fix(base, 50)]), [])
        // The clock restarted at 50 seconds, so arrival comes 45 seconds after that.
        XCTAssertEqual(t.ingest(fix(base, 95)), [.arrived(stopID: idA, at: now.addingTimeInterval(50))])
    }

    func testJitterJustOutsideTheCircleKeepsTheClockRunning() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 0), fix(north(base, 80), 20), fix(north(base, 10), 45)]), [.arrived(stopID: idA, at: now)])
    }

    func testLongSilenceRestartsTheArrivalClock() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 0), fix(base, 200)]), [])
        XCTAssertEqual(t.ingest(fix(base, 245)), [.arrived(stopID: idA, at: now.addingTimeInterval(200))])
    }

    func testRepeatedAndOlderFixesAreIgnored() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(feed(&t, [fix(base, 30), fix(base, 30), fix(base, 10)]), [])
        XCTAssertEqual(t.lastFix?.timestamp, now.addingTimeInterval(30))
        XCTAssertEqual(t.ingest(fix(base, 75)), [.arrived(stopID: idA, at: now.addingTimeInterval(30))])
    }

    // MARK: departure

    func testDepartureNeedsTwoGoodFixesPast120Meters() {
        var t = ArrivalTracker(stops: threeStops())
        arriveAtA(&t)
        XCTAssertEqual(t.ingest(fix(north(base, 100), 60)), [])           // still close: walking the lot
        XCTAssertEqual(t.ingest(fix(north(base, 200), 70)), [])           // one jump is not enough
        XCTAssertEqual(t.ingest(fix(north(base, 50), 80)), [])            // back again, so that jump was jitter
        XCTAssertEqual(t.ingest(fix(north(base, 200), 90, accuracy: 90)), [])   // inaccurate, ignored
        XCTAssertEqual(t.ingest(fix(north(base, 200), 100)), [])
        XCTAssertEqual(t.ingest(fix(north(base, 260), 105)), [.departed(stopID: idA, at: now.addingTimeInterval(100))])
        XCTAssertNil(t.currentStopID)
        XCTAssertEqual(t.finishedIDs, [idA])
        XCTAssertEqual(t.nextStop?.id, idB)
    }

    func testComingBackToAStopDoesNotArriveTwice() {
        var t = ArrivalTracker(stops: threeStops())
        arriveAtA(&t)
        XCTAssertEqual(feed(&t, [fix(north(base, 300), 60), fix(north(base, 300), 65)]), [.departed(stopID: idA, at: now.addingTimeInterval(60))])
        XCTAssertEqual(feed(&t, [fix(base, 100), fix(base, 150), fix(base, 200), fix(base, 260)]), [])
        XCTAssertNil(t.currentStopID)
    }

    func testSavedCheckInsAreNotRepeatedAndAnOpenOneIsWhereTheCrewIs() {
        var t = ArrivalTracker(stops: threeStops(), arrivedIDs: [idA, idB], finishedIDs: [idA])
        XCTAssertEqual(t.currentStopID, idB)
        XCTAssertEqual(t.nextStop?.id, idC)
        // Leaving B counts on the second fix away; the wait at C starts from that fix.
        let c = north(base, 2000)
        XCTAssertEqual(feed(&t, [fix(c, 0), fix(c, 50), fix(c, 95)]),
                       [.departed(stopID: idB, at: now), .arrived(stopID: idC, at: now.addingTimeInterval(50))])
    }

    // MARK: next stop

    func testNextStopFollowsTheRouteEvenWhenAStopIsDoneOutOfOrder() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertEqual(t.nextStop?.id, idA)
        let b = north(base, 1000)
        XCTAssertEqual(feed(&t, [fix(b, 0), fix(b, 45)]), [.arrived(stopID: idB, at: now)])
        XCTAssertEqual(t.currentStopID, idB)
        XCTAssertEqual(t.nextStop?.id, idA)   // A was skipped, so it is still next
        XCTAssertFalse(t.isRouteDone)
    }

    func testPlannedDriveTimeAfterLeavingThePlannedStopBefore() {
        var t = ArrivalTracker(stops: threeStops())
        XCTAssertNil(t.secondsToNextStop())   // no position and nothing left yet
        arriveAtA(&t)
        // While at A, the estimate comes from the last fix.
        XCTAssertEqual(t.secondsToNextStop()!, HaversineDriveTime().seconds(from: north(base, 25), to: north(base, 1000)), accuracy: 0.001)
        _ = feed(&t, [fix(north(base, 300), 60), fix(north(base, 300), 65)])
        XCTAssertEqual(t.secondsToNextStop(), 360)
        XCTAssertEqual(CheckInText.next(t.nextStop!.name, seconds: t.secondsToNextStop()), "Next: 22 Oak St, 6 min")
    }

    func testRouteDoneAfterTheLastStopIsLeft() {
        var t = ArrivalTracker(stops: Array(threeStops().prefix(2)))
        arriveAtA(&t)
        let b = north(base, 1000)
        _ = feed(&t, [fix(north(base, 500), 60), fix(north(base, 600), 65), fix(b, 120), fix(b, 170)])
        XCTAssertEqual(t.currentStopID, idB)
        XCTAssertFalse(t.isRouteDone)
        XCTAssertEqual(feed(&t, [fix(north(base, 1500), 200), fix(north(base, 1600), 205)]), [.departed(stopID: idB, at: now.addingTimeInterval(200))])
        XCTAssertNil(t.nextStop)
        XCTAssertTrue(t.isRouteDone)
    }

    func testUpdatedRouteKeepsStopsAlreadyVisited() {
        var t = ArrivalTracker(stops: threeStops())
        arriveAtA(&t)
        t.updateStops(Array(threeStops().dropFirst()))   // A was marked done, so the new route leaves it out
        XCTAssertEqual(t.stops.map(\.id), [idA, idB, idC])
        XCTAssertEqual(t.currentStopID, idA)
        XCTAssertEqual(t.nextStop?.id, idB)
    }

    func testBannerText() {
        XCTAssertEqual(CheckInText.arrived("14 Elm Ave"), "Arrived at 14 Elm Ave")
        XCTAssertEqual(CheckInText.next("22 Oak St", seconds: 20), "Next: 22 Oak St, 1 min")
        XCTAssertEqual(CheckInText.next("22 Oak St", seconds: 389), "Next: 22 Oak St, 6 min")
        XCTAssertEqual(CheckInText.next("22 Oak St", seconds: nil), "Next: 22 Oak St")
        XCTAssertEqual(CheckInText.next("22 Oak St", seconds: .infinity), "Next: 22 Oak St")
    }

    // MARK: saved on the job, and who may use it

    struct World {
        var data: AppData
        var elm: Job
        var oak: Job
    }

    func world() -> World {
        var d = AppData()
        let customer = Customer(name: "Pat")
        let s1 = Site(customerID: customer.id, address: "14 Elm Ave", latitude: base.latitude, longitude: base.longitude)
        let far = north(base, 1000)
        let s2 = Site(customerID: customer.id, address: "22 Oak St", latitude: far.latitude, longitude: far.longitude)
        d.customers = [customer]
        d.sites = [s1, s2]
        let elm = Job(title: "Plow Elm", kind: .snowPlowing, customerID: customer.id, siteID: s1.id, start: now, createdAt: now)
        let oak = Job(title: "Plow Oak", kind: .snowPlowing, customerID: customer.id, siteID: s2.id, start: now.addingTimeInterval(3600), createdAt: now)
        d.jobs = [elm, oak]
        return World(data: d, elm: elm, oak: oak)
    }

    func signInEmployee(_ d: inout AppData, role: TeamRole = .crewMember) -> TeamMember {
        let m = TeamMember(name: "Dana", role: role, status: .active, createdAt: now)
        d.team.append(m)
        d.session = AppSession(role: .employee, memberID: m.id, startedAt: now)
        return m
    }

    func testStopsFollowThePlanAndKeepStopToStopDriveTimes() {
        let w = world()
        let plain = w.data.autoCheckInStops(on: now, calendar: utc)
        XCTAssertEqual(plain.map(\.id), [w.elm.id, w.oak.id])
        XCTAssertEqual(plain.map(\.name), ["14 Elm Ave", "22 Oak St"])
        XCTAssertEqual(plain[0].siteID, w.elm.siteID)
        XCTAssertNil(plain[1].driveSecondsFromPrevious)

        let route = w.data.routeStops(on: now, calendar: utc)
        let plan = RoutePlanResult(planned: [PlannedStop(stop: route[1], driveSeconds: 500, arrivalOffsetSeconds: 500),
                                             PlannedStop(stop: route[0], driveSeconds: 360, arrivalOffsetSeconds: 1460)], lateStopIDs: [])
        let planned = w.data.autoCheckInStops(on: now, plan: plan, calendar: utc)
        XCTAssertEqual(planned.map(\.id), [w.oak.id, w.elm.id])
        XCTAssertNil(planned[0].driveSecondsFromPrevious)   // from the yard, not from a stop
        XCTAssertEqual(planned[1].previousStopID, w.oak.id)
        XCTAssertEqual(planned[1].driveSecondsFromPrevious, 360)
    }

    func testArrivalIsSavedOnceAndMarksTheJobInProgress() throws {
        var d = world().data
        let id = d.jobs[0].id
        let at = now.addingTimeInterval(120)
        XCTAssertTrue(try d.recordArrival(jobID: id, at: at, calendar: utc))
        XCTAssertFalse(try d.recordArrival(jobID: id, at: at.addingTimeInterval(600), calendar: utc))   // duplicate
        XCTAssertEqual(d.jobs[0].checkIn(on: now, calendar: utc), JobCheckIn(arrivedAt: at))
        XCTAssertEqual(d.jobs[0].status, .inProgress)
        let saved = d.savedCheckIns(for: d.autoCheckInStops(on: now, calendar: utc), on: now, calendar: utc)
        XCTAssertEqual(saved.arrived, [id])
        XCTAssertEqual(saved.finished, [])
    }

    func testDepartureMarksDoneOnlyWhenTheOwnerChoseIt() throws {
        var d = world().data
        let elm = d.jobs[0].id, oak = d.jobs[1].id
        try d.recordArrival(jobID: elm, at: now, calendar: utc)
        try d.recordDeparture(jobID: elm, at: now.addingTimeInterval(900), markDone: false, calendar: utc)
        XCTAssertEqual(d.jobs[0].status, .inProgress)
        XCTAssertEqual(d.jobs[0].checkIn(on: now, calendar: utc)?.departedAt, now.addingTimeInterval(900))
        // A second departure keeps the first time.
        try d.recordDeparture(jobID: elm, at: now.addingTimeInterval(2000), markDone: false, calendar: utc)
        XCTAssertEqual(d.jobs[0].checkIn(on: now, calendar: utc)?.departedAt, now.addingTimeInterval(900))

        try d.recordArrival(jobID: oak, at: now.addingTimeInterval(3600), calendar: utc)
        try d.recordDeparture(jobID: oak, at: now.addingTimeInterval(4500), markDone: true, calendar: utc)
        XCTAssertEqual(d.jobs[1].status, .done)
        // Done jobs leave the route; the saved check-ins say both were left.
        XCTAssertEqual(d.autoCheckInStops(on: now, calendar: utc).map(\.id), [elm])
    }

    func testRepeatingJobIsMarkedForThatDayOnly() throws {
        var d = world().data
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: d.jobs[0].id, calendar: utc)
        let id = d.jobs[0].id
        try d.recordArrival(jobID: id, at: now, calendar: utc)
        try d.recordDeparture(jobID: id, at: now.addingTimeInterval(600), markDone: true, calendar: utc)
        XCTAssertEqual(d.jobs[0].status, .scheduled)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: now, calendar: utc), .done)
        let nextWeek = now.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: nextWeek, calendar: utc), .scheduled)
        XCTAssertNil(d.jobs[0].checkIn(on: nextWeek, calendar: utc))
    }

    func testEmployeesOnlyGetTheirOwnJobs() throws {
        var d = world().data
        let m = signInEmployee(&d, role: .crewLead)   // may see every job, still checks in only to their own
        XCTAssertEqual(d.autoCheckInStops(on: now, calendar: utc), [])
        XCTAssertThrowsError(try d.recordArrival(jobID: d.jobs[0].id, at: now, calendar: utc)) {
            XCTAssertEqual($0 as? AutoCheckInError, .notAllowed)
        }
        d.jobs[1].assigneeIDs = [m.id]
        XCTAssertEqual(d.autoCheckInStops(on: now, calendar: utc).map(\.id), [d.jobs[1].id])
        XCTAssertTrue(try d.recordArrival(jobID: d.jobs[1].id, at: now, calendar: utc))
        XCTAssertThrowsError(try d.setAutoCheckInMarksDone(true))
        XCTAssertFalse(d.autoCheckInMarksDone)
    }

    func testEmployeeWithoutLogVisitsGetsNothing() {
        var d = world().data
        let m = signInEmployee(&d, role: .office)
        d.jobs[0].assigneeIDs = [m.id]
        XCTAssertFalse(d.can(.logVisits))
        XCTAssertEqual(d.autoCheckInStops(on: now, calendar: utc), [])
    }

    func testOwnerSettingAndCheckInsSaveAndLoad() throws {
        var d = world().data
        try d.setAutoCheckInMarksDone(true)
        try d.recordArrival(jobID: d.jobs[0].id, at: now, calendar: utc)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(AppData.self, from: encoder.encode(d))
        XCTAssertTrue(back.autoCheckInMarksDone)
        XCTAssertEqual(back.jobs[0].checkIn(on: now, calendar: utc), JobCheckIn(arrivedAt: now))
        // Files saved before this feature load with the setting off.
        XCTAssertFalse(try decoder.decode(AppData.self, from: Data("{}".utf8)).autoCheckInMarksDone)
    }
}
