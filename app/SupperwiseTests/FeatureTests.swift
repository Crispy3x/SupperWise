import XCTest
@testable import Supperwise

final class FeatureTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)

    // The same sample items as the prototype; the bands must match common sense.
    func testHealthScoreBands() {
        let plainYogurt = Nutrition(kcal: 90, addedSugar: 0, sodium: 55, satFat: 0, protein: 16, fiber: 0)
        let fruitSnacks = Nutrition(kcal: 80, addedSugar: 11, sodium: 20, satFat: 0, protein: 0, fiber: 0, ultraProcessed: true, artificialColor: true)
        let tofuVeg = Nutrition(kcal: 320, addedSugar: 6, sodium: 690, satFat: 2, protein: 20, fiber: 7)
        let orangeChicken = Nutrition(kcal: 890, addedSugar: 42, sodium: 1240, satFat: 7, protein: 33, fiber: 1, fried: true)
        XCTAssertEqual(HealthScore.band(HealthScore.score(plainYogurt)), .good)
        XCTAssertEqual(HealthScore.band(HealthScore.score(tofuVeg)), .good)
        XCTAssertEqual(HealthScore.band(HealthScore.score(fruitSnacks)), .poor)
        XCTAssertEqual(HealthScore.band(HealthScore.score(orangeChicken)), .poor)
        XCTAssertEqual(HealthScore.score(plainYogurt), 87)   // matches preview/template.html
        XCTAssertEqual(HealthScore.score(orangeChicken), 27)
    }

    func testHouseholdConflictsComeFirst() {
        let people = [Person(name: "Dana", diet: .vegetarian), Person(name: "Marcus", avoids: [.shellfish])]
        let f = FoodCheck.findings(nutrition: Nutrition(kcal: 720, addedSugar: 6, sodium: 1520, satFat: 4, protein: 26, fiber: 3),
                                   allergens: [.shellfish, .egg], hasMeat: true, notVegetarianIngredients: [], people: people)
        XCTAssertEqual(f.first?.severity, .conflict)
        XCTAssertTrue(f.contains { $0.text.contains("Marcus") })
        XCTAssertTrue(f.contains { $0.text.contains("Dana") })
        XCTAssertTrue(f.contains { $0.text.contains("sodium") })
    }

    func testLeftoversAddTwoPortions() throws {
        var s = Settings(); s.people = [Person(name: "A"), Person(name: "B")]
        let r = try XCTUnwrap(catalog.recipe("chickpea_tikka"))
        let plain = Pricer(catalog: catalog, settings: s, inKitchen: [])
        let lunch = Pricer(catalog: catalog, settings: s, inKitchen: [], leftovers: [.wed])
        XCTAssertEqual(plain.usage(r, day: .wed)["basmati"]! * 2, lunch.usage(r, day: .wed)["basmati"]!, accuracy: 0.01)
    }

    func testStoreAdjustScalesPrices() throws {
        let s = Settings()
        let r = try XCTUnwrap(catalog.recipe("penne_arrabbiata"))
        let a = Pricer(catalog: catalog, settings: s, inKitchen: []).price([(.mon, r)]).total
        let b = Pricer(catalog: catalog, settings: s, inKitchen: [], adjust: 1.1).price([(.mon, r)]).total
        XCTAssertEqual(b, a * 1.1, accuracy: 0.01)
    }

    func testReceiptTotal() {
        XCTAssertEqual(ReceiptView.parseTotal(["CRUSHED TOM 1.89", "SUBTOTAL 81.20", "TAX 2.10", "TOTAL 83.30", "VISA 83.30"]), 83.30)
        XCTAssertEqual(ReceiptView.parseTotal(["MILK 2.79", "EGGS 3.29"]), 3.29)
    }

    func testTimersInSteps() {
        XCTAssertEqual(CookModeView.minutes(in: "Simmer 18 to 20 minutes, stirring."), 20)
        XCTAssertEqual(CookModeView.minutes(in: "Stir for 1 minute."), 1)
        XCTAssertNil(CookModeView.minutes(in: "Serve with lime."))
    }

    func testOpenFoodFactsParsing() throws {
        let json = """
        {"status":1,"product":{"product_name":"Plain Greek yogurt","brands":"Example","serving_size":"150 g","serving_quantity":150,
         "nutriments":{"energy-kcal_100g":60,"sugars_100g":3.5,"salt_100g":0.1,"saturated-fat_100g":0,"proteins_100g":10.5,"fiber_100g":0},
         "allergens_tags":["en:milk"],"ingredients_text_en":"Cultured nonfat milk","nova_group":1}}
        """.data(using: .utf8)!
        let p = try OpenFoodFacts.parse(json, barcode: "0123456789012")
        XCTAssertEqual(p.nutrition.kcal, 90, accuracy: 0.5)
        XCTAssertEqual(p.nutrition.protein, 15.75, accuracy: 0.01)
        XCTAssertEqual(p.nutrition.sodium, 60, accuracy: 0.5)   // 0.1 g salt per 100 g → 0.04 g sodium → ×1.5 servings
        XCTAssertTrue(p.allergens.contains(.dairy))
        XCTAssertFalse(p.nutrition.ultraProcessed)
        XCTAssertThrowsError(try OpenFoodFacts.parse(#"{"status":0}"#.data(using: .utf8)!, barcode: "1"))
    }

    func testRecipeFromJSONLD() throws {
        let html = """
        <html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},
        {"@type":"Recipe","name":"Weeknight chickpea curry","recipeYield":"4 servings","totalTime":"PT35M",
         "recipeIngredient":["2 cans chickpeas, drained","1 red onion, diced","1 tbsp garam masala"],
         "recipeInstructions":[{"@type":"HowToStep","text":"Soften the onion."},{"@type":"HowToStep","text":"Add the chickpeas and simmer 15 minutes."}]}]}
        </script></head></html>
        """
        let r = try RecipeImporter(catalog: catalog).parse(html: html, source: "example.com")
        XCTAssertEqual(r.name, "Weeknight chickpea curry")
        XCTAssertEqual(r.minutes, 35)
        XCTAssertEqual(r.servings, 4)
        XCTAssertEqual(r.steps.count, 2)
        XCTAssertEqual(r.source, "example.com")
        XCTAssertTrue(r.ingredients.contains { $0.ingredient == "chickpeas" })
        XCTAssertTrue(r.ingredients.contains { $0.ingredient == "garam_masala" })
        // Saved recipes never enter automatic plans.
        let merged = Catalog(ingredients: catalog.ingredients, recipes: catalog.recipes + [r])
        XCTAssertFalse(merged.eligibleRecipes(for: Settings()).contains { $0.id == r.id })
    }

    func testTierMapping() {
        XCTAssertEqual(Subscriptions.tier(for: ["supper_wise_pro"]), .pro)    // the RevenueCat entitlement unlocks everything
        XCTAssertEqual(Subscriptions.tier(for: []), .free)
        XCTAssertEqual(Subscriptions.tier(for: ["family"]), .family)
        XCTAssertEqual(Subscriptions.tier(for: ["plus"]), .plus)
        XCTAssertEqual(Subscriptions.tier(for: ["plus", "family"]), .family)   // a Family product grants plus and family
        XCTAssertEqual(Feature.fridge.tier, .pro)
        XCTAssertEqual(Feature.scanner.tier, .family)
        XCTAssertEqual(Feature.nextWeek.tier, .plus)
    }
}

final class HolidayTests: XCTestCase {
    func testThanksgivingPlan() throws {
        let menu = try XCTUnwrap(HolidayMenu.load(bundle: .main))
        let dinner = Date(timeIntervalSince1970: 1_795_723_200) // any fixed time
        var p = HolidayPlan(menu: menu, guests: 10, vegetarians: 2, dinner: dinner)
        XCTAssertEqual(p.turkeyPounds, 10)                                 // 8 meat eaters × 1.25 lb
        XCTAssertEqual(HolidayPlan.roastMinutes(pounds: 10), 180)          // USDA 8–12 lb: up to 3 h
        XCTAssertEqual(HolidayPlan.thawDays(pounds: 10), 3)
        XCTAssertTrue(p.dishes.contains { $0.id == "tg_squash" })          // vegetarians get a main
        XCTAssertEqual(p.timeline.last?.text, "Dinner.")
        XCTAssertTrue(p.timeline.first!.text.contains("thaw"))             // thawing is the first task
        XCTAssertTrue(p.timeline.allSatisfy { $0.at <= dinner })
        let cat = Catalog.load(bundle: .main)
        let lines = p.groceries(catalog: cat, inKitchen: [], multiplier: 1)
        XCTAssertEqual(lines.first { $0.id == "turkey_whole" }?.packs, 10)  // priced per lb
        p.vegetarians = 0
        XCTAssertFalse(p.dishes.contains { $0.id == "tg_squash" })
        p.vegetarians = 10
        XCTAssertFalse(p.dishes.contains { $0.id == "tg_turkey" })         // all-vegetarian table: no turkey
        XCTAssertEqual(Feature.holidayMenus.tier, .plus)
    }

    func testAllHolidayIngredientsExist() throws {
        let menu = try XCTUnwrap(HolidayMenu.load(bundle: .main))
        let cat = Catalog.load(bundle: .main)
        for d in menu.dishes { for ri in d.ingredients { XCTAssertNotNil(cat.ingredients[ri.ingredient], "\(d.id): \(ri.ingredient)") } }
    }
}

final class FirstFoodsTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)

    func testGuideLoadsAndSafetyRules() throws {
        let g = try XCTUnwrap(FirstFoodsGuide.load(bundle: .main))
        XCTAssertGreaterThanOrEqual(g.foods.count, 100)
        XCTAssertEqual(g.foods.first { $0.id == "honey" }?.fromMonths, 12)
        XCTAssertEqual(g.foods.first { $0.id == "cows_milk_as_a_drink" }?.fromMonths, 12)
        XCTAssertTrue(g.foods.first { $0.id == "grapes" }!.serve6.lowercased().contains("quarter"))
        XCTAssertEqual(Set(g.allergens), ["peanut", "egg", "dairy", "wheat", "soy", "fish", "shellfish", "tree nut", "sesame"])
    }

    func testTonightAdvice() throws {
        let eightMonths = Calendar.current.date(byAdding: .month, value: -8, to: .now)!
        let baby = BabyProfile(name: "June", birthDate: eightMonths)
        XCTAssertEqual(baby.months(), 8)
        let drumsticks = try XCTUnwrap(catalog.recipe("crispy_drumsticks"))   // honey in the slaw, egg and gluten
        let advice = BabyAdvice.tonight(recipe: drumsticks, baby: baby, triedAllergens: ["dairy"], catalog: catalog)
        XCTAssertTrue(advice.contains { $0.contains("honey") })
        XCTAssertTrue(advice.contains { $0.contains("egg") && $0.contains("wheat") })
        XCTAssertTrue(advice.contains { $0.contains("mash") })
        let newborn = BabyProfile(name: "Kai", birthDate: Calendar.current.date(byAdding: .month, value: -3, to: .now)!)
        XCTAssertEqual(BabyAdvice.tonight(recipe: drumsticks, baby: newborn, triedAllergens: [], catalog: catalog).count, 1)
    }
}

