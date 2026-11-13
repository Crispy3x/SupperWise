import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession on Linux (used by the logic tests)
#endif

/// A packaged product read from Open Food Facts (openfoodfacts.org, Open Database License: credit it in the app).
struct FoodProduct: Hashable, Identifiable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let servingLabel: String
    let nutrition: Nutrition
    let allergens: Set<Allergen>
    let ingredientsText: String?
    let notVegetarian: [String]
    let novaGroup: Int?

    var score: Int { HealthScore.score(nutrition) }
}

enum ProductLookupError: LocalizedError {
    case notFound, network, noNutrition
    var errorDescription: String? {
        switch self {
        case .notFound: "That barcode isn't in the product database yet."
        case .network: "Couldn't reach the product database. Check your connection and try again."
        case .noNutrition: "This product has no nutrition facts in the database yet."
        }
    }
}

/// Reads products from the Open Food Facts API. Free; no key. A descriptive User-Agent is requested by the project.
struct OpenFoodFacts {
    var session: URLSession = .shared

    func product(barcode: String) async throws -> FoodProduct {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty, let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,serving_size,serving_quantity,nutriments,allergens_tags,ingredients_text_en,ingredients_text,ingredients_analysis_tags,nova_group,additives_tags") else {
            throw ProductLookupError.notFound
        }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Supperwise iOS - meal planner", forHTTPHeaderField: "User-Agent")
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw ProductLookupError.network }
        return try Self.parse(data, barcode: code)
    }

    /// Parsing is separate so it can be tested with a saved response.
    static func parse(_ data: Data, barcode: String) throws -> FoodProduct {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int) == 1, let p = root["product"] as? [String: Any] else { throw ProductLookupError.notFound }
        let nm = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double? {
            if let d = nm[k] as? Double { return d }
            if let i = nm[k] as? Int { return Double(i) }
            if let s = nm[k] as? String { return Double(s) }
            return nil
        }
        // Prefer per-serving values; fall back to per 100 g scaled to the serving quantity (or 100 g).
        let qty: Double = (p["serving_quantity"] as? Double) ?? Double(p["serving_quantity"] as? String ?? "") ?? 100
        func per(_ base: String) -> Double? { num("\(base)_serving") ?? num("\(base)_100g").map { $0 * qty / 100 } }
        guard let kcal = per("energy-kcal") else { throw ProductLookupError.noNutrition }
        let sugars = per("added-sugars") ?? per("sugars") ?? 0          // added sugar when listed; total sugar otherwise
        let sodiumMg = (per("sodium") ?? (per("salt").map { $0 / 2.5 }) ?? 0) * 1000
        let tags = (p["allergens_tags"] as? [String] ?? []).joined(separator: " ")
        var allergens: Set<Allergen> = []
        let map: [(String, Allergen)] = [("milk", .dairy), ("eggs", .egg), ("gluten", .gluten), ("soybeans", .soy), ("fish", .fish),
                                         ("crustaceans", .shellfish), ("molluscs", .shellfish), ("nuts", .nuts), ("peanuts", .nuts), ("sesame", .sesame)]
        for (k, a) in map where tags.contains(k) { allergens.insert(a) }
        let ingredients = (p["ingredients_text_en"] as? String) ?? (p["ingredients_text"] as? String)
        let lower = (ingredients ?? "").lowercased()
        let analysis = (p["ingredients_analysis_tags"] as? [String] ?? [])
        var notVeg = ["gelatin", "carmine", "anchovy", "lard", "chicken", "beef", "pork"].filter { lower.contains($0) }
        if notVeg.isEmpty, analysis.contains("en:non-vegetarian") { notVeg = ["animal ingredients"] }
        let additives = (p["additives_tags"] as? [String] ?? []).joined(separator: " ")
        let artificialColor = ["e129", "e102", "e133", "e110", "e132", "e127"].contains { additives.contains($0) }
        let nova = (p["nova_group"] as? Int) ?? Int(p["nova_group"] as? String ?? "")
        let n = Nutrition(kcal: kcal, addedSugar: sugars, sodium: sodiumMg, satFat: per("saturated-fat") ?? 0,
                          protein: per("proteins") ?? 0, fiber: per("fiber") ?? 0,
                          ultraProcessed: nova == 4, artificialColor: artificialColor)
        let name = (p["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Product \(barcode)"
        let serving = (p["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(Int(qty)) g"
        return FoodProduct(barcode: barcode, name: name, brand: p["brands"] as? String, servingLabel: serving, nutrition: n,
                           allergens: allergens, ingredientsText: ingredients, notVegetarian: notVeg, novaGroup: nova)
    }
}
