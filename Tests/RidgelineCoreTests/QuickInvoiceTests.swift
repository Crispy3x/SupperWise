import XCTest
@testable import RidgelineCore

final class QuickInvoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func dataWithClient(site: Bool = true) -> (AppData, Customer, Site?) {
        var d = AppData()
        let c = Customer(name: "Jane Doe")
        d.customers.append(c)
        var s: Site?
        if site {
            let made = Site(customerID: c.id, address: "14 Elm Ave")
            d.sites.append(made)
            s = made
        }
        return (d, c, s)
    }

    // MARK: presets

    func testSnowServicesGiveTheSnowList() {
        let list = PriceList.presets(for: [.snowPlowing])
        XCTAssertEqual(list.map(\.name), ["Driveway push", "Sidewalk shovel", "Salting", "Seasonal driveway"])
        XCTAssertEqual(list.map(\.price), [Money(dollars: 45), Money(dollars: 25), Money(dollars: 35), Money(dollars: 450)])
        XCTAssertEqual(list.last?.unit, .season)
        XCTAssertEqual(PriceList.presets(for: [.salting, .shoveling]), PriceList.snowPresets)
    }

    func testLawnServicesGiveTheLawnList() {
        let list = PriceList.presets(for: [.mowing])
        XCTAssertEqual(list.map(\.name), ["Lawn mow", "Trim and edge", "Spring cleanup", "Fall cleanup"])
        XCTAssertEqual(list.map(\.price), [Money(dollars: 40), Money(dollars: 25), Money(dollars: 150), Money(dollars: 175)])
        XCTAssertEqual(PriceList.presets(for: [.landscaping]), PriceList.lawnPresets)
    }

    func testBothGiveTheUnionSnowFirstAndOtherOnlyStillGivesAList() {
        let both = PriceList.presets(for: [.snowPlowing, .mowing])
        XCTAssertEqual(both, PriceList.snowPresets + PriceList.lawnPresets)
        XCTAssertEqual(Set(both.map(\.id)).count, 8)
        XCTAssertEqual(PriceList.presets(for: [.other]).count, 8)
        XCTAssertEqual(PriceList.presets(for: []).count, 8)
    }

    func testPresetIdsAreStableBetweenCalls() {
        XCTAssertEqual(PriceList.presets(for: [.snowPlowing]).map(\.id), PriceList.presets(for: [.snowPlowing]).map(\.id))
    }

    // MARK: the saved list

    func testListFollowsTheProfileUntilEditedThenStaysAndSurvivesSaving() throws {
        var d = AppData()
        d.profile.services = [.mowing]
        XCTAssertNil(d.servicePrices)
        XCTAssertEqual(d.priceList, PriceList.lawnPresets)
        d.profile.services = [.snowPlowing]
        XCTAssertEqual(d.priceList, PriceList.snowPresets)

        var list = d.priceList
        list[0].price = Money(dollars: 55)
        d.setPriceList(list)
        d.profile.services = [.mowing]                          // an edited list no longer follows the profile
        XCTAssertEqual(d.priceList.first?.price, Money(dollars: 55))
        XCTAssertEqual(d.priceList.first?.name, "Driveway push")

        let encoded = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(AppData.self, from: encoded)
        XCTAssertEqual(decoded.servicePrices, d.servicePrices)

        d.resetPriceList()
        XCTAssertEqual(d.priceList, PriceList.lawnPresets)
    }

    func testOlderFilesWithoutAPriceListStillLoad() throws {
        let decoded = try JSONDecoder().decode(AppData.self, from: Data("{\"companyName\":\"Ridge\"}".utf8))
        XCTAssertNil(decoded.servicePrices)
        XCTAssertEqual(decoded.companyName, "Ridge")
    }

    func testAddRemoveAndNegativePrices() {
        var d = AppData()
        d.profile.services = [.snowPlowing]
        let id = d.addService(name: "Roof rake", price: Money(dollars: 60), unit: .job)
        XCTAssertNotNil(id)
        XCTAssertEqual(d.priceList.count, 5)
        XCTAssertEqual(d.priceList.last?.name, "Roof rake")

        d.removeService(id: PriceList.snowPresets[0].id)
        XCTAssertEqual(d.priceList.count, 4)
        XCTAssertFalse(d.priceList.contains { $0.name == "Driveway push" })

        var list = d.priceList
        list[0].price = Money(cents: -500)
        d.setPriceList(list)
        XCTAssertEqual(d.priceList[0].price, .zero)

        d.setPriceList([])
        XCTAssertEqual(d.priceList, [])                         // removing everything is kept, not refilled
    }

    func testListLengthIsCapped() {
        var d = AppData()
        d.setPriceList((0..<100).map { ServicePrice(name: "S\($0)", price: Money(dollars: 1)) })
        XCTAssertEqual(d.priceList.count, PriceList.maxServices)
        XCTAssertNil(d.addService())
    }

    // MARK: totals

    func testLinesAndTotals() {
        let push = PriceList.snowPresets[0], salt = PriceList.snowPresets[2]
        let picks = [QuickInvoicePick(service: push, quantity: 3), QuickInvoicePick(service: salt, quantity: 1),
                     QuickInvoicePick(service: PriceList.snowPresets[1], quantity: 0)]
        let lines = QuickInvoice.lines(picks)
        XCTAssertEqual(lines.map(\.description), ["Driveway push x 3 ($45.00 each)", "Salting"])
        XCTAssertEqual(lines.map(\.amount), [Money(dollars: 135), Money(dollars: 35)])
        XCTAssertEqual(QuickInvoice.total(picks), Money(dollars: 170))
    }

    func testChangedPriceAndCentsAndBlankNames() {
        var push = PriceList.snowPresets[0]
        push.price = Money(cents: 4_250)
        var blank = ServicePrice(name: "   ", price: Money(dollars: 10))
        blank.unit = .hour
        let picks = [QuickInvoicePick(service: push, quantity: 2), QuickInvoicePick(service: blank, quantity: 1)]
        XCTAssertEqual(QuickInvoice.total(picks), Money(cents: 9_500))
        XCTAssertEqual(QuickInvoice.lines(picks).last?.description, "Service")
        XCTAssertEqual(QuickInvoice.total([]), .zero)
    }

    // MARK: creating the invoice

    func testCreatesARealDraftInvoiceWithNumberDueDateAndNote() throws {
        var (d, c, s) = dataWithClient()
        d.profile.netDays = 30
        XCTAssertTrue(d.needsFirstInvoice)
        let picks = [QuickInvoicePick(service: PriceList.snowPresets[0], quantity: 2)]
        let inv = try d.createQuickInvoice(customerID: c.id, picks: picks, note: "  Thanks!  ", now: t0)
        XCTAssertEqual(inv.number, "INV-0001")
        XCTAssertEqual(inv.customerID, c.id)
        XCTAssertEqual(inv.siteID, s?.id)
        XCTAssertEqual(inv.total, Money(dollars: 90))
        XCTAssertEqual(inv.dueDate, t0.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(inv.notes, "Thanks!")
        XCTAssertEqual(inv.status(now: t0), .draft)
        XCTAssertEqual(d.invoices, [inv])
        XCTAssertFalse(d.needsFirstInvoice)                     // the "Send your first invoice" card goes away

        // The existing invoice tools work on it: PDF and email plan.
        XCTAssertNotNil(d.invoicePDF(number: inv.number))
        let second = try d.createQuickInvoice(customerID: c.id, picks: picks, now: t0)
        XCTAssertEqual(second.number, "INV-0002")
    }

    func testEmailPlanWorksForAClientWhoAgreed() throws {
        var (d, c, _) = dataWithClient()
        d.customers[0].email = "jane@example.com"
        d.customers[0].emailConsent = true
        let inv = try d.createQuickInvoice(customerID: c.id, picks: [QuickInvoicePick(service: PriceList.lawnPresets[0], quantity: 1)], now: t0)
        guard case .ready(let message) = d.invoiceEmail(number: inv.number) else { return XCTFail("expected an email ready to send") }
        XCTAssertEqual(message.to, "jane@example.com")
    }

    func testPicksTheChosenAddressWhenTheClientHasSeveral() throws {
        var (d, c, _) = dataWithClient()
        let cabin = Site(customerID: c.id, address: "2 Lake Rd")
        d.sites.append(cabin)
        let picks = [QuickInvoicePick(service: PriceList.lawnPresets[0], quantity: 1)]
        XCTAssertEqual(try d.createQuickInvoice(customerID: c.id, siteID: cabin.id, picks: picks, now: t0).siteID, cabin.id)
        // Someone else's address is never used.
        let other = Customer(name: "Bob")
        let bobSite = Site(customerID: other.id, address: "9 Oak St")
        d.customers.append(other); d.sites.append(bobSite)
        XCTAssertNotEqual(try d.createQuickInvoice(customerID: c.id, siteID: bobSite.id, picks: picks, now: t0).siteID, bobSite.id)
    }

    func testClientWithoutAnAddressNeedsOneAndItIsSaved() throws {
        var (d, c, _) = dataWithClient(site: false)
        let picks = [QuickInvoicePick(service: PriceList.snowPresets[0], quantity: 1)]
        XCTAssertThrowsError(try d.createQuickInvoice(customerID: c.id, newAddress: "  ", picks: picks, now: t0)) {
            XCTAssertEqual($0 as? QuickInvoiceError, .noAddress)
        }
        XCTAssertTrue(d.invoices.isEmpty)
        let inv = try d.createQuickInvoice(customerID: c.id, newAddress: " 5 Pine Ct ", picks: picks, now: t0)
        XCTAssertEqual(d.sites.count, 1)
        XCTAssertEqual(d.sites.first?.address, "5 Pine Ct")
        XCTAssertEqual(inv.siteID, d.sites.first?.id)
        XCTAssertTrue(d.portalLinks.contains { $0.siteID == inv.siteID })
    }

    func testRefusesWhatCannotBeInvoiced() {
        var (d, c, _) = dataWithClient()
        let free = ServicePrice(name: "Free check", price: .zero)
        XCTAssertThrowsError(try d.createQuickInvoice(customerID: UUID(), picks: [QuickInvoicePick(service: free, quantity: 1)], now: t0)) {
            XCTAssertEqual($0 as? QuickInvoiceError, .clientNotFound)
        }
        XCTAssertThrowsError(try d.createQuickInvoice(customerID: c.id, picks: [], now: t0)) {
            XCTAssertEqual($0 as? QuickInvoiceError, .nothingPicked)
        }
        XCTAssertThrowsError(try d.createQuickInvoice(customerID: c.id, picks: [QuickInvoicePick(service: free, quantity: 2)], now: t0)) {
            XCTAssertEqual($0 as? QuickInvoiceError, .zeroTotal)
        }
        XCTAssertTrue(d.invoices.isEmpty)
        XCTAssertFalse(QuickInvoiceError.noAddress.message.isEmpty)
    }
}
