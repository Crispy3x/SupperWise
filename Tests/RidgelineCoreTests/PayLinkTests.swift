import XCTest
@testable import RidgelineCore

final class PayLinkTests: XCTestCase {
    func testAcceptsKnownPaymentSites() {
        XCTAssertEqual(PayLink.clean("https://buy.stripe.com/abc123"), "https://buy.stripe.com/abc123")
        XCTAssertEqual(PayLink.clean("  https://paypal.me/ridgeplow  "), "https://paypal.me/ridgeplow")
        XCTAssertNotNil(PayLink.clean("https://square.link/u/xyz"))
        XCTAssertNotNil(PayLink.clean("https://cash.app/$ridgeplow"))
        XCTAssertNotNil(PayLink.clean("https://account.venmo.com/u/ridge"))
    }

    func testRejectsUnsafeOrUnknownLinks() {
        for bad in ["", "http://paypal.me/x", "https://evil.example.com/pay", "https://paypal.com@evil.example.com/x",
                    "https://notstripe.com/x", "https://stripe.com.evil.com/x", "javascript:alert(1)", "https://stripe.com:8443/x",
                    "https://stripe.com/a b", "ftp://stripe.com/x", "https://stripe.com/x#frag", "stripe.com/x"] {
            XCTAssertNil(PayLink.clean(bad), bad)
        }
        XCTAssertNil(PayLink.clean("https://stripe.com/" + String(repeating: "a", count: 600)))
    }

    func testProblemMessages() {
        XCTAssertNil(PayLink.problem(for: ""))
        XCTAssertNil(PayLink.problem(for: "https://buy.stripe.com/x"))
        XCTAssertEqual(PayLink.problem(for: "http://paypal.me/x"), "The link must start with https://")
        XCTAssertTrue(PayLink.problem(for: "https://evil.example.com")!.contains("not on the list"))
    }

    func testOnboardingStoresOnlyAGoodLink() throws {
        var d = AppData()
        var a = OnboardingAnswers(); a.businessName = "Ridge Plow"; a.payLink = "https://evil.example.com/x"
        try d.finishOnboarding(a, now: Date())
        XCTAssertNil(d.profile.payLink)
        a.payLink = "https://buy.stripe.com/ok"
        try d.finishOnboarding(a, now: Date())
        XCTAssertEqual(d.profile.payLink, "https://buy.stripe.com/ok")
    }

    func testOldSavedProfileWithoutPayLinkStillLoads() throws {
        let old = try JSONEncoder().encode(BusinessProfile())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json.removeValue(forKey: "payLink")
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(BusinessProfile.self, from: data).payLink)
    }

    func testInvoiceEmailAndPortalCarryTheLink() {
        let cust = Customer(name: "Sam", email: "sam@example.com")
        let site = Site(customerID: cust.id, address: "14 Elm Ave")
        var inv = Invoice(number: "INV-1", customerID: cust.id, siteID: site.id, issueDate: Date(), dueDate: Date().addingTimeInterval(86_400),
                          lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])
        _ = inv.lines
        let withLink = InvoiceMessage.compose(invoice: inv, customer: cust, site: site, company: "Ridge Plow", portalURL: nil,
                                              howToPay: "", payLink: "https://buy.stripe.com/ok")
        XCTAssertTrue(withLink.body.contains("Pay online: https://buy.stripe.com/ok"))
        let bad = InvoiceMessage.compose(invoice: inv, customer: cust, site: site, company: "Ridge Plow", portalURL: nil,
                                         howToPay: "", payLink: "https://evil.example.com/x")
        XCTAssertFalse(bad.body.contains("evil.example.com"))
        let none = InvoiceMessage.compose(invoice: inv, customer: cust, site: site, company: "Ridge Plow", portalURL: nil, howToPay: "")
        XCTAssertFalse(none.body.contains("Pay online"))
        inv.notes = ""
    }
}
