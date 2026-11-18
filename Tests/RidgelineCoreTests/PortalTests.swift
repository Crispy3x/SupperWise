import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class ScriptedHTTP: HTTPClient, @unchecked Sendable {
    var status = 200
    var body = Data("{}".utf8)
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        return (body, status)
    }
}

final class PortalSnapshotTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func world() -> (AppData, Site, StormEvent) {
        var d = AppData()
        d.companyName = "Ridge Plow"
        let c = Customer(name: "Pat Miller", phone: "612-555-0100", email: "pat@example.com", emailConsent: true)
        let s = Site(customerID: c.id, address: "14 Elm Ave", priority: 3, triggerInches: 2)
        d.customers = [c]; d.sites = [s]
        d.ensurePortalLinks(now: t0)
        return (d, s, StormEvent(name: "Nov 18", start: t0, forecastInches: 4))
    }

    private func build(_ d: AppData, _ storm: StormEvent, served: Set<UUID>) -> PortalSnapshot {
        PortalSnapshotBuilder.build(data: d, storm: storm, forecastInches: 4, servedSiteIDs: served, visitStormName: "Nov 18", timeZone: TimeZone(identifier: "UTC")!)
    }

    func testPlannedThenDoneThenSkipped() {
        var (d, site, storm) = world()
        XCTAssertEqual(build(d, storm, served: [site.id]).sites[0].status, .planned)
        XCTAssertEqual(build(d, storm, served: []).sites[0].status, .notExpected)
        XCTAssertTrue(build(d, storm, served: []).sites[0].detail.contains("under your 2 inch trigger"))
        d.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "Nov 18", arrival: t0, departure: t0 + 1800))
        let done = build(d, storm, served: [site.id]).sites[0]
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.detail, "Done at 8:30 AM.")                         // 1_800_000_000 is 08:00 UTC, plus 30 minutes
        XCTAssertFalse(done.canRequest)
        d.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "Nov 25", arrival: t0 + 86_400, status: .skipped(reason: "Car in the way")))
        XCTAssertEqual(build(d, storm, served: [site.id]).sites[0].status, .done)    // a different storm's visit does not count
        let skippedStorm = StormEvent(name: "Nov 25", start: t0, forecastInches: 4)
        let sk = PortalSnapshotBuilder.build(data: d, storm: skippedStorm, forecastInches: 4, servedSiteIDs: [site.id], visitStormName: "Nov 25", timeZone: TimeZone(identifier: "UTC")!).sites[0]
        XCTAssertEqual(sk.status, .skipped)
        XCTAssertTrue(sk.detail.contains("Car in the way"))
        XCTAssertTrue(sk.canRequest)
    }

    func testSnapshotHoldsNoPersonalContactDetails() throws {
        let (d, site, storm) = world()
        let json = String(data: try JSONEncoder().encode(build(d, storm, served: [site.id])), encoding: .utf8)!
        for secret in ["pat@example.com", "612-555-0100", "Pat Miller"] { XCTAssertFalse(json.contains(secret), secret) }
        XCTAssertTrue(json.contains("14 Elm Ave"))
    }

    func testOptedOutClientsAndSitesWithoutALinkGetNoPage() {
        var (d, site, storm) = world()
        try! d.optOut(customerID: d.customers[0].id, now: t0)
        XCTAssertTrue(build(d, storm, served: [site.id]).sites.isEmpty)
        (d, _, storm) = world()
        d.portalLinks = []
        XCTAssertTrue(build(d, storm, served: []).sites.isEmpty)
    }

    func testStormInfoUsesRangeWording() {
        let (d, site, storm) = world()
        let snap = build(d, storm, served: [site.id])
        XCTAssertEqual(snap.company, "Ridge Plow")
        XCTAssertEqual(snap.storm.id, storm.id.uuidString)
        XCTAssertEqual(snap.storm.expected, "around 3 to 5 inches")
    }
}

final class PortalClientTests: XCTestCase {
    private let base = URL(string: "https://portal.example.com")!

