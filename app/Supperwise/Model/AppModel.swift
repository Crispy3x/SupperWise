import Foundation
import Observation

/// Everything the person has entered, saved as one JSON file in Application Support.
struct SavedState: Codable {
    var settings = Settings()
    var plan: WeekPlan? = nil
    var nextPlan: WeekPlan? = nil
    var inKitchen: Set<String> = []
    var freeWeekUsed = false
    var onboarded = false
    var history: [String] = []
    /// The person has seen the first-week offer (and kept the free week or subscribed).
    var seenOffer = false
    // Added in v2. Optional so saves from v1 still load.
    var storeAdjust: Double? = nil
    var savedRecipes: [Recipe]? = nil
    var dishes: [SavedDish]? = nil
    var receipts: [ReceiptRecord]? = nil
    var importsByMonth: [String: Int]? = nil
    var fridge: [String]? = nil
    var baby: BabyProfile? = nil
    var foodLog: [FoodLogEntry]? = nil
    // Added in v3: profile, favorites, ratings, hidden dishes, cooked log.
    var favorites: Set<String>? = nil
    var hidden: Set<String>? = nil
    var ratings: [String: Rating]? = nil
    var cookedLog: [CookedEntry]? = nil

    init() {}

    /// Tolerant decoding: any key missing from an older save falls back to its default instead of losing everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        plan = try c.decodeIfPresent(WeekPlan.self, forKey: .plan)
        nextPlan = try c.decodeIfPresent(WeekPlan.self, forKey: .nextPlan)
        inKitchen = try c.decodeIfPresent(Set<String>.self, forKey: .inKitchen) ?? []
        freeWeekUsed = try c.decodeIfPresent(Bool.self, forKey: .freeWeekUsed) ?? false
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        history = try c.decodeIfPresent([String].self, forKey: .history) ?? []
        seenOffer = try c.decodeIfPresent(Bool.self, forKey: .seenOffer) ?? false
        storeAdjust = try c.decodeIfPresent(Double.self, forKey: .storeAdjust)
        savedRecipes = try c.decodeIfPresent([Recipe].self, forKey: .savedRecipes)
        dishes = try c.decodeIfPresent([SavedDish].self, forKey: .dishes)
        receipts = try c.decodeIfPresent([ReceiptRecord].self, forKey: .receipts)
        importsByMonth = try c.decodeIfPresent([String: Int].self, forKey: .importsByMonth)
        fridge = try c.decodeIfPresent([String].self, forKey: .fridge)
        baby = try c.decodeIfPresent(BabyProfile.self, forKey: .baby)
        foodLog = try c.decodeIfPresent([FoodLogEntry].self, forKey: .foodLog)
        favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites)
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden)
        ratings = try c.decodeIfPresent([String: Rating].self, forKey: .ratings)
        cookedLog = try c.decodeIfPresent([CookedEntry].self, forKey: .cookedLog)
    }
}

/// A restaurant dish the person scored (Family).
struct SavedDish: Codable, Hashable, Identifiable {
    var id = UUID()
    var restaurant: String
    var name: String
    var nutrition: Nutrition
    var allergens: Set<Allergen> = []
    var hasMeat = false
    var score: Int { HealthScore.score(nutrition) }
}

/// One receipt check: what the plan estimated against what the person paid (Family).
struct ReceiptRecord: Codable, Hashable {
    var weekStart: Date
    var planned: Double
    var paid: Double
}

@Observable
@MainActor
final class AppModel {
    private let baseCatalog: Catalog
    /// The bundled catalog plus recipes the person saved from links.
    var catalog: Catalog { Catalog(ingredients: baseCatalog.ingredients, recipes: baseCatalog.recipes + (state.savedRecipes ?? [])) }
    private(set) var state: SavedState
    var lastError: String? = nil
    /// Shows a message in the app's alert (used for sign-in link problems).
    func reportProblem(_ message: String) { lastError = message }
    private let fileURL: URL
    private let lunchGuide: LunchGuide?

