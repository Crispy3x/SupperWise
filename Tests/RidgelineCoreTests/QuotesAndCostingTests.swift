import XCTest
@testable import RidgelineCore

final class QuoteTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400
    private func quote() -> Quote {
        Quote(number: "Q-1", customerID: UUID(), address: "5 Pine", season: "2026-27",
              terms: .perPush(rate: Money(dollars: 60)), createdAt: t0, validDays: 30)
    }

    func testLifecycle() throws {
        var q = quote()
        XCTAssertEqual(q.status(now: t0), .draft)
        q.markSent(at: t0 + day)
        XCTAssertEqual(q.status(now: t0 + 2 * day), .sent)
        XCTAssertEqual(q.status(now: t0 + 31 * day), .expired)
        try q.accept(at: t0 + 5 * day)
        XCTAssertEqual(q.status(now: t0 + 90 * day), .accepted)      // accepted stays accepted after the date passes
    }

    func testCannotAcceptExpiredOrDecideTwice() throws {
        var q = quote()
        XCTAssertThrowsError(try q.accept(at: t0 + 31 * day)) { XCTAssertEqual($0 as? QuoteError, .expired) }
        try q.decline(at: t0 + day)
        XCTAssertEqual(q.status(now: t0 + 2 * day), .declined)
        XCTAssertThrowsError(try q.accept(at: t0 + 2 * day)) { XCTAssertEqual($0 as? QuoteError, .alreadyDecided) }
        XCTAssertThrowsError(try q.decline(at: t0 + 2 * day)) { XCTAssertEqual($0 as? QuoteError, .alreadyDecided) }
    }

    func testContractOnlyFromAcceptedQuote() throws {
        var q = quote()
        XCTAssertThrowsError(try q.makeContract(siteID: UUID())) { XCTAssertEqual($0 as? QuoteError, .notAccepted) }
        try q.accept(at: t0 + day)
        let site = UUID()
        let c = try q.makeContract(siteID: site)
        XCTAssertEqual(c.siteID, site)
        XCTAssertEqual(c.terms, q.terms)
        XCTAssertEqual(c.season, "2026-27")
    }

    func testQuoteRoundTripsThroughJSON() throws {
        var q = quote()
        try q.accept(at: t0 + day)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(Quote.self, from: e.encode(q)), q)
    }

    func testSeasonEstimatesForEachContractType() {
        let a = SeasonEstimate.Assumptions(pushes: 10, averageDepthInches: 5, hoursPerPush: 1, materialsPerPush: Money(dollars: 20))
        XCTAssertEqual(SeasonEstimate.cost(.perPush(rate: Money(dollars: 60)), a), Money(dollars: 600))
        XCTAssertEqual(SeasonEstimate.cost(.seasonal(total: Money(dollars: 900)), a), Money(dollars: 900))
        let tiers = [DepthTier(minInches: 2, rate: Money(dollars: 40)), DepthTier(minInches: 6, rate: Money(dollars: 70))]
        XCTAssertEqual(SeasonEstimate.cost(.perInch(tiers: tiers), a), Money(dollars: 400))          // 5 in -> $40 tier
        XCTAssertEqual(SeasonEstimate.cost(.perInch(tiers: tiers), SeasonEstimate.Assumptions(pushes: 10, averageDepthInches: 1)), .zero)
        XCTAssertEqual(SeasonEstimate.cost(.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 8, overagePerPush: Money(dollars: 45)), a), Money(dollars: 590))
        // T&M: (1h x $100) + ($20 x 1.10) = $122 per push
        XCTAssertEqual(SeasonEstimate.cost(.timeAndMaterials(hourly: Money(dollars: 100), materialsMarkupPercent: 10), a), Money(dollars: 1220))
    }

    func testRangeShowsWorstCase() {
        let terms = ContractTerms.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 8, overagePerPush: Money(dollars: 45))
        let r = SeasonEstimate.range(terms, mild: .init(pushes: 6), heavy: .init(pushes: 20))
        XCTAssertEqual(r.low, Money(dollars: 500))
        XCTAssertEqual(r.high, Money(dollars: 500 + 12 * 45))
    }
}

final class JobCostingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testMarginMath() {
        let entries = [TimeEntry(memberName: "Sam", start: t0, end: t0 + 7200), TimeEntry(memberName: "Lee", start: t0, end: t0 + 3600)]
        let cost = JobCosting.site(revenue: Money(dollars: 500), timeEntries: entries, laborCostPerHour: Money(dollars: 30), now: t0 + 99_999,
                                   saltPounds: 100, saltCostPerPound: Money(cents: 25), subcontractorPay: Money(dollars: 100))
        XCTAssertEqual(cost.labor, Money(dollars: 90))          // 3 hours
        XCTAssertEqual(cost.materials, Money(dollars: 25))
        XCTAssertEqual(cost.totalCost, Money(dollars: 215))
        XCTAssertEqual(cost.margin, Money(dollars: 285))
        XCTAssertEqual(cost.marginPercent!, 57, accuracy: 0.001)
    }

    func testLossAndNoRevenue() {
        let loss = JobCosting.site(revenue: Money(dollars: 50), timeEntries: [TimeEntry(memberName: "S", start: t0, end: t0 + 7200)],
                                   laborCostPerHour: Money(dollars: 40), now: t0, saltPounds: 0, saltCostPerPound: .zero)
        XCTAssertEqual(loss.margin, Money(dollars: -30))
        XCTAssertLessThan(loss.marginPercent!, 0)
        XCTAssertNil(JobCost(revenue: .zero, labor: Money(dollars: 10), materials: .zero, subcontractors: .zero).marginPercent)
    }

    func testInvoicedRevenueSkipsVoidAndOtherSites() {
        let site = UUID()
        func inv(_ siteID: UUID, _ dollars: Int) -> Invoice {
            Invoice(number: "I", customerID: UUID(), siteID: siteID, issueDate: t0, dueDate: t0,
                    lines: [InvoiceLineItem(description: "x", amount: Money(dollars: dollars))])
        }
        var voided = inv(site, 300)
        voided.void()
        let revenue = JobCosting.invoicedRevenue(siteID: site, invoices: [inv(site, 100), inv(site, 50), voided, inv(UUID(), 999)])
        XCTAssertEqual(revenue, Money(dollars: 150))
    }
}
