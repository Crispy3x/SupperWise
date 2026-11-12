import SwiftUI

/// Family: 100+ first foods, how to serve each at the baby's age, a log of what's been tried, and the common allergens.
struct FirstFoodsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var category = "all"
    @State private var logging: FirstFoodsGuide.Food? = nil
    @State private var setup = false
    private var guide: FirstFoodsGuide? { FirstFoodsGuide.bundled }

    var body: some View {
        NavigationStack {
            Group {
                if let guide, let baby = model.baby {
                    content(guide, baby)
                } else {
                    BabySetup(onDone: {})   // stay in First foods after setting up
                }
            }
            .background(Paper.ground)
            .navigationTitle("First foods")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if model.baby != nil { ToolbarItem(placement: .topBarLeading) { Button("Baby") { setup = true } } }
            }
            .sheet(item: $logging) { LogFoodSheet(food: $0) }
            .sheet(isPresented: $setup) { NavigationStack { BabySetup() } }
        }
    }

    private func content(_ guide: FirstFoodsGuide, _ baby: BabyProfile) -> some View {
        let months = baby.months()
        let tried = model.triedFoods
        let triedAllergens = Set(guide.foods.filter { tried.contains($0.id) }.compactMap(\.allergen))
        let shown = guide.foods.filter { category == "all" || $0.category == category || (category == "allergen" && $0.allergen != nil) }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(tried.count) of \(guide.foods.count)").font(.serif(60)).foregroundStyle(Color(hex: 0xAD321C)).monospacedDigit()
                    Text("foods \(baby.name) has tried · \(months) months old").font(.subheadline).foregroundStyle(Paper.ink2)
                    ProgressView(value: Double(tried.count), total: Double(guide.foods.count)).tint(Color(hex: 0xAD321C))
                }
            }
            .listRowBackground(Paper.ground)

            Section("Common allergens") {
                WrapLayout(spacing: 8) {
                    ForEach(guide.allergens, id: \.self) { a in
                        let done = triedAllergens.contains(a)
                        Text((done ? "✓ " : "") + a.capitalized)
                            .font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(done ? Color(hex: 0x2F6B3A) : Paper.chip))
                            .foregroundStyle(done ? Paper.ground : Paper.ink)
                    }
                }
                Text("One new allergen at a time, and keep offering it a few times a week once it's tolerated.")
                    .font(.footnote).foregroundStyle(Paper.ink2)
            }
            .listRowBackground(Paper.ground)

            Section {
                Picker("Show", selection: $category) {
                    Text("All").tag("all")
                    Text("Allergens").tag("allergen")
                    ForEach(["veg", "fruit", "protein", "grain", "dairy"], id: \.self) { Text(FirstFoodsGuide.categoryTitles[$0] ?? $0).tag($0) }
                }
                ForEach(shown) { f in
                    Button { logging = f } label: { FoodRow(food: f, months: months, entry: model.lastLog(f.id)) }
                        .buttonStyle(.plain)
                }
            }
            .listRowBackground(Paper.ground)

            Section("Good to know") {
                ForEach(guide.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Paper.ink2) }
                Text("This is general information, not medical advice. Follow your pediatrician's guidance for your baby.")
                    .font(.footnote.weight(.semibold))
            }
            .listRowBackground(Paper.ground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .foregroundStyle(Paper.ink)
    }
}

struct FoodRow: View {
    let food: FirstFoodsGuide.Food
    let months: Int
    let entry: FoodLogEntry?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry == nil ? "circle" : (entry?.reaction == .reaction ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                .foregroundStyle(entry?.reaction == .reaction ? Color(hex: 0xB3261E) : (entry == nil ? Paper.ink2 : Color(hex: 0x2F6B3A)))
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(food.name).font(.headline)
                    if let a = food.allergen { Text(a.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Color(hex: 0xB26B00)) }
                }
                if months < food.fromMonths {
                    Text("From \(food.fromMonths) months. \(food.serve6)").font(.footnote).foregroundStyle(Color(hex: 0xB3261E))
                } else {
                    Text(months < 9 ? food.serve6 : food.serve9).font(.footnote).foregroundStyle(Paper.ink2)
                }
                if let e = entry {
                    Text("\(e.reaction.label) · \(e.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Paper.ink2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LogFoodSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let food: FirstFoodsGuide.Food
    @State private var reaction: Reaction = .liked
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(food.serve6).font(.subheadline)
                    if food.serve9 != food.serve6 { Text("From 9 months: \(food.serve9)").font(.subheadline).foregroundStyle(Paper.ink2) }
                }
                Section("Log it") {
                    DatePicker("Tried on", selection: $date, displayedComponents: .date)
                    Picker("How it went", selection: $reaction) { ForEach(Reaction.allCases) { Text($0.label).tag($0) } }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }
                if reaction == .reaction {
                    Section {
                        Text("Call 911 for trouble breathing, swelling of the lips or face, repeated vomiting, or floppiness. For a mild rash, stop the food and talk to your pediatrician before offering it again.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: 0xB3261E))
                    }
                }
                let history = model.foodLog.filter { $0.foodID == food.id }
                if !history.isEmpty {
                    Section("History") {
                        ForEach(history) { e in
                            Text("\(e.date.formatted(date: .abbreviated, time: .omitted)) · \(e.reaction.label)\(e.note.isEmpty ? "" : " · \(e.note)")").font(.footnote)
                                .swipeActions { Button("Delete", role: .destructive) { model.removeFoodLog(e.id) } }
                        }
                    }
                }
            }
            .navigationTitle(food.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.logFood(FoodLogEntry(foodID: food.id, date: date, reaction: reaction, note: note)); dismiss() }
                }
            }
        }
    }
}

struct BabySetup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// When shown inline (not in its own sheet), the caller keeps the screen open instead of dismissing.
    var onDone: (() -> Void)? = nil
    private func finish() { if let onDone { onDone() } else { dismiss() } }
    @State private var name = ""
    @State private var birth = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now

    var body: some View {
        Form {
            Section {
                Text("Track the foods your baby tries, see how to serve each one at their age, and get a version of tonight's dinner for them.")
                    .font(.subheadline).foregroundStyle(Paper.ink2)
                TextField("Baby's name", text: $name)
                DatePicker("Birthday", selection: $birth, in: ...Date.now, displayedComponents: .date)
            }
            Section {
                Button(model.baby == nil ? "Start" : "Save") {
                    model.setBaby(BabyProfile(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Baby" : name, birthDate: birth))
                    finish()
                }
                if model.baby != nil {
                    Button("Remove baby and log", role: .destructive) { model.setBaby(nil); finish() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { if let b = model.baby { name = b.name; birth = b.birthDate } }
    }
}

/// On the Week screen: how to serve tonight's dinner to the baby.
struct BabyTonightCard: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    let baby: BabyProfile

    var body: some View {
        let guide = FirstFoodsGuide.bundled
        let tried = Set((guide?.foods ?? []).filter { model.triedFoods.contains($0.id) }.compactMap(\.allergen))
        VStack(alignment: .leading, spacing: 6) {
            Text("For \(baby.name) tonight").font(.footnote.weight(.bold))
            ForEach(BabyAdvice.tonight(recipe: recipe, baby: baby, triedAllergens: tried, catalog: model.catalog), id: \.self) { line in
                Text("• " + line).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.2)))
        .foregroundStyle(Ink.onDay)
    }
}
