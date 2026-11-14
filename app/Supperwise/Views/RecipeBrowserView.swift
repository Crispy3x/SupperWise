import SwiftUI

/// Every recipe in Supperwise: search, filter by cuisine, time and diet, favorites, and put any dish on a night.
/// Dishes with something the household avoids are marked, never hidden silently.
struct RecipeBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.todayAccent) private var accent
    @State private var query = ""
    @State private var cuisine: String? = nil
    @State private var maxMinutes = 0
    @State private var vegetarianOnly = false
    @State private var favoritesOnly = false
    @State private var safeOnly = true
    @State private var open: Recipe? = nil

    private var all: [Recipe] { model.catalog.recipes }
    private var cuisines: [String] { CuisineGroup.order }

    /// Sort key without cooking-method prefixes, so "Air fryer…" and "Sheet-pan…" dishes don't crowd the top.
    private func sortName(_ r: Recipe) -> String {
        var n = r.name.lowercased()
        for p in ["air fryer ", "air-fryer ", "sheet-pan ", "sheet pan ", "slow-cooker ", "slow cooker ", "one-pot ", "one-pan ", "skillet ", "baked ", "easy ", "quick ", "classic "] where n.hasPrefix(p) { n = String(n.dropFirst(p.count)) }
        return n
    }
    private func hasPhoto(_ r: Recipe) -> Bool { r.photo.map { UIImage(named: $0) != nil } ?? false }

    private func conflicts(_ r: Recipe) -> [String] {
        var out: [String] = []
        for p in model.settings.people {
            let hit = p.avoids.intersection(r.allergens)
            if !hit.isEmpty { out.append("\(p.name) avoids \(hit.map { $0.label.replacingOccurrences(of: "No ", with: "").lowercased() }.sorted().joined(separator: ", "))") }
        }
        return out
    }

    private var results: [Recipe] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return all.filter { r in
            (q.isEmpty || r.name.localizedCaseInsensitiveContains(q) || r.cuisine.localizedCaseInsensitiveContains(q)
                || r.ingredients.contains { ($0.text + " " + (model.catalog.ingredients[$0.ingredient]?.name ?? "")).localizedCaseInsensitiveContains(q) })
            && (cuisine == nil || CuisineGroup.of(r.cuisine) == cuisine)
            && (maxMinutes == 0 || r.minutes <= maxMinutes)
            && (!vegetarianOnly || r.vegetarian)
            && (!favoritesOnly || model.favorites.contains(r.id))
            && (!safeOnly || conflicts(r).isEmpty)
            && !model.hiddenRecipes.contains(r.id)
        }
        .sorted {
            // Favorites first, then dishes with photos, then A–Z by dish (ignoring the cooking method).
            (model.favorites.contains($0.id) ? 0 : 1, hasPhoto($0) ? 0 : 1, sortName($0)) <
            (model.favorites.contains($1.id) ? 0 : 1, hasPhoto($1) ? 0 : 1, sortName($1))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All cuisines", on: cuisine == nil) { cuisine = nil }
                            ForEach(cuisines, id: \.self) { c in chip(c, on: cuisine == c) { cuisine = cuisine == c ? nil : c } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Any time", on: maxMinutes == 0) { maxMinutes = 0 }
                            chip("≤ 20 min", on: maxMinutes == 20) { maxMinutes = 20 }
                            chip("≤ 30 min", on: maxMinutes == 30) { maxMinutes = 30 }
                            chip("≤ 45 min", on: maxMinutes == 45) { maxMinutes = 45 }
                            chip("Vegetarian", on: vegetarianOnly) { vegetarianOnly.toggle() }
                            chip("Favorites", on: favoritesOnly) { favoritesOnly.toggle() }
                            if !model.settings.people.isEmpty { chip("Safe for everyone", on: safeOnly) { safeOnly.toggle() } }
                        }
                    }
                    Text("\(results.count) recipes").font(.footnote).foregroundStyle(Paper.ink2)
                }
                .listRowBackground(Paper.ground)
                .listRowSeparator(.hidden)

                ForEach(results) { r in
                    Button { open = r } label: { row(r) }
                        .buttonStyle(.plain)
                        .listRowBackground(Paper.ground)
                        .swipeActions(edge: .trailing) {
                            Button { model.toggleFavorite(r.id) } label: {
                                Label(model.favorites.contains(r.id) ? "Unfavorite" : "Favorite", systemImage: model.favorites.contains(r.id) ? "heart.slash" : "heart")
                            }.tint(accent)
                        }
                        .contextMenu { nightMenu(r) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .searchable(text: $query, prompt: "Search dishes or ingredients")
            .navigationTitle("All recipes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $open) { r in NavigationStack { RecipeView(recipe: r, day: model.tonight()?.day ?? .wed) } }
        }
    }

    private func row(_ r: Recipe) -> some View {
        let warn = conflicts(r)
        return HStack(spacing: 12) {
            PlateView(recipe: r, rim: 0).frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.name).font(.headline).foregroundStyle(Paper.ink).lineLimit(2)
                    if model.favorites.contains(r.id) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(accent).accessibilityLabel("Favorite") }
                }
                Text("\(r.cuisine) · \(r.minutes) min\(r.vegetarian ? " · vegetarian" : "")\(r.spice > 0 ? " · spicy" : "")")
                    .font(.caption).foregroundStyle(Paper.ink2)
                if !warn.isEmpty {
                    Label(warn.joined(separator: "; "), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color(hex: 0xB3261E))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func nightMenu(_ r: Recipe) -> some View {
        if let plan = model.plan {
            ForEach(plan.dinners) { d in
                Button("Cook on \(d.day.name)") { model.setDinner(d.day, recipeID: r.id) }
            }
        }
        Button { model.toggleFavorite(r.id) } label: { Label(model.favorites.contains(r.id) ? "Remove favorite" : "Add to favorites", systemImage: "heart") }
    }

    private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(on ? accent : Paper.chip))
            .foregroundStyle(on ? Ink.onDay : Paper.ink)
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}
