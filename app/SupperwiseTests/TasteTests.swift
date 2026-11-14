import XCTest
@testable import Supperwise

final class TasteTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)

    func testHardRulesNeverPlanned() throws {
        var s = Settings()
        s.people = [Person(name: "A"), Person(name: "B")]
        var taste = Taste()
        taste.prefs.maxMinutes = 30
        taste.prefs.dislikedIngredients = ["mushrooms"]
        let some = try XCTUnwrap(catalog.eligibleRecipes(for: s).first { $0.minutes <= 30 && !$0.ingredients.contains { $0.ingredient == "mushrooms" } })
        taste.hidden = [some.id]
        let eligible = catalog.eligibleRecipes(for: s, taste: taste)
        XCTAssertFalse(eligible.isEmpty)
        for r in eligible {
            XCTAssertLessThanOrEqual(r.minutes, 30, r.name)
            XCTAssertFalse(r.ingredients.contains { $0.ingredient == "mushrooms" }, r.name)
            XCTAssertNotEqual(r.id, some.id)
        }
        let plan = try Planner(catalog: catalog, settings: s, inKitchen: [], taste: taste).plan(weekStart: .now, seed: 3)
        for d in plan.dinners { XCTAssertTrue(taste.allows(try XCTUnwrap(catalog.recipe(d.recipeID)))) }
    }

    func testFavoritesComeUpMoreOften() throws {
        var s = Settings()
        s.people = [Person(name: "A"), Person(name: "B")]
        s.budget = 400
        let favs = Set(catalog.eligibleRecipes(for: s).filter { $0.cuisine == "Mexican" }.prefix(5).map(\.id))
        XCTAssertGreaterThanOrEqual(favs.count, 3)
        func picks(_ taste: Taste) throws -> Int {
            var n = 0
            for seed in UInt64(1)...8 {
                let p = try Planner(catalog: catalog, settings: s, inKitchen: [], taste: taste).plan(weekStart: .now, seed: seed)
                n += p.dinners.filter { favs.contains($0.recipeID) }.count
            }
            return n
        }
        XCTAssertGreaterThan(try picks(Taste(favorites: favs)), try picks(Taste()))
    }

    func testEveryCuisineHasAGroup() {
        for r in catalog.recipes { XCTAssertTrue(CuisineGroup.order.contains(CuisineGroup.of(r.cuisine)), r.cuisine) }
        XCTAssertEqual(CuisineGroup.of("Chinese-American"), "Chinese")
        XCTAssertEqual(CuisineGroup.of("Tex-Mex"), "Mexican & Tex-Mex")
        XCTAssertEqual(CuisineGroup.of("Indo-Chinese"), "Indian & Pakistani")
        XCTAssertEqual(CuisineGroup.of("German-American"), "European")
        let groups = Set(catalog.recipes.map { CuisineGroup.of($0.cuisine) })
        XCTAssertGreaterThanOrEqual(groups.count, 12)
    }

    func testSavingsAndStreak() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 19))!   // a Thursday
        func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 19))! }
        // Two full weeks of 3+ dinners (Nov 2–8 and 9–15), and 2 so far this week.
        let days = [2, 3, 5, 9, 10, 12, 13, 17, 18]
        let log = days.map { CookedEntry(date: day($0), recipeID: "r", cost: 16, servings: 4) }
        let s = HomeCookingStats.compute(log, takeoutPerPerson: 15, now: now, calendar: cal)
        XCTAssertEqual(s.dinners, 9)
        XCTAssertEqual(s.thisMonth, 9)
        XCTAssertEqual(s.saved, 9 * (60 - 16), accuracy: 0.01)          // takeout for 4 is $60; home cost $16
        XCTAssertEqual(s.weekStreak, 2)
    }
}
