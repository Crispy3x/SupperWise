import Foundation

// MARK: - Catalog (bundled, read-only)

enum Aisle: String, Codable, CaseIterable {
    case produce, meat, seafood, dairy, cans, dry, bakery, frozen, spices, staples

    var title: String {
        switch self {
        case .produce: "Produce"
        case .meat: "Meat"
        case .seafood: "Fish and seafood"
        case .dairy: "Dairy and eggs"
        case .cans: "Cans and jars"
        case .dry: "Pasta, rice and dry goods"
        case .bakery: "Bakery"
        case .frozen: "Frozen"
        case .spices: "Spices"
        case .staples: "Oils and staples"
        }
    }
}

enum Unit: String, Codable { case g, ml, count }

struct Ingredient: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let aisle: Aisle
    /// Size of one pack in `unit`.
    let packSize: Double
    let unit: Unit
    /// What the shopper sees on the shelf, e.g. "15 oz can".
    let packLabel: String
    /// National reference price for one pack, USD. Adjusted by `PriceProfile`.
    let refPrice: Double
    /// Roughly how long the rest of an opened pack keeps.
    let keepsDays: Int
    /// Oils, salt, pepper, sugar: assumed in the kitchen unless the person unticks them.
    let staple: Bool
}

struct RecipeIngredient: Codable, Hashable {
    let ingredient: String
    /// Amount for the recipe's base servings, in the ingredient's unit.
    let amount: Double
    /// Human amount, e.g. "2 cans", "1 tbsp".
    let text: String
    /// Prep note, e.g. "drained and rinsed".
    let note: String
}

enum Allergen: String, Codable, CaseIterable, Identifiable {
    case dairy, egg, gluten, soy, fish, shellfish, nuts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dairy: "No dairy"
        case .egg: "No eggs"
        case .gluten: "No gluten"
        case .soy: "No soy"
        case .fish: "No fish"
        case .shellfish: "No shellfish"
        case .nuts: "No nuts"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case oven, stovetop, sheet_pan, air_fryer, grill, slow_cooker
    var id: String { rawValue }
    var label: String {
        switch self {
        case .oven: "Oven"
        case .stovetop: "Stovetop"
        case .sheet_pan: "Sheet pan"
        case .air_fryer: "Air fryer"
        case .grill: "Grill"
        case .slow_cooker: "Slow cooker"
        }
    }
}

struct VegetarianSwap: Codable, Hashable {
    let note: String
    /// Extra ingredients for one vegetarian portion set (bought once per week the dish appears).
    let ingredients: [RecipeIngredient]
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let side: String
    let cuisine: String
    let minutes: Int
    let difficulty: String
    let protein: String
    let allergens: [Allergen]
    let equipment: [Equipment]
    /// 0 none, 1 warm, 2 hot.
    let spice: Int
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let photo: String?
    let vegetarian: Bool
    let pescatarian: Bool
    let mildNote: String?
    let vegetarianSwap: VegetarianSwap?
    let servings: Int
    /// Set for recipes the person saved from a link (the website's host). Bundled recipes have none.
    var source: String? = nil
}

// MARK: - The household (the person's own data)

enum Diet: String, Codable, CaseIterable, Identifiable {
    case everything, vegetarian, pescatarian
    var id: String { rawValue }
    var label: String {
        switch self {
        case .everything: "Eats everything"
        case .vegetarian: "Vegetarian"
        case .pescatarian: "Pescatarian"
        }
    }
}

struct Person: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var age: Int? = nil
    var diet: Diet = .everything
    var avoids: Set<Allergen> = []
    var notSpicy: Bool = false
}

enum StoreKind: String, Codable, CaseIterable, Identifiable {
    case discount, supermarket, premium
    var id: String { rawValue }
    var label: String {
        switch self {
        case .discount: "Discount grocer"
        case .supermarket: "Supermarket"
        case .premium: "Premium or organic"
        }
    }
    var multiplier: Double {
        switch self {
        case .discount: 0.86
        case .supermarket: 1.0
        case .premium: 1.24
        }
    }
}

/// How estimates are adjusted for where the person shops. These are estimates, not live prices.
struct PriceProfile: Codable, Hashable {
    var storeName: String = ""
    var storeKind: StoreKind = .supermarket
    var postalCode: String = ""

    /// A coarse regional factor from the first digit of a US ZIP code (Canada: first letter).
    var regionMultiplier: Double {
        guard let first = postalCode.trimmingCharacters(in: .whitespaces).uppercased().first else { return 1.0 }
        switch first {
        case "0", "1": return 1.10   // Northeast
        case "2": return 1.03
        case "3": return 0.97
        case "4", "5": return 0.96   // Midwest
        case "6", "7": return 0.97
        case "8": return 1.02
        case "9": return 1.14        // West coast, Alaska, Hawaii
        case "A"..."Z": return 1.12  // Canada, before conversion to CAD at the store
        default: return 1.0
        }
    }

    var multiplier: Double { storeKind.multiplier * regionMultiplier }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case mon = 1, tue, wed, thu, fri, sat, sun
    var id: Int { rawValue }
    static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }

    var short: String { ["M", "T", "W", "T", "F", "S", "S"][rawValue - 1] }
    var abbreviation: String { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][rawValue - 1] }
    var name: String { ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue - 1] }

    /// Calendar weekday (1 = Sunday) to ours (1 = Monday).
    init(calendarWeekday: Int) {
        self = Weekday(rawValue: calendarWeekday == 1 ? 7 : calendarWeekday - 1) ?? .mon
    }
}

struct Settings: Codable, Hashable {
    var budget: Double = 95
    var cheapestWeek: Bool = false
    var cookNights: Set<Weekday> = [.mon, .tue, .wed, .thu, .fri]
    var people: [Person] = []
    var equipment: Set<Equipment> = [.oven, .stovetop, .sheet_pan]
    var price = PriceProfile()
    var dinnerReminder: Bool = false
    /// Lunchbox planning (Family); nil until it's set up.
    var lunch: LunchSettings? = nil

    var householdSize: Int { max(people.count, 1) }
    var vegetarianCount: Int { people.filter { $0.diet == .vegetarian }.count }
    var pescatarianCount: Int { people.filter { $0.diet == .pescatarian }.count }
    var avoided: Set<Allergen> { people.reduce(into: Set<Allergen>()) { $0.formUnion($1.avoids) } }
    var anyoneNotSpicy: Bool { people.contains { $0.notSpicy } }
}

// MARK: - A planned week

struct PlannedDinner: Codable, Hashable, Identifiable {
    var id: Weekday { day }
    var day: Weekday
    var recipeID: String
    var cooked: Bool = false
}

struct WeekPlan: Codable, Hashable {
    /// The Monday the week starts on.
    var weekStart: Date
    var dinners: [PlannedDinner]
    /// Ingredient ids the person ticked as bought in the grocery list.
    var bought: Set<String> = []
    /// Was this the free first week (kept whether or not they subscribe)?
    var isFreeWeek: Bool = false
    /// Nights cooked with 2 extra portions for the next day's lunch (Family). Optional so older saves still load.
    var leftovers: Set<Weekday>? = nil
    /// Packed lunches this week (Family). Optional so older saves still load.
    var lunches: [PlannedLunch]? = nil
}
