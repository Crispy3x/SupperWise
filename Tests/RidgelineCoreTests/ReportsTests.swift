import XCTest
@testable import RidgelineCore

final class ReportsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)         // Fri 2027-01-15 08:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 1; return c }
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }

    // MARK: timesheets

    func testPeriodsCoverTheRightDays() {
        let this = TimesheetPeriod.thisWeek.interval(now: now, calendar: utc)
        XCTAssertEqual(this.start, day(2027, 1, 10, 0))                         // Sunday
        XCTAssertEqual(this.end, day(2027, 1, 17, 0))
        let last = TimesheetPeriod.lastWeek.interval(now: now, calendar: utc)
        XCTAssertEqual(last.start, day(2027, 1, 3, 0)); XCTAssertEqual(last.end, day(2027, 1, 10, 0))
        let month = TimesheetPeriod.month.interval(now: now, calendar: utc)
        XCTAssertEqual(month.start, day(2027, 1, 1, 0)); XCTAssertEqual(month.end, day(2027, 2, 1, 0))
        let custom = TimesheetPeriod.custom.interval(now: now, calendar: utc, custom: day(2027, 1, 5)...day(2027, 1, 7))
        XCTAssertEqual(custom.start, day(2027, 1, 5, 0)); XCTAssertEqual(custom.end, day(2027, 1, 8, 0))            // includes the last day
        let backwards = TimesheetPeriod.custom.interval(now: now, calendar: utc, custom: day(2027, 1, 5)...day(2027, 1, 5))
        XCTAssertEqual(backwards.duration, 86_400)
    }

    func testHoursAndPayOwedPerPerson() throws {
        var d = AppData()
        var g = SystemRandomNumberGenerator()
        let dana = try d.addTeamMember(name: "Dana Cole", role: .crewMember, username: "dana", password: "Plow-2027-ok", hourlyRate: Money(dollars: 20), now: now, iterations: 2, using: &g)
        _ = try d.addTeamMember(name: "Lee Park", role: .crewLead, username: "lee", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)      // no rate
        d.timeEntries = [
            TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 11, 8), end: day(2027, 1, 11, 12)),                  // 4 h
            TimeEntry(memberName: "dana cole", start: day(2027, 1, 12, 8), end: day(2027, 1, 12, 10).addingTimeInterval(1800)),   // 2.5 h, name case differs
            TimeEntry(memberName: "Lee Park", start: day(2027, 1, 13, 9), end: day(2027, 1, 13, 11)),                   // 2 h, no rate
            TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 2, 8), end: day(2027, 1, 2, 12)),                    // last week
        ]
        let r = TimesheetReport.compute(for: d, interval: TimesheetPeriod.thisWeek.interval(now: now, calendar: utc), now: now)
        XCTAssertEqual(r.totalHours, 8.5, accuracy: 0.001)
        XCTAssertEqual(r.rows.count, 2)                                                                                   // "Dana Cole" and "dana cole" are one person
        XCTAssertEqual(r.rows.first { $0.name == "Dana Cole" }?.hours ?? 0, 6.5, accuracy: 0.001)
        XCTAssertEqual(r.payOwed.cents, 13_000)                                                                           // 6.5 h at $20
        XCTAssertEqual(r.missingRates, ["Lee Park"])
        _ = dana
    }

    func testAnOpenShiftCountsUpToNow() {
        var d = AppData()
        d.timeEntries = [TimeEntry(memberName: "Dana", start: now.addingTimeInterval(-3 * 3600))]
        let r = TimesheetReport.compute(for: d, interval: TimesheetPeriod.thisWeek.interval(now: now, calendar: utc), now: now)
        XCTAssertEqual(r.totalHours, 3, accuracy: 0.001)
        XCTAssertEqual(TimesheetReport.compute(for: d, interval: TimesheetPeriod.lastWeek.interval(now: now, calendar: utc), now: now).totalHours, 0)
    }

    func testHourlyRateIsCheckedAndOptional() throws {
        var d = AppData()
        var g = SystemRandomNumberGenerator()
        let m = try d.addTeamMember(name: "Dana", role: .crewMember, username: "dana", password: "Plow-2027-ok", hourlyRate: Money(dollars: -5), now: now, iterations: 2, using: &g)
        XCTAssertNil(d.team[0].hourlyRate)                                                // a negative rate is ignored
        try d.setHourlyRate(Money(dollars: 18), forMember: m.id)
        XCTAssertEqual(d.team[0].hourlyRate, Money(dollars: 18))
        try d.setHourlyRate(Money(dollars: 5000), forMember: m.id)
        XCTAssertNil(d.team[0].hourlyRate)                                                // absurd values are dropped
        XCTAssertThrowsError(try d.setHourlyRate(nil, forMember: UUID()))
        let old = try JSONDecoder().decode(TeamMember.self, from: JSONEncoder().encode(TeamMember(name: "X", role: .office, createdAt: now)))
        XCTAssertNil(old.hourlyRate)
    }

    // MARK: revenue

    private func world() throws -> AppData {
        var d = AppData()
        let c = Customer(name: "Pat Miller"); d.customers = [c]
        let s = Site(customerID: c.id, address: "14 Elm"); d.sites = [s]
        func inv(_ n: String, _ pays: [(Date, Int)]) throws -> Invoice {
            var i = Invoice(number: n, customerID: c.id, siteID: s.id, issueDate: day(2026, 12, 1), dueDate: day(2027, 2, 1), lines: [InvoiceLineItem(description: "x", amount: Money(cents: 100_000))])
            for p in pays { try i.record(ManualPayment(amount: Money(cents: p.1), date: p.0, method: .cash)) }
            return i
        }
        d.invoices = [try inv("INV-1", [(day(2027, 1, 5), 10_000), (day(2027, 1, 12), 5_000)]),
                      try inv("INV-2", [(day(2026, 12, 20), 8_000)]),
                      try inv("INV-3", [(day(2026, 6, 3), 20_000)])]
        return d
    }

    func testTotalsPeriodsAndComparison() throws {
        let d = try world()
        let m = RevenueReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(m.allTime.cents, 43_000); XCTAssertEqual(m.thisMonth.cents, 15_000); XCTAssertEqual(m.periodTotal.cents, 15_000)
        XCTAssertEqual(m.percentChange, 87.5)                                             // 15,000 vs December's 8,000
        let last = RevenueReport.compute(for: d, period: .lastMonth, now: now, calendar: utc)
        XCTAssertEqual(last.periodTotal.cents, 8_000); XCTAssertNil(last.percentChange)                  // nothing in November to compare with
        let year = RevenueReport.compute(for: d, period: .thisYear, now: now, calendar: utc)
        XCTAssertEqual(year.periodTotal.cents, 15_000)
        let all = RevenueReport.compute(for: d, period: .allTime, now: now, calendar: utc)
        XCTAssertEqual(all.periodTotal.cents, 43_000); XCTAssertNil(all.percentChange)
    }

    func testBarsAreDailyForAMonthAndMonthlyForALongerSpan() throws {
        let d = try world()
        let m = RevenueReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(m.bars.map(\.amount.cents), [10_000, 5_000])
        XCTAssertEqual(m.bars.map(\.start), [day(2027, 1, 5, 0), day(2027, 1, 12, 0)])
        let all = RevenueReport.compute(for: d, period: .allTime, now: now, calendar: utc)
        XCTAssertEqual(all.bars.map(\.amount.cents), [20_000, 8_000, 15_000])             // June, December, January
    }

    func testRecentRevenueIsNewestFirstAndSkipsVoidInvoices() throws {
        var d = try world()
        XCTAssertEqual(RevenueReport.compute(for: d, period: .allTime, now: now, calendar: utc).recent.map(\.invoiceNumber), ["INV-1", "INV-1", "INV-2", "INV-3"])
        XCTAssertEqual(RevenueReport.compute(for: d, period: .allTime, now: now, calendar: utc).recent[0].client, "Pat Miller")
        d.invoices[0].void()
        let r = RevenueReport.compute(for: d, period: .allTime, now: now, calendar: utc)
        XCTAssertEqual(r.allTime.cents, 28_000)                                           // payments on a void invoice are not revenue
        XCTAssertEqual(AppData().invoices.count, 0)
        let empty = RevenueReport.compute(for: AppData(), period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(empty.allTime.cents, 0); XCTAssertEqual(empty.percentChange, 0); XCTAssertTrue(empty.bars.isEmpty); XCTAssertTrue(empty.recent.isEmpty)
    }

    func testTheTrialEndsFourteenDaysAfterItStarts() {
        let s = Subscription.startTrial(at: now)
        XCTAssertEqual(s.trialEnd, now.addingTimeInterval(14 * 86_400))
        XCTAssertNil(Subscription().trialEnd)
    }
}
