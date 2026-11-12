import Foundation

/// Debug-only demo mode for store screenshots: `-demo` opens the app in a realistic mid-week state, in a
/// separate save file so real data is never touched; `-screen <name>` opens one screen.
/// Release builds ignore both.
enum Demo {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")
    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-screen"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    #else
    static let isOn = false
    static let screen: String? = nil
    #endif

    /// A family of four: one vegetarian, one who avoids nuts and doesn't like spicy food.
    @MainActor
    static func model(catalog: Catalog = .load(), lunchGuide: LunchGuide? = LunchGuide.bundled) -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("supperwise-demo.json")
        try? FileManager.default.removeItem(at: url)
        let m = AppModel(catalog: catalog, lunchGuide: lunchGuide, fileURL: url)
        m.updateSettings {
            $0.people = [Person(name: "Dana"), Person(name: "Marcus"),
                         Person(name: "Ari", age: 12, diet: .vegetarian),
                         Person(name: "June", age: 8, avoids: [.nuts], notSpicy: true)]
            $0.budget = 150
            $0.price = PriceProfile(storeName: "", storeKind: .supermarket, postalCode: "60614")
        }
        m.finishOnboarding()
        m.makeFirstWeek()
        m.markOfferSeen()
        m.setLunchSettings(LunchSettings(perDay: 2, days: [.mon, .tue, .wed, .thu, .fri], thermos: true))
        m.toggleLeftovers(.tue)
        if let first = m.plan?.dinners.first?.day { m.markCooked(first) }
        // A few things already in the cupboard, and the first few items in the cart.
        if let plan = m.plan {
            let lines = m.cost(of: plan).lines.filter { !$0.inKitchen }
            for l in lines where ["dry", "cans", "spices"].contains(l.ingredient.aisle.rawValue) { m.setInKitchen(l.id, true); break }
            for l in lines.filter({ $0.ingredient.aisle == .spices }).prefix(2) { m.setInKitchen(l.id, true) }
            for l in lines.filter({ $0.ingredient.aisle == .produce }).prefix(4) { m.toggleBought(l.id) }
        }
        // A baby, 8 months old, partway through first foods.
        let cal = Calendar.current
        m.setBaby(BabyProfile(name: "Rosie", birthDate: cal.date(byAdding: .month, value: -8, to: .now) ?? .now))
        let tried: [(String, Reaction)] = [("sweet_potato", .liked), ("avocado", .liked), ("banana", .liked), ("broccoli", .unsure),
                                           ("egg", .liked), ("peanut", .liked), ("yogurt", .liked), ("oatmeal", .disliked), ("salmon", .liked)]
        for (i, (food, r)) in tried.enumerated() {
            m.logFood(FoodLogEntry(foodID: food, date: cal.date(byAdding: .day, value: -3 * (tried.count - i), to: .now) ?? .now, reaction: r))
        }
        return m
    }
}
