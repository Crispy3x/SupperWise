import SwiftUI

/// Plus and up: Thanksgiving for your guests. Menu, a cooking timeline back from dinner time, and one priced list.
struct HolidayMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let menu: HolidayMenu
    @State private var guests = 8
    @State private var vegetarians = 0
    @State private var dinner: Date
    @State private var tab = 0
    @State private var openDish: HolidayMenu.Dish? = nil
    @State private var bought: Set<String> = []

    init(menu: HolidayMenu) {
        self.menu = menu
        _dinner = State(initialValue: menu.defaultDinner)
    }

    var plan: HolidayPlan { HolidayPlan(menu: menu, guests: guests, vegetarians: min(vegetarians, guests), dinner: dinner) }

    var body: some View {
        NavigationStack {
            let p = plan
            let lines = p.groceries(catalog: model.catalog, inKitchen: model.inKitchen, multiplier: model.settings.price.multiplier * model.storeAdjust)
            let total = lines.reduce(0) { $0 + $1.cost }
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(menu.name) for \(guests)").font(.serif(40)).displayTracking(40)
                        Text("\(total.dollars) for everything, about \((total / Double(max(guests, 1))).dollars) a guest. Prices are estimates for your store.")
                            .font(.subheadline).foregroundStyle(Paper.ink2)
                    }
                    Stepper("Guests: \(guests)", value: $guests, in: 2...30)
                    Stepper("Vegetarian guests: \(min(vegetarians, guests))", value: $vegetarians, in: 0...guests)
                    DatePicker("Dinner", selection: $dinner)
                    if p.meatEaters > 0 {
                        Text(menu.main.kind == "ham"
                             ? "Ham: about \(Int(p.mainPounds)) lb, bone-in, fully cooked. No thawing needed if you buy it chilled."
                             : "Turkey: about \(Int(p.mainPounds)) lb. Start thawing it in the fridge \(HolidayPlan.thawDays(pounds: p.mainPounds)) days ahead.")
                            .font(.footnote).foregroundStyle(Paper.ink2)
                    }
                    Picker("View", selection: $tab) {
                        Text("Menu").tag(0)
                        Text("Timeline").tag(1)
                        Text("Shopping").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Paper.ground)

                switch tab {
                case 0:
                    Section("On the table") {
                        ForEach(p.dishes) { d in
                            Button { openDish = d } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name).font(.headline)
                                        Text("\(d.course.capitalized) · for \(p.eaters(d))\(d.vegetarian ? " · vegetarian" : "")").font(.caption).foregroundStyle(Paper.ink2)
                                        if let clash = conflicts(d) { Text(clash).font(.caption.weight(.semibold)).foregroundStyle(Color(hex: 0xB3261E)) }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Paper.ink2)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Paper.ground)
                        }
                    }
                case 1:
                    Section("Cooking timeline") {
                        ForEach(p.timeline) { s in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(stamp(s.at)).font(.footnote.weight(.semibold)).monospacedDigit().frame(width: 92, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.text).font(.subheadline)
                                    if !s.dish.isEmpty { Text(s.dish).font(.caption).foregroundStyle(Paper.ink2) }
                                }
                            }
                            .listRowBackground(Paper.ground)
                        }
                    }
                default:
                    Section("Shopping, by the pack") {
                        ForEach(lines.filter { !$0.inKitchen }) { l in
                            GroceryRow(line: l, bought: bought.contains(l.id)) {
                                if bought.contains(l.id) { bought.remove(l.id) } else { bought.insert(l.id) }
                            }
                            .listRowBackground(Paper.ground)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .foregroundStyle(Paper.ink)
            .navigationTitle(menu.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $openDish) { HolidayDishView(dish: $0, eaters: plan.eaters($0), mainIngredient: menu.main.ingredient, mainPounds: plan.mainPounds) }
        }
    }

    /// Flags a dish if anyone in the household avoids one of its allergens (guests' own needs aren't known).
    private func conflicts(_ d: HolidayMenu.Dish) -> String? {
        let hits = model.settings.people.compactMap { p -> String? in
            let a = Set(d.allergens).intersection(p.avoids)
            return a.isEmpty ? nil : "\(p.name) avoids \(a.map { $0.label.replacingOccurrences(of: "No ", with: "") }.sorted().joined(separator: ", "))"
        }
        return hits.isEmpty ? nil : hits.joined(separator: "; ")
    }

    private func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: dinner)).day ?? 0
        let time = d.formatted(date: .omitted, time: .shortened)
        switch days {
        case 0: return time
        case 1: return "Day before\n\(time)"
        default: return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

struct HolidayDishView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dish: HolidayMenu.Dish
    let eaters: Int
    let mainIngredient: String
    let mainPounds: Double

    var body: some View {
        NavigationStack {
            List {
                Section("For \(eaters)") {
                    ForEach(dish.ingredients, id: \.self) { ri in
                        let name = model.catalog.ingredients[ri.ingredient]?.name.lowercased() ?? ri.ingredient
                        let amount = ri.ingredient == mainIngredient
                            ? "\(Int(mainPounds)) lb"
                            : (dish.servings == eaters ? ri.text : "\(ri.text) ×\(String(format: "%.2g", Double(eaters) / Double(max(dish.servings, 1))))")
                        HStack(alignment: .firstTextBaseline) {
                            Text(amount).bold().frame(width: 110, alignment: .leading)
                            Text(ri.note.isEmpty ? name : "\(name), \(ri.note)")
                        }
                        .font(.subheadline)
                    }
                }
                Section("Steps") {
                    ForEach(Array(dish.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.serif(24)).foregroundStyle(Color(hex: 0xAD321C))
                            Text(s).font(.body)
                        }
                    }
                }
                if dish.id == "tg_turkey" || dish.id == "xm_ham" {
                    Section {
                        Text(dish.id == "xm_ham"
                             ? "Food safety (USDA): reheat fully cooked ham to 140°F. Refrigerate leftovers within 2 hours and eat them within 3 to 5 days."
                             : "Food safety (USDA): thaw in the fridge, never on the counter. Cook to 165°F in the thickest part of the thigh, the wing and the breast. Refrigerate leftovers within 2 hours.")
                            .font(.footnote).foregroundStyle(Paper.ink2)
                    }
                }
            }
            .navigationTitle(dish.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