    func testPublishSendsTheSnapshotWithTheOwnerToken() async throws {
        let http = ScriptedHTTP()
        let client = PortalClient(baseURL: base, token: "owner-secret", client: http)
        let snap = PortalSnapshot(company: "Ridge", storm: PortalStormInfo(id: "s1", name: "Nov 18", expected: "around 3 to 5 inches"),
                                  sites: [PortalSiteSnapshot(token: "AbCdEfGhIjKlMnOpQrStUv01", label: "14 Elm Ave", status: .planned, detail: "d", canRequest: true)])
        try await client.publish(snap)
        let r = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(r.httpMethod, "PUT")
        XCTAssertEqual(r.url?.path, "/v1/portal/snapshot")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer owner-secret")
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any]
        XCTAssertEqual((sent?["storm"] as? [String: Any])?["name"] as? String, "Nov 18")
        XCTAssertEqual(((sent?["sites"] as? [[String: Any]])?.first)?["status"] as? String, "planned")
    }

    func testFetchRequestsParsesAndUsesSince() async throws {
        let http = ScriptedHTTP()
        http.body = Data(#"{"requests":[{"id":"r1","token":"AbCdEfGhIjKlMnOpQrStUv01","kind":"urgent","reason":"medical","note":"hi","createdAt":"2026-11-18T05:10:00.123Z","stormId":"s1"},{"id":"r2","token":"T","kind":"skip","reason":null,"note":"","createdAt":"2026-11-18T05:11:00.000Z","stormId":"s1"}]}"#.utf8)
        let client = PortalClient(baseURL: base, token: "t", client: http)
        let list = try await client.fetchRequests(since: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(list.map(\.id), ["r1", "r2"])
        XCTAssertEqual(list[0].reason, "medical")
        XCTAssertNil(list[1].reason)
        XCTAssertTrue(http.requests[0].url?.absoluteString.contains("since=2027-01-15") ?? false)
        _ = try await client.fetchRequests()
        XCTAssertFalse(http.requests[1].url?.absoluteString.contains("since") ?? true)
    }

    func testDecisionBody() async throws {
        let http = ScriptedHTTP()
        try await PortalClient(baseURL: base, token: "t", client: http).decide(remoteRequestID: "r1", accept: false, message: "Too far")
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(http.requests[0].httpBody)) as? [String: String]
        XCTAssertEqual(sent, ["id": "r1", "status": "declined", "message": "Too far"])
    }

    func testEmailResultsComeBackInOrderAndOnlySuccessesCount() async throws {
        let http = ScriptedHTTP()
        http.body = Data(#"{"results":[{"index":0,"ok":true},{"index":1,"ok":false,"error":"provider_rejected"},{"index":2,"ok":true}]}"#.utf8)
        func m(_ to: String) -> PlannedMessage { PlannedMessage(siteID: UUID(), customerID: UUID(), channel: .email, to: to, subject: "s", body: "b", sendAfter: Date()) }
        let ok = try await PortalClient(baseURL: base, token: "t", client: http).sendEmails([m("a@x.com"), m("b@x.com"), m("c@x.com")])
        XCTAssertEqual(ok, [true, false, true])
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(http.requests[0].httpBody)) as? [String: Any]
        XCTAssertEqual((sent?["messages"] as? [[String: Any]])?.count, 3)
        let none = try await PortalClient(baseURL: base, token: "t", client: http).sendEmails([])
        XCTAssertEqual(none, [])
    }

    func testErrorsAreReported() async {
        let http = ScriptedHTTP()
        let client = PortalClient(baseURL: base, token: "t", client: http)
        http.status = 401
        do { _ = try await client.fetchRequests(); XCTFail() } catch { XCTAssertEqual(error as? PortalError, .server(401)) }
        http.status = 200; http.body = Data("garbage".utf8)
        do { _ = try await client.fetchRequests(); XCTFail() } catch { XCTAssertEqual(error as? PortalError, .unreadable) }
        do { _ = try await client.sendEmails([PlannedMessage(siteID: UUID(), customerID: UUID(), channel: .email, to: "a@b.co", subject: "s", body: "b", sendAfter: Date())]); XCTFail() }
        catch { XCTAssertEqual(error as? PortalError, .unreadable) }
    }
}

