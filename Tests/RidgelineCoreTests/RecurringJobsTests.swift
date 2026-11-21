import XCTest
@testable import RidgelineCore

final class RecurringJobsTests: XCTestCase {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, in cal: Calendar? = nil) -> Date {
        (cal ?? utc).date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// One repeating job in otherwise empty data.
    func data(start: Date, _ frequency: RepeatFrequency, end: Date? = nil, siteID: UUID? = nil, setup: (inout AppData) -> Void = { _ in }) throws -> (AppData, Job) {
        var d = AppData()
        setup(&d)
        let job = try d.addJob(title: "Mow", kind: .lawnCare, siteID: siteID, start: start, now: start)
        try d.setJobRepeat(RepeatRule(frequency: frequency, endDate: end), id: job.id, calendar: utc)
        return (d, d.jobs[0])
    }

    func testWeeklyCrossesMonthEndAndKeepsTimeAndID() throws {
        let (d, job) = try data(start: day(2027, 1, 28, 9), .weekly)
        let visit = try XCTUnwrap(d.jobs(on: day(2027, 2, 4, 15), calendar: utc).first)
        XCTAssertEqual(visit.id, job.id)
        XCTAssertEqual(visit.start, day(2027, 2, 4, 9))
        XCTAssertEqual(visit.status, .scheduled)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 11), calendar: utc).count, 1)
        XCTAssertTrue(d.jobs(on: day(2027, 2, 5), calendar: utc).isEmpty)
        XCTAssertTrue(d.jobs(on: day(2027, 1, 21), calendar: utc).isEmpty)      // before the first visit
        XCTAssertEqual(d.jobs(on: day(2027, 1, 28), calendar: utc).first?.start, day(2027, 1, 28, 9))
    }

    func testEveryTwoAndFourWeeks() throws {
        let (two, _) = try data(start: day(2026, 12, 24), .everyTwoWeeks)
        XCTAssertTrue(two.jobs(on: day(2026, 12, 31), calendar: utc).isEmpty)
        XCTAssertEqual(two.jobs(on: day(2027, 1, 7), calendar: utc).count, 1)    // across the new year
        let (four, _) = try data(start: day(2027, 1, 7), .everyFourWeeks)
        XCTAssertTrue(four.jobs(on: day(2027, 1, 21), calendar: utc).isEmpty)
        XCTAssertEqual(four.jobs(on: day(2027, 2, 4), calendar: utc).count, 1)
        XCTAssertEqual(four.daysWithJobs(inMonthOf: day(2027, 3, 1), calendar: utc), [4])
    }

    func testEndDateIsTheLastVisit() throws {
        let (d, job) = try data(start: day(2027, 1, 7), .weekly, end: day(2027, 1, 21, 0))
        XCTAssertEqual(d.jobs(on: day(2027, 1, 21), calendar: utc).count, 1)
        XCTAssertTrue(d.jobs(on: day(2027, 1, 28), calendar: utc).isEmpty)
        XCTAssertNil(job.nextOccurrence(onOrAfter: day(2027, 1, 22), calendar: utc))
        XCTAssertEqual(job.nextOccurrence(onOrAfter: day(2027, 1, 15), calendar: utc), day(2027, 1, 21, 9))
        XCTAssertEqual(d.daysWithJobs(inMonthOf: day(2027, 1, 1), calendar: utc), [7, 14, 21])
        XCTAssertTrue(d.daysWithJobs(inMonthOf: day(2027, 2, 1), calendar: utc).isEmpty)
    }

    func testMonthlyOnThe31stUsesLastDayOfShortMonths() throws {
        let (d, job) = try data(start: day(2027, 1, 31), .monthly)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 28), calendar: utc).first?.start, day(2027, 2, 28, 9))
        XCTAssertTrue(d.jobs(on: day(2027, 2, 27), calendar: utc).isEmpty)
        XCTAssertEqual(d.jobs(on: day(2027, 3, 31), calendar: utc).count, 1)     // back on the 31st, no drift
        XCTAssertTrue(d.jobs(on: day(2027, 3, 28), calendar: utc).isEmpty)
        XCTAssertEqual(d.jobs(on: day(2027, 4, 30), calendar: utc).count, 1)
        XCTAssertEqual(d.jobs(on: day(2028, 2, 29), calendar: utc).count, 1)     // leap year
        XCTAssertEqual(d.daysWithJobs(inMonthOf: day(2027, 2, 10), calendar: utc), [28])
        XCTAssertEqual(job.nextOccurrence(onOrAfter: day(2027, 2, 1), calendar: utc), day(2027, 2, 28, 9))
        XCTAssertEqual(job.nextOccurrence(onOrAfter: day(2027, 3, 1), calendar: utc), day(2027, 3, 31, 9))
    }

    func testDaysWithJobsForWeeklyMonth() throws {
        let (d, _) = try data(start: day(2027, 1, 7), .weekly)
        XCTAssertEqual(d.daysWithJobs(inMonthOf: day(2027, 2, 15), calendar: utc), [4, 11, 18, 25])
    }

    func testOneVisitDoneOrSkippedLeavesTheOthers() throws {
        var (d, job) = try data(start: day(2027, 1, 28), .weekly)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2027, 2, 4), calendar: utc)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 4), calendar: utc).first?.status, .done)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 11), calendar: utc).first?.status, .scheduled)
        XCTAssertEqual(d.jobs(on: day(2027, 1, 28), calendar: utc).first?.status, .scheduled)
        try d.skipOccurrence(id: job.id, on: day(2027, 2, 11), calendar: utc)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 11), calendar: utc).first?.status, .cancelled)
        XCTAssertEqual(d.jobs(on: day(2027, 2, 4), calendar: utc).first?.status, .done)
        XCTAssertEqual(d.jobs[0].status, .scheduled)                              // the series itself is untouched
        XCTAssertEqual(d.jobs[0].occurrenceStatuses, ["2027-02-04": .done, "2027-02-11": .cancelled])
        try d.setOccurrenceStatus(.scheduled, id: job.id, on: day(2027, 2, 4), calendar: utc)
        try d.setOccurrenceStatus(.scheduled, id: job.id, on: day(2027, 2, 11), calendar: utc)
        XCTAssertNil(d.jobs[0].occurrenceStatuses)
        XCTAssertThrowsError(try d.setOccurrenceStatus(.done, id: job.id, on: day(2027, 2, 5), calendar: utc)) {
            XCTAssertEqual($0 as? OperationError, .notFound)
        }
        XCTAssertEqual(d.jobs.count, 1)                                            // no copies were made
    }

    func testRouteStopsIncludeVisitsButNotDoneOnes() throws {
        let c = Customer(name: "Pat")
        let site = Site(customerID: c.id, address: "1 Elm", latitude: 44.9, longitude: -93.2)
        var (d, job) = try data(start: day(2027, 1, 7), .everyTwoWeeks, siteID: site.id) { x in
            x.customers.append(c)
            x.sites = [site]
        }
        XCTAssertEqual(d.routeStops(on: day(2027, 1, 21), calendar: utc).map(\.id), [job.id])
        XCTAssertTrue(d.routeStops(on: day(2027, 1, 14), calendar: utc).isEmpty)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2027, 1, 21), calendar: utc)
        XCTAssertTrue(d.routeStops(on: day(2027, 1, 21), calendar: utc).isEmpty)
        XCTAssertEqual(d.routeStops(on: day(2027, 2, 4), calendar: utc).map(\.id), [job.id])
    }

    func testSetRepeatNeverClearsAndEarlyEndClamps() throws {
        var (d, job) = try data(start: day(2027, 1, 7), .weekly)
        try d.setJobRepeat(RepeatRule(frequency: .weekly, endDate: day(2026, 12, 1)), id: job.id, calendar: utc)
        XCTAssertEqual(d.jobs[0].repeatRule?.endDate, day(2027, 1, 7))
        XCTAssertTrue(d.jobs(on: day(2027, 1, 14), calendar: utc).isEmpty)
        try d.setJobRepeat(RepeatRule(frequency: .never), id: job.id, calendar: utc)
        XCTAssertNil(d.jobs[0].repeatRule)
        XCTAssertFalse(d.jobs[0].repeats)
        XCTAssertThrowsError(try d.setJobRepeat(nil, id: UUID(), calendar: utc))
    }

    func testWeeklyKeepsWallClockTimeAcrossDaylightSaving() throws {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        var d = AppData()
        let job = try d.addJob(title: "Mow", start: day(2027, 3, 4, 9, in: chicago), now: Date())
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: job.id, calendar: chicago)
        let visit = try XCTUnwrap(d.jobs(on: day(2027, 3, 18, 12, in: chicago), calendar: chicago).first)
        XCTAssertEqual(chicago.component(.hour, from: visit.start), 9)
    }

    func testSummaryAndCalendarFileRule() throws {
        XCTAssertEqual(RepeatRule(frequency: .weekly).summary, "Repeats every week")
        XCTAssertEqual(RepeatRule(frequency: .everyTwoWeeks).summary, "Repeats every 2 weeks")
        XCTAssertEqual(RepeatRule(frequency: .monthly).summary, "Repeats every month")
        let (_, two) = try data(start: day(2027, 1, 7), .everyTwoWeeks)
        XCTAssertEqual(two.icsRepeatRule(calendar: utc), "FREQ=WEEKLY;INTERVAL=2")
        let (_, monthly) = try data(start: day(2027, 1, 31), .monthly, end: day(2027, 6, 30, 12))
        XCTAssertEqual(monthly.icsRepeatRule(calendar: utc), "FREQ=MONTHLY;BYMONTHDAY=-1;UNTIL=20270630T235959Z")
        XCTAssertNil(Job(title: "Once", start: day(2027, 1, 7), createdAt: day(2027, 1, 7)).icsRepeatRule(calendar: utc))
        XCTAssertEqual(Job.dayKey(day(2027, 2, 4), calendar: utc), "2027-02-04")
    }

    func testOldSavedJobsStillLoadAndNewFieldsRoundTrip() throws {
        let once = Job(title: "Plow", start: day(2027, 1, 7), createdAt: day(2027, 1, 7))
        let oldData = try JSONEncoder().encode(once)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("repeatRule"))  // same shape as before
        XCTAssertEqual(try JSONDecoder().decode(Job.self, from: oldData), once)
        var repeating = once
        repeating.repeatRule = RepeatRule(frequency: .monthly, endDate: day(2027, 12, 1))
        repeating.occurrenceStatuses = ["2027-02-07": .done]
        let back = try JSONDecoder().decode(Job.self, from: try JSONEncoder().encode(repeating))
        XCTAssertEqual(back, repeating)
    }
}
