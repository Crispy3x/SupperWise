import Foundation

/// A small seeded generator so plans are reproducible in tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum PlanError: Error, Equatable {
    /// Fewer recipes work for this household than there are cook nights.
    case notEnoughRecipes(available: Int, needed: Int)
}

struct Planner {
    let catalog: Catalog
    let settings: Settings
    let inKitchen: Set<String>
    var adjust: Double = 1
    var leftovers: Set<Weekday> = []

    var pricer: Pricer { Pricer(catalog: catalog, settings: settings, inKitchen: inKitchen, leftovers: leftovers, adjust: adjust) }

    /// Builds a week: every dinner works for everyone, no dish repeats, the same protein never
    /// runs two nights in a row, and the whole-pack bill stays under budget when it can.
    /// Dishes from last week are avoided when there are enough others.
    func plan(weekStart: Date, avoiding lastWeek: Set<String> = [], seed: UInt64 = UInt64.random(in: 1...UInt64.max)) throws -> WeekPlan {
        let nights = settings.cookNights.sorted()
        let eligible = catalog.eligibleRecipes(for: settings)
        guard eligible.count >= nights.count else {
            throw PlanError.notEnoughRecipes(available: eligible.count, needed: nights.count)
        }
        let fresh = eligible.filter { !lastWeek.contains($0.id) }
        let pool = fresh.count >= nights.count ? fresh : eligible

        var rng = SeededRandom(seed: seed)
        var best: (recipes: [Recipe], score: Double)? = nil
        for _ in 0..<400 {
            guard let pick = draw(pool, count: nights.count, rng: &rng) else { continue }
            let s = score(pick, nights: nights)
            if best == nil || s < best!.score { best = (pick, s) }
        }
        let chosen = best?.recipes ?? Array(pool.prefix(nights.count))
        let dinners = zip(nights, chosen).map { PlannedDinner(day: $0.0, recipeID: $0.1.id) }
        return WeekPlan(weekStart: weekStart, dinners: dinners)
    }

    /// Replaces one night's dinner with the dish that keeps the bill closest to where it was,
    /// that isn't already in the week, and that doesn't repeat the protein of the nights beside it.
    func swap(_ day: Weekday, in plan: WeekPlan, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> WeekPlan {
        guard let index = plan.dinners.firstIndex(where: { $0.day == day }) else { return plan }
        let inWeek = Set(plan.dinners.map(\.recipeID))
        let current = recipes(of: plan)
        let before = pricer.price(current).total
        var rng = SeededRandom(seed: seed)
        let candidates = catalog.eligibleRecipes(for: settings).filter { !inWeek.contains($0.id) }.shuffled(using: &rng)
        var bestPlan = plan
        var bestScore = Double.infinity
        for c in candidates {
            var trial = plan
            trial.dinners[index].recipeID = c.id
            trial.dinners[index].cooked = false
            let r = recipes(of: trial)
            let total = pricer.price(r).total
            var s = abs(total - before)
            if total > settings.budget { s += (total - settings.budget) * 4 }
            if proteinClash(r.map(\.1)) { s += 50 }
            if s < bestScore { bestScore = s; bestPlan = trial }
        }
        return bestPlan
    }

    func recipes(of plan: WeekPlan) -> [(Weekday, Recipe)] {
        plan.dinners.compactMap { d in catalog.recipe(d.recipeID).map { (d.day, $0) } }
    }

    // MARK: - Internals

    private func draw(_ pool: [Recipe], count: Int, rng: inout SeededRandom) -> [Recipe]? {
        var remaining = pool.shuffled(using: &rng)
        var out: [Recipe] = []
        while out.count < count, !remaining.isEmpty {
            // Prefer a dish whose protein differs from the previous night's.
            if let i = remaining.firstIndex(where: { $0.protein != out.last?.protein || $0.protein == "none" }) {
                out.append(remaining.remove(at: i))
            } else {
                out.append(remaining.removeFirst())
            }
        }
        return out.count == count ? out : nil
    }

    private func proteinClash(_ recipes: [Recipe]) -> Bool {
        zip(recipes, recipes.dropFirst()).contains { $0.protein == $1.protein && $0.protein != "none" }
    }

    /// Lower is better.
    private func score(_ pick: [Recipe], nights: [Weekday]) -> Double {
        let total = pricer.price(Array(zip(nights, pick))).total
        var s = 0.0
        if settings.cheapestWeek {
            s += total
        } else {
            // Under budget is what matters; after that, prefer variety to squeezing pennies.
            if total > settings.budget { s += (total - settings.budget) * 10 + 100 }
            s += total * 0.05
        }
        if proteinClash(pick) { s += 40 }
        let cuisines = Set(pick.map(\.cuisine)).count
        s -= Double(cuisines) * 1.5
        // Long cooks on more than two nights is a lot for a weeknight.
        let long = pick.filter { $0.minutes > 50 }.count
        if long > 2 { s += Double(long - 2) * 6 }
        return s
    }
}
