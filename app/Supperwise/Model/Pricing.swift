import Foundation

/// One line of the grocery list: what to buy, how many packs, what it costs, who it's for.
struct GroceryLine: Identifiable, Hashable {
    var id: String { ingredient.id }
    let ingredient: Ingredient
    /// Total used this week, in the ingredient's unit.
    let used: Double
    /// Whole packs to buy (0 if the person already has it).
    let packs: Int
    /// Price for the whole packs, adjusted for the store.
    let cost: Double
    let days: [Weekday]
    let inKitchen: Bool
    /// Some of it goes into packed lunches.
    var lunch: Bool = false

    var leftoverFraction: Double {
        guard packs > 0 else { return 0 }
        return max(0, Double(packs) * ingredient.packSize - used) / (Double(packs) * ingredient.packSize)
    }

    /// "2 × 15 oz can" or "3 lb bag".
    var packText: String { packs > 1 ? "\(packs) × \(ingredient.packLabel)" : ingredient.packLabel }

    /// A plain note when a good part of the pack is left over.
    var leftoverNote: String? {
        guard packs > 0, leftoverFraction >= 0.3 else { return nil }
        let i = ingredient
        if i.aisle == .spices {
            let perDinner = days.isEmpty ? used : used / Double(days.count)
            let more = Int(((Double(packs) * i.packSize - used) / max(perDinner, 0.1)).rounded(.down))
            return more > 1 ? "The rest of the jar covers about \(more) more dinners." : nil
        }
        let share = leftoverFraction >= 0.6 ? "Most of it is left over." : "About \(Int((leftoverFraction * 100 / 10).rounded()) * 10)% is left over."
        if i.keepsDays >= 60 { return "\(share) It keeps for months." }
        if i.keepsDays >= 14 { return "\(share) It keeps about \(i.keepsDays / 7) weeks." }
        return "\(share) Use it within \(i.keepsDays) days."
    }
}

struct WeekCost: Hashable {
    let lines: [GroceryLine]
    /// Each dinner's share of the bill. Shares add up to the total.
    let perDinner: [Weekday: Double]
    /// The packed lunches' share of the bill (0 without a lunch plan).
    var lunches: Double = 0
    var total: Double { lines.reduce(0) { $0 + $1.cost } }
}

/// Prices a set of dinners by the whole pack, the way a shopper actually pays.
struct Pricer {
    let catalog: Catalog
    let settings: Settings
    /// Ingredient ids the person has said are already in the kitchen.
    let inKitchen: Set<String>
    /// Nights cooked with 2 extra portions for lunch.
    var leftovers: Set<Weekday> = []
    /// Learned from receipts: how this person's store runs against the estimates (1 = as estimated).
    var adjust: Double = 1
    /// Ingredients for the week's packed lunches (Family), added to the same whole-pack list.
    var lunchUsage: [String: Double] = [:]

    func scale(_ recipe: Recipe, day: Weekday? = nil) -> Double {
        let extra = day.map { leftovers.contains($0) ? 2 : 0 } ?? 0
        return Double(settings.householdSize + extra) / Double(max(recipe.servings, 1))
    }

    /// How many people need the written vegetarian plate for this dish.
    func swapPortions(_ recipe: Recipe) -> Int {
        guard recipe.vegetarianSwap != nil, !recipe.vegetarian else { return 0 }
        return settings.vegetarianCount + (recipe.pescatarian ? 0 : settings.pescatarianCount)
    }

    /// Ingredient amounts this dish uses for this household.
    func usage(_ recipe: Recipe, day: Weekday? = nil) -> [String: Double] {
        var out: [String: Double] = [:]
        let s = scale(recipe, day: day)
        for ri in recipe.ingredients where !ri.ingredient.isEmpty {
            out[ri.ingredient, default: 0] += catalog.ingredients[ri.ingredient]?.unit == .count ? (ri.amount * s).rounded(.up) : ri.amount * s
        }
        if swapPortions(recipe) > 0, let swap = recipe.vegetarianSwap {
            for ri in swap.ingredients { out[ri.ingredient, default: 0] += ri.amount }
        }
        return out
    }

    func owned(_ i: Ingredient) -> Bool { inKitchen.contains(i.id) }

    func price(_ dinners: [(Weekday, Recipe)]) -> WeekCost {
        var used: [String: Double] = [:]
        var days: [String: [Weekday]] = [:]
        var dishUse: [Weekday: [String: Double]] = [:]
        for (day, r) in dinners {
            let u = usage(r, day: day)
            dishUse[day] = u
            for (k, v) in u {
                used[k, default: 0] += v
                days[k, default: []].append(day)
            }
        }
        for (k, v) in lunchUsage {
            let unitCount = catalog.ingredients[k]?.unit == .count
            used[k, default: 0] += unitCount ? v.rounded(.up) : v
        }
        var lines: [GroceryLine] = []
        for (id, amount) in used {
            guard let ing = catalog.ingredients[id] else { continue }
            let have = owned(ing)
            let packs = have ? 0 : Int((amount / ing.packSize - 1e-9).rounded(.up))
            let cost = Double(packs) * ing.refPrice * settings.price.multiplier * adjust
            lines.append(GroceryLine(ingredient: ing, used: amount, packs: packs, cost: cost,
                                     days: (days[id] ?? []).sorted(), inKitchen: have, lunch: lunchUsage[id] != nil))
        }
        lines.sort { ($0.ingredient.aisle.sortIndex, $0.ingredient.name) < ($1.ingredient.aisle.sortIndex, $1.ingredient.name) }

        // Split each line's cost between the dinners that use it, in proportion to use.
        var share: [Weekday: Double] = [:]
        for line in lines where line.cost > 0 {
            for d in line.days {
                let part = (dishUse[d]?[line.id] ?? 0) / max(line.used, 1e-9)
                share[d, default: 0] += line.cost * part
            }
        }
        // What's left of each line after the dinners' shares belongs to the lunches.
        var lunchShare = 0.0
        for line in lines where line.cost > 0 && lunchUsage[line.id] != nil {
            let dinners = line.days.reduce(0) { $0 + (dishUse[$1]?[line.id] ?? 0) }
            lunchShare += line.cost * max(0, line.used - dinners) / max(line.used, 1e-9)
        }
        return WeekCost(lines: lines, perDinner: share, lunches: lunchShare)
    }
}

extension Aisle {
    var sortIndex: Int { Aisle.allCases.firstIndex(of: self) ?? 0 }
}

extension Double {
    /// "$83.40"
    var dollars: String { String(format: "$%.2f", self) }
}
