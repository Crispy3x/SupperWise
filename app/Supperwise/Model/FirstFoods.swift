import Foundation

/// The bundled first-foods guide (first-foods.json): general information following widely published US advice.
struct FirstFoodsGuide: Codable {
    struct Food: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let category: String
        let allergen: String?
        let fromMonths: Int
        let serve6: String
        let serve9: String
    }
    let foods: [Food]
    let allergens: [String]
    let notes: [String]

    /// Loaded once from the bundle.
    static let bundled: FirstFoodsGuide? = load()

    static func load(bundle: Bundle = .main) -> FirstFoodsGuide? {
        guard let url = bundle.url(forResource: "first-foods", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FirstFoodsGuide.self, from: data)
    }

    static let categoryTitles: [String: String] = ["veg": "Vegetables and flavours", "fruit": "Fruit", "protein": "Protein", "grain": "Grains", "dairy": "Dairy"]
}

struct BabyProfile: Codable, Hashable {
    var name: String
    var birthDate: Date

    func months(at now: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.month], from: birthDate, to: now).month ?? 0)
    }
}

enum Reaction: String, Codable, CaseIterable, Identifiable {
    case liked, unsure, disliked, reaction
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liked: "Liked it"
        case .unsure: "Not sure yet"
        case .disliked: "Didn't like it"
        case .reaction: "Possible reaction"
        }
    }
}

struct FoodLogEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var foodID: String
    var date: Date
    var reaction: Reaction
    var note: String = ""
}

enum BabyAdvice {
    /// Maps the planner's allergens to the guide's allergen names.
    static func guideAllergens(_ a: Allergen) -> [String] {
        switch a {
        case .dairy: ["dairy"]
        case .egg: ["egg"]
        case .gluten: ["wheat"]
        case .soy: ["soy"]
        case .fish: ["fish"]
        case .shellfish: ["shellfish"]
        case .nuts: ["peanut", "tree nut"]
        case .sesame: ["sesame"]
        }
    }

    /// How to serve tonight's dinner to the baby, in plain steps. General guidance, not medical advice.
    static func tonight(recipe: Recipe, baby: BabyProfile, triedAllergens: Set<String>, catalog: Catalog, now: Date = .now) -> [String] {
        let m = baby.months(at: now)
        guard m >= 6 else { return ["Solids usually start at about 6 months, when \(baby.name) sits with support and shows interest. Ask your pediatrician."] }
        var out: [String] = ["Set \(baby.name)'s portion aside before adding salt."]
        if recipe.spice > 0 { out.append("Take it out before the chili or hot spices go in.") }
        let names = Set(recipe.ingredients.map(\.ingredient))
        if m < 12 && names.contains("honey") { out.append("This has honey: leave it out of \(baby.name)'s portion. No honey before 12 months, even cooked.") }
        if m < 12 && names.contains("milk") { out.append("Milk cooked into food is fine; cow's milk as a drink waits until 12 months.") }
        let untried = Set(recipe.allergens.flatMap(guideAllergens)).subtracting(triedAllergens).sorted()
        if !untried.isEmpty {
            out.append("Contains \(untried.joined(separator: ", ")), which \(baby.name) hasn't had yet. Introduce one new allergen at a time, at home, earlier in the day, and check with your pediatrician if \(baby.name) is at high risk.")
        }
        switch m {
        case ..<9: out.append("Texture: mash it, or offer soft pieces about the length of a finger to hold.")
        case ..<12: out.append("Texture: soft, bite-size pieces \(baby.name) can pick up.")
        default: out.append("Texture: small pieces of the family meal. Cut round foods like grapes and cherry tomatoes into quarters.")
        }
        return out
    }
}
