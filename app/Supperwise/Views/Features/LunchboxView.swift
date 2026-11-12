import SwiftUI

/// Family: a packed lunch for each school or work day, nut-free, priced on the same whole-pack grocery list as dinner.
/// Nights cooked with leftovers turn into the next day's lunch.
struct LunchboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.todayAccent) private var accent
    @State private var draft = LunchSettings()
    @State private var editing = false

    var body: some View {
        NavigationStack {
            Group {
                if let ls = model.settings.lunch, !editing, let lp = model.lunchPlanner, let guide = LunchGuide.bundled {
                    week(ls, lp, guide)
                } else {
                    setup
                }
            }
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .navigationTitle("Lunchbox")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if model.settings.lunch != nil && !editing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Change") { draft = model.settings.lunch ?? LunchSettings(); editing = true }
                    }
                }
            }
        }
    }

    private var setup: some View {
        Form {
            Section {
                Stepper("\(draft.perDay) lunch\(draft.perDay == 1 ? "" : "es") a day", value: $draft.perDay, in: 1...8)
                Toggle("We have a thermos", isOn: $draft.thermos)
            } footer: {
                Text("Every lunch is nut-free for school. Allergies and diets from your household are always followed.")
            }
            Section("Packing days") {
                ForEach(Weekday.allCases) { d in
                    Toggle(d.name, isOn: Binding(get: { draft.days.contains(d) },
                                                 set: { on in if on { draft.days.insert(d) } else { draft.days.remove(d) } }))
                }
            }
            Section {
                Button("Plan this week's lunches") {
                    model.setLunchSettings(draft)
                    editing = false
                }
                .disabled(draft.days.isEmpty)
                if model.settings.lunch != nil {
                    Button("Stop planning lunches", role: .destructive) {
                        model.setLunchSettings(nil)
                        editing = false
                    }
                }
            }
        }
    }

    private func week(_ ls: LunchSettings, _ lp: LunchPlanner, _ guide: LunchGuide) -> some View {
        let plan = model.plan
        let leftovers = plan?.leftovers ?? []
        let dinners = Dictionary(uniqueKeysWithValues: (plan.map { model.recipes(of: $0) } ?? []).map { ($0.0, $0.1) })
        let cost = plan.map { model.cost(of: $0) }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text((cost?.lunches ?? 0).dollars).font(.serif(60)).monospacedDigit().foregroundStyle(accent)
                    Text("for \(ls.perDay * ls.days.count) lunches this week, on your grocery list with dinner.")
                        .font(.subheadline).foregroundStyle(Paper.ink2)
                }
            }
            .listRowBackground(Paper.ground)

            if plan == nil {
                Text("Make this week's dinner plan first; lunches are planned with it.").foregroundStyle(Paper.ink2)
            } else if (plan?.lunches ?? []).isEmpty {
                Text("No lunch ideas fit everyone's allergies and diets yet. Try turning on the thermos.").foregroundStyle(Paper.ink2)
            }

            ForEach(plan?.lunches ?? []) { p in
                if let l = guide.lunch(p.lunchID) {
                    Section {
                        if let night = LunchPlanner.leftoverNight(for: p.day, leftovers), let r = dinners[night] {
                            Label("\(min(2, ls.perDay)) from last night: \(r.name)", systemImage: "takeoutbag.and.cup.and.straw")
                                .foregroundStyle(Paper.ink)
                        }
                        let n = lp.boxes(p, leftovers: leftovers)
                        if n > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(l.name).font(.headline).foregroundStyle(Paper.ink)
                                    if l.thermos { Image(systemName: "flame").foregroundStyle(accent).accessibilityLabel("Hot, in a thermos") }
                                    Spacer()
                                    Text("× \(n)").monospacedDigit().foregroundStyle(Paper.ink2)
                                }
                                Text(l.ingredients.map(\.text).joined(separator: " · ")).font(.footnote).foregroundStyle(Paper.ink2)
                                Text(l.note).font(.footnote).foregroundStyle(Paper.ink)
                            }
                            Button("Swap") { model.swapLunch(p.day) }.foregroundStyle(accent)
                        }
                    } header: {
                        Text(p.day.name).font(.serif(26, relativeTo: .title2)).foregroundStyle(Paper.ink).textCase(nil)
                    }
                    .listRowBackground(Paper.raised)
                }
            }

            Section("Keeping lunches safe") {
                ForEach(guide.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Paper.ink2) }
            }
            .listRowBackground(Paper.ground)
        }
    }
}
