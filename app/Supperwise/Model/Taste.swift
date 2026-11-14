import Foundation

/// What the household likes, set in Profile. Optional on Settings so older saves still load.
struct Preferences: Codable, Hashable {
    var displayName: String = ""
    /// Cuisines to see more often ("Italian", "Mexican"...). Empty means no preference.
    var favoriteCuisines: Set<String> = []
    /// Ingredient ids nobody wants. Dishes that use one are never planned.
    var dislikedIngredients: Set<String> = []
    /// Longest total cooking time for a weeknight dinner (nil = any).
    var maxMinutes: Int? = nil
    /// What one takeout meal costs per person here, for the money-saved tracker.
    var takeoutPerPerson: Double = 15
}

enum Rating: Int, Codable, Hashable { case down = -1, up = 1 }

/// One dinner cooked at home: when, what, what it cost and how many it fed.
struct CookedEntry: Codable, Hashable {
    var date: Date
    var recipeID: String
    var cost: Double
    var servings: Int
}

/// Everything the planner learns from the household: favorites, ratings, dishes to skip and preferences.
struct Taste: Hashable {
    var favorites: Set<String> = []
    var hidden: Set<String> = []
    var ratings: [String: Rating] = [:]
    var prefs = Preferences()

    /// Hard rules: never planned if hidden, too long, or using an ingredient nobody wants.
    func allows(_ r: Recipe) -> Bool {
        if hidden.contains(r.id) { return false }
        if let max = prefs.maxMinutes, r.minutes > max { return false }
        if !prefs.dislikedIngredients.isEmpty && r.ingredients.contains(where: { prefs.dislikedIngredients.contains($0.ingredient) }) { return false }
        return true
    }

    /// Soft preference: higher means the planner should pick it more often.
    func bonus(_ r: Recipe) -> Double {
        var b = 0.0
        if favorites.contains(r.id) { b += 4 }
        switch ratings[r.id] { case .up: b += 3; case .down: b -= 6; case nil: break }
        if prefs.favoriteCuisines.contains(CuisineGroup.of(r.cuisine)) || prefs.favoriteCuisines.contains(r.cuisine) { b += 2 }
        return b
    }
}

/// Home-cooking stats from the cooked log: dinners, money saved against takeout, and the week streak.
struct HomeCookingStats: Equatable {
    var dinners = 0
    var thisMonth = 0
    var saved = 0.0
    /// Consecutive weeks (ending this week or last) with at least 3 dinners cooked at home.
    var weekStreak = 0

    static func compute(_ log: [CookedEntry], takeoutPerPerson: Double, now: Date = .now, calendar: Calendar = .current) -> HomeCookingStats {
        var s = HomeCookingStats()
        s.dinners = log.count
        s.saved = log.reduce(0) { $0 + max(0, takeoutPerPerson * Double($1.servings) - $1.cost) }
        s.thisMonth = log.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }.count
        var cal = calendar
        cal.firstWeekday = 2
        func weekStart(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d }
        var perWeek: [Date: Int] = [:]
        for e in log { perWeek[weekStart(e.date), default: 0] += 1 }
        var week = weekStart(now)
        // This week still in progress: start counting from last week if it hasn't reached 3 yet.
        if (perWeek[week] ?? 0) < 3 { week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week }
        while (perWeek[week] ?? 0) >= 3 {
            s.weekStreak += 1
            week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        if (perWeek[weekStart(now)] ?? 0) >= 3, s.weekStreak == 0 { s.weekStreak = 1 }
        return s
    }
}

/// Cuisines grouped into a short list people recognise (the recipe keeps its precise label).
enum CuisineGroup {
    static let order = ["American", "Southern & Cajun", "Mexican & Tex-Mex", "Latin & Caribbean", "Italian", "Mediterranean & Greek",
                        "Middle Eastern", "Indian & Pakistani", "Chinese", "Japanese & Korean", "Thai & Southeast Asian", "European", "African"]

    static func of(_ cuisine: String) -> String {
        let c = cuisine.lowercased()
        func has(_ words: String...) -> Bool { words.contains { c.contains($0) } }
        if has("southern", "cajun") { return "Southern & Cajun" }
        if has("tex-mex", "mexican") { return "Mexican & Tex-Mex" }
        if has("peru", "cuba", "caribbean", "brazil", "colombia", "argentin") { return "Latin & Caribbean" }
        if has("italian") { return "Italian" }
        if has("greek", "mediterranean", "spanish") { return "Mediterranean & Greek" }
        if has("middle eastern", "lebanese", "turkish", "persian") { return "Middle Eastern" }
        if has("indo-chinese") { return "Indian & Pakistani" }
        if has("indian", "pakistan") { return "Indian & Pakistani" }
        if has("chinese") { return "Chinese" }
        if has("japan", "korea") { return "Japanese & Korean" }
        if has("thai", "vietnam", "filipino", "indonesia", "asian") { return "Thai & Southeast Asian" }
        if has("french", "british", "german", "polish", "hungarian", "russian", "swedish", "eastern european") { return "European" }
        if has("african", "ethiopia") { return "African" }
        return "American"
    }
}
