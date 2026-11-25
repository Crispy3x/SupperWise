import XCTest
@testable import RidgelineCore

final class SetupChecklistTests: XCTestCase {
    func testStartsIncompleteAndEachStepTicksOffByItself() throws {
        var d = AppData()
        var items = SetupChecklist.items(for: d, serverConfigured: false)
        XCTAssertEqual(SetupChecklist.progress(items).done, 0)
        XCTAssertEqual(SetupChecklist.progress(items).total, 4)               // the server, page address and Apple sign-in steps are optional and not counted
        XCTAssertTrue(items.last?.optional ?? false)
        d.customers = [Customer(name: "Pat", email: "p@x.com", emailConsent: true)]
        d.depot = Coordinate(latitude: 45, longitude: -93)
        d.profile.paymentInstructions = "Check"
        d.broadcastSettings.portalBaseURL = "https://portal.example.com"
        items = SetupChecklist.items(for: d, serverConfigured: true)
        XCTAssertEqual(SetupChecklist.progress(items).done, 4)
        XCTAssertFalse(items.last!.done)
        try d.signIn(appleUserID: "001.x", displayName: "", email: "", now: Date())
        XCTAssertTrue(SetupChecklist.items(for: d, serverConfigured: true).last!.done)
    }

    func testAnInsecurePageAddressOrAStoppedClientDoesNotCount() {
        var d = AppData()
        d.broadcastSettings.portalBaseURL = "http://portal.example.com"
        d.customers = [Customer(name: "Pat", email: "p@x.com", emailConsent: true, optedOutAt: Date())]
        let items = SetupChecklist.items(for: d, serverConfigured: false)
        XCTAssertFalse(items.first { $0.id == "page" }!.done)
        XCTAssertFalse(items.first { $0.id == "consent" }!.done)               // a client who asked to stop is not "agreed"
    }
}

final class SeasonStatementTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func world(terms: ContractTerms) -> (AppData, Site) {
        var d = AppData()
        let c = Customer(name: "Pat"); let s = Site(customerID: c.id, address: "1 Elm")
        d.customers = [c]; d.sites = [s]
        d.contracts = [SnowContract(siteID: s.id, season: "x", terms: terms)]
        return (d, s)
    }

    func testHybridShowsPushesAgainstTheCapAndWhatIsOwed() throws {
        var (d, s) = world(terms: .hybrid(seasonalBase: Money(dollars: 500), includedPushes: 2, overagePerPush: Money(dollars: 40)))
        for (i, storm) in ["S1", "S2", "S3"].enumerated() {
            d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: storm, arrival: t0 - Double(i + 1) * 86_400))
        }
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "S4", arrival: t0 - 5 * 86_400, status: .skipped(reason: "gate")))
        var inv = Invoice(number: "I-1", customerID: s.customerID, siteID: s.id, issueDate: t0 - 86_400, dueDate: t0 + 86_400,
                          lines: [InvoiceLineItem(description: "Season", amount: Money(dollars: 500)), InvoiceLineItem(description: "S3 over cap", amount: Money(dollars: 40))])
        try inv.markSent(at: t0 - 86_400)
        try inv.record(ManualPayment(amount: Money(dollars: 300), date: t0, method: .check))
        d.invoices = [inv]
        let st = try XCTUnwrap(SeasonStatement.build(data: d, siteID: s.id, now: t0))
        XCTAssertEqual(st.stormsServiced, 3)
        XCTAssertEqual(st.skippedVisits, 1)
        XCTAssertEqual(st.pushesUsed, 3)
        XCTAssertEqual(st.capLine, "2 of 2 included pushes used, 1 beyond the cap")
        XCTAssertEqual(st.billed, Money(dollars: 540))
        XCTAssertEqual(st.paid, Money(dollars: 300))
        XCTAssertEqual(st.outstanding, Money(dollars: 240))
    }

    func testNoCapNoDraftsNoVoidsAndNoLastWinter() throws {
        var (d, s) = world(terms: .perPush(rate: Money(dollars: 60)))
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "Old", arrival: t0 - 300 * 86_400))
        func inv(_ n: String, sent: Bool, void: Bool = false, ago: Double = 1) throws -> Invoice {
            var i = Invoice(number: n, customerID: s.customerID, siteID: s.id, issueDate: t0 - ago * 86_400, dueDate: t0,
                            lines: [InvoiceLineItem(description: "x", amount: Money(dollars: 60))])
            if sent { try i.markSent(at: t0 - ago * 86_400) }
            if void { i.void() }
            return i
        }
        d.invoices = [try inv("A", sent: true), try inv("B", sent: false), try inv("C", sent: true, void: true), try inv("D", sent: true, ago: 300)]
        let st = try XCTUnwrap(SeasonStatement.build(data: d, siteID: s.id, now: t0))
        XCTAssertNil(st.capLine)
        XCTAssertEqual(st.billed, Money(dollars: 60))              // only the sent, valid, this-winter invoice
        XCTAssertEqual(st.stormsServiced, 0)
        XCTAssertNil(SeasonStatement.build(data: d, siteID: UUID(), now: t0))
    }
}

