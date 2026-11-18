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