final class ChristmasTests: XCTestCase {
    func testChristmasHamPlan() throws {
        let menu = try XCTUnwrap(HolidayMenu.load("holiday-christmas", bundle: .main))
        let dinner = Date(timeIntervalSince1970: 1_798_210_800)
        let p = HolidayPlan(menu: menu, guests: 12, vegetarians: 1, dinner: dinner)
        XCTAssertEqual(p.mainPounds, 8)                                     // 11 × 0.75 = 8.25 → 8
        XCTAssertEqual(HolidayPlan.hamMinutes(pounds: 8), 112)              // 14 min/lb, USDA upper end
        XCTAssertFalse(p.timeline.contains { $0.text.contains("thaw") })   // chilled ham: no thawing
        XCTAssertTrue(p.timeline.contains { $0.text.contains("140°F") })
        XCTAssertTrue(p.dishes.contains { $0.id == "xm_pie" })
        XCTAssertEqual(p.groceries(catalog: Catalog.load(bundle: .main), inKitchen: [], multiplier: 1).first { $0.id == "ham_spiral" }?.packs, 8)
        XCTAssertEqual(HolidayMenu.all(bundle: .main).count, 2)
    }
}

final class LunchboxTests: XCTestCase {
    let catalog = Catalog.load(bundle: .main)

