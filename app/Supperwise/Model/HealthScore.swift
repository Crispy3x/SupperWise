import Foundation

/// Nutrition for one serving of a product or a restaurant dish.
struct Nutrition: Codable, Hashable {
    var kcal: Double
    var addedSugar: Double = 0   // g
    var sodium: Double = 0       // mg
    var satFat: Double = 0       // g
    var protein: Double = 0      // g
    var fiber: Double = 0        // g
    var fried = false
    var refined = false
    var ultraProcessed = false
    var artificialColor = false
}

/// The Supperwise health score, 1 to 100. The same formula as the prototype (preview/template.html, `healthScore`).
/// It judges food per calorie: each nutrient's share of its FDA daily value against the serving's share of a 2,000-calorie day.
enum HealthScore {
    static let dvSugar = 50.0, dvSodium = 2300.0, dvSatFat = 20.0, dvProtein = 50.0, dvFiber = 28.0

    static func score(_ n: Nutrition) -> Int {
        let cal = max(n.kcal, 40) / 2000
        func r(_ v: Double, _ dv: Double) -> Double { (v / dv) / cal }
        func pen(_ x: Double) -> Double { min(45, max(0, 15 * (x - 1))) }
        var s = 85.0
        s -= pen(r(n.addedSugar, dvSugar)) + pen(r(n.sodium, dvSodium)) + pen(r(n.satFat, dvSatFat))
        s += min(10, 3 * r(n.protein, dvProtein)) + min(8, 3 * r(n.fiber, dvFiber))
        s -= max(0, 10 * (1 - r(n.protein, dvProtein))) + max(0, 8 * (1 - r(n.fiber, dvFiber)))
        if n.artificialColor { s -= 5 }
        if n.fried { s -= 20 }
        if n.ultraProcessed { s -= 12 }
        if n.refined { s -= 10 }
        s -= max(0, (n.kcal - 600) / 15)
        return Int(min(100, max(1, s.rounded())))
    }

    enum Band: String { case good = "Good", ok = "OK", poor = "Poor" }
    static func band(_ s: Int) -> Band { s >= 70 ? .good : s >= 40 ? .ok : .poor }

    /// Percent of the FDA daily value in one serving.
    static func percentDV(_ value: Double, _ dv: Double) -> Int { Int((100 * value / dv).rounded()) }
}

/// A plain-language finding about a product or dish for this household.
struct Finding: Hashable, Identifiable {
    enum Severity: Int { case conflict, warning, info, fine }
    var id: String { text }
    let severity: Severity
    let text: String
}

enum FoodCheck {
    /// Checks allergens and diets for each person, then the daily-value thresholds (FDA: 20% or more is high).
    static func findings(nutrition n: Nutrition, allergens: Set<Allergen>, hasMeat: Bool, notVegetarianIngredients: [String],
                         people: [Person]) -> [Finding] {
        var out: [Finding] = []
        for p in people {
            let hit = allergens.intersection(p.avoids)
            if !hit.isEmpty {
                let names = hit.map { $0.label.replacingOccurrences(of: "No ", with: "") }.sorted().joined(separator: ", ")
                out.append(Finding(severity: .conflict, text: "Contains \(names). \(p.name) avoids it."))
            }
            if p.diet == .vegetarian && (hasMeat || !notVegetarianIngredients.isEmpty) {
                let why = notVegetarianIngredients.isEmpty ? "meat" : notVegetarianIngredients.joined(separator: ", ")
                out.append(Finding(severity: .conflict, text: "Not vegetarian (\(why)). \(p.name) is vegetarian."))
            }
        }
        for (v, dv, label) in [(n.addedSugar, HealthScore.dvSugar, "added sugar"), (n.sodium, HealthScore.dvSodium, "sodium"), (n.satFat, HealthScore.dvSatFat, "saturated fat")] {
            let pct = HealthScore.percentDV(v, dv)
            if pct >= 20 { out.append(Finding(severity: .warning, text: "High in \(label): \(pct)% of the daily value in one serving.")) }
        }
        if n.artificialColor { out.append(Finding(severity: .info, text: "Has artificial colours. Some families choose to avoid them.")) }
        if n.ultraProcessed { out.append(Finding(severity: .info, text: "Ultra-processed (processing group 4).")) }
        if out.isEmpty { out.append(Finding(severity: .fine, text: "Nothing your household avoids, and low in added sugar, sodium and saturated fat.")) }
        return out.sorted { $0.severity.rawValue < $1.severity.rawValue }
    }
}
