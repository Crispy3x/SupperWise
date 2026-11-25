import XCTest
@testable import RidgelineCore

final class AccountingExportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)         // Fri 2027-01-15 08:00 UTC
    let zone = TimeZone(identifier: "UTC")!
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
    var january: DateInterval { DateInterval(start: day(2027, 1, 1, 0), end: day(2027, 2, 1, 0)) }

    /// Two clients and five invoices: partly paid, overdue, paid last month, void, and a draft.
    func sample() throws -> AppData {
        var d = AppData()
        let pat = Customer(name: "Pat Miller")
        let smith = Customer(name: "Smith, \"Bud\" & Sons")
        d.customers = [pat, smith]
        let site = UUID()

        var one = Invoice(number: "INV-0001", customerID: pat.id, siteID: site, issueDate: day(2027, 1, 5), dueDate: day(2027, 1, 19), lines: [
            InvoiceLineItem(description: "Plowing 1/4", amount: Money(dollars: 100)),
            InvoiceLineItem(description: " Salt ", amount: Money(cents: 2_550)),
        ])
        try one.markSent(at: day(2027, 1, 5))
        try one.record(ManualPayment(amount: Money(dollars: 50), date: day(2027, 1, 10), method: .check))
        try one.record(ManualPayment(amount: Money(cents: 2_550), date: day(2027, 1, 12), method: .bankTransfer))

        var two = Invoice(number: "INV-0002", customerID: smith.id, siteID: site, issueDate: day(2027, 1, 8), dueDate: day(2027, 1, 12),
                          lines: [InvoiceLineItem(description: "Lot, north side", amount: Money(dollars: 300))])
        try two.markSent(at: day(2027, 1, 8))

        var three = Invoice(number: "INV-0003", customerID: pat.id, siteID: site, issueDate: day(2026, 12, 20), dueDate: day(2027, 1, 3),
                            lines: [InvoiceLineItem(description: "Plowing 12/19", amount: Money(dollars: 80))])
        try three.markSent(at: day(2026, 12, 20))
        try three.record(ManualPayment(amount: Money(dollars: 80), date: day(2026, 12, 28), method: .cash))

        var four = Invoice(number: "INV-0004", customerID: pat.id, siteID: site, issueDate: day(2027, 1, 9), dueDate: day(2027, 1, 23),
                           lines: [InvoiceLineItem(description: "Entered by mistake", amount: Money(dollars: 999))])
        try four.record(ManualPayment(amount: Money(dollars: 999), date: day(2027, 1, 9), method: .card))
        four.void()

        let five = Invoice(number: "INV-0005", customerID: pat.id, siteID: site, issueDate: day(2027, 1, 14), dueDate: day(2027, 1, 28),
                           lines: [InvoiceLineItem(description: "Mowing", amount: Money(dollars: 45))])

        d.invoices = [five, four, three, two, one]                // saved out of order on purpose
        return d
    }

    func testInvoicesForADateRange() throws {
        let csv = AccountingExport.invoicesCSV(try sample(), in: january, now: now, timeZone: zone)
        let expected = [
            "Invoice Number,Invoice Date,Due Date,Client,Description,Total,Paid,Balance,Status",
            "INV-0001,2027-01-05,2027-01-19,Pat Miller,Plowing 1/4; Salt,125.50,75.50,50.00,Partly paid",
            "INV-0002,2027-01-08,2027-01-12,\"Smith, \"\"Bud\"\" & Sons\",\"Lot, north side\",300.00,0.00,300.00,Overdue",
            "INV-0005,2027-01-14,2027-01-28,Pat Miller,Mowing,45.00,0.00,45.00,Draft",
        ].joined(separator: "\r\n") + "\r\n"
        XCTAssertEqual(csv, expected)                             // oldest first, December and the void invoice left out
        // Every row reads back with the same nine columns, commas and quotes intact.
        let rows = ClientImport.parseCSV(csv)
        XCTAssertTrue(rows.allSatisfy { $0.count == 9 })
        XCTAssertEqual(rows[2][3], "Smith, \"Bud\" & Sons")
        XCTAssertEqual(rows[2][4], "Lot, north side")
    }

    func testAllInvoicesWhenThereIsNoRange() throws {
        let rows = ClientImport.parseCSV(AccountingExport.invoicesCSV(try sample(), now: now, timeZone: zone))
        XCTAssertEqual(rows.dropFirst().map { $0[0] }, ["INV-0003", "INV-0001", "INV-0002", "INV-0005"])
        XCTAssertEqual(rows[1][8], "Paid")
        XCTAssertEqual(Array(rows[1][5...7]), ["80.00", "80.00", "0.00"])
    }

    func testPaymentsForADateRange() throws {
        let d = try sample()
        let expected = [
            "Date,Invoice Number,Client,Amount,Method",
            "2027-01-10,INV-0001,Pat Miller,50.00,Check",
            "2027-01-12,INV-0001,Pat Miller,25.50,Bank transfer",
        ].joined(separator: "\r\n") + "\r\n"
        XCTAssertEqual(AccountingExport.paymentsCSV(d, in: january, timeZone: zone), expected)      // the void invoice's payment is not income
        let all = ClientImport.parseCSV(AccountingExport.paymentsCSV(d, timeZone: zone))
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(all[1], ["2026-12-28", "INV-0003", "Pat Miller", "80.00", "Cash"])
    }

    func testTheStartOfTheRangeCountsAndTheEndDoesNot() throws {
        let d = try sample()
        let paidAt = day(2027, 1, 10)                             // the first payment on INV-0001
        let startingThen = DateInterval(start: paidAt, end: paidAt.addingTimeInterval(60))
        let endingThen = DateInterval(start: paidAt.addingTimeInterval(-60), end: paidAt)
        XCTAssertEqual(ClientImport.parseCSV(AccountingExport.paymentsCSV(d, in: startingThen, timeZone: zone)).count, 2)   // header and the payment
        XCTAssertEqual(ClientImport.parseCSV(AccountingExport.paymentsCSV(d, in: endingThen, timeZone: zone)).count, 1)     // header only
        let issuedAt = day(2027, 1, 8)                            // INV-0002
        XCTAssertEqual(ClientImport.parseCSV(AccountingExport.invoicesCSV(d, in: DateInterval(start: issuedAt, end: issuedAt.addingTimeInterval(60)), now: now, timeZone: zone)).count, 2)
        XCTAssertEqual(ClientImport.parseCSV(AccountingExport.invoicesCSV(d, in: DateInterval(start: issuedAt.addingTimeInterval(-60), end: issuedAt), now: now, timeZone: zone)).count, 1)
    }

    func testDatesUseTheGivenTimeZoneAndFormulasAreDefused() throws {
        var d = AppData()
        let c = Customer(name: "=HYPERLINK(\"http://bad\")")
        d.customers = [c]
        var inv = Invoice(number: "INV-0001", customerID: c.id, siteID: UUID(), issueDate: day(2027, 1, 1, 3), dueDate: day(2027, 1, 15, 3),
                          lines: [InvoiceLineItem(description: "Line one\nLine two", amount: Money(dollars: 10))])
        try inv.markSent(at: day(2027, 1, 1, 3))
        try inv.record(ManualPayment(amount: Money(dollars: 10), date: day(2027, 1, 1, 3), method: .other))
        d.invoices = [inv]
        let newYork = TimeZone(identifier: "America/New_York")!
        let invoices = ClientImport.parseCSV(AccountingExport.invoicesCSV(d, now: now, timeZone: newYork))
        XCTAssertEqual(invoices[1][1], "2026-12-31")              // 03:00 UTC is still the evening before in New York
        XCTAssertEqual(invoices[1][2], "2027-01-14")
        XCTAssertEqual(invoices[1][3], "'=HYPERLINK(\"http://bad\")")
        XCTAssertEqual(invoices[1][4], "Line one Line two")       // one line per invoice, whatever was typed
        XCTAssertEqual(invoices[1][8], "Paid")
        let payments = ClientImport.parseCSV(AccountingExport.paymentsCSV(d, timeZone: newYork))
        XCTAssertEqual(payments[1], ["2026-12-31", "INV-0001", "'=HYPERLINK(\"http://bad\")", "10.00", "Other"])
        XCTAssertEqual(ClientImport.parseCSV(AccountingExport.paymentsCSV(d, timeZone: zone))[1][0], "2027-01-01")
    }

    func testEmptyFilesStillHaveTheirHeader() {
        XCTAssertEqual(AccountingExport.invoicesCSV(AppData(), now: now, timeZone: zone), AccountingExport.invoiceColumns.joined(separator: ",") + "\r\n")
        XCTAssertEqual(AccountingExport.paymentsCSV(AppData(), timeZone: zone), "Date,Invoice Number,Client,Amount,Method\r\n")
    }
}
