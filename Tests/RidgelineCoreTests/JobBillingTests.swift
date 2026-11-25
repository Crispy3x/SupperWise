import XCTest
@testable import RidgelineCore

final class JobBillingTests: XCTestCase {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    var now: Date { day(2026, 11, 25, 12) }

    /// Two clients with one address each. Automatic invoices are off unless a test turns them on.
    private func world(automation: InvoiceAutomation = .off) -> (AppData, Customer, Customer) {
        var d = AppData()
        d.profile.invoiceAutomation = automation
        d.profile.netDays = 14
        let pat = Customer(name: "Pat Miller")
        let sam = Customer(name: "Sam Lee")
        d.customers = [pat, sam]
        d.sites = [Site(customerID: pat.id, address: "14 Elm Ave"), Site(customerID: sam.id, address: "2 Oak St")]
        return (d, pat, sam)
    }

    private func mow(_ dollars: Int = 40) -> [JobPriceLine] { [JobPriceLine(name: "Lawn mow", quantity: 1, unitPrice: Money(dollars: dollars))] }

    @discardableResult
    private func addJob(_ d: inout AppData, _ title: String, client: Customer?, start: Date, lines: [JobPriceLine],
                        repeats: RepeatFrequency? = nil, done: Bool = false) throws -> Job {
        let site = d.sites.first { $0.customerID == client?.id }
        let job = try d.addJob(title: title, kind: .lawnCare, customerID: client?.id, siteID: site?.id, start: start, now: start)
        if let repeats { try d.setJobRepeat(RepeatRule(frequency: repeats), id: job.id, calendar: utc) }
        try d.setJobPrice(lines, id: job.id)
        if done { try d.setOccurrenceStatus(.done, id: job.id, on: start, calendar: utc) }
        return try XCTUnwrap(d.jobs.first { $0.id == job.id })
    }

    // MARK: price and totals

