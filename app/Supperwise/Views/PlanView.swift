import SwiftUI

/// Next week's settings: budget, cook nights, who's eating, the kitchen. Then build it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.todayAccent) private var accent
    @State private var showPaywall = false
    @State private var editing: Person? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HouseholdForm(editing: $editing)
                    if let next = model.nextPlan {
                        NextWeekPreview(plan: next)
                    }
                    Button {
                        if subs.has(.nextWeek) { model.makeNextWeek() } else { showPaywall = true }
                    } label: {
                        Text(model.nextPlan == nil ? "Plan next week" : "Plan it again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(fill: accent, ink: Ink.onDay))
                }
                .padding(22)
            }
            .background(Paper.ground)
            .foregroundStyle(Paper.ink)
            .navigationTitle("Next week")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPaywall) { PlansSheet(need: .plus) { model.makeNextWeek() } }
            .sheet(item: $editing) { p in PersonEditor(person: p) }
        }
    }
}

/// The settings that shape every plan. Shared by onboarding and Plan.
struct HouseholdForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.todayAccent) private var accent
    @Binding var editing: Person?

    var body: some View {
        let s = model.settings
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                label("Grocery budget")
                HStack(alignment: .bottom) {
                    Text(s.budget, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.serif(92))
                        .displayTracking(92)
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    OnionGlyph(color: accent, ground: Paper.ground).frame(width: 52, height: 52).padding(.bottom, 12)
                }
                Slider(value: Binding(get: { s.budget }, set: { v in model.updateSettings { $0.budget = v.rounded() } }), in: 40...300, step: 5)
                    .tint(accent)
                Toggle("Just build the cheapest week", isOn: Binding(get: { s.cheapestWeek }, set: { v in model.updateSettings { $0.cheapestWeek = v } }))
                    .font(.subheadline)
                    .tint(accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Cook nights")
                HStack(spacing: 8) {
                    ForEach(Weekday.allCases) { d in
                        let on = s.cookNights.contains(d)
                        Button {
                            model.updateSettings { if on { $0.cookNights.remove(d) } else { $0.cookNights.insert(d) } }
                        } label: {
                            Text(d.short)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 42, height: 42)
                                .foregroundStyle(on ? Ink.onDay : Paper.ink2)
                                .background(Circle().fill(on ? DayPalette.of(d).ground : .clear))
                                .overlay(Circle().strokeBorder(on ? .clear : Paper.rule, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(d.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text("\(s.cookNights.count) dinners a week")
                    .font(.footnote).foregroundStyle(Paper.ink2)
            }

            VStack(alignment: .leading, spacing: 0) {
                label("Who's eating")
                ForEach(s.people) { p in
                    Button { editing = p } label: {
                        HStack {
                            Text(p.name).font(.headline)
                            if let age = p.age { Text("\(age)").foregroundStyle(Paper.ink2) }
                            Spacer()
                            ForEach(tags(p), id: \.self) { t in
                                Text(t).font(.footnote)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Paper.chip))
                            }
                            if tags(p).isEmpty { Text("Eats everything").font(.footnote).foregroundStyle(Paper.ink2) }
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Paper.rule)
                }
                Button {
                    let p = Person(name: "")
                    model.updateSettings { $0.people.append(p) }
                    editing = p
                } label: {
                    Label("Add someone", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(accent)
                .padding(.top, 12)
                if s.people.count > 1 {
                    Text("Every dinner works for everyone. Vegetarians get a written vegetarian plate when a dish has meat. Dishes with an allergen someone avoids are left out. Always check labels.")
                        .font(.footnote).foregroundStyle(Paper.ink2).padding(.top, 8)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                label("Your kitchen")
                FlowChips(items: Equipment.allCases.map { e in (e.label, s.equipment.contains(e)) }) { i in
                    let e = Equipment.allCases[i]
                    model.updateSettings { if $0.equipment.contains(e) { $0.equipment.remove(e) } else { $0.equipment.insert(e) } }
                }
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
    }

    private func tags(_ p: Person) -> [String] {
        var t: [String] = []
        if p.diet != .everything { t.append(p.diet.label) }
        t += p.avoids.sorted { $0.rawValue < $1.rawValue }.map(\.label)
        if p.notSpicy { t.append("Not spicy") }
        return t
    }
}

/// Chips that wrap onto new lines.
struct FlowChips: View {
    let items: [(String, Bool)]
    let tap: (Int) -> Void

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button { tap(i) } label: {
                    Text(item.0)
                        .font(.subheadline)
                        .strikethrough(!item.1)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(item.1 ? Paper.ground : Paper.ink2)
                        .background(Capsule().fill(item.1 ? Paper.ink : .clear))
                        .overlay(Capsule().strokeBorder(item.1 ? .clear : Paper.rule, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.1 ? .isSelected : [])
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

struct PersonEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var person: Person

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $person.name)
                Picker("Age", selection: Binding(get: { person.age ?? 0 }, set: { person.age = $0 == 0 ? nil : $0 })) {
                    Text("Adult").tag(0)
                    ForEach(1..<18, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Eats", selection: $person.diet) {
                    ForEach(Diet.allCases) { Text($0.label).tag($0) }
                }
                Section("Never serve") {
                    ForEach(Allergen.allCases) { a in
                        Toggle(a.label, isOn: Binding(get: { person.avoids.contains(a) }, set: { on in
                            if on { person.avoids.insert(a) } else { person.avoids.remove(a) }
                        }))
                    }
                }
                Toggle("Not spicy", isOn: $person.notSpicy)
                Section {
                    Button("Remove \(person.name.isEmpty ? "this person" : person.name)", role: .destructive) {
                        model.updateSettings { $0.people.removeAll { $0.id == person.id } }
                        dismiss()
                    }
                }
            }
            .navigationTitle(person.name.isEmpty ? "Someone new" : person.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if person.name.trimmingCharacters(in: .whitespaces).isEmpty { person.name = "Someone" }
                        model.updateSettings { s in
                            if let i = s.people.firstIndex(where: { $0.id == person.id }) { s.people[i] = person }
                            else { s.people.append(person) }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NextWeekPreview: View {
    @Environment(AppModel.self) private var model
    let plan: WeekPlan

    var body: some View {
        let cost = model.cost(of: plan)
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready for Monday · \(cost.total.dollars)")
                .font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
            ForEach(Array(model.recipes(of: plan).enumerated()), id: \.offset) { _, pair in
                let (day, r) = pair
                HStack(spacing: 12) {
                    PlateView(recipe: r, rim: 0, tint: DayPalette.of(day).ground).frame(width: 40, height: 40)
                    Text(day.abbreviation).font(.footnote.weight(.semibold)).foregroundStyle(Paper.ink2).frame(width: 32, alignment: .leading)
                    Text(r.name).font(.subheadline)
                }
            }
        }
    }
}
