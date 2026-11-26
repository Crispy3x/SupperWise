import XCTest
@testable import RidgelineCore

final class InvoicingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private func invoice(lines: [Money] = [Money(dollars: 100), Money(dollars: 50)]) -> Invoice {
        Invoice(number: "INV-0001", customerID: UUID(), siteID: UUID(), issueDate: t0, dueDate: t0 + 14 * day,
                lines: lines.map { InvoiceLineItem(description: "Storm", amount: $0) })
    }

    func testTotalsAndStatusLifecycle() throws {
        var inv = invoice()
        XCTAssertEqual(inv.total, Money(dollars: 150))
        XCTAssertEqual(inv.status(now: t0), .draft)
        try inv.markSent(at: t0)
        XCTAssertEqual(inv.status(now: t0 + day), .sent)
        XCTAssertEqual(inv.status(now: t0 + 20 * day), .overdue)
        try inv.record(ManualPayment(amount: Money(dollars: 50), date: t0 + day, method: .check))
        XCTAssertEqual(inv.balance, Money(dollars: 100))
        XCTAssertEqual(inv.status(now: t0 + 2 * day), .partiallyPaid)
        XCTAssertEqual(inv.status(now: t0 + 30 * day), .overdue)     // partial but past due
        try inv.record(ManualPayment(amount: Money(dollars: 100), date: t0 + 3 * day, method: .cash))
        XCTAssertEqual(inv.status(now: t0 + 30 * day), .paid)
        XCTAssertEqual(inv.balance, .zero)
    }

    func testAnInvoiceIsOverdueOnlyOnceItsDueDayIsOver() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var west = Calendar(identifier: .gregorian); west.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // Due "on receipt": t0 is 08:00 UTC on Jan 15, which is midnight in Los Angeles.
        var inv = Invoice(number: "INV-0009", customerID: UUID(), siteID: UUID(), issueDate: t0, dueDate: t0,
                          lines: [InvoiceLineItem(description: "Push", amount: Money(dollars: 60))])
        try inv.markSent(at: t0)
        XCTAssertEqual(inv.status(now: t0 + 60, calendar: utc), .sent)               // a minute later is not late
        XCTAssertEqual(inv.status(now: t0 + 15 * 3600, calendar: utc), .sent)        // 23:00 on the due day
        XCTAssertEqual(inv.status(now: t0 + 16 * 3600, calendar: utc), .overdue)     // the next day has begun
        XCTAssertEqual(inv.status(now: t0 + 16 * 3600, calendar: west), .sent)       // still Jan 15 for an owner out west
        XCTAssertEqual(inv.status(now: t0 + 24 * 3600, calendar: west), .overdue)
        try inv.record(ManualPayment(amount: Money(dollars: 10), date: t0, method: .cash))
        XCTAssertEqual(inv.status(now: t0 + 15 * 3600, calendar: utc), .partiallyPaid)
        XCTAssertEqual(inv.status(now: t0 + 16 * 3600, calendar: utc), .overdue)
    }

    func testAPaymentOnAnUnsentInvoiceEndsItsDraftState() throws {
        // Paid in cash on the spot and never emailed: it must not sit under "drafts to send" forever.
        var cash = invoice()
        XCTAssertNil(cash.sentAt)
        try cash.record(ManualPayment(amount: Money(dollars: 150), date: t0 + day, method: .cash))
        XCTAssertEqual(cash.sentAt, t0 + day)
        XCTAssertEqual(cash.status(now: t0 + day), .paid)
        // An invoice that was really sent keeps its own date.
        var sent = invoice()
        try sent.markSent(at: t0)
        try sent.record(ManualPayment(amount: Money(dollars: 1), date: t0 + day, method: .cash))
        XCTAssertEqual(sent.sentAt, t0)
    }

    func testEditingAllowedUntilFirstPayment() throws {
        var inv = invoice()
        let id = inv.lines[0].id
        try inv.updateLine(id: id, description: "Dec 3 storm", amount: Money(dollars: 120))
        XCTAssertEqual(inv.total, Money(dollars: 170))
        try inv.addLine(InvoiceLineItem(description: "Salt", amount: Money(dollars: 15)))
        try inv.removeLine(id: inv.lines[1].id)
        XCTAssertEqual(inv.total, Money(dollars: 135))
        XCTAssertThrowsError(try inv.removeLine(id: UUID())) { XCTAssertEqual($0 as? InvoiceError, .lineNotFound) }
        try inv.record(ManualPayment(amount: Money(dollars: 10), date: t0, method: .cash))
        XCTAssertFalse(inv.isEditable)
        XCTAssertThrowsError(try inv.addLine(InvoiceLineItem(description: "x", amount: Money(dollars: 1)))) { XCTAssertEqual($0 as? InvoiceError, .notEditable) }
        XCTAssertThrowsError(try inv.updateLine(id: id, amount: .zero)) { XCTAssertEqual($0 as? InvoiceError, .notEditable) }
    }

    func testPaymentValidation() throws {
        var inv = invoice()
        XCTAssertThrowsError(try inv.record(ManualPayment(amount: .zero, date: t0, method: .cash))) { XCTAssertEqual($0 as? InvoiceError, .invalidAmount) }
        XCTAssertThrowsError(try inv.record(ManualPayment(amount: Money(dollars: 151), date: t0, method: .cash))) { XCTAssertEqual($0 as? InvoiceError, .exceedsBalance) }
        XCTAssertTrue(inv.payments.isEmpty)
    }

    func testVoidBlocksFurtherChanges() throws {
        var inv = invoice()
        inv.void()
        XCTAssertEqual(inv.status(now: t0), .void)
        XCTAssertThrowsError(try inv.record(ManualPayment(amount: Money(dollars: 1), date: t0, method: .cash))) { XCTAssertEqual($0 as? InvoiceError, .alreadyVoid) }
        XCTAssertThrowsError(try inv.markSent(at: t0)) { XCTAssertEqual($0 as? InvoiceError, .alreadyVoid) }
        XCTAssertThrowsError(try inv.applyLateFee(policy: LateFeePolicy(flatFee: Money(dollars: 10)), now: t0 + 100 * day))
    }

    func testLateFeeRules() throws {
        let policy = LateFeePolicy(graceDays: 10, flatFee: Money(dollars: 25), monthlyPercent: 2, maxTotalFee: Money(dollars: 40))
        let due = t0
        let balance = Money(dollars: 1000)
        XCTAssertEqual(policy.fee(balance: balance, dueDate: due, now: due + 9 * day), .zero)        // inside grace
        XCTAssertEqual(policy.fee(balance: balance, dueDate: due, now: due + 11 * day), Money(dollars: 25))
        XCTAssertEqual(policy.fee(balance: balance, dueDate: due, now: due + 41 * day), Money(dollars: 40)) // 25 + 20 = 45, capped
        XCTAssertEqual(policy.fee(balance: .zero, dueDate: due, now: due + 100 * day), .zero)
        let uncapped = LateFeePolicy(graceDays: 0, flatFee: .zero, monthlyPercent: 1)
        XCTAssertEqual(uncapped.fee(balance: balance, dueDate: due, now: due + 65 * day), Money(dollars: 20))  // two full months
    }

    func testLateFeeIsExplicitAndOnlyOnce() throws {
        var inv = invoice()
        try inv.markSent(at: t0)
        let policy = LateFeePolicy(graceDays: 5, flatFee: Money(dollars: 20))
        XCTAssertThrowsError(try inv.applyLateFee(policy: policy, now: t0 + 15 * day)) { XCTAssertEqual($0 as? InvoiceError, .noLateFeeDue) }
        XCTAssertEqual(inv.total, Money(dollars: 150))            // nothing added by itself
        try inv.applyLateFee(policy: policy, now: t0 + 30 * day)
        XCTAssertEqual(inv.total, Money(dollars: 170))
        XCTAssertTrue(inv.lines.last?.isLateFee ?? false)
        XCTAssertThrowsError(try inv.applyLateFee(policy: policy, now: t0 + 60 * day)) { XCTAssertEqual($0 as? InvoiceError, .lateFeeAlreadyApplied) }
    }

    func testFromBillingDropsZeroLinesAndSetsDueDate() {
        let result = SnowBilling.bill(terms: .perPush(rate: Money(dollars: 60)),
                                      visits: [Visit(stormID: "S1", date: t0), Visit(stormID: "S2", date: t0 + day, status: .skipped(reason: "gate"))])
        let inv = Invoice.fromBilling(result, number: "INV-0002", customerID: UUID(), siteID: UUID(), issueDate: t0, netDays: 30)
        XCTAssertEqual(inv.lines.count, 1)
        XCTAssertEqual(inv.total, Money(dollars: 60))
        XCTAssertEqual(inv.dueDate, t0 + 30 * day)
        XCTAssertEqual(inv.lines[0].stormID, "S1")
    }

    func testNumbering() {
        XCTAssertEqual(InvoiceNumbering.next(existing: []), "INV-0001")
        XCTAssertEqual(InvoiceNumbering.next(existing: ["INV-0007", "INV-0003", "X-9"]), "INV-0008")
        XCTAssertEqual(InvoiceNumbering.next(existing: ["INV-9999"]), "INV-10000")
        XCTAssertEqual(InvoiceNumbering.next(existing: ["A-0001"], prefix: "A-", width: 3), "A-002")
    }

    func testInstallmentsSumExactly() {
        let parts = InstallmentPlan.split(total: Money(dollars: 1000), count: 3, firstDue: t0)
        XCTAssertEqual(parts.map(\.amount), [Money(cents: 33_333), Money(cents: 33_333), Money(cents: 33_334)])
        XCTAssertEqual(parts.reduce(Money.zero) { $0 + $1.amount }, Money(dollars: 1000))
        XCTAssertTrue(parts[0].dueDate < parts[1].dueDate && parts[1].dueDate < parts[2].dueDate)
        XCTAssertTrue(InstallmentPlan.split(total: Money(dollars: 10), count: 0, firstDue: t0).isEmpty)
        for total in [1, 7, 100, 12_345] {
            for n in 1...12 {
                XCTAssertEqual(InstallmentPlan.split(total: Money(cents: total), count: n, firstDue: t0).reduce(0) { $0 + $1.amount.cents }, total)
            }
        }
    }

    func testCSVEscapingAndFormulaProtection() throws {
        var inv = invoice(lines: [])
        try inv.addLine(InvoiceLineItem(description: "Plow, salt \"2x\"", amount: Money(cents: 12_345)))
        try inv.addLine(InvoiceLineItem(description: "Credit", amount: Money(cents: -500)))
        let csv = InvoiceCSV.export([inv], customerName: { _ in "=HYPERLINK(\"http://evil\")" }, now: t0)
        let lines = csv.split(separator: "\r\n").map(String.init)
        XCTAssertEqual(lines[0], "Invoice Number,Customer,Invoice Date,Due Date,Description,Amount,Status")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].contains("\"Plow, salt \"\"2x\"\"\""))
        XCTAssertTrue(lines[1].contains(",123.45,"))
        XCTAssertTrue(lines[2].contains(",-5.00,"))
        XCTAssertTrue(lines[1].contains("\"'=HYPERLINK(\"\"http://evil\"\")\""))   // leading apostrophe, quoted
        XCTAssertFalse(lines[1].hasPrefix("="))
    }

    func testInvoicesSurviveSaveAndOldFilesStillLoad() throws {
        var data = AppData()
        var inv = invoice()
        try inv.markSent(at: t0)
        try inv.record(ManualPayment(amount: Money(dollars: 20), date: t0, method: .check, note: "#1042"))
        data.invoices = [inv]
        data.lateFeePolicy = LateFeePolicy(graceDays: 7, flatFee: Money(dollars: 15))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-inv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(data)
        XCTAssertEqual(try store.load(), data)

        // A file saved before invoices existed (missing keys) still loads with defaults.
        let old = try FileStore.decoder.decode(AppData.self, from: Data(#"{"schemaVersion":1,"companyName":"Old Co"}"#.utf8))
        XCTAssertEqual(old.companyName, "Old Co")
        XCTAssertTrue(old.invoices.isEmpty)
        XCTAssertTrue(old.customers.isEmpty)
    }
}

final class InvoicePlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private func visit(_ storm: String, _ d: Double, skipped: Bool = false) -> Visit {
        Visit(stormID: storm, date: t0 + d * day, status: skipped ? .skipped(reason: "gate") : .completed, snowDepthInches: 4)
    }
    private func issue(_ terms: ContractTerms, visits: [Visit], existing: [Invoice], on d: Double) -> Invoice {
        let next = InvoicePlanner.nextBilling(terms: terms, visits: visits, existing: existing)
        return Invoice.fromBilling(next.result, number: "INV-\(existing.count + 1)", customerID: UUID(), siteID: UUID(), issueDate: t0 + d * day)
    }

    func testSecondInvoiceOnlyBillsNewStorms() {
        let terms = ContractTerms.perPush(rate: Money(dollars: 60))
        let v1 = [visit("S1", 0), visit("S2", 5)]
        let first = issue(terms, visits: v1, existing: [], on: 6)
        XCTAssertEqual(first.total, Money(dollars: 120))
        let v2 = v1 + [visit("S3", 10)]
        let again = InvoicePlanner.nextBilling(terms: terms, visits: v2, existing: [first])
        XCTAssertEqual(again.result.total, Money(dollars: 60))
        XCTAssertEqual(again.result.lines.first?.stormID, "S3")
        XCTAssertTrue(again.heldBack.isEmpty)
    }

    func testNothingNewMeansNothingToBill() {
        let terms = ContractTerms.perPush(rate: Money(dollars: 60))
        let v = [visit("S1", 0)]
        let first = issue(terms, visits: v, existing: [], on: 1)
        XCTAssertTrue(InvoicePlanner.nextBilling(terms: terms, visits: v, existing: [first]).result.lines.isEmpty)
    }

    func testVoidedInvoiceStormsAreBilledAgain() {
        let terms = ContractTerms.perPush(rate: Money(dollars: 60))
        let v = [visit("S1", 0)]
        var first = issue(terms, visits: v, existing: [], on: 1)
        first.void()
        XCTAssertEqual(InvoicePlanner.nextBilling(terms: terms, visits: v, existing: [first]).result.total, Money(dollars: 60))
    }

    func testSeasonalBaseBilledOnlyOnce() {
        let terms = ContractTerms.seasonal(total: Money(dollars: 900))
        let first = issue(terms, visits: [visit("S1", 0)], existing: [], on: 1)
        XCTAssertEqual(first.total, Money(dollars: 900))
        XCTAssertEqual(InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 0), visit("S2", 4)], existing: [first]).result.total, .zero)
    }

    func testOtherWorkAtTheAddressDoesNotBlockTheSeasonalBase() {
        let terms = ContractTerms.seasonal(total: Money(dollars: 900))
        func billedByHand(_ description: String, _ dollars: Int) -> Invoice {
            Invoice(number: "INV-1", customerID: UUID(), siteID: UUID(), issueDate: t0, dueDate: t0 + 14 * day,
                    lines: [InvoiceLineItem(description: description, amount: Money(dollars: dollars))])
        }
        // A mowing job or Quick invoice has no storm either, but it is not the season price.
        let afterMowing = InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 1)], existing: [billedByHand("Lawn mow", 40)])
        XCTAssertEqual(afterMowing.result.total, Money(dollars: 900))
        // The season billed by hand from the price list still counts, so it is not billed twice.
        let afterSeason = InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 1)], existing: [billedByHand("Seasonal driveway", 450)])
        XCTAssertEqual(afterSeason.result.total, .zero)
    }

    func testHybridCapCountsEarlierInvoicedPushes() {
        let terms = ContractTerms.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 2, overagePerPush: Money(dollars: 40))
        let first = issue(terms, visits: [visit("S1", 0), visit("S2", 3)], existing: [], on: 4)   // base + 2 pushes (inside cap)
        XCTAssertEqual(first.total, Money(dollars: 500))
        let next = InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 0), visit("S2", 3), visit("S3", 8)], existing: [first])
        XCTAssertEqual(next.result.total, Money(dollars: 40))     // third push is over the cap, no second base fee
        XCTAssertTrue(next.result.capReached)
    }

    func testReturnTripAfterInvoicingIsHeldBackNotLost() {
        let terms = ContractTerms.perPush(rate: Money(dollars: 60), counting: .perVisit)
        let first = issue(terms, visits: [visit("S1", 0)], existing: [], on: 1)
        let lateReturn = visit("S1", 2)                           // same storm, after the invoice was issued
        let next = InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 0), lateReturn], existing: [first])
        XCTAssertEqual(next.result.total, .zero)
        XCTAssertEqual(next.heldBack.map(\.id), [lateReturn.id])
    }

    func testLateFeeLinesDoNotCountAsBilledStorms() throws {
        let terms = ContractTerms.perPush(rate: Money(dollars: 60))
        var first = issue(terms, visits: [visit("S1", 0)], existing: [], on: 1)
        try first.markSent(at: t0)
        try first.applyLateFee(policy: LateFeePolicy(graceDays: 0, flatFee: Money(dollars: 10)), now: t0 + 40 * day)
        let next = InvoicePlanner.nextBilling(terms: terms, visits: [visit("S1", 0), visit("S9", 20)], existing: [first])
        XCTAssertEqual(next.result.total, Money(dollars: 60))
    }
}
