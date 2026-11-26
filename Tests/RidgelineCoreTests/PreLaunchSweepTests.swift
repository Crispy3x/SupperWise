import XCTest
@testable import RidgelineCore

/// Fixes from the pre-launch sweep that are not about the assistant: client requests, the legal text and plan claims.
final class PreLaunchSweepTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func world() -> AppData {
        var d = AppData()
        let pat = Customer(name: "Pat Miller")
        d.customers = [pat]
        d.sites = [Site(customerID: pat.id, address: "14 Elm Ave")]
        d.ensurePortalLinks(now: now)
        return d
    }

    private func incoming(_ id: String, _ token: String, kind: String = "service", status: String? = nil) -> IncomingRequest {
        IncomingRequest(id: id, token: token, kind: kind, reason: nil, note: "n", createdAt: "2027-01-15T08:00:00.000Z", stormId: nil, status: status)
    }

    func testRequestsTheServerSaysWereAnsweredAreNotImportedAsWaiting() throws {
        var d = world()
        let token = d.portalLinks[0].token
        // A second device, or the app set up again: the server still lists last month's answered requests.
        let added = d.importRequests([incoming("a", token, status: "accepted"), incoming("b", token, status: "declined"),
                                      incoming("c", token, status: "pending"), incoming("d", token), incoming("e", token, kind: "thanks", status: "accepted")])
        XCTAssertEqual(added, 2)
        XCTAssertEqual(Set(d.serviceRequests.compactMap(\.remoteID)), ["c", "d"])
        XCTAssertTrue(d.serviceRequests.allSatisfy { $0.status == .pending })
        XCTAssertEqual(d.importRequests([incoming("c", token, status: "pending")]), 0)                     // never twice
    }

    func testAnOlderServerThatSendsNoStatusStillWorks() throws {
        let json = Data(#"{"id":"r1","token":"t","kind":"urgent","reason":"medical","note":"x","createdAt":"2027-01-15T08:00:00.000Z","stormId":null}"#.utf8)
        let old = try JSONDecoder().decode(IncomingRequest.self, from: json)
        XCTAssertNil(old.status); XCTAssertEqual(old.reason, "medical")
        let new = try JSONDecoder().decode(IncomingRequest.self, from: Data(#"{"id":"r1","token":"t","kind":"thanks","reason":null,"note":"x","createdAt":"2027-01-15T08:00:00.000Z","stormId":"s","status":"pending"}"#.utf8))
        XCTAssertEqual(new.status, "pending")
    }

    func testThePrivacyTextSaysWhatTheAppReallyDoes() {
        let p = LegalText.privacy
        // Each way the assistant can reach Anthropic, and what the built-in server keeps.
        for fact in ["your own Anthropic key", "through your own server", "Ridgeline Ops assistant server", "does not store it",
                     "Client phone numbers and email addresses are not sent",
                     // Things that stay on the device.
                     "expenses and receipt photos", "Contacts you pick", "never reads the rest of your address book", "notifications made on your device",
                     // Where everything else goes.
                     "Apple Maps", "National Weather Service", "email provider", "Purchases are handled by Apple", "We do not sell your data",
                     "Delete my account and data"] {
            XCTAssertTrue(p.contains(fact), fact)
        }
        XCTAssertFalse(p.contains("\\")); XCTAssertFalse(p.contains("`"))                                 // the server shows the same text from JavaScript
        for step in ["Subscriptions", "Restore purchases", "Delete my account and data"] { XCTAssertTrue(LegalText.support.contains(step), step) }
        XCTAssertEqual(StoreProducts.termsURL, "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    func testPlanClaimsMatchWhatTheCodeUnlocks() {
        // Nothing that was never built is offered as a feature.
        let names = Set(Feature.allCases.map(\.rawValue))
        for ghost in ["subManagement", "quickBooksSync", "marketing"] { XCTAssertFalse(names.contains(ghost), ghost) }
        // What Max adds over Pro: custom permissions and a bigger team. Everything else is in both.
        let maxOnly = Feature.allCases.filter { Entitlements.requiredTier(for: $0) == .max }
        XCTAssertEqual(Set(maxOnly), [.rolesAndReports, .stormAutomation])
        XCTAssertEqual(Entitlements.requiredTier(for: .routeOptimizer), .pro)
        XCTAssertLessThan(TeamRules.employeeLimit(for: .pro), TeamRules.employeeLimit(for: .max))
        // Four products: Pro and Max, monthly and yearly, and every one maps back to its plan.
        XCTAssertEqual(StoreProducts.allIDs.count, 4)
        for id in StoreProducts.allIDs { XCTAssertNotNil(StoreProducts.plan(for: id), id) }
    }
}
