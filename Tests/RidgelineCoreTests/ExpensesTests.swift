import XCTest
@testable import RidgelineCore

final class ExpensesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)         // Fri 2027-01-15 08:00 UTC
    let zone = TimeZone(identifier: "UTC")!
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 1; return c }
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }

    /// An invoice for `total` dollars with the given payments recorded on it.
    func invoice(_ number: String, total: Int, issued: Date, payments: [(dollars: Int, date: Date)]) throws -> Invoice {
        var inv = Invoice(number: number, customerID: UUID(), siteID: UUID(), issueDate: issued, dueDate: issued.addingTimeInterval(14 * 86_400),
                          lines: [InvoiceLineItem(description: "Plowing", amount: Money(dollars: total))])
        try inv.markSent(at: issued)
        for p in payments { try inv.record(ManualPayment(amount: Money(dollars: p.dollars), date: p.date, method: .check)) }
        return inv
    }

    // MARK: totals by category

    func testTotalsByCategoryLargestFirst() {
        var d = AppData()
        d.expenses = [
            Expense(date: day(2027, 1, 4), category: .fuel, amount: Money(dollars: 40), vendor: "Shell"),
            Expense(date: day(2027, 1, 11), category: .fuel, amount: Money(dollars: 60)),
            Expense(date: day(2027, 1, 6), category: .saltAndMaterials, amount: Money(dollars: 250)),
            Expense(date: day(2027, 1, 12), category: .repairs, amount: Money(dollars: 100)),
            Expense(date: day(2026, 12, 20), category: .insurance, amount: Money(dollars: 900)),          // last month
        ]
        let r = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(r.byCategory.map(\.category), [.saltAndMaterials, .fuel, .repairs])               // a tie keeps the list order
        XCTAssertEqual(r.byCategory.map(\.total.cents), [25_000, 10_000, 10_000])
        XCTAssertEqual(r.byCategory.map(\.count), [1, 2, 1])
        XCTAssertEqual(r.expensesTotal, Money(dollars: 450))
        XCTAssertEqual(r.expenses.map(\.date), [day(2027, 1, 12), day(2027, 1, 11), day(2027, 1, 6), day(2027, 1, 4)])   // newest first
        XCTAssertEqual(r.previousMoneyOut, Money(dollars: 900))
    }

    // MARK: mileage

    func testMileageWorksOutTheAmount() {
        let trip = MileageTrip(miles: 42, centsPerMile: 70)
        XCTAssertEqual(trip.amount.cents, 2_940)
        XCTAssertEqual(trip.summary, "42 miles at $0.70")
        XCTAssertEqual(MileageTrip(miles: 1, centsPerMile: 70).summary, "1 mile at $0.70")
        let half = MileageTrip(miles: 12.5, centsPerMile: 72.5)                                         // a half-cent rate
        XCTAssertEqual(half.amount.cents, 906)                                                           // 906.25 to the nearest cent
        XCTAssertEqual(half.summary, "12.5 miles at $0.725")
        XCTAssertEqual(MileageTrip(miles: 42, dollarsPerMile: 0.70), trip)                               // a rate typed in dollars
        XCTAssertEqual(MileageTrip(miles: 10, dollarsPerMile: 0.67).rateText, "$0.67")
        XCTAssertEqual(MileageTrip(miles: 10, dollarsPerMile: 0.725).centsPerMile, 72.5)
        XCTAssertEqual(MileageTrip(miles: -5, centsPerMile: 70).amount, .zero)                           // nonsense is not money
        XCTAssertEqual(MileageTrip(miles: .infinity, centsPerMile: .nan).amount, .zero)

        var e = Expense(date: day(2027, 1, 5), mileage: trip, note: "Salt yard run")
        XCTAssertEqual(e.amount.cents, 2_940)
        XCTAssertEqual(e.category, .fuel)
        e.setMileage(MileageTrip(miles: 10, centsPerMile: 70))
        XCTAssertEqual(e.amount.cents, 700)
        e.setAmount(Money(dollars: 12))
        XCTAssertNil(e.mileage)
        XCTAssertEqual(e.amount, Money(dollars: 12))

        var d = AppData()
        d.expenses = [Expense(date: day(2027, 1, 5), mileage: trip)]
        XCTAssertEqual(ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc).expensesTotal.cents, 2_940)
    }

    // MARK: labor

    func testLaborIsHoursTimesEachPersonsRate() throws {
        var d = AppData()
        var g = SystemRandomNumberGenerator()
        _ = try d.addTeamMember(name: "Dana Cole", role: .crewMember, username: "dana", password: "Plow-2027-ok", hourlyRate: Money(dollars: 20), now: now, iterations: 2, using: &g)
        _ = try d.addTeamMember(name: "Lee Park", role: .crewLead, username: "lee", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)      // no rate
        _ = try d.addTeamMember(name: "Sam Roy", role: .crewMember, username: "sam", password: "Plow-2027-ok", hourlyRate: Money(cents: 3_050), now: now, iterations: 2, using: &g)
        d.timeEntries = [
            TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 11, 8), end: day(2027, 1, 11, 12)),                             // 4 h
            TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 12, 8), end: day(2027, 1, 12, 10).addingTimeInterval(1800)),    // 2.5 h
            TimeEntry(memberName: "Lee Park", start: day(2027, 1, 13, 9), end: day(2027, 1, 13, 11)),                              // 2 h, no rate
            TimeEntry(memberName: "Sam Roy", start: day(2027, 1, 14, 9), end: day(2027, 1, 14, 11)),                               // 2 h at $30.50
            TimeEntry(memberName: "Dana Cole", start: day(2026, 12, 30, 8), end: day(2026, 12, 30, 18)),                           // last month: 10 h
        ]
        let r = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(r.laborHours, 10.5, accuracy: 0.001)
        XCTAssertEqual(r.laborCost.cents, 13_000 + 6_100)                                 // 6.5 h at $20 plus 2 h at $30.50
        XCTAssertEqual(r.missingRates, ["Lee Park"])                                      // Lee's hours are not in the cost
        XCTAssertEqual(r.labor.count, 3)
        XCTAssertEqual(r.moneyOut.cents, 19_100)
        XCTAssertEqual(r.previousMoneyOut.cents, 20_000)                                  // December's 10 h at $20
        // The same sums as the timesheets screen.
        let sheet = TimesheetReport.compute(for: d, interval: TimesheetPeriod.month.interval(now: now, calendar: utc), now: now)
        XCTAssertEqual(r.laborCost, sheet.payOwed)
    }

    // MARK: profit and margin

    func testProfitAndMarginComparedWithThePeriodBefore() throws {
        var d = AppData()
        var g = SystemRandomNumberGenerator()
        _ = try d.addTeamMember(name: "Dana Cole", role: .crewMember, username: "dana", password: "Plow-2027-ok", hourlyRate: Money(dollars: 20), now: now, iterations: 2, using: &g)
        var voided = try invoice("INV-0003", total: 700, issued: day(2027, 1, 3), payments: [(700, day(2027, 1, 4))])
        voided.void()
        d.invoices = [
            try invoice("INV-0001", total: 1_000, issued: day(2027, 1, 2), payments: [(600, day(2027, 1, 5)), (400, day(2027, 1, 9))]),
            try invoice("INV-0002", total: 400, issued: day(2026, 12, 2), payments: [(400, day(2026, 12, 10))]),
            voided,                                                                       // a void invoice is not income
        ]
        d.expenses = [
            Expense(date: day(2027, 1, 6), category: .saltAndMaterials, amount: Money(dollars: 300)),
            Expense(date: day(2026, 12, 6), category: .fuel, amount: Money(dollars: 100)),
        ]
        d.timeEntries = [TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 11, 6), end: day(2027, 1, 11, 16))]      // 10 h at $20
        let r = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(r.moneyIn, Money(dollars: 1_000))
        XCTAssertEqual(r.expensesTotal, Money(dollars: 300))
        XCTAssertEqual(r.laborCost, Money(dollars: 200))
        XCTAssertEqual(r.moneyOut, Money(dollars: 500))
        XCTAssertEqual(r.profit, Money(dollars: 500))
        XCTAssertEqual(r.marginPercent, 50)
        XCTAssertTrue(r.hasPrevious)
        XCTAssertEqual(r.previousProfit, Money(dollars: 300))                             // December: 400 in, 100 out
        XCTAssertEqual(r.profitChange, Money(dollars: 200))
        XCTAssertFalse(r.isEmpty)
    }

    func testALossAndAnEmptyPeriod() throws {
        var d = AppData()
        let empty = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.marginPercent)                                                 // nothing came in, so no margin
        XCTAssertFalse(empty.hasPrevious)
        XCTAssertEqual(empty.profit, .zero)

        d.expenses = [Expense(date: day(2027, 1, 6), category: .repairs, amount: Money(dollars: 150))]
        let onlyOut = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(onlyOut.profit.cents, -15_000)
        XCTAssertNil(onlyOut.marginPercent)

        d.invoices = [try invoice("INV-0001", total: 100, issued: day(2027, 1, 2), payments: [(100, day(2027, 1, 5))])]
        let loss = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(loss.profit.cents, -5_000)
        XCTAssertEqual(loss.marginPercent, -50)
        d.expenses = [Expense(date: day(2027, 1, 6), category: .repairs, amount: Money(cents: 3_333))]
        XCTAssertEqual(ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc).marginPercent, 66.7)   // one decimal
    }

    // MARK: period boundaries

    func testPeriodsCoverTheRightDays() {
        let week = ProfitPeriod.thisWeek.intervals(now: now, calendar: utc)
        XCTAssertEqual(week.current.start, day(2027, 1, 10, 0)); XCTAssertEqual(week.current.end, day(2027, 1, 17, 0))      // Sunday to Sunday
        XCTAssertEqual(week.previous.start, day(2027, 1, 3, 0)); XCTAssertEqual(week.previous.end, day(2027, 1, 10, 0))
        let month = ProfitPeriod.thisMonth.intervals(now: now, calendar: utc)
        XCTAssertEqual(month.current.start, day(2027, 1, 1, 0)); XCTAssertEqual(month.current.end, day(2027, 2, 1, 0))
        XCTAssertEqual(month.previous.start, day(2026, 12, 1, 0)); XCTAssertEqual(month.previous.end, day(2027, 1, 1, 0))
        let year = ProfitPeriod.thisYear.intervals(now: now, calendar: utc)
        XCTAssertEqual(year.current.start, day(2027, 1, 1, 0)); XCTAssertEqual(year.current.end, day(2028, 1, 1, 0))
        XCTAssertEqual(year.previous.start, day(2026, 1, 1, 0)); XCTAssertEqual(year.previous.end, day(2027, 1, 1, 0))
        // A season runs July to June, so January 2027 belongs to the season that began in July 2026.
        let season = ProfitPeriod.season.intervals(now: now, calendar: utc)
        XCTAssertEqual(season.current.start, day(2026, 7, 1, 0)); XCTAssertEqual(season.current.end, day(2027, 7, 1, 0))
        XCTAssertEqual(season.previous.start, day(2025, 7, 1, 0)); XCTAssertEqual(season.previous.end, day(2026, 7, 1, 0))
        let summer = ProfitPeriod.season.intervals(now: day(2027, 7, 1, 0), calendar: utc)                                    // the first minute of a new season
        XCTAssertEqual(summer.current.start, day(2027, 7, 1, 0)); XCTAssertEqual(summer.current.end, day(2028, 7, 1, 0))
        XCTAssertEqual(summer.previous.start, day(2026, 7, 1, 0))
    }

    func testTheStartOfAPeriodCountsAndTheEndDoesNot() throws {
        var d = AppData()
        var g = SystemRandomNumberGenerator()
        _ = try d.addTeamMember(name: "Dana Cole", role: .crewMember, username: "dana", password: "Plow-2027-ok", hourlyRate: Money(dollars: 20), now: now, iterations: 2, using: &g)
        let lastSecondOfDecember = day(2027, 1, 1, 0).addingTimeInterval(-1)
        d.expenses = [
            Expense(date: day(2027, 1, 1, 0), category: .fuel, amount: Money(dollars: 1)),               // first instant of January
            Expense(date: lastSecondOfDecember, category: .fuel, amount: Money(dollars: 10)),
            Expense(date: day(2027, 2, 1, 0), category: .fuel, amount: Money(dollars: 100)),             // first instant of February
        ]
        d.invoices = [try invoice("INV-0001", total: 1_110, issued: day(2026, 12, 1), payments: [
            (1, day(2027, 1, 1, 0)), (10, lastSecondOfDecember), (100, day(2027, 2, 1, 0)),
        ])]
        d.timeEntries = [
            TimeEntry(memberName: "Dana Cole", start: day(2027, 1, 1, 0), end: day(2027, 1, 1, 1)),      // 1 h, starts with January
            TimeEntry(memberName: "Dana Cole", start: day(2027, 2, 1, 0), end: day(2027, 2, 1, 5)),      // starts with February
        ]
        let january = ProfitReport.compute(for: d, period: .thisMonth, now: now, calendar: utc)
        XCTAssertEqual(january.expensesTotal, Money(dollars: 1))
        XCTAssertEqual(january.moneyIn, Money(dollars: 1))
        XCTAssertEqual(january.laborCost, Money(dollars: 20))
        XCTAssertEqual(january.previousMoneyIn, Money(dollars: 10))
        XCTAssertEqual(january.previousMoneyOut, Money(dollars: 10))
        // Nothing is counted twice: February picks up exactly what January left out.
        let february = ProfitReport.compute(for: d, period: .thisMonth, now: day(2027, 2, 10), calendar: utc)
        XCTAssertEqual(february.expensesTotal, Money(dollars: 100))
        XCTAssertEqual(february.moneyIn, Money(dollars: 100))
        XCTAssertEqual(february.laborCost, Money(dollars: 100))
        XCTAssertEqual(february.previousMoneyIn, Money(dollars: 1))
        // The week only sees its own days.
        d.expenses = [Expense(date: day(2027, 1, 9, 23), category: .fuel, amount: Money(dollars: 5)),
                      Expense(date: day(2027, 1, 10, 0), category: .fuel, amount: Money(dollars: 7))]
        let week = ProfitReport.compute(for: d, period: .thisWeek, now: now, calendar: utc)
        XCTAssertEqual(week.expensesTotal, Money(dollars: 7))
        XCTAssertEqual(week.previousMoneyOut, Money(dollars: 5))
    }

    // MARK: spreadsheet for the accountant

    func testCSVQuotesCommasQuotesAndLineBreaks() {
        let list = [
            Expense(date: day(2027, 1, 7), category: .other, amount: Money(cents: 505), vendor: "=SUM(A1)"),
            Expense(date: day(2027, 1, 5), category: .saltAndMaterials, amount: Money(cents: 123_450), vendor: "Bob's \"Best\" Salt, Inc.", note: "two\nlines"),
            Expense(date: day(2027, 1, 6), mileage: MileageTrip(miles: 42, centsPerMile: 70), note: "Salt yard run"),
            Expense(date: day(2027, 1, 8), category: .fuel, mileage: MileageTrip(miles: 3, centsPerMile: 70)),
        ]
        let csv = ExpenseCSV.export(list, timeZone: zone)
        let expected = [
            "Date,Category,Vendor,Amount,Note",
            "2027-01-05,Salt and materials,\"Bob's \"\"Best\"\" Salt, Inc.\",1234.50,two lines",
            "2027-01-06,Fuel,,29.40,Salt yard run (42 miles at $0.70)",
            "2027-01-07,Other,'=SUM(A1),5.05,",                                           // a formula is defused
            "2027-01-08,Fuel,,2.10,3 miles at $0.70",
        ].joined(separator: "\r\n") + "\r\n"
        XCTAssertEqual(csv, expected)
        // A spreadsheet reads the quoted cell back as typed.
        let rows = ClientImport.parseCSV(csv)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[1], ["2027-01-05", "Salt and materials", "Bob's \"Best\" Salt, Inc.", "1234.50", "two lines"])
        XCTAssertTrue(rows.allSatisfy { $0.count == 5 })
        XCTAssertEqual(ExpenseCSV.export([], timeZone: zone), "Date,Category,Vendor,Amount,Note\r\n")
    }

    func testCSVDatesUseTheGivenTimeZone() {
        let lateEvening = Expense(date: day(2027, 1, 1, 3), category: .fuel, amount: Money(dollars: 20))     // 03:00 UTC is still Dec 31 in New York
        XCTAssertTrue(ExpenseCSV.export([lateEvening], timeZone: zone).contains("2027-01-01,Fuel"))
        XCTAssertTrue(ExpenseCSV.export([lateEvening], timeZone: TimeZone(identifier: "America/New_York")!).contains("2026-12-31,Fuel"))
    }

    // MARK: saving

    func testSavingReplacingAndRemoving() throws {
        var d = AppData()
        XCTAssertThrowsError(try d.saveExpense(Expense(date: now, category: .fuel, amount: .zero))) { XCTAssertEqual($0 as? ExpenseError, .invalidAmount) }
        XCTAssertThrowsError(try d.saveExpense(Expense(date: now, category: .fuel, amount: Money(cents: -500))))
        XCTAssertThrowsError(try d.saveExpense(Expense(date: now, category: .fuel, amount: Expense.maxAmount + Money(cents: 1))))
        XCTAssertTrue(d.expenses.isEmpty)

        var e = Expense(date: now, category: .fuel, amount: Money(dollars: 40), vendor: "  Shell  ", note: String(repeating: "x", count: 900), receiptPhoto: "abc.jpg")
        try d.saveExpense(e)
        XCTAssertEqual(d.expenses.count, 1)
        XCTAssertEqual(d.expenses[0].vendor, "Shell")
        XCTAssertEqual(d.expenses[0].note.count, 500)
        XCTAssertEqual(d.expenses[0].receiptPhoto, "abc.jpg")

        e.setAmount(Money(dollars: 45))
        e.category = .repairs
        try d.saveExpense(e)                                                              // same id: replaced, not added twice
        XCTAssertEqual(d.expenses.count, 1)
        XCTAssertEqual(d.expenses[0].amount, Money(dollars: 45))
        XCTAssertEqual(d.expenses[0].category, .repairs)

        try d.removeExpense(id: e.id)
        XCTAssertTrue(d.expenses.isEmpty)
        XCTAssertThrowsError(try d.removeExpense(id: e.id)) { XCTAssertEqual($0 as? ExpenseError, .notFound) }
    }

    func testTypedAmounts() {
        XCTAssertEqual(ExpenseInput.money("12"), Money(dollars: 12))
        XCTAssertEqual(ExpenseInput.money("12.5"), Money(cents: 1_250))
        XCTAssertEqual(ExpenseInput.money("19.99"), Money(cents: 1_999))
        XCTAssertEqual(ExpenseInput.money(" $1,234.50 "), Money(cents: 123_450))
        XCTAssertEqual(ExpenseInput.money("12,50"), Money(cents: 1_250))                  // a comma as the decimal mark
        XCTAssertEqual(ExpenseInput.money("1,234"), Money(dollars: 1_234))                // a comma as the thousands mark
        for bad in ["", "abc", "0", "0.004", "-5", "1.2.3", "12 dollars", "99999999999"] {
            XCTAssertNil(ExpenseInput.money(bad), bad)
        }
        XCTAssertEqual(ExpenseInput.number("42.5"), 42.5)
        XCTAssertEqual(ExpenseInput.number("0"), 0)
        XCTAssertNil(ExpenseInput.number("forty"))
    }

    // MARK: old saved files

    func testOldSavedFilesStillLoad() throws {
        // A file saved before expenses existed.
        let old = Data(#"{"companyName":"Old Plow Co","customers":[]}"#.utf8)
        let loaded = try FileStore.decoder.decode(AppData.self, from: old)
        XCTAssertEqual(loaded.companyName, "Old Plow Co")
        XCTAssertEqual(loaded.expenses, [])

        // An expense with only the basics, and a category this version does not know.
        let sparse = Data(#"{"expenses":[{"date":"2027-01-05T12:00:00Z","amount":{"cents":1250}},{"date":"2027-01-06T12:00:00Z","amount":{"cents":900},"category":"drones"}]}"#.utf8)
        let two = try FileStore.decoder.decode(AppData.self, from: sparse).expenses
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two[0].amount.cents, 1_250)
        XCTAssertEqual(two[0].category, .other)
        XCTAssertEqual(two[0].vendor, "")
        XCTAssertNil(two[0].receiptPhoto)
        XCTAssertNil(two[0].mileage)
        XCTAssertEqual(two[1].category, .other)
    }

    func testExpensesSurviveSavingAndLoading() throws {
        var d = AppData()
        try d.saveExpense(Expense(date: day(2027, 1, 5), category: .insurance, amount: Money(dollars: 310), vendor: "Acme Mutual", note: "January", receiptPhoto: "r1.jpg"))
        try d.saveExpense(Expense(date: day(2027, 1, 6), mileage: MileageTrip(miles: 42, centsPerMile: 72.5), note: "Depot"))
        let back = try FileStore.decoder.decode(AppData.self, from: FileStore.encoder.encode(d))
        XCTAssertEqual(back.expenses, d.expenses)
        XCTAssertEqual(back.expenses[1].mileage?.summary, "42 miles at $0.725")
        XCTAssertEqual(back.expenses[1].amount.cents, 3_045)
    }
}
