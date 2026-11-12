import SwiftUI

/// Family: score restaurant dishes 1–100 from the nutrition the restaurant publishes
/// (chains with 20+ locations must post calories in the US, and most post full nutrition online).
struct EatOutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SavedDish? = nil
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Add a dish from a restaurant's posted nutrition. Each gets a health score from 1 to 100, checked against everyone at your table. Best picks first.")
                        .font(.subheadline).foregroundStyle(Paper.ink2)
                        .listRowBackground(Paper.ground)
                    Button {
                        editing = SavedDish(restaurant: filter, name: "", nutrition: Nutrition(kcal: 500))
                    } label: { Label("Add a dish", systemImage: "plus") }
                    .listRowBackground(Paper.ground)
                }
                let groups = Dictionary(grouping: model.dishes.filter { filter.isEmpty || $0.restaurant.localizedCaseInsensitiveContains(filter) }, by: \.restaurant)
                ForEach(groups.keys.sorted(), id: \.self) { rest in
                    Section(rest.isEmpty ? "Other" : rest) {
                        ForEach(sorted(groups[rest] ?? [])) { d in
                            Button { editing = d } label: { DishRow(dish: d) }
                                .buttonStyle(.plain)
                                .listRowBackground(Paper.ground)
                                .swipeActions { Button("Delete", role: .destructive) { model.deleteDish(d.id) } }
                        }
                    }
                }
                Section { HowTheScoreWorks().listRowBackground(Paper.ground) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .searchable(text: $filter, prompt: "Restaurant")
            .navigationTitle("Eating out")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { DishEditor(dish: $0) }
        }
    }

    /// Dishes nobody can't eat come first, then by score.
    private func sorted(_ ds: [SavedDish]) -> [SavedDish] {
        ds.sorted { a, b in
            let ca = conflicts(a).isEmpty, cb = conflicts(b).isEmpty
            return ca != cb ? ca : a.score > b.score
        }
    }

    func conflicts(_ d: SavedDish) -> [Finding] {
        FoodCheck.findings(nutrition: d.nutrition, allergens: d.allergens, hasMeat: d.hasMeat, notVegetarianIngredients: [], people: model.settings.people)
            .filter { $0.severity == .conflict }
    }
}

struct DishRow: View {
    @Environment(AppModel.self) private var model
    let dish: SavedDish
    var body: some View {
        let conflicts = FoodCheck.findings(nutrition: dish.nutrition, allergens: dish.allergens, hasMeat: dish.hasMeat,
                                           notVegetarianIngredients: [], people: model.settings.people).filter { $0.severity == .conflict }
        HStack(spacing: 12) {
            ScoreBadge(score: dish.score, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.name).font(.headline)
                Text("\(dish.nutrition.kcal.formatted(.number.precision(.fractionLength(0)))) cal · \(dish.nutrition.sodium.formatted(.number.precision(.fractionLength(0)))) mg sodium · \(dish.nutrition.protein.formatted(.number.precision(.fractionLength(0)))) g protein")
                    .font(.caption).foregroundStyle(Paper.ink2)
                if let c = conflicts.first { Text(c.text).font(.caption.weight(.semibold)).foregroundStyle(Color(hex: 0xB3261E)) }
                else { Text(HealthScore.band(dish.score).rawValue + (dish.score >= 70 ? " pick" : "")).font(.caption.weight(.semibold)) }
            }
        }
    }
}

struct DishEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var dish: SavedDish

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Restaurant", text: $dish.restaurant)
                    TextField("Dish", text: $dish.name)
                }
                Section("From the restaurant's nutrition facts") {
                    number("Calories", $dish.nutrition.kcal)
                    number("Sodium (mg)", $dish.nutrition.sodium)
                    number("Added or total sugar (g)", $dish.nutrition.addedSugar)
                    number("Saturated fat (g)", $dish.nutrition.satFat)
                    number("Protein (g)", $dish.nutrition.protein)
                    number("Fibre (g)", $dish.nutrition.fiber)
                }
                Section("What's in it") {
                    Toggle("Fried", isOn: $dish.nutrition.fried)
                    Toggle("Has meat or fish", isOn: $dish.hasMeat)
                    ForEach(Allergen.allCases) { a in
                        Toggle("Contains " + a.label.replacingOccurrences(of: "No ", with: ""), isOn: Binding(
                            get: { dish.allergens.contains(a) },
                            set: { on in if on { dish.allergens.insert(a) } else { dish.allergens.remove(a) } }))
                    }
                }
                Section {
                    HStack {
                        ScoreBadge(score: dish.score, size: 52)
                        Text(HealthScore.band(dish.score).rawValue).font(.headline)
                    }
                }
            }
            .navigationTitle(dish.name.isEmpty ? "New dish" : dish.name)
            .onChange(of: dish.nutrition) { _, n in
                // Keep typed values in a sane range so the score and labels never overflow.
                func c(_ v: Double, _ hi: Double) -> Double { min(max(v.isFinite ? v : 0, 0), hi) }
                let fixed = Nutrition(kcal: c(n.kcal, 10_000), addedSugar: c(n.addedSugar, 1_000), sodium: c(n.sodium, 50_000),
                                      satFat: c(n.satFat, 1_000), protein: c(n.protein, 1_000), fiber: c(n.fiber, 1_000),
                                      fried: n.fried, refined: n.refined, ultraProcessed: n.ultraProcessed, artificialColor: n.artificialColor)
                if fixed != n { dish.nutrition = fixed }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveDish(dish); dismiss() }.disabled(dish.name.isEmpty)
                }
            }
        }
    }

    private func number(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}
