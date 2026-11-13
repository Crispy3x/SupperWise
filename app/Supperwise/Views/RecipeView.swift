import SwiftUI

struct RecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let day: Weekday

    @State private var servings: Int = 4
    @AppStorage("recipeTextLarge") private var largeText = false
    @State private var cooking = false

    var body: some View {
        let palette = DayPalette.of(day)
        let factor = Double(servings) / Double(recipe.servings)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(palette: palette)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Servings").font(.headline)
                        Spacer()
                        Stepper(value: $servings, in: 1...12) {
                            Text("\(servings)").monospacedDigit()
                        }
                        .fixedSize()
                    }
                    .padding(.bottom, 14)
                    Divider().overlay(Paper.rule)

                    sectionTitle("You'll need")
                    ForEach(recipe.ingredients, id: \.self) { ri in
                        ingredientRow(ri, factor: factor)
                    }

                    if let swap = recipe.vegetarianSwap, !recipe.vegetarian, model.settings.vegetarianCount + model.settings.pescatarianCount > 0 {
                        sectionTitle("Vegetarian plate")
                        Text(swap.note)
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Paper.chip))
                        ForEach(swap.ingredients, id: \.self) { ri in ingredientRow(ri, factor: 1) }
                    }
                    if let mild = recipe.mildNote, model.settings.anyoneNotSpicy {
                        sectionTitle("Milder")
                        Text(mild)
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Paper.chip))
                    }

                    if let credit = PhotoCredits.bundled[recipe.id] {
                        Group {
                            if let page = credit.page, let url = URL(string: page) { Link(credit.line, destination: url) } else { Text(credit.line) }
                        }
                        .font(.caption2).foregroundStyle(Paper.ink2).padding(.top, 14)
                    }
                    GatedButton(feature: .cookMode, action: { cooking = true }) {
                        Label("Cook step by step", systemImage: "play.circle").font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 16)
                    HStack {
                        sectionTitle("Directions")
                        Spacer()
                        Button(largeText ? "Smaller text" : "Bigger text") { largeText.toggle() }
                            .font(.footnote.weight(.semibold))
                            .padding(.top, 18)
                    }
                    if servings != recipe.servings {
                        Text("Amounts above are for \(servings). The steps are written for \(recipe.servings); use the amounts above.")
                            .font(.footnote)
                            .foregroundStyle(Paper.ink2)
                            .padding(.bottom, 8)
                    }
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, text in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.serif(28, relativeTo: .title3))
                                .foregroundStyle(palette.ground)
                                .frame(width: 26, alignment: .leading)
                            Text(text)
                                .font(largeText ? .title3 : .body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                    }

                    Button {
                        model.markCooked(day)
                        dismiss()
                    } label: {
                        Text("I cooked it").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(fill: palette.ground, ink: Ink.onDay))
                    .padding(.top, 20)
                }
                .foregroundStyle(Paper.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(Paper.ground))
            }
        }
        .background(alignment: .top) { palette.ground(scheme).frame(height: 600).ignoresSafeArea() }
        .background(Paper.ground)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText()) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear { servings = model.settings.householdSize }
        .fullScreenCover(isPresented: $cooking) { CookModeView(recipe: recipe, day: day) }
        .sensoryFeedback(.success, trigger: model.plan?.dinners.first { $0.day == day }?.cooked ?? false)
    }

    private func header(palette: DayPalette) -> some View {
        ZStack(alignment: .topTrailing) {
            PlateView(recipe: recipe, tint: palette.deep(scheme))
                .frame(width: 210, height: 210)
                .offset(x: 60, y: 8)
            VStack(alignment: .leading, spacing: 10) {
                Text(recipe.name)
                    .font(.serif(46, relativeTo: .title))
                    .displayTracking(46)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(recipe.minutes) min · serves \(servings)\n\(recipe.difficulty)\(recipe.vegetarian ? " · vegetarian" : "")")
                    .font(.subheadline)
                    .foregroundStyle(Ink.onDay2)
            }
            .foregroundStyle(Ink.onDay)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
        .frame(minHeight: 250, alignment: .top)
        .clipped()
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.footnote.weight(.bold))
            .foregroundStyle(Paper.ink2)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func ingredientRow(_ ri: RecipeIngredient, factor: Double) -> some View {
        let name = model.catalog.ingredients[ri.ingredient]?.name.lowercased() ?? ri.ingredient
        if recipe.source != nil {
            // Saved from a link: show the line exactly as the website wrote it.
            return AnyView(Text(ri.text).font(.subheadline).padding(.vertical, 4).fixedSize(horizontal: false, vertical: true))
        }
        return AnyView(HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(scaledText(ri, factor: factor))
                .font(.subheadline.weight(.semibold))
                .frame(width: 84, alignment: .leading)
            Text(ri.note.isEmpty ? name : "\(name), \(ri.note)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4))
    }

    /// Recipe amounts are written for the base servings. Scale them plainly.
    private func scaledText(_ ri: RecipeIngredient, factor: Double) -> String {
        guard abs(factor - 1) > 0.01 else { return ri.text }
        let parts = ri.text.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, let n = Self.parseQuantity(first) else { return "\(ri.text) ×\(Self.format(factor))" }
        let rest = parts.count > 1 ? " " + parts[1] : ""
        return Self.format(n * factor) + rest
    }

    nonisolated static func parseQuantity(_ s: String) -> Double? {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
        var whole = 0.0, frac = 0.0, digits = ""
        for c in s {
            if c.isNumber, let d = Int(String(c)) { digits.append(String(d)) }
            else if let f = fractions[c] { frac = f }
            else { return nil }
        }
        if !digits.isEmpty { whole = Double(digits) ?? 0 }
        let v = whole + frac
        return v > 0 ? v : nil
    }

    nonisolated static func format(_ v: Double) -> String {
        let whole = Int(v)
        let rest = v - Double(whole)
        let nice: [(Double, String)] = [(0, ""), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "")]
        let nearest = nice.min { abs($0.0 - rest) < abs($1.0 - rest) }!
        let w = nearest.0 == 1 ? whole + 1 : whole
        if w == 0 { return nearest.1.isEmpty ? "1" : nearest.1 }
        return "\(w)\(nearest.1)"
    }

    private func shareText() -> String {
        var s = "\(recipe.name)\n\(recipe.minutes) min · serves \(recipe.servings)\n\n"
        for ri in recipe.ingredients {
            let name = model.catalog.ingredients[ri.ingredient]?.name.lowercased() ?? ri.ingredient
            s += "• \(ri.text) \(name)\(ri.note.isEmpty ? "" : ", \(ri.note)")\n"
        }
        s += "\n"
        for (i, t) in recipe.steps.enumerated() { s += "\(i + 1). \(t)\n" }
        return s
    }
}
