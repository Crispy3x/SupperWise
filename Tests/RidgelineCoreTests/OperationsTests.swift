import XCTest
@testable import RidgelineCore

final class PhotoStorageTests: XCTestCase {
    private func storage() -> (PhotoStorage, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-photos-\(UUID().uuidString)")
        return (PhotoStorage(directory: dir), dir)
    }

    func testSaveLoadAndTamperDetection() throws {
        let (store, dir) = storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data((0..<2000).map { UInt8($0 % 251) })
        let ref = try store.save(bytes, kind: .after, capturedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(try store.data(for: ref), bytes)
        XCTAssertTrue(store.isIntact(ref))
        try Data("swapped".utf8).write(to: dir.appendingPathComponent(ref.filename))
        XCTAssertFalse(store.isIntact(ref))
        XCTAssertThrowsError(try store.data(for: ref)) { XCTAssertEqual($0 as? PhotoStorageError, .hashMismatch) }
        try FileManager.default.removeItem(at: dir.appendingPathComponent(ref.filename))
        XCTAssertThrowsError(try store.data(for: ref)) { XCTAssertEqual($0 as? PhotoStorageError, .missing) }
    }

    func testTwoSavesOfTheSameBytesGetDifferentFiles() throws {
        let (store, dir) = storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try store.save(Data("x".utf8), kind: .before, capturedAt: Date())
        let b = try store.save(Data("x".utf8), kind: .before, capturedAt: Date())
        XCTAssertNotEqual(a.filename, b.filename)
        XCTAssertEqual(a.sha256, b.sha256)
    }
}

final class OperationsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    func testAcceptQuoteCreatesSiteAndContractOnce() throws {
        var data = AppData()
        let customer = Customer(name: "Pat")
        data.customers = [customer]
        let q = Quote(number: "Q-1", customerID: customer.id, address: "5 Pine", season: "2026-27",
                      terms: .perPush(rate: Money(dollars: 60)), createdAt: t0)
        data.quotes = [q]
        let contract = try data.acceptQuote(id: q.id, now: t0 + day)
        XCTAssertEqual(data.sites.count, 1)
        XCTAssertEqual(data.sites[0].address, "5 Pine")
        XCTAssertEqual(data.contracts, [contract])
        XCTAssertEqual(data.quotes[0].status(now: t0 + 2 * day), .accepted)
        let again = try data.acceptQuote(id: q.id, now: t0 + 3 * day)      // second tap changes nothing
        XCTAssertEqual(again, contract)
        XCTAssertEqual(data.contracts.count, 1)
        XCTAssertEqual(data.sites.count, 1)
    }

    func testAcceptReusesExistingSiteAndRejectsExpiredOrUnknown() throws {
        var data = AppData()
        let customer = Customer(name: "Pat")
        let site = Site(customerID: customer.id, address: "5 Pine")
        data.customers = [customer]
        data.sites = [site]
        let q = Quote(number: "Q-1", customerID: customer.id, address: "5 Pine", season: "2026-27",
                      terms: .seasonal(total: Money(dollars: 800)), createdAt: t0, validDays: 10)
        data.quotes = [q]
        XCTAssertThrowsError(try data.acceptQuote(id: q.id, now: t0 + 20 * day)) { XCTAssertEqual($0 as? QuoteError, .expired) }
        XCTAssertTrue(data.contracts.isEmpty)
        XCTAssertEqual(data.quotes[0].status(now: t0 + 1 * day), .draft)    // a failed accept changed nothing
        XCTAssertThrowsError(try data.acceptQuote(id: UUID(), now: t0)) { XCTAssertEqual($0 as? OperationError, .notFound) }
        let c = try data.acceptQuote(id: q.id, now: t0 + day)
        XCTAssertEqual(c.siteID, site.id)
        XCTAssertEqual(data.sites.count, 1)
    }

    func testClockInOut() throws {
        var data = AppData()
        let site = UUID()
        try data.clockIn(member: "  Sam ", siteID: site, now: t0)
        XCTAssertEqual(data.timeEntries[0].memberName, "Sam")
        XCTAssertThrowsError(try data.clockIn(member: "Sam", now: t0 + 60)) { XCTAssertEqual($0 as? OperationError, .alreadyClockedIn) }
        try data.clockIn(member: "Lee", now: t0)                              // a different person is fine
        try data.clockOut(member: "Sam", now: t0 + 3600)
        XCTAssertEqual(data.timeEntries[0].end, t0 + 3600)
        XCTAssertThrowsError(try data.clockOut(member: "Sam", now: t0 + 7200)) { XCTAssertEqual($0 as? OperationError, .notClockedIn) }
        try data.clockIn(member: "Sam", now: t0 + 7200)                       // can clock in again after out
        XCTAssertEqual(data.timeEntries.count, 3)
        XCTAssertThrowsError(try data.clockIn(member: "   ", now: t0)) { XCTAssertEqual($0 as? OperationError, .emptyName) }
    }