final class PortalBillsAndEtaTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
    private var utcCal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let utc = TimeZone(identifier: "UTC")!

    func testArrivalWindowIsARangeOnQuarterHours() {
        // Crews start at 08:00, this stop is 50 minutes in: arrival 08:50, window 08:05 to 09:35 widened to 08:00 and 09:45.
        XCTAssertEqual(ArrivalWindow.describe(routeStart: t0, offsetSeconds: 50 * 60, calendar: utcCal), "Expected between 8:00 AM and 9:45 AM.")
        XCTAssertEqual(ArrivalWindow.describe(routeStart: t0, offsetSeconds: 0, spreadMinutes: 30, calendar: utcCal), "Expected between 7:30 AM and 8:30 AM.")
        XCTAssertEqual(ArrivalWindow.describe(routeStart: t0, offsetSeconds: -500, spreadMinutes: 30, calendar: utcCal), "Expected between 7:30 AM and 8:30 AM.")
        let late = utcCal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 23, minute: 30))!
        XCTAssertEqual(ArrivalWindow.describe(routeStart: late, offsetSeconds: 3600, spreadMinutes: 30, calendar: utcCal), "Expected between 12:00 AM and 1:00 AM.")
    }

    private func world() -> (AppData, Site, StormEvent) {
        var d = AppData()
        d.companyName = "Ridge Plow"
        let c = Customer(name: "Pat", email: "pat@example.com", emailConsent: true)
        let s = Site(customerID: c.id, address: "14 Elm Ave", triggerInches: 2)
        d.customers = [c]; d.sites = [s]
        d.contracts = [SnowContract(siteID: s.id, season: "x", terms: .perPush(rate: Money(dollars: 60)))]
        d.ensurePortalLinks(now: t0)
        return (d, s, StormEvent(name: "Nov 18", start: t0, forecastInches: 4))
    }

    private func snapshot(_ d: AppData, _ s: Site, _ storm: StormEvent, offsets: [UUID: Double] = [:]) -> PortalSiteSnapshot {
        PortalSnapshotBuilder.build(data: d, storm: storm, forecastInches: 4, servedSiteIDs: [s.id], visitStormName: "Nov 18", routeStart: t0,
                                    arrivalOffsets: offsets, now: t0 + 86_400, timeZone: utc).sites[0]
    }

    func testPlannedSiteGetsAnArrivalWindowOnlyWhenItHasAnOffset() {
        let (d, s, storm) = world()
        XCTAssertTrue(snapshot(d, s, storm).eta.isEmpty)
        XCTAssertTrue(snapshot(d, s, storm, offsets: [s.id: 3000]).eta.hasPrefix("Expected between"))
    }

    func testBillsShowSentInvoicesOnlyWithStatusAndAmounts() throws {
        var (d, s, storm) = world()
        func inv(_ n: String, _ dollars: Int, due: Double) -> Invoice {
            Invoice(number: n, customerID: s.customerID, siteID: s.id, issueDate: t0, dueDate: t0 + due * 86_400,
                    lines: [InvoiceLineItem(description: "Storm \(n)", amount: Money(dollars: dollars))])
        }
        var paid = inv("INV-0001", 60, due: 14); try paid.markSent(at: t0); try paid.record(ManualPayment(amount: Money(dollars: 60), date: t0, method: .check))
        var due = inv("INV-0002", 60, due: 400); try due.markSent(at: t0)
        var overdue = inv("INV-0003", 90, due: -30); try overdue.markSent(at: t0 - 90 * 86_400)
        let draft = inv("INV-0004", 70, due: 14)
        var voided = inv("INV-0005", 80, due: 14); try voided.markSent(at: t0); voided.void()
        d.invoices = [paid, due, overdue, draft, voided]
        let bills = snapshot(d, s, storm).bills
        XCTAssertEqual(Set(bills.map(\.number)), ["INV-0001", "INV-0002", "INV-0003"])          // no draft, no voided
        XCTAssertEqual(bills.first { $0.number == "INV-0001" }?.status, "Paid")
        XCTAssertEqual(bills.first { $0.number == "INV-0003" }?.status, "Overdue")
        XCTAssertEqual(bills.first { $0.number == "INV-0002" }?.total, "$60.00")
        XCTAssertEqual(bills.first { $0.number == "INV-0001" }?.due, "")                        // nothing "due" on a paid bill
        d.profile.portalShowsAmounts = false
        XCTAssertTrue(snapshot(d, s, storm).bills.allSatisfy { $0.total.isEmpty })              // status only, no amounts
        _ = storm
    }

    func testWinterSummaryCountsStormsAndExplainsTheCap() {
        var (d, s, storm) = world()
        XCTAssertEqual(snapshot(d, s, storm).summary, "")
        for (i, name) in ["S1", "S2", "S2"].enumerated() {
            d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: name, arrival: t0 - Double(i + 1) * 86_400))
        }
        XCTAssertEqual(snapshot(d, s, storm).summary, "2 storms serviced so far this winter.")      // two visits in one storm count once
        d.contracts = [SnowContract(siteID: s.id, season: "x", terms: .hybrid(seasonalBase: Money(dollars: 500), includedPushes: 1, overagePerPush: Money(dollars: 40)))]
        XCTAssertEqual(snapshot(d, s, storm).summary, "Seasonal contract: 1 of 1 included pushes used, 1 beyond that.")
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "Old", arrival: t0 - 300 * 86_400))   // last winter is not counted
        XCTAssertEqual(snapshot(d, s, storm).summary, "Seasonal contract: 1 of 1 included pushes used, 1 beyond that.")
        _ = storm
    }
}