    func testLunchIdeasUseCatalogIngredients() throws {
        let guide = try XCTUnwrap(LunchGuide.load(bundle: .main))
        XCTAssertGreaterThanOrEqual(guide.lunches.count, 15)
        for l in guide.lunches {
            XCTAssertFalse(l.allergens.contains(.nuts), l.name)            // nut-free for school
            for i in l.ingredients { XCTAssertNotNil(catalog.ingredients[i.ingredient], "\(l.name): \(i.ingredient)") }
        }
    }

    func testPlanFollowsHouseholdAndThermos() throws {
        let guide = try XCTUnwrap(LunchGuide.load(bundle: .main))
        var s = Settings()
        s.people = [Person(name: "A", avoids: [.dairy]), Person(name: "B", diet: .vegetarian)]
        let lp = LunchPlanner(guide: guide, settings: s, lunch: LunchSettings(perDay: 2, days: [.mon, .tue, .wed, .thu, .fri], thermos: false))
        let plan = lp.plan(seed: 7)
        XCTAssertEqual(plan.map(\.day), [.mon, .tue, .wed, .thu, .fri])
        for p in plan {
            let l = try XCTUnwrap(guide.lunch(p.lunchID))
            XCTAssertFalse(l.allergens.contains(.dairy))
            XCTAssertTrue(l.vegetarian)
            XCTAssertFalse(l.thermos)
        }
        for (a, b) in zip(plan, plan.dropFirst()) { XCTAssertNotEqual(a.lunchID, b.lunchID) }
        XCTAssertEqual(lp.plan(seed: 7), plan)                           // reproducible
        let swapped = lp.swap(.wed, in: plan, seed: 3)
        XCTAssertNotEqual(swapped.first { $0.day == .wed }?.lunchID, plan.first { $0.day == .wed }?.lunchID)
    }

