import SwiftUI

/// You: name, home-cooking stats, taste (cuisines, dislikes, time limit), favorites and skipped dishes.
/// Everything here stays on the iPhone and shapes every plan.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.todayAccent) private var accent
    @State private var ingredientQuery = ""
    @State private var open: Recipe? = nil

    private var cuisines: [String] {
        Array(Set(model.catalog.recipes.filter { $0.source == nil }.map(\.cuisine))).sorted()
    }

    var body: some View {
        let stats = model.stats
        Form {
            Section {
                TextField("Your name", text: Binding(get: { model.prefs.displayName }, set: { v in model.updatePrefs { $0.displayName = String(v.prefix(30)) } }))
                    .font(.title3)
                HomeCookingCard(stats: stats, accent: accent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: { Text("You") }

            Section {
                WrapLayout(spacing: 8) {
                    ForEach(cuisines, id: \.self) { c in
                        let on = model.prefs.favoriteCuisines.contains(c)
                        Button(c) { model.updatePrefs { if on { $0.favoriteCuisines.remove(c) } else { $0.favoriteCuisines.insert(c) } } }
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(on ? accent : Paper.chip))
                            .foregroundStyle(on ? Ink.onDay : Paper.ink)
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Cuisines you love") } footer: { Text("They come up more often. Leave all off for a bit of everything.") }

            Section {
                Picker("Longest weeknight cook", selection: Binding(get: { model.prefs.maxMinutes ?? 0 }, set: { v in model.updatePrefs { $0.maxMinutes = v == 0 ? nil : v } })) {
                    Text("Any length").tag(0)
                    Text("20 minutes").tag(20)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("60 minutes").tag(60)
                }
                Stepper(value: Binding(get: { model.prefs.takeoutPerPerson }, set: { v in model.updatePrefs { $0.takeoutPerPerson = v } }), in: 5...50, step: 1) {
                    VStack(alignment: .leading) {
                        Text("Takeout costs about \(Int(model.prefs.takeoutPerPerson).formatted(.currency(code: "USD").precision(.fractionLength(0)))) a person")
                        Text("Used for “saved by cooking at home”.").font(.footnote).foregroundStyle(Paper.ink2)
                    }
                }
            } header: { Text("How you cook") }

            Section {
                let disliked = model.prefs.dislikedIngredients.compactMap { model.catalog.ingredients[$0] }.sorted { $0.name < $1.name }
                ForEach(disliked) { i in
                    HStack {
                        Text(i.name)
                        Spacer()
                        Button("Remove") { model.updatePrefs { $0.dislikedIngredients.remove(i.id) } }.font(.footnote)
                    }
                }
                TextField("Add an ingredient nobody eats (e.g. mushrooms)", text: $ingredientQuery)
                    .textInputAutocapitalization(.never)
                if ingredientQuery.count >= 2 {
                    let matches = model.catalog.ingredients.values
                        .filter { $0.name.localizedCaseInsensitiveContains(ingredientQuery) && !$0.staple && !model.prefs.dislikedIngredients.contains($0.id) }
                        .sorted { $0.name < $1.name }.prefix(6)
                    ForEach(Array(matches)) { i in
                        Button { model.updatePrefs { $0.dislikedIngredients.insert(i.id) }; ingredientQuery = "" } label: { Label(i.name, systemImage: "plus.circle") }
                    }
                }
            } header: { Text("Ingredients to skip") } footer: { Text("Dinners that use them are never planned. For allergies, set them per person under Next week › Who's eating.") }

            let favs = model.favorites.compactMap { model.catalog.recipe($0) }.sorted { $0.name < $1.name }
            Section("Favorites (\(favs.count))") {
                if favs.isEmpty { Text("Tap the heart on any recipe and it comes up more often.").foregroundStyle(Paper.ink2) }
                ForEach(favs) { r in
                    Button { open = r } label: { Label(r.name, systemImage: "heart.fill") }.tint(accent)
                }
            }

            let skipped = model.hiddenRecipes.compactMap { model.catalog.recipe($0) }.sorted { $0.name < $1.name }
            if !skipped.isEmpty {
                Section {
                    ForEach(skipped) { r in
                        HStack {
                            Text(r.name)
                            Spacer()
                            Button("Bring back") { model.setHidden(r.id, false) }.font(.footnote)
                        }
                    }
                } header: { Text("Not suggested") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Paper.ground)
        .navigationTitle("Profile")
        .sheet(item: $open) { r in NavigationStack { RecipeView(recipe: r, day: model.tonight()?.day ?? .wed) } }
    }
}

/// Dinners cooked at home, money saved against takeout, and the week streak.
struct HomeCookingCard: View {
    let stats: HomeCookingStats
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            cell(stats.saved.formatted(.currency(code: "USD").precision(.fractionLength(0))), "saved by\ncooking at home")
            Divider().frame(height: 44)
            cell("\(stats.thisMonth)", "dinners at home\nthis month")
            Divider().frame(height: 44)
            cell(stats.weekStreak == 0 ? "–" : "\(stats.weekStreak)", stats.weekStreak == 1 ? "week streak\n(3+ dinners)" : "weeks in a row\n(3+ dinners)")
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Paper.raised))
        .accessibilityElement(children: .combine)
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.serif(30, relativeTo: .title2)).monospacedDigit().foregroundStyle(accent)
            Text(label).font(.caption2).multilineTextAlignment(.center).foregroundStyle(Paper.ink2)
        }
        .frame(maxWidth: .infinity)
    }
}
