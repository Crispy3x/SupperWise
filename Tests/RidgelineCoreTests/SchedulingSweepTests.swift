import XCTest
@testable import RidgelineCore

/// Bugs found in the pre-launch sweep of scheduling, routes and field work. Each test fails on the old code.
final class SchedulingSweepTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0, in cal: Calendar? = nil) -> Date {
        (cal ?? utc).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// One client with one site on the map.
    private func business() -> (data: AppData, site: Site) {
        var d = AppData()
        let c = Customer(name: "Pat")
        let s = Site(customerID: c.id, address: "14 Elm Ave", latitude: 44.9, longitude: -93.2)
        d.customers = [c]
        d.sites = [s]
        return (d, s)
    }

    private func repeating(_ d: inout AppData, start: Date, _ frequency: RepeatFrequency, end: Date? = nil, siteID: UUID? = nil) throws -> UUID {
        let job = try d.addJob(title: "Mow", kind: .lawnCare, siteID: siteID, start: start, now: start)
        try d.setJobRepeat(RepeatRule(frequency: frequency, endDate: end), id: job.id, calendar: utc)
        return job.id
    }

    // MARK: the Jobs list

    func testJobsListShowsTheNextOpenVisitOfARepeatingJob() throws {
        var d = AppData()
        let id = try repeating(&d, start: day(2027, 1, 7), .weekly)
        let now = day(2027, 1, 20, 15)

        // Not the first date (Jan 7): the next visit from today.
        var row = try XCTUnwrap(d.jobListEntries(now: now, calendar: utc).first)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.start, day(2027, 1, 21))
        XCTAssertEqual(row.status, .scheduled)

        // That visit is done: the list moves on to the next one, and the job still counts as active.
        try d.setOccurrenceStatus(.done, id: id, on: day(2027, 1, 21), calendar: utc)
        row = try XCTUnwrap(d.jobListEntries(now: now, calendar: utc).first)
        XCTAssertEqual(row.start, day(2027, 1, 28))
        XCTAssertTrue(row.status.isOpen)