final class ReminderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)         // 08:00 UTC
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func world(consent: Bool = true) throws -> (AppData, Invoice) {
        var d = AppData()
        d.companyName = "Ridge Plow"; d.profile.paymentInstructions = "E-transfer to Ridge Plow"
        d.broadcastSettings.portalBaseURL = "https://portal.example.com"
        let c = Customer(name: "Pat", email: "pat@example.com", emailConsent: consent)
        let s = Site(customerID: c.id, address: "1 Elm")
        d.customers = [c]; d.sites = [s]; d.ensurePortalLinks(now: t0)
        var inv = Invoice(number: "INV-0001", customerID: c.id, siteID: s.id, issueDate: t0 - 40 * 86_400, dueDate: t0 - 10 * 86_400,
                          lines: [InvoiceLineItem(description: "Storm", amount: Money(dollars: 60))])
        try inv.markSent(at: t0 - 40 * 86_400)
        d.invoices = [inv]
        return (d, inv)
    }

    func testReminderIsFriendlyAndShowsTheBalance() throws {
        var (d, inv) = try world()
        try d.invoices[0].record(ManualPayment(amount: Money(dollars: 20), date: t0, method: .cash))
        let plan = ReminderPlanner.plan(data: d, now: t0, calendar: utc)
        XCTAssertEqual(plan.invoiceNumbers, ["INV-0001"])
        let m = plan.messages[0]
        XCTAssertTrue(m.subject.contains("INV-0001"))
        XCTAssertTrue(m.body.contains("The balance is $40.00."))
        XCTAssertTrue(m.body.contains("If you have already paid, thank you"))
        XCTAssertTrue(m.body.contains("How to pay: E-transfer to Ridge Plow"))
        XCTAssertTrue(m.body.contains("https://portal.example.com/c/\(d.portalLinks[0].token)"))
        XCTAssertFalse(m.body.contains("reply to this message"))
        _ = inv
    }

    func testOnlyOverdueSentUnpaidInvoicesToConsentingClients() throws {
        var (d, _) = try world()
        let s = d.sites[0], c = d.customers[0]
        func make(_ n: String, due: Double, sent: Bool = true) throws -> Invoice {
            var i = Invoice(number: n, customerID: c.id, siteID: s.id, issueDate: t0 - 50 * 86_400, dueDate: t0 + due * 86_400,
                            lines: [InvoiceLineItem(description: "x", amount: Money(dollars: 10))])
            if sent { try i.markSent(at: t0 - 50 * 86_400) }
            return i
        }
        var paid = try make("PAID", due: -5); try paid.record(ManualPayment(amount: Money(dollars: 10), date: t0, method: .cash))
        var voided = try make("VOID", due: -5); voided.void()
        d.invoices += [try make("NOTDUE", due: 5), try make("DRAFT", due: -5, sent: false), paid, voided]
        XCTAssertEqual(ReminderPlanner.plan(data: d, now: t0, calendar: utc).invoiceNumbers, ["INV-0001"])
    }

    func testNoConsentOptOutOrBadEmailMeansNoReminder() throws {
        XCTAssertTrue(ReminderPlanner.plan(data: try world(consent: false).0, now: t0, calendar: utc).messages.isEmpty)
        var (d, _) = try world()
        try d.optOut(customerID: d.customers[0].id, now: t0)
        XCTAssertTrue(ReminderPlanner.plan(data: d, now: t0, calendar: utc).messages.isEmpty)
        (d, _) = try world(); d.customers[0].email = "nope"
        XCTAssertTrue(ReminderPlanner.plan(data: d, now: t0, calendar: utc).messages.isEmpty)
    }

    func testNoNaggingPauseBetweenAndALimitPerInvoice() throws {
        var (d, _) = try world()
        d.recordReminders(["INV-0001"], at: t0 - 3 * 86_400)
        XCTAssertTrue(ReminderPlanner.plan(data: d, now: t0, calendar: utc).messages.isEmpty)              // reminded 3 days ago
        XCTAssertEqual(ReminderPlanner.plan(data: d, now: t0 + 5 * 86_400, calendar: utc).messages.count, 1) // 8 days after: fine
        d.recordReminders(["INV-0001", "INV-0001"], at: t0 - 20 * 86_400)
        XCTAssertTrue(ReminderPlanner.plan(data: d, now: t0 + 60 * 86_400, calendar: utc).messages.isEmpty) // three is the limit
    }

    func testQuietHoursDelayAReminder() throws {
        let (d, _) = try world()
        let night = utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 23))!
        let m = ReminderPlanner.plan(data: d, now: night, calendar: utc).messages[0]
        XCTAssertEqual(utc.component(.hour, from: m.sendAfter), 6)
        XCTAssertGreaterThan(m.sendAfter, night)
    }

    func testReminderLogSurvivesSave() throws {
        var (d, _) = try world()
        d.recordReminders(["INV-0001"], at: t0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-rem-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(d)
        XCTAssertEqual(try store.load().reminderLog, d.reminderLog)
    }
}