    func testClockOutNeverEndsBeforeStart() throws {
        var data = AppData()
        try data.clockIn(member: "Sam", now: t0)
        try data.clockOut(member: "Sam", now: t0 - 500)                       // device clock went backwards
        XCTAssertEqual(data.timeEntries[0].hours(now: t0), 0)
    }

    func testRoutesAndCrewsNeedNames() throws {
        var data = AppData()
        try data.addCrew(name: " Truck 1 ")
        try data.addRoute(name: "North", crewID: data.crews[0].id, weekday: 2)
        XCTAssertEqual(data.crews[0].name, "Truck 1")
        XCTAssertEqual(data.routes[0].weekday, 2)
        XCTAssertThrowsError(try data.addRoute(name: "")) { XCTAssertEqual($0 as? OperationError, .emptyName) }
        XCTAssertThrowsError(try data.addCrew(name: "  ")) { XCTAssertEqual($0 as? OperationError, .emptyName) }
    }

    func testJobCostUsesInvoicesTimeAndSalt() throws {
        var data = AppData()
        data.laborCostPerHour = Money(dollars: 30)
        data.saltCostPerPound = Money(cents: 20)
        let site = Site(customerID: UUID(), address: "1 Main")
        data.sites = [site]
        var inv = Invoice(number: "I-1", customerID: site.customerID, siteID: site.id, issueDate: t0, dueDate: t0,
                          lines: [InvoiceLineItem(description: "Storm", amount: Money(dollars: 200))])
        try inv.markSent(at: t0)
        data.invoices = [inv]
        data.timeEntries = [TimeEntry(memberName: "Sam", start: t0, end: t0 + 7200, siteID: site.id),
                            TimeEntry(memberName: "Sam", start: t0, end: t0 + 3600, siteID: UUID())]   // other site: ignored
        data.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "S1", arrival: t0, saltPounds: 50))
        let cost = data.jobCost(for: site, now: t0 + 99_999)
        XCTAssertEqual(cost.revenue, Money(dollars: 200))
        XCTAssertEqual(cost.labor, Money(dollars: 60))
        XCTAssertEqual(cost.materials, Money(dollars: 10))
        XCTAssertEqual(cost.margin, Money(dollars: 130))
    }

    func testUnreadableFileIsKeptNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("data.json")
        let garbage = Data("{ this is not valid json".utf8)
        try garbage.write(to: file)
        let store = FileStore(url: file)
        XCTAssertThrowsError(try store.load())
        let r = store.loadOrRecover(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(r.data, AppData())
        XCTAssertNotNil(r.notice)
        XCTAssertTrue(r.safeToSave)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let kept = dir.appendingPathComponent("data.unreadable-1800000000.json")
        XCTAssertEqual(try Data(contentsOf: kept), garbage)               // the bytes are still there
        let again = store.loadOrRecover()                                  // nothing left to fail on
        XCTAssertNil(again.notice)
    }

    func testGoodFileHasNoNotice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-ok-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        var data = AppData(); data.companyName = "Ridge"
        try store.save(data)
        let r = store.loadOrRecover()
        XCTAssertEqual(r.data, data)
        XCTAssertNil(r.notice)
    }

    func testAcceptQuoteMatchesAddressIgnoringCaseAndSpaces() throws {
        var data = AppData()
        let customer = Customer(name: "Pat")
        data.customers = [customer]
        data.sites = [Site(customerID: customer.id, address: "5 pine  street")]
        let q = Quote(number: "Q-1", customerID: customer.id, address: " 5 Pine Street ", season: "2026-27",
                      terms: .seasonal(total: Money(dollars: 500)), createdAt: t0)
        data.quotes = [q]
        try data.acceptQuote(id: q.id, now: t0 + day)
        XCTAssertEqual(data.sites.count, 1)       // no duplicate site for the same place
    }

    func testDraftInvoicesAreNotRevenueAndUnassignedTimeIsCounted() throws {
        var data = AppData()
        let site = Site(customerID: UUID(), address: "1 Main")
        data.sites = [site]
        let draft = Invoice(number: "I-1", customerID: site.customerID, siteID: site.id, issueDate: t0, dueDate: t0,
                            lines: [InvoiceLineItem(description: "x", amount: Money(dollars: 100))])
        var sent = Invoice(number: "I-2", customerID: site.customerID, siteID: site.id, issueDate: t0, dueDate: t0,
                           lines: [InvoiceLineItem(description: "y", amount: Money(dollars: 40))])
        try sent.markSent(at: t0)
        data.invoices = [draft, sent]
        XCTAssertEqual(data.jobCost(for: site, now: t0).revenue, Money(dollars: 40))
        data.timeEntries = [TimeEntry(memberName: "Sam", start: t0, end: t0 + 5400), TimeEntry(memberName: "Sam", start: t0, end: t0 + 3600, siteID: site.id)]
        XCTAssertEqual(data.unassignedHours(now: t0 + 99_999), 1.5, accuracy: 0.0001)
    }

    func testRoutingProviderDefaultsAndSurvivesSave() throws {
        XCTAssertEqual(AppData().routingProvider, .appleMaps)
        let old = try FileStore.decoder.decode(AppData.self, from: Data(#"{"companyName":"Old"}"#.utf8))
        XCTAssertEqual(old.routingProvider, .appleMaps)               // older files get the default
        var data = AppData(); data.routingProvider = .server
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-rp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(data)
        XCTAssertEqual(try store.load().routingProvider, .server)
    }

    func testNewFieldsSurviveSaveAndLoad() throws {
        var data = AppData()
        data.laborCostPerHour = Money(dollars: 28)
        data.quotes = [Quote(number: "Q-9", customerID: UUID(), address: "A", season: "2026-27", terms: .seasonal(total: Money(dollars: 500)), createdAt: t0)]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-ops-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(data)
        XCTAssertEqual(try store.load(), data)
    }
}

final class TermsSummaryTests: XCTestCase {
    func testSummaries() {
        XCTAssertEqual(ContractTerms.perPush(rate: Money(dollars: 60)).summary, "Per push $60.00 (one push per storm)")
        XCTAssertEqual(ContractTerms.perPush(rate: Money(dollars: 50), counting: .perVisit).summary, "Per push $50.00 (every visit is a push)")
        XCTAssertEqual(ContractTerms.seasonal(total: Money(dollars: 1400)).summary, "Seasonal $1,400.00 for the whole season")
        XCTAssertEqual(ContractTerms.hybrid(seasonalBase: Money(dollars: 900), includedPushes: 8, overagePerPush: Money(dollars: 85)).summary,
                       "Seasonal $900.00 covers 8 pushes, then $85.00 per push (one push per storm)")
        XCTAssertEqual(ContractTerms.perInch(tiers: [DepthTier(minInches: 6, rate: Money(dollars: 70)), DepthTier(minInches: 2.5, rate: Money(dollars: 40))]).summary,
                       "By depth: $40.00 from 2.5 in, $70.00 from 6 in")
        XCTAssertEqual(ContractTerms.timeAndMaterials(hourly: Money(dollars: 95), materialsMarkupPercent: 15).summary,
                       "Time and materials at $95.00 per hour, materials plus 15%")
    }
}

final class RoutingServerSettingsTests: XCTestCase {
    func testOnlyHTTPSOrLocalTestingAllowed() {
        XCTAssertNotNil(RoutingServerSettings.validatedURL("https://routes.example.com"))
        XCTAssertNotNil(RoutingServerSettings.validatedURL("  https://routes.example.com/  "))
        XCTAssertNotNil(RoutingServerSettings.validatedURL("http://localhost:8080"))
        XCTAssertNotNil(RoutingServerSettings.validatedURL("http://127.0.0.1:8080"))
        XCTAssertNil(RoutingServerSettings.validatedURL("http://routes.example.com"))      // token would travel unencrypted
        XCTAssertNil(RoutingServerSettings.validatedURL("ftp://routes.example.com"))
        XCTAssertNil(RoutingServerSettings.validatedURL("routes.example.com"))
        XCTAssertNil(RoutingServerSettings.validatedURL(""))
        XCTAssertNil(RoutingServerSettings.validatedURL("https://"))
        XCTAssertNil(RoutingServerSettings.validatedURL("http://localhost.evil.com"))
    }
}