    init(catalog: Catalog = .load(), lunchGuide: LunchGuide? = LunchGuide.bundled, fileURL: URL? = nil) {
        self.baseCatalog = catalog
        self.lunchGuide = lunchGuide
        let url = fileURL ?? AppModel.defaultURL()
        self.fileURL = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = saved
        } else {
            var fresh = SavedState()
            // Oils, salt, pepper and sugar start ticked as "in the kitchen".
            fresh.inKitchen = Set(catalog.ingredients.values.filter(\.staple).map(\.id))
            state = fresh
        }
        rollWeekIfNeeded()
    }

    nonisolated static func defaultURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("supperwise.json")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            lastError = "Couldn't save your changes: \(error.localizedDescription)"
        }
    }

    // MARK: Read

    var settings: Settings { state.settings }
    var plan: WeekPlan? { state.plan }
    var nextPlan: WeekPlan? { state.nextPlan }
    var inKitchen: Set<String> { state.inKitchen }
    var onboarded: Bool { state.onboarded }
    var freeWeekUsed: Bool { state.freeWeekUsed }

    var planner: Planner {
        Planner(catalog: catalog, settings: state.settings, inKitchen: state.inKitchen,
                adjust: state.storeAdjust ?? 1, leftovers: state.plan?.leftovers ?? [], taste: taste)
    }
    var storeAdjust: Double { state.storeAdjust ?? 1 }
    var savedRecipes: [Recipe] { state.savedRecipes ?? [] }
    var dishes: [SavedDish] { state.dishes ?? [] }
    var receipts: [ReceiptRecord] { state.receipts ?? [] }
    var fridge: [String] { state.fridge ?? [] }

    func recipes(of plan: WeekPlan) -> [(Weekday, Recipe)] { planner.recipes(of: plan) }

    /// Each week is priced with its own leftover nights and the store adjustment learned from receipts.
    /// Packed lunches (Family) go on the same list, so packs are shared with dinners.
    /// `ignoringKitchen` prices the same week as if nothing were ticked in the kitchen (for the pantry saving).
    func cost(of plan: WeekPlan, ignoringKitchen: Bool = false) -> WeekCost {
        var pricer = Pricer(catalog: catalog, settings: state.settings, inKitchen: ignoringKitchen ? [] : state.inKitchen,
                            leftovers: plan.leftovers ?? [], adjust: storeAdjust)
        if let lp = lunchPlanner, let lunches = plan.lunches { pricer.lunchUsage = lp.usage(lunches, leftovers: plan.leftovers ?? []) }
        return pricer.price(recipes(of: plan))
    }

    // MARK: Lunchbox (Family)

    var lunchPlanner: LunchPlanner? {
        guard let guide = lunchGuide, let ls = state.settings.lunch else { return nil }
        return LunchPlanner(guide: guide, settings: state.settings, lunch: ls)
    }

    /// Turns lunch planning on or changes it, and replans this week's lunches to match.
    func setLunchSettings(_ ls: LunchSettings?) {
        state.settings.lunch = ls
        if var p = state.plan {
            p.lunches = lunchPlanner?.plan()
            state.plan = p
        }
        if var n = state.nextPlan {
            n.lunches = lunchPlanner?.plan()
            state.nextPlan = n
        }
        save()
    }

    func swapLunch(_ day: Weekday) {
        guard var p = state.plan, let lp = lunchPlanner, let l = p.lunches else { return }
        p.lunches = lp.swap(day, in: l)
        state.plan = p
        save()
    }

    /// Tonight, or the next cook night this week.
    func tonight(now: Date = .now) -> PlannedDinner? {
        guard let plan = state.plan else { return nil }
        let today = Weekday(calendarWeekday: Calendar.current.component(.weekday, from: now))
        return plan.dinners.first { $0.day == today && !$0.cooked }
            ?? plan.dinners.first { $0.day >= today && !$0.cooked }
            ?? plan.dinners.first { !$0.cooked }
    }

    // MARK: Write

    func updateSettings(_ change: (inout Settings) -> Void) {
        change(&state.settings)
        save()
    }

    func markOfferSeen() {
        state.seenOffer = true
        save()
    }

    var seenOffer: Bool { state.seenOffer }

    func finishOnboarding() {
        state.onboarded = true
        save()
    }

    /// Builds this week's plan. The first one is free and is the person's to keep.
    func makeFirstWeek(now: Date = .now) {
        do {
            var p = try planner.plan(weekStart: Self.monday(of: now))
            p.isFreeWeek = !state.freeWeekUsed
            p.lunches = lunchPlanner?.plan()
            state.plan = p
            state.freeWeekUsed = true
            save()
        } catch PlanError.notEnoughRecipes(let available, let needed) {
            lastError = "Only \(available) recipes work for everyone with this kitchen, and you cook \(needed) nights. Turn on more equipment or cook fewer nights."
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Builds next week (needs a subscription; the caller checks).
    func makeNextWeek(now: Date = .now) {
        let start = Calendar.current.date(byAdding: .day, value: 7, to: Self.monday(of: now)) ?? now
        let last = Set(state.plan?.dinners.map(\.recipeID) ?? [])
        do {
            var next = try planner.plan(weekStart: start, avoiding: last)
            next.lunches = lunchPlanner?.plan()
            state.nextPlan = next
            save()
        } catch PlanError.notEnoughRecipes(let available, let needed) {
            lastError = "Only \(available) recipes work for everyone with this kitchen, and you cook \(needed) nights. Turn on more equipment or cook fewer nights."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func swap(_ day: Weekday) {
        guard let p = state.plan else { return }
        state.plan = planner.swap(day, in: p)
        save()
    }

    func markCooked(_ day: Weekday, _ cooked: Bool = true, now: Date = .now) {
        guard var p = state.plan, let i = p.dinners.firstIndex(where: { $0.day == day }) else { return }
        let wasCooked = p.dinners[i].cooked
        p.dinners[i].cooked = cooked
        state.plan = p
        if cooked, !wasCooked {
            let id = p.dinners[i].recipeID
            state.history.append(id)
            let plate = cost(of: p).perDinner[day] ?? 0
            var log = state.cookedLog ?? []
            log.append(CookedEntry(date: now, recipeID: id, cost: plate, servings: state.settings.householdSize))
            state.cookedLog = log
        }
        save()
    }

    // MARK: Profile, favorites and ratings

    var prefs: Preferences { state.settings.prefs ?? Preferences() }
    var favorites: Set<String> { state.favorites ?? [] }
    var hiddenRecipes: Set<String> { state.hidden ?? [] }
    var taste: Taste { Taste(favorites: favorites, hidden: hiddenRecipes, ratings: state.ratings ?? [:], prefs: prefs) }
    var stats: HomeCookingStats { HomeCookingStats.compute(state.cookedLog ?? [], takeoutPerPerson: prefs.takeoutPerPerson) }

    func rating(_ id: String) -> Rating? { state.ratings?[id] }

    func updatePrefs(_ change: (inout Preferences) -> Void) {
        var p = prefs
        change(&p)
        state.settings.prefs = p
        save()
    }

    func toggleFavorite(_ id: String) {
        var f = favorites
        if f.contains(id) { f.remove(id) } else { f.insert(id) }
        state.favorites = f
        save()
    }

    func rate(_ id: String, _ r: Rating?) {
        var all = state.ratings ?? [:]
        all[id] = r
        state.ratings = all
        save()
    }

    /// "Don't suggest this again": never planned automatically. Can be undone in Profile.
    func setHidden(_ id: String, _ hide: Bool) {
        var h = hiddenRecipes
        if hide { h.insert(id) } else { h.remove(id) }
        state.hidden = h
        if hide { state.favorites?.remove(id) }
        save()
    }

    func toggleBought(_ ingredientID: String) {
        guard var p = state.plan else { return }
        if p.bought.contains(ingredientID) { p.bought.remove(ingredientID) } else { p.bought.insert(ingredientID) }
        state.plan = p
        save()
    }

    func setInKitchen(_ ingredientID: String, _ have: Bool) {
        if have { state.inKitchen.insert(ingredientID) } else { state.inKitchen.remove(ingredientID) }
        save()
    }

    /// When a new week starts, next week's plan (if made) becomes this week's.
    func rollWeekIfNeeded(now: Date = .now) {
        let monday = Self.monday(of: now)
        if let next = state.nextPlan, next.weekStart <= monday {
            state.plan = next
            state.nextPlan = nil
            save()
        }
    }

    // MARK: v2 features

    func toggleLeftovers(_ day: Weekday) {
        guard var p = state.plan else { return }
        var set = p.leftovers ?? []
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        p.leftovers = set
        state.plan = p
        save()
    }

    /// Puts a recipe (from the fridge matches or a saved link) on one night.
    func setDinner(_ day: Weekday, recipeID: String) {
        guard var p = state.plan, let i = p.dinners.firstIndex(where: { $0.day == day }) else { return }
        p.dinners[i].recipeID = recipeID
        p.dinners[i].cooked = false
        state.plan = p
        save()
    }

    static func monthKey(_ d: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }
    var importsThisMonth: Int { state.importsByMonth?[Self.monthKey()] ?? 0 }

    func saveRecipe(_ r: Recipe) {
        var list = state.savedRecipes ?? []
        list.removeAll { $0.id == r.id }
        list.insert(r, at: 0)
        state.savedRecipes = list
        var counts = state.importsByMonth ?? [:]
        counts[Self.monthKey(), default: 0] += 1
        state.importsByMonth = counts
        save()
    }

    /// Whether a saved recipe is on this or next week's plan (it can't be deleted while it is).
    func isPlanned(_ id: String) -> Bool {
        (state.plan?.dinners ?? []).contains { $0.recipeID == id } || (state.nextPlan?.dinners ?? []).contains { $0.recipeID == id }
    }

    func deleteSavedRecipe(_ id: String) {
        guard !isPlanned(id) else {
            lastError = "That recipe is in your plan. Swap it out first, then delete it."
            return
        }
        state.savedRecipes?.removeAll { $0.id == id }
        save()
    }

    func saveDish(_ d: SavedDish) {
        var list = state.dishes ?? []
        list.removeAll { $0.id == d.id }
        list.insert(d, at: 0)
        state.dishes = list
        save()
    }

    func deleteDish(_ id: UUID) {
        state.dishes?.removeAll { $0.id == id }
        save()
    }

    /// Records a receipt and, if asked, moves future estimates toward what this store charges (clamped to ±25%).
    func recordReceipt(planned: Double, paid: Double, learn: Bool) {
        guard planned > 0, paid > 0, let plan = state.plan else { return }
        var list = state.receipts ?? []
        list.removeAll { $0.weekStart == plan.weekStart }
        list.append(ReceiptRecord(weekStart: plan.weekStart, planned: planned, paid: paid))
        state.receipts = list
        if learn { state.storeAdjust = min(1.25, max(0.8, (state.storeAdjust ?? 1) * paid / planned)) }
        save()
    }

    // MARK: First foods

    var baby: BabyProfile? { state.baby }
    var foodLog: [FoodLogEntry] { state.foodLog ?? [] }
    /// Foods tried at least once without a possible reaction logged last.
    var triedFoods: Set<String> {
        var latest: [String: FoodLogEntry] = [:]
        for e in foodLog where (latest[e.foodID]?.date ?? .distantPast) <= e.date { latest[e.foodID] = e }
        return Set(latest.values.filter { $0.reaction != .reaction }.map(\.foodID))
    }
    func lastLog(_ foodID: String) -> FoodLogEntry? { foodLog.filter { $0.foodID == foodID }.max { $0.date < $1.date } }

    func setBaby(_ b: BabyProfile?) {
        state.baby = b
        if b == nil { state.foodLog = nil }
        save()
    }

    func logFood(_ e: FoodLogEntry) {
        var list = state.foodLog ?? []
        list.append(e)
        state.foodLog = list
        save()
    }

    func removeFoodLog(_ id: UUID) {
        state.foodLog?.removeAll { $0.id == id }
        save()
    }

    func setFridge(_ ids: [String]) {
        state.fridge = ids
        save()
    }

    func eraseEverything() {
        try? FileManager.default.removeItem(at: fileURL)
        var fresh = SavedState()
        fresh.inKitchen = Set(catalog.ingredients.values.filter(\.staple).map(\.id))
        state = fresh
    }

    static func monday(of date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
}
