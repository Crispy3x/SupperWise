import XCTest
@testable import RidgelineCore

final class ReviewRequestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private let link = "https://g.page/r/ridgeplow/review"

    private func data(customer: Customer, link: String? = "https://g.page/r/ridgeplow/review") -> AppData {
        var d = AppData()
        d.companyName = "Ridge Plow"
        d.profile.reviewLink = link
        d.customers = [customer]
        return d
    }

    // MARK: link validation

    func testAcceptsReviewSites() {
        XCTAssertEqual(ReviewLink.clean("https://g.page/r/abc/review"), "https://g.page/r/abc/review")
        XCTAssertEqual(ReviewLink.clean("  https://maps.app.goo.gl/xyz  "), "https://maps.app.goo.gl/xyz")
        XCTAssertNotNil(ReviewLink.clean("https://search.google.com/local/writereview?placeid=ChIJ123"))
        XCTAssertNotNil(ReviewLink.clean("https://www.google.com/maps/place/Ridge+Plow"))
        XCTAssertNotNil(ReviewLink.clean("https://www.yelp.com/biz/ridge-plow"))
        XCTAssertNotNil(ReviewLink.clean("https://www.facebook.com/ridgeplow/reviews"))
        XCTAssertNotNil(ReviewLink.clean("https://nextdoor.com/pages/ridge-plow"))
    }

    func testRejectsOtherLinks() {
        for bad in ["http://g.page/r/abc", "https://evil.example.com/review", "https://google.com.evil.com/x",
                    "https://notgoogle.com/x", "https://goo.gl/abc", "https://g.page@evil.com/x", "https://yelp.com:8443/x",
                    "https://yelp.com/a b", "javascript:alert(1)", "g.page/r/abc", "https://yelp.com/biz#top", "ftp://yelp.com/x"] {
            XCTAssertNil(ReviewLink.clean(bad), bad)
        }
        XCTAssertNil(ReviewLink.clean("https://yelp.com/" + String(repeating: "a", count: 600)))
    }

    func testLinkProblemsSayWhy() {
        XCTAssertNil(ReviewLink.problem(for: ""))
        XCTAssertNil(ReviewLink.problem(for: link))
        XCTAssertEqual(ReviewLink.problem(for: "http://g.page/r/abc"), "The link must start with https://")
        XCTAssertTrue(ReviewLink.problem(for: "https://evil.example.com/x")!.contains("Google, Yelp, Facebook or Nextdoor"))
        XCTAssertTrue(ReviewLink.problem(for: "https://yelp.com/a b")!.contains("spaces"))
        XCTAssertTrue(ReviewLink.problem(for: "https://g.page:444/x")!.contains("port"))
    }

    func testOldProfileWithoutReviewFieldsStillLoads() throws {
        let json = try JSONEncoder().encode(BusinessProfile())
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        dict.removeValue(forKey: "reviewLink")
        dict.removeValue(forKey: "reviewSuggestionsEnabled")
        let p = try JSONDecoder().decode(BusinessProfile.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(p.reviewLink)
        XCTAssertTrue(p.reviewSuggestionsOn)
    }

    func testCustomerAskDateRoundTripsAndOldFilesLoad() throws {
        var c = Customer(name: "Sam Lee")
        c.reviewAskedAt = now
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(Customer.self, from: e.encode(c)).reviewAskedAt, now)
        let old = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        XCTAssertNil(try d.decode(Customer.self, from: old).reviewAskedAt)
    }

    // MARK: who can be asked

    func testNinetyDayRule() throws {
        var c = Customer(name: "Sam Lee", phone: "555-123-4567")
        var d = data(customer: c)
        XCTAssertNil(ReviewRequests.blocker(for: c, link: link, now: now))
        try d.recordReviewAsked(customerID: c.id, now: now)
        XCTAssertEqual(d.customers[0].reviewAskedAt, now)
        c = d.customers[0]
        if case .askedRecently(let asked, let next)? = ReviewRequests.blocker(for: c, link: link, now: now.addingTimeInterval(89 * day)) {
            XCTAssertEqual(asked, now)
            XCTAssertEqual(next, now.addingTimeInterval(90 * day))
        } else { XCTFail("should be blocked inside 90 days") }
        XCTAssertThrowsError(try d.recordReviewAsked(customerID: c.id, now: now.addingTimeInterval(30 * day)))
        XCTAssertNil(ReviewRequests.blocker(for: c, link: link, now: now.addingTimeInterval(90 * day)))
        XCTAssertNoThrow(try d.recordReviewAsked(customerID: c.id, now: now.addingTimeInterval(91 * day)))
    }

    func testOptedOutClientIsNeverAsked() {
        let c = Customer(name: "Sam Lee", phone: "555-123-4567", optedOutAt: now.addingTimeInterval(-day))
        var d = data(customer: c)
        XCTAssertEqual(ReviewRequests.blocker(for: c, link: link, now: now), .optedOut)
        guard case .failure(.optedOut)? = d.reviewDraft(customerID: c.id, now: now) else { return XCTFail("opted out") }
        XCTAssertThrowsError(try d.recordReviewAsked(customerID: c.id, now: now)) { XCTAssertEqual($0 as? ReviewAskBlocker, .optedOut) }
        XCTAssertNil(d.customers[0].reviewAskedAt)
    }

    func testLeadsAndMissingLinkAreBlocked() {
        let lead = Customer(name: "New Person", isLead: true)
        XCTAssertEqual(ReviewRequests.blocker(for: lead, link: link, now: now), .notAClient)
        let c = Customer(name: "Sam Lee")
        XCTAssertEqual(ReviewRequests.blocker(for: c, link: nil, now: now), .noLink)
        XCTAssertEqual(ReviewRequests.blocker(for: c, link: "https://evil.example.com", now: now), .noLink)
        guard case .failure(.noLink)? = data(customer: c, link: nil).reviewDraft(customerID: c.id, now: now) else { return XCTFail("no link") }
        XCTAssertNil(data(customer: c).reviewDraft(customerID: UUID(), now: now))
    }

    // MARK: message text

    func testMessageUsesFirstNameCompanyAndLink() {
        let text = ReviewRequests.message(clientName: "Sam Lee", company: "Ridge Plow", link: link)
        XCTAssertTrue(text.hasPrefix("Hi Sam, thanks for choosing Ridge Plow."))
        XCTAssertTrue(text.contains(link))
        XCTAssertTrue(text.contains("review"))
        XCTAssertLessThan(text.count, 260)
        XCTAssertTrue(ReviewRequests.message(clientName: "", company: "", link: link).hasPrefix("Hi there, thanks for choosing us."))
    }

    func testFirstName() {
        XCTAssertEqual(ReviewRequests.firstName("Sam Lee"), "Sam")
        XCTAssertEqual(ReviewRequests.firstName("  Maria  "), "Maria")
        XCTAssertEqual(ReviewRequests.firstName("Maple Ridge HOA"), "there")
        XCTAssertEqual(ReviewRequests.firstName("Smith Properties LLC"), "there")
        XCTAssertEqual(ReviewRequests.firstName(""), "there")
    }

    func testDraftBuildsTextAndMailLinks() throws {
        let c = Customer(name: "Sam Lee", phone: "(555) 123-4567", email: "sam@example.com")
        guard case .success(let draft)? = data(customer: c).reviewDraft(customerID: c.id, now: now) else { return XCTFail("should be ready") }
        XCTAssertTrue(draft.text.contains(link))
        XCTAssertEqual(draft.subject, "A quick favor from Ridge Plow")
        let sms = try XCTUnwrap(draft.smsURL).absoluteString
        XCTAssertTrue(sms.hasPrefix("sms:5551234567&body=Hi%20Sam"))
        XCTAssertFalse(sms.contains(" "))
        let mail = try XCTUnwrap(draft.mailURL).absoluteString
        XCTAssertTrue(mail.hasPrefix("mailto:sam@example.com?subject=A%20quick%20favor"))
        XCTAssertTrue(mail.contains("g.page%2Fr%2Fridgeplow"))
    }

    func testNoPhoneOrEmailMeansNoTextOrMailLink() {
        let c = Customer(name: "Sam Lee", phone: "12", email: "not-an-email")
        guard case .success(let draft)? = data(customer: c).reviewDraft(customerID: c.id, now: now) else { return XCTFail("should be ready") }
        XCTAssertNil(draft.smsURL)
        XCTAssertNil(draft.mailURL)
    }

    // MARK: suggestions

    func testSuggestsAfterPaidInvoiceOrThanks() throws {
        let c = Customer(name: "Sam Lee")
        let site = Site(customerID: c.id, address: "1 Main St")
        var d = data(customer: c)
        d.sites = [site]
        XCTAssertFalse(d.shouldSuggestReview(customerID: c.id, now: now))

        var inv = Invoice(number: "INV-1", customerID: c.id, siteID: site.id, issueDate: now.addingTimeInterval(-20 * day),
                          dueDate: now, lines: [InvoiceLineItem(description: "Plowing", amount: Money(dollars: 60))])
        try inv.record(ManualPayment(amount: Money(dollars: 60), date: now.addingTimeInterval(-2 * day), method: .cash))
        d.invoices = [inv]
        XCTAssertTrue(d.shouldSuggestReview(customerID: c.id, now: now))
        XCTAssertFalse(d.shouldSuggestReview(customerID: c.id, now: now.addingTimeInterval(20 * day)))

        d.profile.reviewSuggestionsEnabled = false
        XCTAssertFalse(d.shouldSuggestReview(customerID: c.id, now: now))
        d.profile.reviewSuggestionsEnabled = nil

        d.invoices = []
        let thanks = ServiceRequest(siteID: site.id, kind: .thanks, note: "Great job!", createdAt: now.addingTimeInterval(-day))
        d.serviceRequests = [thanks]
        XCTAssertEqual(d.customerID(forRequest: thanks), c.id)
        XCTAssertTrue(d.shouldSuggestReview(customerID: c.id, now: now))

        try d.recordReviewAsked(customerID: c.id, now: now)
        XCTAssertFalse(d.shouldSuggestReview(customerID: c.id, now: now.addingTimeInterval(day)))
    }
}
