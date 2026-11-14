import Foundation

/// The bundled recipes and ingredient reference prices.
struct Catalog {
    let ingredients: [String: Ingredient]
    let recipes: [Recipe]

    func recipe(_ id: String) -> Recipe? { recipes.first { $0.id == id } }

    static func load(bundle: Bundle = .main) -> Catalog {
        func decode<T: Decodable>(_ name: String) -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                fatalError("Missing bundled \(name).json")
            }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { fatalError("Bad \(name).json: \(error)") }
        }
        let list: [Ingredient] = decode("ingredients")
        let recipes: [Recipe] = decode("recipes")
        return Catalog(ingredients: Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) }), recipes: recipes)
    }

    /// Mirrors the engine's rules: which recipes work for everyone in this household, with this kitchen.
    func eligibleRecipes(for settings: Settings, taste: Taste = Taste()) -> [Recipe] {
        let avoided = settings.avoided
        return recipes.filter { r in
            // Hidden dishes, dishes over the time limit, and dishes with an ingredient nobody wants.
            guard taste.allows(r) else { return false }
            // Saved recipes have no checked allergen or equipment data, so they're never planned automatically.
            guard r.source == nil else { return false }
            // Every piece of equipment the recipe needs must be in the kitchen.
            guard Set(r.equipment).isSubset(of: settings.equipment) else { return false }
            // Allergies are hard rules: never served, never swapped around.
            guard avoided.isDisjoint(with: r.allergens) else { return false }
            // Vegetarians need the dish to be vegetarian, or to have a written vegetarian plate.
            if settings.vegetarianCount > 0 && !r.vegetarian && r.vegetarianSwap == nil { return false }
            // Pescatarians: vegetarian dishes, fish dishes, or a written vegetarian plate.
            if settings.pescatarianCount > 0 && !r.pescatarian && r.vegetarianSwap == nil { return false }
            // Not spicy: mild dishes, or hot ones with a written mild version.
            if settings.anyoneNotSpicy && r.spice > 0 && r.mildNote == nil { return false }
            return true
        }
    }
}
