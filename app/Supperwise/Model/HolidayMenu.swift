import Foundation

/// A one-off menu (Thanksgiving first): dishes, a cooking timeline that works back from dinner time,
/// and one grocery list priced by the pack. Included in every paid plan (Plus and up); no one-time purchases.
struct HolidayMenu: Codable, Identifiable {
    struct Prep: Codable, Hashable { let minutesBefore: Int; let task: String }
    struct Dish: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let course: String
        let vegetarian: Bool
        let servings: Int
        let allergens: [Allergen]
        let ingredients: [RecipeIngredient]
        let steps: [String]
        let schedule: [Prep]
        let forVegetarians: Bool
    }
    /// The centrepiece and how it's sized: "turkey" (thawed and roasted) or "ham" (fully cooked, reheated).
    struct Main: Codable, Hashable { let kind: String; let ingredient: String; let lbPerPerson: Double; let minLb: Double }

    let id: String
    let name: String
    let defaultDate: String
    let main: Main
    let dishes: [Dish]

    static func load(_ name: String = "holiday-thanksgiving", bundle: Bundle = .main) -> HolidayMenu? {
        guard let url = bundle.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HolidayMenu.self, from: data)
    }

    /// Loaded once from the bundle.
    static let bundled: [HolidayMenu] = all()

    static func all(bundle: Bundle = .main) -> [HolidayMenu] {
        ["holiday-thanksgiving", "holiday-christmas"].compactMap { load($0, bundle: bundle) }
    }

    /// Shown on the Week screen from 30 days before until the day after.
    func inSeason(_ now: Date = .now) -> Bool {
        now >= defaultDinner.addingTimeInterval(-30 * 86_400) && now <= defaultDinner.addingTimeInterval(86_400)
    }

    var defaultDinner: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard var d = f.date(from: defaultDate) else { return .now }
        // Roll a past holiday forward to its next year, so the menu keeps working after this season.
        while d < Date.now.addingTimeInterval(-86_400), let next = Calendar.current.date(byAdding: .year, value: 1, to: d) { d = next }
        return d
    }
}

/// What the person chose: guests, vegetarians among them, dinner time.
struct HolidayPlan {
    let menu: HolidayMenu
    var guests: Int
    var vegetarians: Int
    var dinner: Date

    var meatEaters: Int { max(0, guests - vegetarians) }

    /// Turkey: about 1.25 lb per person who eats it, at least 8 lb. Bone-in ham: about 0.75 lb, at least 6 lb.
    var mainPounds: Double { meatEaters == 0 ? 0 : max(menu.main.minLb, (Double(meatEaters) * menu.main.lbPerPerson).rounded()) }
    var turkeyPounds: Double { mainPounds }
    var mainName: String { menu.main.kind == "ham" ? "ham" : "turkey" }

    /// USDA: reheat a fully cooked spiral ham at 325°F to 140°F, about 10–14 minutes per pound (upper end used).
    static func hamMinutes(pounds lb: Double) -> Int { Int((lb * 14).rounded()) }

    /// USDA roasting times at 325°F for an unstuffed whole turkey (upper end of each range), in minutes.
    static func roastMinutes(pounds lb: Double) -> Int {
        switch lb {
        case ..<12: 180
        case ..<14: 225
        case ..<18: 255
        case ..<20: 270
        default: 300
        }
    }

    /// USDA: thaw in the fridge about 24 hours per 4–5 lb. Uses 4 lb to be safe.
    static func thawDays(pounds lb: Double) -> Int { Int((lb / 4).rounded(.up)) }

    /// Which dishes are on the table: the turkey and gravy only if someone eats meat; the squash only if someone is vegetarian.
    var dishes: [HolidayMenu.Dish] {
        menu.dishes.filter { d in
            if d.forVegetarians { return vegetarians > 0 }
            if !d.vegetarian { return meatEaters > 0 }
            return true
        }
    }

    func eaters(_ d: HolidayMenu.Dish) -> Int { d.forVegetarians ? vegetarians : (d.vegetarian ? guests : meatEaters) }

