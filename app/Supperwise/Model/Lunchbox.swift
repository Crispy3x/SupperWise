import Foundation

/// The bundled lunchbox ideas (lunches.json). Every one is nut-free.
struct LunchGuide: Codable {
    struct Item: Codable, Hashable {
        let ingredient: String
        /// Per lunch, in the ingredient's unit.
        let amount: Double
        let text: String
    }
    struct Lunch: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let note: String
        let ingredients: [Item]
        let allergens: [Allergen]
        let vegetarian: Bool
        let thermos: Bool
    }
    let lunches: [Lunch]
    let notes: [String]

    func lunch(_ id: String) -> Lunch? { lunches.first { $0.id == id } }

    /// Loaded once from the bundle.
    static let bundled: LunchGuide? = load()

    static func load(bundle: Bundle = .main) -> LunchGuide? {
        guard let url = bundle.url(forResource: "lunches", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LunchGuide.self, from: data)
    }
}

/// What the household packs: how many lunches a day, on which days, and whether there's a thermos.
struct LunchSettings: Codable, Hashable {
    var perDay: Int = 2
    var days: Set<Weekday> = [.mon, .tue, .wed, .thu, .fri]
    var thermos: Bool = false
}

/// One day's packed lunch. When last night's dinner was cooked with 2 extra portions, those cover 2 lunches
/// and the rest get `lunchID` (worked out from the week's leftover nights, so it follows any change to them).
struct PlannedLunch: Codable, Hashable, Identifiable {
    var id: Weekday { day }
    var day: Weekday
    var lunchID: String
}

struct LunchPlanner {
    let guide: LunchGuide
    let settings: Settings
    let lunch: LunchSettings

    /// Ideas that work for everyone: no avoided allergen; vegetarian when anyone is vegetarian or pescatarian;
    /// hot lunches only with a thermos.
    var eligible: [LunchGuide.Lunch] {
        let avoided = settings.avoided
        let meatFree = settings.vegetarianCount + settings.pescatarianCount > 0
        return guide.lunches.filter { l in
            avoided.isDisjoint(with: l.allergens) && (!meatFree || l.vegetarian) && (lunch.thermos || !l.thermos)
        }
    }

    /// A different lunch each packing day where possible, and never the same one two days running.
    func plan(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> [PlannedLunch] {
        var rng = SeededRandom(seed: seed)
        var pool = eligible.shuffled(using: &rng)
        guard !pool.isEmpty else { return [] }
        var out: [PlannedLunch] = []
        for (n, day) in lunch.days.sorted().enumerated() {
            if n > 0 && n % pool.count == 0 {
                let last = pool[pool.count - 1]
                pool.shuffle(using: &rng)
                if pool.count > 1 && pool[0] == last { pool.swapAt(0, 1) }
            }
            out.append(PlannedLunch(day: day, lunchID: pool[n % pool.count].id))
        }
        return out
    }

    /// Dinner leftovers go into the next day's lunch (within the same Monday-to-Sunday week).
    static func leftoverNight(for day: Weekday, _ leftovers: Set<Weekday>) -> Weekday? {
        guard let before = Weekday(rawValue: day.rawValue - 1), leftovers.contains(before) else { return nil }
        return before
    }

    /// Lunches to pack from the idea itself that day (last night's leftovers cover 2).
    func boxes(_ p: PlannedLunch, leftovers: Set<Weekday>) -> Int {
        max(0, lunch.perDay - (Self.leftoverNight(for: p.day, leftovers) == nil ? 0 : 2))
    }

    /// Ingredient amounts for the week's lunches, ready to be added to the grocery list.
    func usage(_ plan: [PlannedLunch], leftovers: Set<Weekday>) -> [String: Double] {
        var out: [String: Double] = [:]
        for p in plan {
            guard let l = guide.lunch(p.lunchID) else { continue }
            let n = Double(boxes(p, leftovers: leftovers))
            for item in l.ingredients where n > 0 { out[item.ingredient, default: 0] += item.amount * n }
        }
        return out
    }

    /// Swaps one day for another idea that isn't already planned this week, if there is one.
    func swap(_ day: Weekday, in plan: [PlannedLunch], seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> [PlannedLunch] {
        var rng = SeededRandom(seed: seed)
        guard let i = plan.firstIndex(where: { $0.day == day }) else { return plan }
        let used = Set(plan.map(\.lunchID))
        let fresh = eligible.filter { !used.contains($0.id) }
        let others = eligible.filter { $0.id != plan[i].lunchID }
        guard let pick = (fresh.isEmpty ? others : fresh).randomElement(using: &rng) else { return plan }
        var out = plan
        out[i].lunchID = pick.id
        return out
    }
}