    func testPriceLinesAddUpAndAreTidiedWhenSaved() throws {
        XCTAssertEqual(JobPriceLine(name: "Lawn mow", quantity: 2, unitPrice: Money(dollars: 40)).total, Money(dollars: 80))
        XCTAssertEqual(JobPriceLine(name: "Lawn mow", quantity: 2, unitPrice: Money(dollars: 40)).label, "Lawn mow x 2")
        XCTAssertEqual(JobPriceLine(name: "Refund", quantity: 1, unitPrice: Money(cents: -500)).total, .zero)     // never below zero

        var (d, pat, _) = world()
        let job = try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 12), lines: [
            JobPriceLine(name: "  Lawn mow ", quantity: 1, unitPrice: Money(dollars: 40)),
            JobPriceLine(name: "Trim and edge", quantity: 2, unitPrice: Money(dollars: 25)),
            JobPriceLine(name: "Free salt", quantity: 1, unitPrice: .zero),                                       // no price: dropped
            JobPriceLine(name: "Nothing", quantity: 0, unitPrice: Money(dollars: 10)),                            // none: dropped
            JobPriceLine(name: "", quantity: 5_000, unitPrice: Money(cents: 1)),                                  // capped at 999
        ])
        XCTAssertEqual(job.priceLines?.map(\.name), ["Lawn mow", "Trim and edge", "Service"])
        XCTAssertEqual(job.priceLines?.last?.quantity, 999)
        XCTAssertEqual(job.priceTotal, Money(cents: 4_000 + 5_000 + 999))
        XCTAssertTrue(job.hasPrice)

        try d.setJobPrice([], id: job.id)
        XCTAssertNil(d.jobs[0].priceLines)
        XCTAssertFalse(d.jobs[0].hasPrice)
        XCTAssertEqual(d.jobs[0].priceTotal, .zero)
        XCTAssertThrowsError(try d.setJobPrice(mow(), id: UUID()))
    }

    func testATypedAmountBecomesALineNamedAfterTheJob() {
        XCTAssertEqual(JobBilling.cents(fromDollars: "$45"), 4_500)
        XCTAssertEqual(JobBilling.cents(fromDollars: " 45.50 "), 4_550)
        XCTAssertEqual(JobBilling.cents(fromDollars: "1,200"), 120_000)
        XCTAssertEqual(JobBilling.cents(fromDollars: "45,5"), 4_550)                // a comma keyboard
        XCTAssertNil(JobBilling.cents(fromDollars: "abc"))
        XCTAssertNil(JobBilling.cents(fromDollars: "0"))
        XCTAssertNil(JobBilling.cents(fromDollars: ""))

        let lines = JobBilling.lines(picked: mow(), customAmount: "15", customName: "Mow and haul")
        XCTAssertEqual(lines.map(\.name), ["Lawn mow", "Mow and haul"])
        XCTAssertEqual(JobBilling.total(lines), Money(dollars: 55))
        XCTAssertEqual(JobBilling.lines(picked: [], customAmount: "20", customName: " ").map(\.name), ["Custom price"])
        XCTAssertTrue(JobBilling.lines(picked: [], customAmount: "", customName: "Mow").isEmpty)
    }

    // MARK: one visit, one invoice

    func testOneFinishedVisitBecomesOneDraftInvoice() throws {
        var (d, pat, _) = world()
        let job = try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 12), lines: [
            JobPriceLine(name: "Lawn mow", quantity: 1, unitPrice: Money(dollars: 40)),
            JobPriceLine(name: "Trim and edge", quantity: 2, unitPrice: Money(dollars: 25)),
        ])
        // Not done yet: nothing to bill.
        XCTAssertTrue(d.uninvoicedWork(calendar: utc).isEmpty)
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: job.id, on: job.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .notDone)
        }

        try d.setOccurrenceStatus(.done, id: job.id, on: job.start, calendar: utc)
        XCTAssertTrue(d.invoices.isEmpty)                                            // automatic invoices are off
        XCTAssertEqual(d.uninvoicedWork(calendar: utc).first?.total, Money(dollars: 90))

        let invoice = try d.createInvoice(forJobVisit: job.id, on: job.start, now: now, calendar: utc)
        XCTAssertEqual(invoice.number, "INV-0001")
        XCTAssertEqual(invoice.customerID, pat.id)
        XCTAssertEqual(invoice.siteID, d.sites[0].id)
        XCTAssertEqual(invoice.lines.map(\.description), ["Lawn mow", "Trim and edge x 2 ($25.00 each)"])
        XCTAssertEqual(invoice.total, Money(dollars: 90))
        XCTAssertEqual(invoice.notes, "Mow and trim, Nov 12")
        XCTAssertEqual(invoice.issueDate, now)
        XCTAssertEqual(invoice.dueDate, now.addingTimeInterval(14 * 86_400))         // the owner's payment terms
        XCTAssertEqual(invoice.status(now: now), .draft)
        XCTAssertEqual(d.invoices, [invoice])
        XCTAssertEqual(d.invoice(forJobVisit: job.id, on: job.start, calendar: utc), invoice)
        XCTAssertTrue(d.uninvoicedWork(calendar: utc).isEmpty)

        // Never twice.
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: job.id, on: job.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .alreadyInvoiced("INV-0001"))
        }
        XCTAssertEqual(d.createInvoices(now: now, calendar: utc).invoices.count, 0)
        XCTAssertEqual(d.invoices.count, 1)
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: UUID(), on: job.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .jobNotFound)
        }
    }

    // MARK: batch billing

    func testBatchMakesOneInvoicePerClientWithALinePerVisit() throws {
        var (d, pat, sam) = world()
        try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 19), lines: mow(), done: true)
        try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 12), lines: mow(), done: true)
        try addJob(&d, "Mow and trim", client: pat, start: day(2026, 11, 26), lines: mow())               // still scheduled
        try addJob(&d, "Fall cleanup", client: sam, start: day(2026, 11, 10), lines: [JobPriceLine(name: "Fall cleanup", quantity: 1, unitPrice: Money(dollars: 150))], done: true)

        let work = d.uninvoicedWork(calendar: utc)
        XCTAssertEqual(work.map(\.customerName), ["Pat Miller", "Sam Lee"])
        XCTAssertEqual(work[0].visits.count, 3)
        XCTAssertEqual(work[0].total, Money(dollars: 120))
        XCTAssertEqual(work[0].visits.map(\.dayKey), ["2026-11-05", "2026-11-12", "2026-11-19"])           // oldest first
        XCTAssertEqual(work[1].total, Money(dollars: 150))

        let result = d.createInvoices(now: now, calendar: utc)
        XCTAssertEqual(result.invoices.map(\.number), ["INV-0001", "INV-0002"])
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertEqual(result.total, Money(dollars: 270))
        XCTAssertEqual(result.summary, "2 draft invoices created for $270.00.")
        let pats = result.invoices[0]
        XCTAssertEqual(pats.customerID, pat.id)
        XCTAssertEqual(pats.lines.map(\.description), ["Nov 5  Mow and trim", "Nov 12  Mow and trim", "Nov 19  Mow and trim"])
        XCTAssertEqual(pats.lines.map(\.amount), [Money(dollars: 40), Money(dollars: 40), Money(dollars: 40)])
        XCTAssertEqual(pats.total, Money(dollars: 120))
        XCTAssertEqual(pats.status(now: now), .draft)
        XCTAssertEqual(result.invoices[1].lines.map(\.description), ["Nov 10  Fall cleanup"])
        XCTAssertEqual(d.invoices.count, 2)

        // A second run finds nothing: no visit is billed twice.
        let again = d.createInvoices(now: now, calendar: utc)
        XCTAssertTrue(again.invoices.isEmpty)
        XCTAssertEqual(again.summary, "Nothing to bill.")
        XCTAssertEqual(d.invoices.count, 2)
        XCTAssertTrue(d.uninvoicedWork(calendar: utc).isEmpty)
    }

    func testBatchCanBillOneClientAndStopAtADay() throws {
        var (d, pat, sam) = world()
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 12, 16), lines: mow(), done: true)
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 19), lines: mow(), done: true)
        try addJob(&d, "Mow", client: sam, start: day(2026, 11, 6), lines: mow(55), done: true)

        // Only Pat, through Nov 12 (the whole day counts).
        let first = d.createInvoices(forClient: pat.id, through: day(2026, 11, 12, 1), now: now, calendar: utc)
        XCTAssertEqual(first.invoices.count, 1)
        XCTAssertEqual(first.invoices[0].lines.map(\.description), ["Nov 5  Mow", "Nov 12  Mow"])
        XCTAssertEqual(d.uninvoicedWork(calendar: utc).map(\.customerName), ["Pat Miller", "Sam Lee"])
        XCTAssertEqual(d.uninvoicedWork(through: day(2026, 11, 12), calendar: utc).map(\.customerName), ["Sam Lee"])

        // The rest later: Pat's last visit and Sam's.
        let rest = d.createInvoices(now: now, calendar: utc)
        XCTAssertEqual(rest.invoices.map { $0.lines.map(\.description) }, [["Nov 19  Mow"], ["Nov 6  Mow"]])
        XCTAssertEqual(d.invoices.reduce(Money.zero) { $0 + $1.total }, Money(dollars: 40 * 3 + 55))
    }

    func testAClientWithTwoAddressesGetsTheAddressOnEachLine() throws {
        var (d, pat, _) = world()
        let cabin = Site(customerID: pat.id, address: "9 Lake Rd")
        d.sites.append(cabin)
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        let second = try d.addJob(title: "Mow", customerID: pat.id, siteID: cabin.id, start: day(2026, 11, 6), now: now)
        try d.setJobPrice(mow(60), id: second.id)
        try d.setOccurrenceStatus(.done, id: second.id, on: second.start, calendar: utc)
        let invoice = try XCTUnwrap(d.createInvoices(now: now, calendar: utc).invoices.first)
        XCTAssertEqual(invoice.lines.map(\.description), ["Nov 5  Mow (14 Elm Ave)", "Nov 6  Mow (9 Lake Rd)"])
        XCTAssertEqual(invoice.total, Money(dollars: 100))
    }

    // MARK: repeating jobs

    func testEachVisitOfARepeatingJobIsBilledOnce() throws {
        var (d, pat, _) = world()
        let job = try addJob(&d, "Mow", client: pat, start: day(2026, 11, 4), lines: mow(), repeats: .weekly)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 4), calendar: utc)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 11), calendar: utc)
        try d.skipOccurrence(id: job.id, on: day(2026, 11, 18), calendar: utc)

        let visits = try XCTUnwrap(d.uninvoicedWork(calendar: utc).first).visits
        XCTAssertEqual(visits.map(\.dayKey), ["2026-11-04", "2026-11-11"])            // the skipped visit is not billed
        XCTAssertEqual(visits.map(\.start), [day(2026, 11, 4), day(2026, 11, 11)])
        XCTAssertEqual(visits.map(\.total), [Money(dollars: 40), Money(dollars: 40)]) // every visit bills the same lines

        // One visit on its own invoice.
        let first = try d.createInvoice(forJobVisit: job.id, on: day(2026, 11, 4, 15), now: now, calendar: utc)
        XCTAssertEqual(first.total, Money(dollars: 40))
        XCTAssertEqual(first.notes, "Mow, Nov 4")
        XCTAssertEqual(d.invoice(forJobVisit: job.id, on: day(2026, 11, 4), calendar: utc)?.number, "INV-0001")
        XCTAssertNil(d.invoice(forJobVisit: job.id, on: day(2026, 11, 11), calendar: utc))
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: job.id, on: day(2026, 11, 4), now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .alreadyInvoiced("INV-0001"))
        }
        // A visit that is skipped or still scheduled cannot be invoiced.
        for open in [day(2026, 11, 18), day(2026, 11, 25), day(2026, 11, 26)] {
            XCTAssertThrowsError(try d.createInvoice(forJobVisit: job.id, on: open, now: now, calendar: utc)) {
                XCTAssertEqual($0 as? JobBillingError, .notDone)
            }
        }

        // The batch takes only what is left.
        let second = d.createInvoices(now: now, calendar: utc)
        XCTAssertEqual(second.invoices.map { $0.lines.map(\.description) }, [["Nov 11  Mow"]])

        // Next week's visit is billed when it is done, and only that one.
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 25), calendar: utc)
        let third = d.createInvoices(now: now, calendar: utc)
        XCTAssertEqual(third.invoices.map { $0.lines.map(\.description) }, [["Nov 25  Mow"]])
        XCTAssertTrue(d.createInvoices(now: now, calendar: utc).invoices.isEmpty)
        XCTAssertEqual(d.invoices.count, 3)
        XCTAssertEqual(d.invoices.reduce(Money.zero) { $0 + $1.total }, Money(dollars: 120))
        XCTAssertEqual(d.jobs[0].invoicedVisits?.count, 3)
    }

    // MARK: void

    func testVoidingAnInvoiceFreesItsVisits() throws {
        var (d, pat, _) = world()
        let job = try addJob(&d, "Mow", client: pat, start: day(2026, 11, 4), lines: mow(), repeats: .weekly)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 4), calendar: utc)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 11), calendar: utc)
        let once = try addJob(&d, "Hedge trim", client: pat, start: day(2026, 11, 6), lines: mow(75), done: true)

        let invoice = try XCTUnwrap(d.createInvoices(now: now, calendar: utc).invoices.first)
        XCTAssertEqual(invoice.lines.count, 3)
        XCTAssertTrue(d.uninvoicedWork(calendar: utc).isEmpty)

        d.invoices[0].void()
        XCTAssertNil(d.invoice(forJobVisit: job.id, on: day(2026, 11, 4), calendar: utc))
        XCTAssertNil(d.invoice(forJobVisit: once.id, on: once.start, calendar: utc))
        XCTAssertEqual(d.uninvoicedWork(calendar: utc).first?.visits.count, 3)

        // Billed again on a new invoice, and then not a third time.
        let redo = try XCTUnwrap(d.createInvoices(now: now, calendar: utc).invoices.first)
        XCTAssertEqual(redo.number, "INV-0002")
        XCTAssertEqual(redo.lines.map(\.description), ["Nov 4  Mow", "Nov 6  Hedge trim", "Nov 11  Mow"])
        XCTAssertEqual(redo.total, Money(dollars: 155))
        XCTAssertEqual(d.invoice(forJobVisit: once.id, on: once.start, calendar: utc)?.number, "INV-0002")
        XCTAssertTrue(d.createInvoices(now: now, calendar: utc).invoices.isEmpty)
        XCTAssertEqual(d.invoices.count, 2)
    }

    // MARK: what is left out

    func testJobsWithoutAPriceOrAClientAreSkipped() throws {
        var (d, pat, _) = world()
        let free = try addJob(&d, "Check the gate", client: pat, start: day(2026, 11, 5), lines: [], done: true)        // no price
        let nobody = try addJob(&d, "Yard tidy", client: nil, start: day(2026, 11, 6), lines: mow(), done: true)        // no client
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 7), lines: mow())                                       // not done
        let cancelled = try addJob(&d, "Mow", client: pat, start: day(2026, 11, 8), lines: mow())
        try d.setOccurrenceStatus(.cancelled, id: cancelled.id, on: cancelled.start, calendar: utc)
        let task = try d.addJob(title: "Call the county", start: day(2026, 11, 9), isTask: true, now: now)              // a reminder
        try d.setJobPrice(mow(), id: task.id)
        try d.setOccurrenceStatus(.done, id: task.id, on: task.start, calendar: utc)

        XCTAssertTrue(d.uninvoicedWork(calendar: utc).isEmpty)
        let result = d.createInvoices(now: now, calendar: utc)
        XCTAssertTrue(result.invoices.isEmpty)
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertTrue(d.invoices.isEmpty)
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: free.id, on: free.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .noPrice)
        }
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: nobody.id, on: nobody.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .noClient)
        }
        XCTAssertThrowsError(try d.createInvoice(forJobVisit: task.id, on: task.start, now: now, calendar: utc)) {
            XCTAssertEqual($0 as? JobBillingError, .noPrice)
        }
    }

    func testAJobAtAnAddressIsBilledToThatAddressesClient() throws {
        var (d, _, sam) = world()
        let job = try d.addJob(title: "Mow", siteID: d.sites[1].id, start: day(2026, 11, 5), now: now)                  // no client picked
        try d.setJobPrice(mow(), id: job.id)
        try d.setOccurrenceStatus(.done, id: job.id, on: job.start, calendar: utc)
        XCTAssertEqual(d.uninvoicedWork(calendar: utc).map(\.customerID), [sam.id])
        XCTAssertEqual(try d.createInvoice(forJobVisit: job.id, on: job.start, now: now, calendar: utc).customerID, sam.id)
    }

    func testAClientWithNoAddressIsReportedNotBilled() throws {
        var (d, pat, _) = world()
        let lee = Customer(name: "Lee Park")
        d.customers.append(lee)
        try addJob(&d, "Mow", client: lee, start: day(2026, 11, 5), lines: mow(), done: true)
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        let result = d.createInvoices(now: now, calendar: utc)
        XCTAssertEqual(result.invoices.map(\.customerID), [pat.id])
        XCTAssertEqual(result.problems, ["Lee Park has no address yet. Add one in Clients, then invoice."])
        XCTAssertEqual(d.uninvoicedWork(calendar: utc).map(\.customerName), ["Lee Park"])   // still waiting
        XCTAssertEqual(d.sites.count, 2)                                                    // no address was made up
    }

    // MARK: the automatic invoice setting

    func testMarkingDoneFollowsTheAutomaticInvoiceSetting() throws {
        // Off: nothing happens.
        var (off, pat, _) = world(automation: .off)
        try addJob(&off, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        XCTAssertTrue(off.invoices.isEmpty)
        XCTAssertNil(off.autoInvoice(afterJobDone: off.jobs[0].id, on: off.jobs[0].start, now: now, calendar: utc))

        // Draft: one draft for that visit, and marking it done again makes no second one.
        var (draft, pat2, _) = world(automation: .draft)
        let job = try addJob(&draft, "Mow", client: pat2, start: day(2026, 11, 5), lines: mow(), done: true)
        XCTAssertEqual(draft.invoices.count, 1)
        XCTAssertEqual(draft.invoices[0].total, Money(dollars: 40))
        XCTAssertEqual(draft.invoices[0].status(now: now), .draft)
        try draft.setOccurrenceStatus(.scheduled, id: job.id, on: job.start, calendar: utc)
        try draft.setOccurrenceStatus(.done, id: job.id, on: job.start, calendar: utc)
        try draft.setJobStatus(.done, id: job.id)
        XCTAssertEqual(draft.invoices.count, 1)
        XCTAssertTrue(draft.uninvoicedWork(calendar: utc).isEmpty)
        // A job with no price makes nothing.
        try addJob(&draft, "Check the gate", client: pat2, start: day(2026, 11, 6), lines: [], done: true)
        XCTAssertEqual(draft.invoices.count, 1)

        // Send: still only a draft. Sending waits for the owner.
        var (send, pat3, _) = world(automation: .send)
        let weekly = try addJob(&send, "Mow", client: pat3, start: day(2026, 11, 4), lines: mow(), repeats: .weekly)
        try send.setOccurrenceStatus(.done, id: weekly.id, on: day(2026, 11, 4), calendar: utc)
        try send.setOccurrenceStatus(.done, id: weekly.id, on: day(2026, 11, 11), calendar: utc)
        try send.skipOccurrence(id: weekly.id, on: day(2026, 11, 18), calendar: utc)
        XCTAssertEqual(send.invoices.count, 2)                                              // one per finished visit
        XCTAssertTrue(send.invoices.allSatisfy { $0.sentAt == nil && $0.status(now: now) == .draft })
        XCTAssertEqual(send.invoices.map(\.notes), ["Mow, Nov 4", "Mow, Nov 11"])

        // The plain status change (used by the assistant) follows the setting too.
        var (plain, pat4, _) = world(automation: .draft)
        let single = try addJob(&plain, "Mow", client: pat4, start: day(2026, 11, 5), lines: mow())
        try plain.setJobStatus(.done, id: single.id)
        XCTAssertEqual(plain.invoices.count, 1)
    }

    // MARK: saved files

    func testOldSavedFilesStillLoadAndNewFieldsRoundTrip() throws {
        // A job saved before prices existed has neither new field.
        let old = Job(title: "Mow", start: day(2026, 11, 5), createdAt: day(2026, 11, 1))
        let oldData = try JSONEncoder().encode(old)
        let oldText = String(decoding: oldData, as: UTF8.self)
        XCTAssertFalse(oldText.contains("priceLines"))
        XCTAssertFalse(oldText.contains("invoicedVisits"))
        let loaded = try JSONDecoder().decode(Job.self, from: oldData)
        XCTAssertEqual(loaded, old)
        XCTAssertNil(loaded.priceLines)
        XCTAssertNil(loaded.invoicedVisits)
        XCTAssertFalse(loaded.hasPrice)

        // A whole old file, written by hand without the new fields.
        let file = """
        {"companyName":"Ridge","jobs":[{"id":"6F9619FF-8B86-4011-B42D-00C04FC964FF","title":"Mow","kind":"lawnCare","start":0,
        "durationMinutes":60,"status":"done","assigneeIDs":[],"notes":"","isTask":false,"createdAt":0}]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(file.utf8))
        XCTAssertEqual(data.companyName, "Ridge")
        XCTAssertEqual(data.jobs.count, 1)
        XCTAssertEqual(data.jobs[0].priceTotal, .zero)
        XCTAssertTrue(data.uninvoicedWork(calendar: utc).isEmpty)

        // Prices and billed visits survive saving and loading.
        var (d, pat, _) = world()
        let job = try addJob(&d, "Mow", client: pat, start: day(2026, 11, 4), lines: mow(), repeats: .weekly)
        try d.setOccurrenceStatus(.done, id: job.id, on: day(2026, 11, 4), calendar: utc)
        try d.createInvoice(forJobVisit: job.id, on: day(2026, 11, 4), now: now, calendar: utc)
        let back = try JSONDecoder().decode(AppData.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(back.jobs, d.jobs)
        XCTAssertEqual(back.jobs[0].priceLines, mowLines(of: d))
        XCTAssertEqual(back.jobs[0].invoicedVisits, ["2026-11-04": d.invoices[0].id])
        XCTAssertNotNil(back.invoice(forJobVisit: job.id, on: day(2026, 11, 4), calendar: utc))
    }

    private func mowLines(of d: AppData) -> [JobPriceLine]? { d.jobs[0].priceLines }

    // MARK: the assistant

    private func run(_ name: String, _ input: [String: JSONValue], _ d: inout AppData) -> ToolOutcome {
        AssistantTools.execute(ToolCall(id: "t", name: name, input: .object(input)), data: &d, now: now, calendar: utc)
    }

    func testAssistantCanPriceAJobWhenItIsCreated() throws {
        var (d, _, _) = world()
        guard case .text(let t) = run("create_job", ["title": .string("Mow and trim"), "client_name": .string("Pat Miller"),
                                                      "start": .string("2026-11-12 09:00"), "price": .number(42.5)], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("Price: $42.50"))
        XCTAssertEqual(d.jobs[0].priceTotal, Money(cents: 4_250))
        XCTAssertEqual(d.jobs[0].priceLines?.map(\.name), ["Mow and trim"])
        // No price given: none saved. A reminder never gets one.
        _ = run("create_job", ["title": .string("Visit"), "start": .string("2026-11-13")], &d)
        XCTAssertNil(d.jobs[1].priceLines)
        _ = run("create_job", ["title": .string("Call the county"), "start": .string("2026-11-13"), "is_task": .bool(true), "price": .number(10)], &d)
        XCTAssertNil(d.jobs[2].priceLines)
    }

    func testAssistantBillsFinishedJobsAsDrafts() throws {
        var (d, pat, sam) = world()
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 12), lines: mow(), done: true)
        try addJob(&d, "Fall cleanup", client: sam, start: day(2026, 11, 10), lines: mow(150), done: true)

        guard case .error(let unknown) = run("bill_finished_jobs", ["client_name": .string("Nobody")], &d) else { return XCTFail() }
        XCTAssertTrue(unknown.contains("Nobody"))
        XCTAssertTrue(d.invoices.isEmpty)

        guard case .text(let one) = run("bill_finished_jobs", ["client_name": .string("sam")], &d) else { return XCTFail() }
        XCTAssertTrue(one.hasPrefix("Created 1 draft invoice for $150.00."))
        XCTAssertTrue(one.contains("- INV-0001 | Sam Lee | $150.00 | 1 visit"))
        XCTAssertEqual(d.invoices.count, 1)

        guard case .text(let rest) = run("bill_finished_jobs", [:], &d) else { return XCTFail() }
        XCTAssertTrue(rest.contains("NOT been sent"))
        XCTAssertTrue(rest.contains("- INV-0002 | Pat Miller | $80.00 | 2 visits"))
        XCTAssertEqual(d.invoices.count, 2)
        XCTAssertTrue(d.invoices.allSatisfy { $0.sentAt == nil })

        XCTAssertEqual(run("bill_finished_jobs", [:], &d), .text("No finished jobs are waiting for an invoice."))
        XCTAssertEqual(run("bill_finished_jobs", ["client_name": .string("Pat Miller")], &d), .text("Pat Miller has no finished jobs waiting for an invoice."))
        XCTAssertEqual(d.invoices.count, 2)
    }

    func testAssistantBillingNeedsRevenuePermissionAndStaysUnderTheToolLimit() throws {
        var (d, pat, _) = world()
        try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow(), done: true)
        XCTAssertTrue(AssistantTools.definitions(for: d).contains { $0.name == "bill_finished_jobs" })
        XCTAssertLessThanOrEqual(AssistantTools.definitions(for: d).count, 20)                  // the server takes 20 at most

        var g = SeededGenerator(state: 5)
        let crew = try d.addTeamMember(name: "Dana", role: .crewMember, username: "dana", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        d.session = AppSession(role: .employee, memberID: crew.id, startedAt: now)
        XCTAssertFalse(AssistantTools.definitions(for: d).contains { $0.name == "bill_finished_jobs" })
        guard case .error(let why) = run("bill_finished_jobs", [:], &d) else { return XCTFail() }
        XCTAssertTrue(why.contains("not allowed"))
        XCTAssertTrue(d.invoices.isEmpty)
    }

    func testAssistantMarkingAJobDoneFollowsTheAutomaticInvoiceSetting() throws {
        var (d, pat, _) = world(automation: .draft)
        let job = try addJob(&d, "Mow", client: pat, start: day(2026, 11, 5), lines: mow())
        guard case .text = run("update_job_status", ["job_id": .string(job.id.uuidString), "status": .string("done")], &d) else { return XCTFail() }
        XCTAssertEqual(d.invoices.count, 1)
        XCTAssertEqual(d.invoices[0].total, Money(dollars: 40))
        XCTAssertEqual(run("bill_finished_jobs", [:], &d), .text("No finished jobs are waiting for an invoice."))
    }
}