final class AccountTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSignInKeepsNameAndEmailThatAppleOnlyGivesOnce() throws {
        var d = AppData()
        try d.signIn(appleUserID: "001.abc", displayName: "Pat Miller", email: "pat@privaterelay.appleid.com", now: t0)
        XCTAssertEqual(d.account?.displayName, "Pat Miller")
        try d.signIn(appleUserID: "001.abc", displayName: "", email: "", now: t0 + 100)           // second sign-in has no name or email
        XCTAssertEqual(d.account?.displayName, "Pat Miller")
        XCTAssertEqual(d.account?.email, "pat@privaterelay.appleid.com")
        XCTAssertEqual(d.account?.createdAt, t0)
    }

    func testBadAndDifferentAccountsAreRefused() throws {
        var d = AppData()
        XCTAssertThrowsError(try d.signIn(appleUserID: "  ", displayName: "x", email: "", now: t0)) { XCTAssertEqual($0 as? AccountError, .missingIdentifier) }
        try d.signIn(appleUserID: "001.abc", displayName: "Pat", email: "", now: t0)
        XCTAssertThrowsError(try d.signIn(appleUserID: "002.zzz", displayName: "Sam", email: "", now: t0)) { XCTAssertEqual($0 as? AccountError, .differentAccount) }
        XCTAssertEqual(d.account?.appleUserID, "001.abc")                                          // the first account is untouched
        d.signOut()
        XCTAssertNil(d.account)
    }

    func testDeletingEverythingKeepsOnlyTheDevicesTrialAndPlan() throws {
        var d = AppData()
        d.subscription = .startTrial(at: t0)
        d.companyName = "Ridge"
        d.customers = [Customer(name: "Pat", email: "p@x.com", emailConsent: true)]
        d.portalLinks = [PortalLink(siteID: UUID(), token: PortalToken.generate(), createdAt: t0)]
        try d.signIn(appleUserID: "001.abc", displayName: "Pat", email: "p@x.com", now: t0)
        d.profile.onboardingCompletedAt = t0
        let fresh = d.erasedCopy()
        XCTAssertEqual(fresh.subscription, d.subscription)         // deleting an account must not hand out a new free trial
        XCTAssertTrue(fresh.customers.isEmpty); XCTAssertTrue(fresh.portalLinks.isEmpty)
        XCTAssertNil(fresh.account); XCTAssertEqual(fresh.companyName, "")
        XCTAssertNil(fresh.profile.onboardingCompletedAt)          // so the welcome flow starts again
    }

    func testAccountSurvivesSaveAndOldFilesHaveNone() throws {
        var d = AppData()
        try d.signIn(appleUserID: "001.abc", displayName: "Pat", email: "", now: t0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-acct-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(d)
        XCTAssertEqual(try store.load().account?.appleUserID, "001.abc")
        XCTAssertNil(try FileStore.decoder.decode(AppData.self, from: Data(#"{"companyName":"Old"}"#.utf8)).account)
    }

    func testPhotoDeleteAllRemovesFilesAndIsSafeWhenEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-ph-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PhotoStorage(directory: dir)
        XCTAssertNoThrow(try store.deleteAll())                    // nothing there yet
        let ref = try store.save(Data("x".utf8), kind: .after, capturedAt: t0)
        try store.deleteAll()
        XCTAssertFalse(store.isIntact(ref))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
