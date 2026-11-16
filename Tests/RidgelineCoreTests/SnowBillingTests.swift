import XCTest
@testable import RidgelineCore

final class SnowBillingTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    func testPerPushBillsEachCompletedVisitOncePerStormLine() {
        let visits = [
            Visit(stormID: "S1", date: day(1)),
            Visit(stormID: "S1", date: day(2)),
            Visit(stormID: "S2", date: day(10)),
        ]
        let r = SnowBilling.bill(terms: .perPush(rate: Money(dollars: 60)), visits: visits)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.total, Money(dollars: 180))
        XCTAssertEqual(r.pushesUsed, 3)
    }

    func testSkippedVisitsAreNeverBilled() {
        let visits = [
            Visit(stormID: "S1", date: day(1)),
            Visit(stormID: "S2", date: day(2), status: .skipped(reason: "Gate locked")),
        ]
        let r = SnowBilling.bill(terms: .perPush(rate: Money(dollars: 50)), visits: visits)
        XCTAssertEqual(r.total, Money(dollars: 50))
        XCTAssertEqual(r.skippedVisitCount, 1)
        XCTAssertEqual(r.lines.count, 1)
    }

    func testSeasonalBilledOnceAndCanBeSuppressed() {
        let visits = [Visit(stormID: "S1", date: day(1)), Visit(stormID: "S2", date: day(5))]
        let first = SnowBilling.bill(terms: .seasonal(total: Money(dollars: 900)), visits: visits)
        XCTAssertEqual(first.total, Money(dollars: 900))
        let later = SnowBilling.bill(terms: .seasonal(total: Money(dollars: 900)), visits: visits, includeSeasonalBase: false)
        XCTAssertEqual(later.total, .zero)
    }

    func testPerInchUsesDeepestVisitTier() {
        let tiers = [
            DepthTier(minInches: 2, rate: Money(dollars: 40)),
            DepthTier(minInches: 6, rate: Money(dollars: 70)),
            DepthTier(minInches: 12, rate: Money(dollars: 120)),
        ]
        let visits = [
            Visit(stormID: "S1", date: day(1), snowDepthInches: 3),
            Visit(stormID: "S1", date: day(2), snowDepthInches: 7),   // deepest: 7 -> $70
            Visit(stormID: "S2", date: day(9), snowDepthInches: 1),   // below trigger -> $0
            Visit(stormID: "S3", date: day(15), snowDepthInches: 12), // exactly 12 -> $120
        ]
        let r = SnowBilling.bill(terms: .perInch(tiers: tiers), visits: visits)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.total, Money(dollars: 190))
    }

    func testHybridBillsOverageOnlyAfterCap() {
        let terms = ContractTerms.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 3, overagePerPush: Money(dollars: 45))
        let visits = [
            Visit(stormID: "S1", date: day(1)),
            Visit(stormID: "S2", date: day(5)),
            Visit(stormID: "S3", date: day(9)),
            Visit(stormID: "S4", date: day(13)),   // 4th push -> overage
            Visit(stormID: "S4", date: day(14)),   // 5th push -> overage
        ]
        let r = SnowBilling.bill(terms: terms, visits: visits)
        XCTAssertEqual(r.total, Money(dollars: 500 + 90))
        XCTAssertTrue(r.capReached)
        XCTAssertEqual(r.pushesUsed, 5)
    }

    func testHybridCountsEarlierInvoicedPushesAndSkipsBase() {
        let terms = ContractTerms.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 3, overagePerPush: Money(dollars: 45))
        let visits = [Visit(stormID: "S5", date: day(20))]
        let r = SnowBilling.bill(terms: terms, visits: visits, includeSeasonalBase: false, alreadyUsedPushes: 3)
        XCTAssertEqual(r.total, Money(dollars: 45))
        XCTAssertEqual(r.pushesUsed, 4)
    }

    func testHybridUnderCapDoesNotWarnUntilReached() {
        let terms = ContractTerms.hybrid(seasonalBase: Money(dollars: 500), includedPushes: 5, overagePerPush: Money(dollars: 45))
        let r = SnowBilling.bill(terms: terms, visits: [Visit(stormID: "S1", date: day(1))])
        XCTAssertFalse(r.capReached)
        XCTAssertEqual(r.total, Money(dollars: 500))
    }

    func testTimeAndMaterialsWithMarkup() {
        let terms = ContractTerms.timeAndMaterials(hourly: Money(dollars: 100), materialsMarkupPercent: 20)
        let visits = [
            Visit(stormID: "S1", date: day(1), hours: 1.5, materials: Money(dollars: 40)),
            Visit(stormID: "S1", date: day(2), hours: 0.5, materials: Money(dollars: 10)),
        ]
        let r = SnowBilling.bill(terms: terms, visits: visits)
        // labor 2h x $100 = $200, materials $50 x 1.2 = $60
        XCTAssertEqual(r.total, Money(dollars: 260))
        XCTAssertEqual(r.lines.count, 1)
    }

    func testVisitOrderDoesNotMatter() {
        let a = Visit(stormID: "S1", date: day(1))
        let b = Visit(stormID: "S2", date: day(2))
        let c = Visit(stormID: "S3", date: day(3))
        let terms = ContractTerms.hybrid(seasonalBase: .zero, includedPushes: 1, overagePerPush: Money(dollars: 10))
        XCTAssertEqual(SnowBilling.bill(terms: terms, visits: [a, b, c]),
                       SnowBilling.bill(terms: terms, visits: [c, a, b]))
    }
}
