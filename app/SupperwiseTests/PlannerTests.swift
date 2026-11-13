import XCTest
@testable import Supperwise

/// The rules the reviews said competitors get wrong: diets and allergies respected, prices by
/// the whole pack, budgets kept. Run with ⌘U.
final class PlannerTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)
    let monday = Date(timeIntervalSince1970: 1_762_732_800) // Mon 10 Nov 2025, any Monday works

    /// The household from the design: Dana vegetarian, Marcus no shellfish, Ari not spicy, June.
    func household() -> Settings {
        var s = Settings()
        s.people = [
            Person(name: "Dana", diet: .vegetarian),
            Person(name: "Marcus", avoids: [.shellfish]),
            Person(name: "Ari", age: 7, notSpicy: true),
            Person(name: "June", age: 4),
        ]
        s.budget = 95
        s.price.postalCode = "45206"
        return s
    }

    func staples() -> Set<String> { Set(catalog.ingredients.values.filter(\.staple).map(\.id)) }

    func testCatalogIsConsistent() {
        XCTAssertGreaterThanOrEqual(catalog.recipes.count, 15)
        for r in catalog.recipes {
            XCTAssertGreaterThanOrEqual(r.steps.count, 4, r.id)
            for ri in r.ingredients + (r.vegetarianSwap?.ingredients ?? []) {
                XCTAssertNotNil(catalog.ingredients[ri.ingredient], "\(r.id) uses unknown \(ri.ingredient)")
            }
        }
        // A dish with meat or fish and no written vegetarian plate is never planned for a household with a vegetarian.
        var veg = Settings()
        veg.people = [Person(name: "A"), Person(name: "B", diet: .vegetarian)]
        for r in catalog.eligibleRecipes(for: veg) {
            XCTAssertTrue(r.vegetarian || r.vegetarianSwap != nil, "\(r.id) would leave the vegetarian without a plate")
        }
    }

    func testAllergiesAreNeverServed() throws {
        let s = household()
        for seed in UInt64(1)...50 {
            let plan = try Planner(catalog: catalog, settings: s, inKitchen: staples()).plan(weekStart: monday, seed: seed)
            for d in plan.dinners {
                let r = try XCTUnwrap(catalog.recipe(d.recipeID))
                XCTAssertFalse(r.allergens.contains(.shellfish), "\(r.id) served to Marcus")
                XCTAssertTrue(r.vegetarian || r.vegetarianSwap != nil, "\(r.id) has nothing for Dana")
                XCTAssertTrue(r.spice == 0 || r.mildNote != nil, "\(r.id) too hot for Ari")
            }
        }
    }

    func testEquipmentIsRespected() throws {
        var s = household()
        s.equipment = [.stovetop]
        let plan = try Planner(catalog: catalog, settings: s, inKitchen: staples()).plan(weekStart: monday, seed: 7)
        for d in plan.dinners {
            XCTAssertEqual(catalog.recipe(d.recipeID)?.equipment, [.stovetop])
        }
    }

    func testWeekIsUnderBudgetAndVaried() throws {
        let s = household()
        for seed in UInt64(1)...30 {
            let planner = Planner(catalog: catalog, settings: s, inKitchen: staples())
            let plan = try planner.plan(weekStart: monday, seed: seed)
            XCTAssertEqual(plan.dinners.count, 5)
            XCTAssertEqual(Set(plan.dinners.map(\.recipeID)).count, 5, "a dish repeats")
            let total = planner.pricer.price(planner.recipes(of: plan)).total
            XCTAssertLessThanOrEqual(total, s.budget, "seed \(seed): \(total)")
        }
    }

    func testPricesWholePacksNotSpoonfuls() throws {
        let s = household()
        let pricer = Pricer(catalog: catalog, settings: s, inKitchen: staples())
        let tikka = try XCTUnwrap(catalog.recipe("chickpea_tikka"))
        let cost = pricer.price([(.wed, tikka)])
        // 1 tbsp of garam masala still means buying the whole jar.
        let jar = try XCTUnwrap(cost.lines.first { $0.id == "garam_masala" })
        XCTAssertEqual(jar.packs, 1)
        XCTAssertEqual(jar.cost, 3.49 * s.price.multiplier, accuracy: 0.001)
        XCTAssertNotNil(jar.leftoverNote)
        // Staples in the kitchen cost nothing.
        XCTAssertEqual(cost.lines.first { $0.id == "salt" }?.cost, 0)
        // Dinner shares add up to the total.
        XCTAssertEqual(cost.perDinner.values.reduce(0, +), cost.total, accuracy: 0.01)
    }

    func testSharedIngredientsAreBoughtOnce() throws {
        let s = household()
        let pricer = Pricer(catalog: catalog, settings: s, inKitchen: staples())
        let a = try XCTUnwrap(catalog.recipe("chickpea_tikka"))
        let b = try XCTUnwrap(catalog.recipe("coconut_dal"))
        let both = pricer.price([(.mon, a), (.tue, b)])
        // Both use cumin or garam masala jars, garlic, ginger and basmati; one bag of basmati covers both.
        XCTAssertEqual(both.lines.first { $0.id == "basmati" }?.packs, 1)
        XCTAssertEqual(both.lines.first { $0.id == "garlic" }?.packs, 1)
    }

    func testSwapKeepsRulesAndChangesTheDish() throws {
        let s = household()
        let planner = Planner(catalog: catalog, settings: s, inKitchen: staples())
        let plan = try planner.plan(weekStart: monday, seed: 3)
        let swapped = planner.swap(.wed, in: plan, seed: 9)
        let before = plan.dinners.first { $0.day == .wed }?.recipeID
        let after = swapped.dinners.first { $0.day == .wed }?.recipeID
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(Set(swapped.dinners.map(\.recipeID)).count, swapped.dinners.count)
        let r = try XCTUnwrap(catalog.recipe(after ?? ""))
        XCTAssertFalse(r.allergens.contains(.shellfish))
    }

    func testTooFewRecipesSaysSo() {
        var s = household()
        s.equipment = [.grill]
        XCTAssertThrowsError(try Planner(catalog: catalog, settings: s, inKitchen: []).plan(weekStart: monday, seed: 1))
    }

    func testQuantityScaling() {
        XCTAssertEqual(RecipeView.parseQuantity("1½"), 1.5)
        XCTAssertEqual(RecipeView.parseQuantity("¾"), 0.75)
        XCTAssertNil(RecipeView.parseQuantity("a"))
        XCTAssertEqual(RecipeView.format(1.5), "1½")
        XCTAssertEqual(RecipeView.format(0.75 * 2), "1½")
        XCTAssertEqual(RecipeView.format(2.0), "2")
    }
}
