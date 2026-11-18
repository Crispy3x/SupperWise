import XCTest
@testable import RidgelineCore

final class ModelsTests: XCTestCase {
    func testContractRoundTripsThroughJSON() throws {
        let c = Customer(name: "Pat")
        let s = Site(customerID: c.id, address: "1 Main St", priority: 1, triggerInches: 1.5)
        let contract = SnowContract(siteID: s.id, season: "2026-27",
                                    terms: .hybrid(seasonalBase: Money(dollars: 300), includedPushes: 4,
                                                   overagePerPush: Money(dollars: 40), counting: .perVisit))
        let data = try JSONEncoder().encode(contract)
        let back = try JSONDecoder().decode(SnowContract.self, from: data)
        XCTAssertEqual(back, contract)
    }

    func testPerInchContractRoundTrips() throws {
        let terms = ContractTerms.perInch(tiers: [DepthTier(minInches: 2, rate: Money(dollars: 40))])
        let data = try JSONEncoder().encode(terms)
        XCTAssertEqual(try JSONDecoder().decode(ContractTerms.self, from: data), terms)
    }

    func testSiteDefaults() {
        let s = Site(customerID: UUID(), address: "x")
        XCTAssertEqual(s.priority, 3)
        XCTAssertEqual(s.triggerInches, 2)
    }
}