final class ClientImportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testCSVReaderHandlesQuotesCommasNewlinesAndBOM() {
        let text = "\u{FEFF}Name,Address,Notes\r\n\"Miller, Pat\",\"14 Elm Ave, Unit 2\",\"said \"\"call first\"\"\"\r\nSam,\"1 Oak\nRear lot\",\r\n\r\n"
        let rows = ClientImport.parseCSV(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["Name", "Address", "Notes"])
        XCTAssertEqual(rows[1], ["Miller, Pat", "14 Elm Ave, Unit 2", "said \"call first\""])
        XCTAssertEqual(rows[2], ["Sam", "1 Oak\nRear lot", ""])
        XCTAssertTrue(ClientImport.parseCSV("").isEmpty)
        XCTAssertEqual(ClientImport.parseCSV("a,b\nc,d"), [["a", "b"], ["c", "d"]])        // no trailing newline
    }

    func testFindsColumnsByNameInAnyOrderAndSkipsBadRows() {
        let csv = "Phone,E-mail,Customer,Service Address\n612-555-0100,pat@example.com,Pat Miller,14 Elm Ave\n,not-an-email,Sam,1 Oak\n555,x@y.com,,2 Pine\n555,x@y.com,Lee,\n"
        let r = ClientImport.clients(from: csv, existing: AppData())
        XCTAssertNil(r.problem)
        XCTAssertEqual(r.clients.map(\.name), ["Pat Miller", "Sam"])
        XCTAssertEqual(r.clients[0].email, "pat@example.com")
        XCTAssertEqual(r.clients[1].email, "")                              // a client is kept, an address that cannot work is dropped
        XCTAssertEqual(r.skipped.map(\.row), [4, 5])
        XCTAssertTrue(r.skipped.allSatisfy { $0.reason.contains("Missing") })
    }

    func testDuplicatesAreSkippedAgainstTheFileAndAgainstWhatYouAlreadyHave() {
        var d = AppData()
        let c = Customer(name: "Pat Miller"); let s = Site(customerID: c.id, address: "14 Elm Ave")
        d.customers = [c]; d.sites = [s]
        let csv = "Name,Address\n pat   miller ,14 elm ave\nNew Person,5 Pine\nnew person,5  PINE\n"
        let r = ClientImport.clients(from: csv, existing: d)
        XCTAssertEqual(r.clients.map(\.name), ["New Person"])
        XCTAssertEqual(r.skipped.count, 2)
        XCTAssertTrue(r.skipped.allSatisfy { $0.reason == "Already in your list" })
    }

    func testUnusableFilesGetAPlainExplanation() {
        XCTAssertEqual(ClientImport.clients(from: "", existing: AppData()).problem, "The file is empty.")
        XCTAssertTrue(ClientImport.clients(from: "Foo,Bar\n1,2", existing: AppData()).problem?.contains("Name and Address") ?? false)
        let huge = "Name,Address\n" + (0...ClientImport.maxRows).map { "N\($0),A\($0)" }.joined(separator: "\n")
        XCTAssertTrue(ClientImport.clients(from: huge, existing: AppData()).problem?.contains("more than") ?? false)
    }

    func testControlCharactersAreRemovedAndLengthsLimited() {
        let csv = "Name,Address\n\"Pat\u{0007}\u{0000} Miller\",\(String(repeating: "x", count: 500))\n"
        let c = ClientImport.clients(from: csv, existing: AppData()).clients[0]
        XCTAssertEqual(c.name, "Pat Miller")
        XCTAssertEqual(c.address.count, 200)
    }

    func testImportedClientsAreNeverMarkedAsAgreed() {
        var d = AppData()
        d.profile.defaultTriggerInches = 3
        let r = ClientImport.clients(from: "Name,Address,Email\nPat,1 Elm,pat@example.com\nSam,2 Oak,sam@example.com\n", existing: d)
        XCTAssertEqual(d.importClients(r.clients, perPush: Money(dollars: 55), now: t0), 2)
        XCTAssertEqual(d.customers.count, 2)
        XCTAssertTrue(d.customers.allSatisfy { !$0.emailConsent && $0.consentRecordedAt == nil })       // consent must be recorded later, one by one
        XCTAssertTrue(d.sites.allSatisfy { $0.triggerInches == 3 })
        XCTAssertEqual(d.contracts.count, 2)
        XCTAssertEqual(d.contracts[0].terms, .perPush(rate: Money(dollars: 55)))
        XCTAssertEqual(d.portalLinks.count, 2)
        // the same file imported again adds nobody
        XCTAssertTrue(ClientImport.clients(from: "Name,Address\nPat,1 Elm\n", existing: d).clients.isEmpty)
    }

    func testNoPriceMeansNoContract() {
        var d = AppData()
        d.importClients([ImportedClient(name: "Pat", address: "1 Elm", phone: "", email: "")], perPush: nil, now: t0)
        XCTAssertEqual(d.sites.count, 1)
        XCTAssertTrue(d.contracts.isEmpty)
    }
}