        // A visit in progress today is the one shown.
        try d.setOccurrenceStatus(.inProgress, id: id, on: day(2027, 1, 28), calendar: utc)
        row = try XCTUnwrap(d.jobListEntries(now: day(2027, 1, 28, 6), calendar: utc).first)
        XCTAssertEqual(row.start, day(2027, 1, 28))
        XCTAssertEqual(row.status, .inProgress)
        XCTAssertEqual(d.jobs.count, 1)
    }

    func testAnEndedRepeatingJobIsListedAsItsLastVisitAndIsNotActiveOnceDone() throws {
        var d = AppData()
        let id = try repeating(&d, start: day(2027, 1, 7), .weekly, end: day(2027, 1, 21))
        try d.setOccurrenceStatus(.done, id: id, on: day(2027, 1, 21), calendar: utc)
        let after = try XCTUnwrap(d.jobListEntries(now: day(2027, 3, 1), calendar: utc).first)
        XCTAssertEqual(after.start, day(2027, 1, 21))
        XCTAssertEqual(after.status, .done)
        // The last visit was marked ahead of time: nothing open is left, so it is not counted as active.
        let before = try XCTUnwrap(d.jobListEntries(now: day(2027, 1, 20), calendar: utc).first)
        XCTAssertEqual(before.start, day(2027, 1, 21))
        XCTAssertFalse(before.status.isOpen)
    }

    func testJobsListLeavesOutTasksAndKeepsOneOffJobsAsTheyAre() throws {
        var d = AppData()
        let once = try d.addJob(title: "Plow", start: day(2027, 1, 5), now: day(2027, 1, 1))
        _ = try d.addJob(title: "Buy salt", start: day(2027, 1, 6), isTask: true, now: day(2027, 1, 1))
        let list = d.jobListEntries(now: day(2027, 2, 1), calendar: utc)
        XCTAssertEqual(list, [once])
    }

    func testLastVisitOnOrBeforeADay() throws {
        var d = AppData()
        let weekly = try repeating(&d, start: day(2027, 1, 7), .everyTwoWeeks)
        let monthly = try repeating(&d, start: day(2027, 1, 31), .monthly)
        let w = try XCTUnwrap(d.jobs.first { $0.id == weekly })
        let m = try XCTUnwrap(d.jobs.first { $0.id == monthly })
        XCTAssertNil(w.lastOccurrence(onOrBefore: day(2027, 1, 6), calendar: utc))
        XCTAssertEqual(w.lastOccurrence(onOrBefore: day(2027, 1, 20), calendar: utc), day(2027, 1, 7))
        XCTAssertEqual(w.lastOccurrence(onOrBefore: day(2027, 1, 21, 1), calendar: utc), day(2027, 1, 21))
        XCTAssertEqual(m.lastOccurrence(onOrBefore: day(2027, 2, 27), calendar: utc), day(2027, 1, 31))
        XCTAssertEqual(m.lastOccurrence(onOrBefore: day(2027, 3, 15), calendar: utc), day(2027, 2, 28))   // the 31st in a short month
    }

    // MARK: reminders

    func testEveningReminderCoversLaterVisitsOfARepeatingJob() throws {
        let now = day(2027, 1, 15, 8)
        var (d, site) = business()
        d.profile.remindersEnabled = true
        d.session = AppSession(role: .owner, startedAt: now)
        d.subscription = Subscription(trialStart: nil, plan: .pro)
        let id = try repeating(&d, start: day(2027, 1, 9, 7), .weekly, siteID: site.id)

        // Jan 16 is the second visit: the old code only looked at the first date and stayed silent.
        var jobs = LocalReminderPlanner.plan(data: d, now: now, calendar: utc).filter { $0.kind == .jobs }
        XCTAssertEqual(jobs.map(\.id), ["ridgeline.reminder.jobs.2027-01-16"])
        XCTAssertEqual(jobs.first?.fireDate, day(2027, 1, 15, 19))
        XCTAssertEqual(jobs.first?.title, "Tomorrow: 1 job, first at 7:00 AM")

        // A skipped visit is not announced.
        try d.skipOccurrence(id: id, on: day(2027, 1, 16), calendar: utc)
        jobs = LocalReminderPlanner.plan(data: d, now: now, calendar: utc).filter { $0.kind == .jobs }
        XCTAssertTrue(jobs.isEmpty)
    }

    // MARK: auto check-in past midnight

    func testLeavingAfterMidnightClosesTheVisitTheCrewArrivedAt() throws {
        var (d, site) = business()
        let job = try d.addJob(title: "Plow", kind: .snowPlowing, siteID: site.id, start: day(2027, 1, 15, 23), now: day(2027, 1, 15))
        let arrived = day(2027, 1, 15, 23, 50), left = day(2027, 1, 16, 0, 20)
        XCTAssertTrue(try d.recordArrival(jobID: job.id, at: arrived, calendar: utc))
        let visitDay = try d.recordDeparture(jobID: job.id, at: left, markDone: true, calendar: utc)

        XCTAssertEqual(Job.dayKey(visitDay, calendar: utc), "2027-01-15")
        XCTAssertEqual(d.jobs[0].checkIn(on: arrived, calendar: utc), JobCheckIn(arrivedAt: arrived, departedAt: left))
        XCTAssertNil(d.jobs[0].checkIn(on: left, calendar: utc), "no second check-in on the next day")
        XCTAssertEqual(d.jobs[0].status, .done)
    }

    func testRepeatingVisitLeftAfterMidnightIsMarkedDoneOnItsOwnDay() throws {
        var (d, site) = business()
        let id = try repeating(&d, start: day(2027, 1, 8, 23), .weekly, siteID: site.id)
        let arrived = day(2027, 1, 15, 23, 50), left = day(2027, 1, 16, 0, 20)
        try d.recordArrival(jobID: id, at: arrived, calendar: utc)
        // The old code looked for a visit on Jan 16, found none and threw, so the departure was lost.
        XCTAssertNoThrow(try d.recordDeparture(jobID: id, at: left, markDone: true, calendar: utc))
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: arrived, calendar: utc), .done)
        XCTAssertEqual(d.jobs[0].checkIn(on: arrived, calendar: utc)?.departedAt, left)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: day(2027, 1, 22), calendar: utc), .scheduled)

        // Arriving just after midnight at last night's visit also belongs to that visit.
        var (late, lateSite) = business()
        let lateID = try repeating(&late, start: day(2027, 1, 8, 23), .weekly, siteID: lateSite.id)
        XCTAssertNoThrow(try late.recordArrival(jobID: lateID, at: day(2027, 1, 16, 0, 10), calendar: utc))
        XCTAssertEqual(late.jobs[0].occurrenceStatus(on: day(2027, 1, 15), calendar: utc), .inProgress)
        XCTAssertNotNil(late.jobs[0].checkIn(on: day(2027, 1, 15), calendar: utc))
    }

    // MARK: a storm that runs past midnight

    func testOpenStormJobsStayOnTheListAndRouteTheNextDay() throws {
        var d = AppData()
        for i in 0..<2 {
            let c = Customer(name: "Client \(i)")
            d.customers.append(c)
            d.sites.append(Site(customerID: c.id, address: "\(i + 1) Main St", latitude: 45 + Double(i) * 0.01, longitude: -93))
        }
        let started = day(2027, 1, 15, 22)
        let nextDay = day(2027, 1, 16, 3)
        try d.startStorm(baseName: "Jan 15", expectedInches: 4, siteIDs: d.sites.map(\.id), now: started)
        XCTAssertEqual(d.jobs(on: started, calendar: utc).count, 2)
        // After midnight the crew is still plowing: the old code showed an empty day and an empty route.
        XCTAssertEqual(d.jobs(on: nextDay, calendar: utc).count, 2)
        XCTAssertEqual(d.routeStops(on: nextDay, calendar: utc).count, 2)
        XCTAssertTrue(d.jobs(on: day(2027, 1, 17, 3), calendar: utc).isEmpty)

        // A site that is done leaves, and nothing is carried once the storm is finished.
        d.visitLog.append(VisitRecord(siteID: d.sites[0].id, crewMemberName: "Sam", stormID: "Jan 15", arrival: nextDay))
        d.markStormJobDone(after: d.visitLog.entries[0].record)
        XCTAssertEqual(d.routeStops(on: nextDay, calendar: utc).count, 1)
        try d.finishStorm(now: day(2027, 1, 16, 6))
        XCTAssertTrue(d.jobs(on: nextDay, calendar: utc).isEmpty)
        XCTAssertEqual(d.jobs(on: started, calendar: utc).count, 2)   // still on their own day, done and cancelled
    }

    // MARK: route order shared with employees

    func testAnEmployeeReorderingTheirStopsKeepsEveryoneElsesPlaces() {
        var d = AppData()
        let when = day(2027, 1, 15)
        let a = UUID(), b = UUID(), c = UUID(), e = UUID(), new = UUID()
        d.setRouteOrder([a, b, c, e], on: when, optimized: true, calendar: utc)
        // An employee who only sees b and e drags e first, with a stop they just added. The old code saved only
        // their stops, which threw away the order of a and c.
        d.setRouteOrder([e, b, new, e], on: when, optimized: false, calendar: utc)
        XCTAssertEqual(d.routeOrder(on: when, calendar: utc)?.stopIDs, [a, e, c, b, new])
        XCTAssertEqual(d.routeOrders.count, 1)
        // The owner, who sees every stop, still replaces the whole order.
        d.setRouteOrder([new, c, b, a, e], on: when, optimized: true, calendar: utc)
        XCTAssertEqual(d.routeOrder(on: when, calendar: utc)?.stopIDs, [new, c, b, a, e])
    }

    // MARK: calendar file

    func testCalendarFileKeepsARepeatingJobAtItsClockTimeAndMarksCancelledJobs() throws {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        var d = AppData()
        // Starts a week and a half before the clocks change (Mar 14, 2027).
        let weekly = try d.addJob(title: "Mow", start: day(2027, 3, 4, 9, in: chicago), durationMinutes: 90, now: day(2027, 3, 1))
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: weekly.id, calendar: chicago)
        let once = try d.addJob(title: "Plow", start: day(2027, 3, 5, 9, in: chicago), now: day(2027, 3, 1))
        try d.setJobStatus(.cancelled, id: once.id)

        let ics = CalendarExport.ics(jobs: d.jobs, data: d, company: "", now: day(2027, 3, 1), calendar: chicago)
        // In UTC (15:00Z) every visit after Mar 14 would show at 10 AM instead of 9.
        XCTAssertTrue(ics.contains("DTSTART;TZID=America/Chicago:20270304T090000\r\n"))
        XCTAssertTrue(ics.contains("DTEND;TZID=America/Chicago:20270304T103000\r\n"))
        XCTAssertTrue(ics.contains("RRULE:FREQ=WEEKLY;INTERVAL=1\r\n"))
        // A job that happens once stays in UTC, and a cancelled one says so.
        XCTAssertTrue(ics.contains("DTSTART:20270305T150000Z\r\n"))
        XCTAssertEqual(ics.components(separatedBy: "STATUS:CANCELLED").count, 2)
    }
}
