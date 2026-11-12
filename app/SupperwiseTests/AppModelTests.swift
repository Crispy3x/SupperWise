import XCTest
@testable import Supperwise

/// The app's saved state and how features hang together, through the same calls the screens make.
final class AppModelTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)
    let lunches = LunchGuide.load(bundle: .main)

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("supperwise-test-\(UUID().uuidString).json")
    }

    @MainActor func family(_ m: AppModel) {
        m.updateSettings { $0.people = [Person(name: "A"), Person(name: "B"), Person(name: "C", diet: .vegetarian)] }
        m.finishOnboarding()
        m.makeFirstWeek()
    }

    @MainActor func testFirstWeekIsFreeAndSaved() async throws {
        let url = tempURL()
        let m = AppModel(catalog: catalog, lunchGuide: lunches, fileURL: url)
        XCTAssertTrue(m.inKitchen.contains("salt"))                       // staples start ticked
        family(m)
        let plan = try XCTUnwrap(m.plan)
        XCTAssertTrue(plan.isFreeWeek)
        XCTAssertEqual(plan.dinners.count, 5)
        XCTAssertNil(plan.lunches)                                        // lunches are off until set up
        // A second launch reads the same week back.
        let again = AppModel(catalog: catalog, lunchGuide: lunches, fileURL: url)
        XCTAssertEqual(again.plan, plan)
        XCTAssertTrue(again.onboarded)
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor func testLunchesJoinTheGroceryList() async throws {
        let m = AppModel(catalog: catalog, lunchGuide: lunches, fileURL: tempURL())
        family(m)
        let before = try XCTUnwrap(m.plan.map { m.cost(of: $0) })
        XCTAssertEqual(before.lunches, 0)
        m.setLunchSettings(LunchSettings(perDay: 2, days: [.mon, .tue, .wed, .thu, .fri], thermos: false))
        let plan = try XCTUnwrap(m.plan)
        XCTAssertEqual(plan.lunches?.count, 5)
        let after = m.cost(of: plan)
        XCTAssertGreaterThan(after.lunches, 0)
        XCTAssertGreaterThan(after.total, before.total)
        XCTAssertTrue(after.lines.contains { $0.lunch })
        for l in plan.lunches ?? [] { XCTAssertTrue(try XCTUnwrap(lunches?.lunch(l.lunchID)).vegetarian) }  // C is vegetarian

        // Leftovers from Monday's dinner cover 2 of Tuesday's lunches, so lunches cost less.
        m.toggleLeftovers(.mon)
        XCTAssertLessThan(m.cost(of: try XCTUnwrap(m.plan)).lunches, after.lunches)

        // Swapping changes only that day.
        let tue = plan.lunches?.first { $0.day == .tue }?.lunchID
        m.swapLunch(.tue)
        XCTAssertNotEqual(m.plan?.lunches?.first { $0.day == .tue }?.lunchID, tue)

        // Next week gets its own lunches; turning lunches off clears them.
        m.makeNextWeek()
        XCTAssertEqual(m.nextPlan?.lunches?.count, 5)
        m.setLunchSettings(nil)
        XCTAssertNil(m.plan?.lunches)
        XCTAssertEqual(m.cost(of: try XCTUnwrap(m.plan)).lunches, 0)
    }

    @MainActor func testOlderSavesStillLoad() async throws {
        // A version-1 save: no lunches, leftovers, recipes or baby fields.
        let url = tempURL()
        let v1 = #"{"settings":{"budget":80,"cheapestWeek":false,"cookNights":[1,2,3],"people":[],"equipment":["oven","stovetop"],"price":{"storeName":"","storeKind":"supermarket","postalCode":""},"dinnerReminder":false},"inKitchen":["salt"],"freeWeekUsed":true,"onboarded":true,"history":[],"seenOffer":true}"#
        try Data(v1.utf8).write(to: url)
        let m = AppModel(catalog: catalog, lunchGuide: lunches, fileURL: url)
        XCTAssertEqual(m.settings.budget, 80)
        XCTAssertNil(m.settings.lunch)
        XCTAssertTrue(m.onboarded)
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor func testDemoFamily() async throws {
        let m = Demo.model(catalog: catalog, lunchGuide: lunches)
        XCTAssertEqual(m.settings.people.count, 4)
        let plan = try XCTUnwrap(m.plan)
        XCTAssertEqual(plan.lunches?.count, 5)
        XCTAssertEqual(plan.leftovers, [.tue])
        XCTAssertTrue(m.seenOffer)
        // Every dinner works for the vegetarian and the child who avoids nuts and spice.
        for (_, r) in m.recipes(of: plan) {
            XCTAssertFalse(r.allergens.contains(.nuts), r.name)
            XCTAssertTrue(r.vegetarian || r.vegetarianSwap != nil, r.name)
            XCTAssertTrue(r.spice == 0 || r.mildNote != nil, r.name)
        }
        XCTAssertGreaterThan(m.cost(of: plan).lunches, 0)
        XCTAssertEqual(m.baby?.months(), 8)
        XCTAssertEqual(m.triedFoods.count, 9)
        XCTAssertFalse(m.plan?.bought.isEmpty ?? true)
    }
}
