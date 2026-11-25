import XCTest
@testable import RidgelineCore

final class ClientOverviewTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
    }

    private var now: Date { day(2027, 1, 20, 12) }

    private let sam = Customer(name: "Sam Lee", phone: "555-0100")
    private let other = Customer(name: "Pat Other")

    /// Sam with two properties, and another client whose records must never show up on Sam's profile.
    private func base() -> (data: AppData, elm: Site, oak: Site, otherSite: Site) {
        var d = AppData()
        let elm = Site(customerID: sam.id, address: "14 Elm Ave")
        let oak = Site(customerID: sam.id, address: "9 Oak St")
        let otherSite = Site(customerID: other.id, address: "1 Far Rd")
        d.customers = [sam, other]
        d.sites = [elm, oak, otherSite]
        return (d, elm, oak, otherSite)
    }

    private func invoice(_ number: String, customer: Customer, site: Site, dollars: Int, issued: Date, netDays: Int = 7,
                         sent: Bool = true) throws -> Invoice {
        var inv = Invoice(number: number, customerID: customer.id, siteID: site.id, issueDate: issued,
                          dueDate: issued.addingTimeInterval(Double(netDays) * 86_400),
                          lines: [InvoiceLineItem(description: "Driveway push", amount: Money(dollars: dollars))])
        if sent { try inv.markSent(at: issued) }
        return inv
    }

    // MARK: money

    func testBalanceCountsSentUnpaidInvoicesOnly() throws {
        var (d, elm, oak, otherSite) = base()
        let overdue = try invoice("INV-0001", customer: sam, site: elm, dollars: 100, issued: day(2027, 1, 2))           // due Jan 9
        var part = try invoice("INV-0002", customer: sam, site: oak, dollars: 80, issued: day(2027, 1, 15), netDays: 14)  // due Jan 29
        try part.record(ManualPayment(amount: Money(dollars: 30), date: day(2027, 1, 16), method: .cash))
        let draft = try invoice("INV-0003", customer: sam, site: elm, dollars: 60, issued: day(2027, 1, 18), sent: false)
        var voided = try invoice("INV-0004", customer: sam, site: elm, dollars: 40, issued: day(2027, 1, 3))
        voided.void()
        var paid = try invoice("INV-0005", customer: sam, site: elm, dollars: 200, issued: day(2027, 1, 8))
        try paid.record(ManualPayment(amount: Money(dollars: 200), date: day(2027, 1, 10), method: .check))
        var lastYear = try invoice("INV-0006", customer: sam, site: elm, dollars: 75, issued: day(2026, 12, 1))
        try lastYear.record(ManualPayment(amount: Money(dollars: 75), date: day(2026, 12, 10), method: .card))
        let notSams = try invoice("INV-0007", customer: other, site: otherSite, dollars: 999, issued: day(2027, 1, 2))
        d.invoices = [overdue, part, draft, voided, paid, lastYear, notSams]

        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.balanceOwed, Money(dollars: 150))          // 100 overdue + 50 left on the part-paid one
        XCTAssertEqual(o.overdueAmount, Money(dollars: 100))
        XCTAssertTrue(o.isOverdue)
        XCTAssertEqual(o.paidThisYear, Money(dollars: 230))         // 30 + 200, not last December's 75
        XCTAssertEqual(o.draftTotal, Money(dollars: 60))
        XCTAssertEqual(o.unpaidInvoiceCount, 2)
        XCTAssertEqual(o.overdueInvoiceCount, 1)
        XCTAssertEqual(o.draftInvoiceCount, 1)
        XCTAssertEqual(o.invoiceCount, 6)
        XCTAssertEqual(o.invoices.first?.number, "INV-0003")        // newest first
        XCTAssertFalse(o.invoices.contains { $0.number == "INV-0007" })
        XCTAssertFalse(o.timeline.contains { $0.invoiceNumber == "INV-0007" })
        XCTAssertFalse(o.timeline.contains { $0.kind == .invoicePaid && $0.invoiceNumber == "INV-0004" })
    }

    func testNothingOverdueBeforeTheDueDate() throws {
        var (d, elm, _, _) = base()
        let inv = try invoice("INV-0001", customer: sam, site: elm, dollars: 100, issued: day(2027, 1, 18))
        d.invoices = [inv]
        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.balanceOwed, Money(dollars: 100))
        XCTAssertEqual(o.overdueAmount, .zero)
        XCTAssertFalse(o.isOverdue)
        let later = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: day(2027, 2, 1), calendar: utc))
        XCTAssertEqual(later.overdueAmount, Money(dollars: 100))
    }

    func testAnInvoiceForOneOfTheClientsSitesCounts() throws {
        var (d, elm, _, _) = base()
        var inv = Invoice(number: "INV-0001", customerID: UUID(), siteID: elm.id, issueDate: day(2027, 1, 18), dueDate: day(2027, 2, 1),
                          lines: [InvoiceLineItem(description: "Push", amount: Money(dollars: 45))])
        try inv.markSent(at: day(2027, 1, 18))
        d.invoices = [inv]
        XCTAssertEqual(d.clientOverview(customerID: sam.id, now: now, calendar: utc)?.balanceOwed, Money(dollars: 45))
    }

    func testMoneyIsHiddenFromSomeoneWhoMayNotSeeRevenue() throws {
        var (d, elm, _, _) = base()
        let inv = try invoice("INV-0001", customer: sam, site: elm, dollars: 100, issued: day(2027, 1, 2))
        d.invoices = [inv]
        let crew = TeamMember(name: "Alex", role: .crewMember, permissions: [.viewClients, .viewAllJobs], status: .active, createdAt: now)
        d.team = [crew]
        d.session = AppSession(role: .employee, memberID: crew.id, startedAt: now)
        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.balanceOwed, .zero)
        XCTAssertTrue(o.invoices.isEmpty)
        XCTAssertFalse(o.timeline.contains { $0.kind == .invoiceCreated || $0.kind == .invoicePaid })
    }

    func testUnknownClientGivesNothing() {
        let (d, _, _, _) = base()
        XCTAssertNil(d.clientOverview(customerID: UUID(), now: now, calendar: utc))
    }

    // MARK: last and next service

    func testLastAndNextService() throws {
        var (d, elm, oak, otherSite) = base()
        let created = day(2027, 1, 1)
        let done = try d.addJob(title: "Plow driveway", kind: .snowPlowing, customerID: sam.id, siteID: elm.id, start: day(2027, 1, 12), now: created)
        try d.setJobStatus(.done, id: done.id)
        // Every Tuesday from Jan 5: the 5th, 12th and 19th are done, the 26th is skipped, so the next visit is Feb 2.
        let weekly = try d.addJob(title: "Salt walks", kind: .salting, siteID: oak.id, start: day(2027, 1, 5), now: created)
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: weekly.id, calendar: utc)
        for dayOfMonth in [5, 12, 19] { try d.setOccurrenceStatus(.done, id: weekly.id, on: day(2027, 1, dayOfMonth), calendar: utc) }
        try d.skipOccurrence(id: weekly.id, on: day(2027, 1, 26), calendar: utc)
        let soon = try d.addJob(title: "Clear the roof", customerID: sam.id, start: day(2027, 1, 22, 8), now: created)
        let cancelled = try d.addJob(title: "Cancelled visit", customerID: sam.id, start: day(2027, 1, 21), now: created)
        try d.setJobStatus(.cancelled, id: cancelled.id)
        try d.addJob(title: "Call Sam", customerID: sam.id, start: day(2027, 1, 21), isTask: true, now: created)
        try d.addJob(title: "Someone else's job", customerID: other.id, siteID: otherSite.id, start: day(2027, 1, 20, 15), now: created)
        d.visitLog.append(VisitRecord(siteID: elm.id, crewMemberName: "Alex", stormID: "Jan 18", arrival: day(2027, 1, 18, 6), departure: day(2027, 1, 18, 6, 30)))

        var o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.lastServiceDate, day(2027, 1, 19))                  // the weekly visit, later than the logged visit
        XCTAssertEqual(o.nextJob?.id, soon.id)
        XCTAssertEqual(o.nextJob?.start, day(2027, 1, 22, 8))
        XCTAssertEqual(o.upcomingJobs.map(\.id), [soon.id, weekly.id])
        XCTAssertEqual(o.upcomingJobs.last?.start, day(2027, 2, 2))          // past the done and skipped visits
        XCTAssertEqual(o.openJobCount, 2)
        XCTAssertEqual(o.siteCount, 2)
        XCTAssertEqual(o.visitCount, 1)

        // A visit logged this morning is newer than any job. A skipped visit or someone else's visit is not service.
        d.visitLog.append(VisitRecord(siteID: oak.id, crewMemberName: "Alex", stormID: "Jan 20", arrival: day(2027, 1, 20, 7), departure: day(2027, 1, 20, 7, 40)))
        d.visitLog.append(VisitRecord(siteID: oak.id, crewMemberName: "Alex", stormID: "Jan 20", arrival: day(2027, 1, 20, 10), status: .skipped(reason: "Car in the way")))
        d.visitLog.append(VisitRecord(siteID: otherSite.id, crewMemberName: "Alex", stormID: "Jan 20", arrival: day(2027, 1, 20, 11)))
        o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.lastServiceDate, day(2027, 1, 20, 7, 40))
        XCTAssertEqual(o.visitCount, 3)
        XCTAssertTrue(o.timeline.contains { $0.title == "Visit skipped" && $0.detail.contains("Car in the way") })

        // Once the roof job is done the weekly visit is next.
        try d.setJobStatus(.done, id: soon.id)
        o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.nextJob?.id, weekly.id)
        XCTAssertEqual(o.nextJob?.start, day(2027, 2, 2))
        XCTAssertEqual(o.lastServiceDate, now)                               // finished ahead of its day: it counts as done by now
    }

    func testNoServiceYet() throws {
        let (d, _, _, _) = base()
        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertNil(o.lastServiceDate)
        XCTAssertNil(o.nextJob)
        XCTAssertTrue(o.timeline.isEmpty)
        XCTAssertEqual(o.balanceOwed, .zero)
    }

    func testAnOpenJobFromAnEarlierDayStaysUpcomingButIsNotNext() throws {
        var (d, elm, _, _) = base()
        let late = try d.addJob(title: "Still to do", customerID: sam.id, siteID: elm.id, start: day(2027, 1, 15), now: day(2027, 1, 1))
        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.upcomingJobs.map(\.id), [late.id])
        XCTAssertNil(o.nextJob)
    }

    // MARK: history

    func testTimelineIsNewestFirstWithEveryKind() throws {
        var (d, elm, _, _) = base()
        let job = try d.addJob(title: "Plow driveway", kind: .snowPlowing, customerID: sam.id, siteID: elm.id, start: day(2027, 1, 12), now: day(2027, 1, 10, 8))
        try d.setJobStatus(.done, id: job.id)
        let photos = [PhotoRef(kind: .before, filename: "a.jpg", capturedAt: day(2027, 1, 12, 9, 5), sha256: "x"),
                      PhotoRef(kind: .after, filename: "b.jpg", capturedAt: day(2027, 1, 12, 9, 30), sha256: "y")]
        d.visitLog.append(VisitRecord(siteID: elm.id, crewMemberName: "Alex", stormID: "Jan 12", arrival: day(2027, 1, 12, 9, 5),
                                      departure: day(2027, 1, 12, 9, 35), photos: photos))
        var inv = try invoice("INV-0001", customer: sam, site: elm, dollars: 120, issued: day(2027, 1, 13))
        try inv.record(ManualPayment(amount: Money(dollars: 120), date: day(2027, 1, 14), method: .check))
        d.invoices = [inv]
        d.serviceRequests = [ServiceRequest(siteID: elm.id, kind: .thanks, note: "Great job", createdAt: day(2027, 1, 15))]
        d.customers[0].reviewAskedAt = day(2027, 1, 16)

        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.timeline.map(\.kind), [.reviewAsked, .requestReceived, .invoicePaid, .invoiceCreated, .visitLogged, .jobDone, .jobScheduled])
        XCTAssertEqual(o.timeline.map(\.date), o.timeline.map(\.date).sorted(by: >))
        XCTAssertEqual(Set(o.timeline.map(\.id)).count, o.timeline.count)
        XCTAssertEqual(o.timeline[2].title, "Invoice INV-0001 paid in full")
        XCTAssertEqual(o.timeline[2].detail, "$120.00 by check")
        XCTAssertEqual(o.timeline[2].invoiceNumber, "INV-0001")
        XCTAssertEqual(o.timeline[3].title, "Invoice INV-0001 created")
        XCTAssertEqual(o.timeline[4].photoCount, 2)
        XCTAssertTrue(o.timeline[4].detail.contains("2 photos"))
        XCTAssertTrue(o.timeline[4].detail.contains("14 Elm Ave"))
        XCTAssertEqual(o.timeline[5].title, "Job done: Plow driveway")
        XCTAssertEqual(o.timeline[5].date, day(2027, 1, 12))
        XCTAssertEqual(o.timeline[6].date, day(2027, 1, 10, 8))
        XCTAssertEqual(o.timeline[1].title, "Sent a thank-you")
        XCTAssertEqual(o.photos.map(\.ref.filename), ["b.jpg", "a.jpg"])     // newest photo first
        XCTAssertEqual(o.photos.first?.address, "14 Elm Ave")
        XCTAssertEqual(o.photoCount, 2)
    }

    func testAPartPaymentIsNotCalledPaidInFull() throws {
        var (d, elm, _, _) = base()
        var inv = try invoice("INV-0001", customer: sam, site: elm, dollars: 100, issued: day(2027, 1, 13), netDays: 30)
        try inv.record(ManualPayment(amount: Money(dollars: 40), date: day(2027, 1, 14), method: .cash))
        try inv.record(ManualPayment(amount: Money(dollars: 60), date: day(2027, 1, 16), method: .other))
        d.invoices = [inv]
        let o = try XCTUnwrap(d.clientOverview(customerID: sam.id, now: now, calendar: utc))
        XCTAssertEqual(o.timeline.map(\.title), ["Invoice INV-0001 paid in full", "Payment on invoice INV-0001", "Invoice INV-0001 created"])
        XCTAssertEqual(o.timeline.map(\.detail), ["$60.00", "$40.00 by cash", "$100.00"])
    }

    // MARK: changes made on the profile

    func testAddAnotherProperty() throws {
        var (d, _, _, _) = base()
        d.profile.defaultTriggerInches = 3
        let site = try d.addSite(customerID: sam.id, address: "  22 Pine Ct  ", coordinate: Coordinate(latitude: 44.9, longitude: -93.2), now: now)
        XCTAssertEqual(site.address, "22 Pine Ct")
        XCTAssertEqual(site.customerID, sam.id)
        XCTAssertEqual(site.latitude, 44.9)
        XCTAssertEqual(site.longitude, -93.2)
        XCTAssertEqual(site.triggerInches, 3)
        XCTAssertEqual(d.sites.filter { $0.customerID == sam.id }.count, 3)
        XCTAssertTrue(d.portalLinks.contains { $0.siteID == site.id })
        XCTAssertEqual(d.clientOverview(customerID: sam.id, now: now, calendar: utc)?.siteCount, 3)

        XCTAssertThrowsError(try d.addSite(customerID: sam.id, address: "   ", now: now)) { XCTAssertEqual($0 as? ClientProfileError, .emptyAddress) }
        XCTAssertThrowsError(try d.addSite(customerID: sam.id, address: "22  PINE ct", now: now)) { XCTAssertEqual($0 as? ClientProfileError, .duplicateAddress) }
        XCTAssertThrowsError(try d.addSite(customerID: UUID(), address: "5 New St", now: now)) { XCTAssertEqual($0 as? OperationError, .notFound) }
        XCTAssertEqual(d.sites.count, 4)
        // Another client may have the same address (a duplex, or a new owner).
        XCTAssertNoThrow(try d.addSite(customerID: other.id, address: "22 Pine Ct", now: now))
    }

    func testChangingAnAddressClearsTheOldMapLocation() throws {
        var (d, elm, oak, _) = base()
        d.sites[0].latitude = 44.9
        d.sites[0].longitude = -93.2
        try d.updateSiteAddress(siteID: elm.id, address: "14 elm  ave")          // same place, typed differently
        XCTAssertEqual(d.sites[0].latitude, 44.9)
        try d.updateSiteAddress(siteID: elm.id, address: "16 Elm Ave")
        XCTAssertEqual(d.sites[0].address, "16 Elm Ave")
        XCTAssertNil(d.sites[0].latitude)
        XCTAssertNil(d.sites[0].longitude)
        try d.updateSiteAddress(siteID: elm.id, address: "18 Elm Ave", coordinate: Coordinate(latitude: 45, longitude: -93))
        XCTAssertEqual(d.sites[0].latitude, 45)
        XCTAssertThrowsError(try d.updateSiteAddress(siteID: elm.id, address: oak.address)) { XCTAssertEqual($0 as? ClientProfileError, .duplicateAddress) }
        XCTAssertThrowsError(try d.updateSiteAddress(siteID: elm.id, address: "")) { XCTAssertEqual($0 as? ClientProfileError, .emptyAddress) }
        XCTAssertThrowsError(try d.updateSiteAddress(siteID: UUID(), address: "1 A St")) { XCTAssertEqual($0 as? OperationError, .notFound) }
    }

    func testNotesAndInstructionsSave() throws {
        var (d, elm, _, _) = base()
        try d.setSiteInstructions(siteID: elm.id, instructions: "  Gate code 4411. Pile snow on the left.  ")
        XCTAssertEqual(d.sites[0].instructions, "Gate code 4411. Pile snow on the left.")
        try d.setCustomerNotes(customerID: sam.id, notes: "Pays by check.\nDog in the yard.")
        XCTAssertEqual(d.customers[0].notes, "Pays by check.\nDog in the yard.")
        try d.setCustomerNotes(customerID: sam.id, notes: String(repeating: "a", count: 3000))
        XCTAssertEqual(d.customers[0].notes.count, 2000)
        XCTAssertThrowsError(try d.setSiteInstructions(siteID: UUID(), instructions: "x"))
        XCTAssertThrowsError(try d.setCustomerNotes(customerID: UUID(), notes: "x"))
    }
}
