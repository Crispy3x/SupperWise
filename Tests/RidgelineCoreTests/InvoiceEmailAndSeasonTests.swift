import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class Recorder: HTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { requests.append(request); return (Data(#"{"results":[{"index":0,"ok":true}]}"#.utf8), 200) }
}

final class InvoiceEmailAndSeasonTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)       // 2027-01-15

    private func world() -> AppData {
        var d = AppData()
        d.companyName = "Ridge Plow"
        let pat = Customer(name: "Pat Miller", email: "pat@example.com", emailConsent: true)
        let sam = Customer(name: "Sam Lee", email: "sam@example.com")                              // never agreed
        let opted = Customer(name: "Opt Out", email: "o@example.com", emailConsent: true, optedOutAt: now)
        let lead = Customer(name: "Lee Lead", email: "l@example.com", emailConsent: true, isLead: true)
        d.customers = [pat, sam, opted, lead]
        d.sites = d.customers.enumerated().map { Site(customerID: $1.id, address: "\($0 + 1) Elm Ave") }
        d.profile.payLink = "https://buy.stripe.com/abc123"
        d.broadcastSettings.portalBaseURL = "https://track.ridgeplow.com/"
        d.ensurePortalLinks(now: now)
        return d
    }

    // MARK: the invoice email carries a PDF and the pay links

    func testTheInvoiceEmailHasAPDFAndThePayLinks() throws {
        var d = world()
        d.invoices = [Invoice(number: "INV-7", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now.addingTimeInterval(86_400 * 14),
                              lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])]
        guard case .ready(let m) = d.invoiceEmail(number: "INV-7") else { return XCTFail() }
        XCTAssertEqual(m.attachment?.filename, "Invoice-INV-7.pdf")
        XCTAssertTrue(String(decoding: m.attachment!.data.prefix(8), as: UTF8.self).hasPrefix("%PDF-1."))
        XCTAssertTrue(m.body.contains("A PDF copy of this invoice is attached."))
        XCTAssertTrue(m.body.contains("Pay online: https://buy.stripe.com/abc123"))
        XCTAssertTrue(m.body.contains("https://track.ridgeplow.com/c/"))
        XCTAssertTrue(String(decoding: m.attachment!.data, as: UTF8.self).contains("/URI (https://buy.stripe.com/abc123)"))    // tappable inside the PDF too
    }

    func testAutomaticInvoicesSendThePDFToo() throws {
        var d = world()
        d.profile.invoiceAutomation = .send
        let site = d.sites[0]
        d.contracts = [SnowContract(siteID: site.id, season: "2026-27", terms: .perPush(rate: Money(dollars: 60)))]
        let visit = VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "Jan 15", arrival: now, departure: now.addingTimeInterval(1800))
        d.visitLog.append(visit)
        let outcome = d.autoInvoice(afterVisit: visit, now: now)
        let m = try XCTUnwrap(outcome.message)
        XCTAssertNotNil(m.attachment)
        XCTAssertTrue(m.attachment!.filename.hasSuffix(".pdf"))
    }

    func testTheEmailGoesToTheServerWithTheFileAsBase64() async throws {
        var d = world()
        d.invoices = [Invoice(number: "INV-7", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now,
                              lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])]
        guard case .ready(let m) = d.invoiceEmail(number: "INV-7") else { return XCTFail() }
        let http = Recorder()
        let ok = try await PortalClient(baseURL: URL(string: "https://example.com")!, token: "t", client: http).sendEmails([m])
        XCTAssertEqual(ok, [true])
        let body = try JSONDecoder().decode([String: JSONValue].self, from: http.requests[0].httpBody!)
        let att = try XCTUnwrap(body["messages"]?.array?.first?["attachments"]?.array?.first)
        XCTAssertEqual(att["filename"]?.string, "Invoice-INV-7.pdf")
        XCTAssertEqual(Data(base64Encoded: att["content"]?.string ?? ""), m.attachment!.data)
        XCTAssertTrue((att["content"]?.string ?? "").hasPrefix("JVBERi0"))                              // "%PDF-" in base64: what the server checks for
        // A message without a file sends no attachments key at all.
        let plain = PlannedMessage(siteID: m.siteID, customerID: m.customerID, channel: .email, to: "a@b.co", subject: "s", body: "b", sendAfter: now)
        let h2 = Recorder()
        _ = try await PortalClient(baseURL: URL(string: "https://example.com")!, token: "t", client: h2).sendEmails([plain])
        XCTAssertFalse(String(decoding: h2.requests[0].httpBody!, as: UTF8.self).contains("attachments"))
    }

    // MARK: season links

    func testTheSeasonIsNamedFromJulyToJune() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ y: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: 15))! }
        XCTAssertEqual(SeasonWelcome.season(for: at(2026, 11), calendar: cal), "2026-27")
        XCTAssertEqual(SeasonWelcome.season(for: at(2027, 2), calendar: cal), "2026-27")
        XCTAssertEqual(SeasonWelcome.season(for: at(2027, 7), calendar: cal), "2027-28")
        XCTAssertEqual(SeasonWelcome.season(for: at(2099, 12), calendar: cal), "2099-00")
    }

    func testOnlyClientsWhoAgreedGetTheirLinkOnce() {
        var d = world()
        let plan = SeasonWelcome.plan(data: d, now: now)
        XCTAssertEqual(plan.messages.count, 1)
        let m = plan.messages[0]
        XCTAssertEqual(m.to, "pat@example.com")
        XCTAssertTrue(m.body.contains("https://track.ridgeplow.com/c/\(d.portalLinks.first { $0.siteID == m.siteID }!.token)"))   // one slash, not two
        XCTAssertFalse(m.body.contains("com//c/"))
        XCTAssertTrue(m.body.contains("whole season")); XCTAssertTrue(m.body.contains("To stop them"))
        XCTAssertEqual(Set(plan.skipped.map(\.reason)), [.noConsent, .optedOut])                    // the lead is simply not a client yet
        d.recordSeasonLinks(plan.messages, season: plan.season, at: now)
        let again = SeasonWelcome.plan(data: d, now: now)
        XCTAssertTrue(again.messages.isEmpty); XCTAssertTrue(again.skipped.contains { $0.reason == .alreadySent })
        let next = SeasonWelcome.plan(data: d, now: now.addingTimeInterval(200 * 86_400))            // a new winter sends again
        XCTAssertEqual(next.messages.count, 1)
    }

    func testNoPageAddressMeansNothingToSend() {
        var d = world(); d.broadcastSettings.portalBaseURL = ""
        let plan = SeasonWelcome.plan(data: d, now: now)
        XCTAssertTrue(plan.messages.isEmpty); XCTAssertFalse(plan.problem.isEmpty)
    }

    func testThankYouMessagesAreImportedButNeverBlockRealRequests() {
        var d = world()
        let token = d.portalLinks[0].token
        func incoming(_ id: String, _ kind: String) -> IncomingRequest { IncomingRequest(id: id, token: token, kind: kind, reason: nil, note: "n", createdAt: "2027-01-15T08:00:00.000Z", stormId: nil) }
        XCTAssertEqual(d.importRequests((1...8).map { incoming("t\($0)", "thanks") }), 8)                // messages are not capped like requests
        XCTAssertEqual(d.importRequests((1...6).map { incoming("s\($0)", "service") }), 5)              // real requests keep their cap of 5
        XCTAssertEqual(d.importRequests([incoming("x", "rocket")]), 0)                                 // unknown kinds are ignored
        XCTAssertEqual(d.serviceRequests.filter { $0.kind == .thanks }.count, 8)
        let ids = d.serviceRequests.filter { $0.kind == .thanks }.map(\.id)
        XCTAssertTrue(d.serviceRequests.filter { $0.kind == .thanks }.allSatisfy { $0.status == .pending })
        XCTAssertNoThrow(try d.decideRequest(id: ids[0], accept: true, message: "", now: now))
        // A thank-you never changes who gets plowed.
        XCTAssertTrue(DispatchRules.effectiveSites(sites: d.sites, inches: 0, stormID: nil, requests: d.serviceRequests.filter { $0.kind == .thanks }).isEmpty)
        let notes = Notifications.items(for: d, now: now)
        XCTAssertTrue(notes.contains { $0.id == "thanks" }); XCTAssertTrue(notes.contains { $0.id == "requests" })
    }

    func testCrewPayLinksAreSentOnlyWhenSafe() {
        var d = world()
        d.profile.venmoLink = "https://venmo.com/ridgeplow"; d.profile.cashAppLink = "https://cash.app/$ridgeplow"
        d.profile.paypalLink = "https://evil.example.com/x"
        let tips = PortalTips.make(from: d.profile)
        XCTAssertEqual(tips?.venmoURL, "https://venmo.com/ridgeplow"); XCTAssertEqual(tips?.cashappURL, "https://cash.app/$ridgeplow")
        XCTAssertNil(tips?.paypalURL)
        d.profile.tippingEnabled = false
        XCTAssertNil(PortalTips.make(from: d.profile))                 // switched off: nothing is sent
        d.profile.tippingEnabled = true
        XCTAssertNotNil(PortalTips.make(from: d.profile))
    }
}