    func testLeftoversAndPricing() throws {
        let guide = try XCTUnwrap(LunchGuide.load(bundle: .main))
        var s = Settings()
        s.people = [Person(name: "A"), Person(name: "B"), Person(name: "C")]
        let lp = LunchPlanner(guide: guide, settings: s, lunch: LunchSettings(perDay: 3, days: [.mon, .tue], thermos: true))
        let plan = [PlannedLunch(day: .mon, lunchID: "turkey_cheddar"), PlannedLunch(day: .tue, lunchID: "turkey_cheddar")]
        // Monday dinner cooked with leftovers covers 2 of Tuesday's 3 lunches.
        XCTAssertEqual(LunchPlanner.leftoverNight(for: .tue, [.mon]), .mon)
        XCTAssertNil(LunchPlanner.leftoverNight(for: .mon, [.sun]))       // Sunday's leftovers belong to last week
        XCTAssertEqual(lp.boxes(plan[1], leftovers: [.mon]), 1)
        let use = lp.usage(plan, leftovers: [.mon])
        XCTAssertEqual(use["sandwich_bread"], 8)                          // (3 + 1) lunches × 2 slices
        XCTAssertEqual(use["apples"], 4)

        let dinner = try XCTUnwrap(catalog.eligibleRecipes(for: s).first)
        var pricer = Pricer(catalog: catalog, settings: s, inKitchen: [])
        let dinnerOnly = pricer.price([(.mon, dinner)])
        pricer.lunchUsage = use
        let both = pricer.price([(.mon, dinner)])
        XCTAssertEqual(dinnerOnly.lunches, 0)
        XCTAssertGreaterThan(both.lunches, 0)
        XCTAssertEqual(both.total, (both.perDinner.values.reduce(0, +) + both.lunches), accuracy: 0.01)  // shares add up
        let bread = try XCTUnwrap(both.lines.first { $0.id == "sandwich_bread" })
        XCTAssertEqual(bread.packs, 1)
        XCTAssertTrue(bread.lunch)
        XCTAssertTrue(bread.days.isEmpty)
    }
}
