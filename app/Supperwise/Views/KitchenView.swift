import SwiftUI

/// The pantry: tick what you already have and it comes off this week's bill, and stays off.
struct KitchenView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.todayAccent) private var accent
    @State private var query = ""
    @State private var showFridge = false
    @State private var showImport = false
    @State private var showScanner = false
    @State private var holiday: HolidayMenu? = nil
    @State private var showFirstFoods = false
    @State private var showLunchbox = false
    @State private var showFoodScan = false
    @State private var showCommunity = false
    private var menus: [HolidayMenu] { HolidayMenu.bundled }

    var body: some View {
        NavigationStack {
            let saved = savings()
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(saved.dollars)
                            .font(.serif(60))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        Text("off this week's list, from what you already have.")
                            .font(.subheadline)
                            .foregroundStyle(Paper.ink2)
                    }
                    .listRowBackground(Paper.ground)
                }
                if model.stats.dinners > 0 {
                    Section {
                        HomeCookingCard(stats: model.stats, accent: accent)
                    }
                    .listRowBackground(Paper.ground)
                }
                Section {
                    GatedButton(feature: .fridge, action: { showFridge = true }) { Label("What can I cook tonight?", systemImage: "camera.viewfinder") }
                    GatedButton(feature: .scanner, action: { showFoodScan = true }) { Label("Scan food: score and calories", systemImage: "camera.metering.matrix") }
                    GatedButton(feature: .scanner, action: { showScanner = true }) { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                    GatedButton(feature: .importRecipe, action: { showCommunity = true }) { Label("Community recipes", systemImage: "person.3") }
                    GatedButton(feature: .importRecipe, action: { showImport = true }) { Label("Save a recipe from a link", systemImage: "link") }
                    GatedButton(feature: .lunchbox, action: { showLunchbox = true }) { Label("Plan school lunches", systemImage: "bag") }
                    GatedButton(feature: .firstFoods, action: { showFirstFoods = true }) { Label("First foods for baby", systemImage: "figure.and.child.holdinghands") }
                    ForEach(menus, id: \.id) { m in
                        GatedButton(feature: .holidayMenus, action: { holiday = m }) { Label("\(m.name) menu and timeline", systemImage: "fork.knife") }
                    }
                }
                .foregroundStyle(accent)
                .listRowBackground(Paper.ground)
                ForEach([Aisle.staples, .spices, .cans, .dry, .dairy, .produce, .frozen, .bakery], id: \.self) { aisle in
                    let items = model.catalog.ingredients.values
                        .filter { $0.aisle == aisle && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
                        .sorted { $0.name < $1.name }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { ing in
                                let have = model.inKitchen.contains(ing.id)
                                Button {
                                    model.setInKitchen(ing.id, !have)
                                } label: {
                                    HStack {
                                        Image(systemName: have ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(have ? accent : Paper.ink2)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ing.name).foregroundStyle(Paper.ink)
                                            Text(ing.packLabel).font(.footnote).foregroundStyle(Paper.ink2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Paper.ground)
                                .accessibilityAddTraits(have ? .isSelected : [])
                            }
                        } header: {
                            Text(aisle.title)
                                .font(.serif(28, relativeTo: .title2))
                                .foregroundStyle(Paper.ink)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .searchable(text: $query, prompt: "Search any ingredient")
            .navigationTitle("Kitchen")
            .sheet(isPresented: $showFridge) { FridgeView() }
            .sheet(isPresented: $showImport) { ImportRecipeView() }
            .sheet(isPresented: $showScanner) { ScannerView() }
            .sheet(isPresented: $showFirstFoods) { FirstFoodsView() }
            .sheet(isPresented: $showLunchbox) { LunchboxView() }
            .sheet(isPresented: $showFoodScan) { FoodScanView() }
            .sheet(isPresented: $showCommunity) { CommunityView() }
            .sheet(item: $holiday) { HolidayMenuView(menu: $0) }
        }
    }

    /// What this week's list would cost if nothing were ticked, minus what it costs now.
    private func savings() -> Double {
        guard let plan = model.plan else { return 0 }
        let none = model.cost(of: plan, ignoringKitchen: true).total
        let now = model.cost(of: plan).total
        return max(0, none - now)
    }
}
