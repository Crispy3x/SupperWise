import XCTest
@testable import RidgelineCore

final class PricingTests: XCTestCase {
    func testProMonthlyTotals() {
        XCTAssertEqual(Pricing.monthly(.pro, crews: 1), Money(dollars: 29))
        XCTAssertEqual(Pricing.monthly(.pro, crews: 3), Money(dollars: 67))
        XCTAssertEqual(Pricing.monthly(.pro, crews: 5), Money(dollars: 105))
        XCTAssertEqual(Pricing.monthly(.pro, crews: 10), Money(dollars: 165))
    }

    func testMaxMonthlyTotals() {
        XCTAssertEqual(Pricing.monthly(.max, crews: 1), Money(dollars: 79))
        XCTAssertEqual(Pricing.monthly(.max, crews: 3), Money(dollars: 137))
        XCTAssertEqual(Pricing.monthly(.max, crews: 5), Money(dollars: 195))
        XCTAssertEqual(Pricing.monthly(.max, crews: 10), Money(dollars: 290))
    }

    func testAnnualIsTwentyPercentOff() {
        XCTAssertEqual(Pricing.annualPerMonth(.pro, crews: 10), Money(dollars: 132))
        XCTAssertEqual(Pricing.annualPerMonth(.max, crews: 10), Money(dollars: 232))
        XCTAssertEqual(Pricing.annualPerMonth(.pro, crews: 1), Money(cents: 2320))
        XCTAssertEqual(Pricing.annualTotal(.pro, crews: 10), Money(dollars: 1584))
    }

    func testCrewsBelowOneTreatedAsOne() {
        XCTAssertEqual(Pricing.monthly(.pro, crews: 0), Money(dollars: 29))
        XCTAssertEqual(Pricing.monthly(.max, crews: -3), Money(dollars: 79))
    }

    func testPriceIsMonotonicInCrews() {
        for tier in PlanTier.allCases {
            var last = Money.zero
            for n in 1...30 {
                let p = Pricing.monthly(tier, crews: n)
                XCTAssertGreaterThan(p, last)
                last = p
            }
        }
    }

    func testMoneyFormatting() {
        XCTAssertEqual(Money(cents: 123450).formatted, "$1,234.50")
        XCTAssertEqual(Money(cents: 5).formatted, "$0.05")
        XCTAssertEqual(Money(cents: -2500).formatted, "-$25.00")
    }
}