    /// Ingredient amounts for this table.
    func usage(_ d: HolidayMenu.Dish) -> [String: Double] {
        var out: [String: Double] = [:]
        for ri in d.ingredients {
            let amount: Double
            if ri.ingredient == menu.main.ingredient { amount = mainPounds * 454 }
            else { amount = ri.amount * Double(eaters(d)) / Double(max(d.servings, 1)) }
            out[ri.ingredient, default: 0] += amount
        }
        return out
    }

    struct Step: Identifiable, Hashable {
        var id: String { "\(at.timeIntervalSince1970)-\(text)" }
        let at: Date
        let text: String
        let dish: String
    }

    /// Every task, earliest first, as clock times.
    var timeline: [Step] {
        var out: [Step] = []
        func at(_ minutesBefore: Int) -> Date { dinner.addingTimeInterval(-Double(minutesBefore) * 60) }
        if meatEaters > 0 && menu.main.kind == "ham" {
            let lb = mainPounds, heat = Self.hamMinutes(pounds: lb), rest = 45
            out.append(Step(at: at(heat + rest + 20), text: "Heat the oven to 325°F. Unwrap the \(Int(lb)) lb ham into a covered pan with a little water.", dish: "Glazed ham"))
            out.append(Step(at: at(heat + rest), text: "Ham in the oven, covered. About \(heat / 60) h \(heat % 60) min; it's ready at 140°F in the thickest part.", dish: "Glazed ham"))
            out.append(Step(at: at(rest + 20), text: "Uncover, brush on the glaze, oven up to 400°F.", dish: "Glazed ham"))
            out.append(Step(at: at(rest), text: "Ham out. Keep it covered with foil; it stays hot while the sides roast. Turn the oven to 425°F.", dish: "Glazed ham"))
            out.append(Step(at: at(5), text: "Slice the ham.", dish: "Glazed ham"))
        } else if meatEaters > 0 {
            let lb = mainPounds, roast = Self.roastMinutes(pounds: lb), rest = 30
            out.append(Step(at: at((Self.thawDays(pounds: lb) * 24 + 1) * 60 + roast + rest),
                            text: "Move the \(Int(lb)) lb turkey from the freezer to the fridge to thaw (\(Self.thawDays(pounds: lb)) days for this size).", dish: "Roast turkey"))
            out.append(Step(at: at(roast + rest + 60), text: "Take the turkey out of the fridge. Heat the oven to 325°F.", dish: "Roast turkey"))
            out.append(Step(at: at(roast + rest + 30), text: "Turkey in the oven. Plan on about \(roast / 60) h \(roast % 60) min; check with a thermometer from an hour before.", dish: "Roast turkey"))
            out.append(Step(at: at(rest), text: "Turkey out when it reads 165°F in the thigh, wing and breast. Rest 30 minutes, loosely covered.", dish: "Roast turkey"))
            out.append(Step(at: at(5), text: "Carve the turkey.", dish: "Roast turkey"))
        }
        for d in dishes { for t in d.schedule { out.append(Step(at: at(t.minutesBefore), text: t.task, dish: d.name)) } }
        out.append(Step(at: dinner, text: "Dinner.", dish: ""))
        return out.sorted { $0.at < $1.at }
    }

    /// One shopping list for the whole meal, by the pack, minus what's already in the kitchen.
    func groceries(catalog: Catalog, inKitchen: Set<String>, multiplier: Double) -> [GroceryLine] {
        var used: [String: Double] = [:]
        for d in dishes { for (k, v) in usage(d) { used[k, default: 0] += v } }
        return used.compactMap { id, amount in
            guard let ing = catalog.ingredients[id] else { return nil }
            let have = inKitchen.contains(id)
            let packs = have ? 0 : Int((amount / ing.packSize - 1e-9).rounded(.up))
            return GroceryLine(ingredient: ing, used: amount, packs: packs, cost: Double(packs) * ing.refPrice * multiplier, days: [], inKitchen: have)
        }
        .sorted { ($0.ingredient.aisle.sortIndex, $0.ingredient.name) < ($1.ingredient.aisle.sortIndex, $1.ingredient.name) }
    }
}
