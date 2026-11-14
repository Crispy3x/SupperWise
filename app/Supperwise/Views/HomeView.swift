import SwiftUI

/// Home: what Supperwise is for, tonight's dinner, money saved, and every job the app does, one tap each.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(\.todayAccent) private var accent
    @Binding var tab: Int
    @State private var sheet: HomeTool? = nil
    @State private var lockedFor: Feature? = nil
    @State private var openTonight = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    tonightCard
                    if model.stats.dinners > 0 { HomeCookingCard(stats: model.stats, accent: accent) }
                    ForEach(HomeTool.Section.allCases, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title).font(.serif(26, relativeTo: .title2)).foregroundStyle(Paper.ink)
                            Text(section.subtitle).font(.footnote).foregroundStyle(Paper.ink2)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(HomeTool.allCases.filter { $0.section == section }) { tool in
                                    Button { open(tool) } label: { ToolTile(tool: tool, locked: tool.feature.map { !subs.has($0) } ?? false) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Paper.ground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Profile and settings")
                }
            }
            .sheet(item: $sheet) { tool in toolSheet(tool) }
            .sheet(item: $lockedFor) { f in PlansSheet(need: f.tier) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $openTonight) {
                if let t = model.tonight(), let r = model.catalog.recipe(t.recipeID) { NavigationStack { RecipeView(recipe: r, day: t.day) } }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting).font(.subheadline).foregroundStyle(Paper.ink2)
            Text("Feed your family well, for less.").font(.serif(40)).foregroundStyle(Paper.ink).fixedSize(horizontal: false, vertical: true)
            Text("Supperwise plans dinners everyone can eat, shops to your budget, and helps you eat healthier at home, at school and out.")
                .font(.subheadline).foregroundStyle(Paper.ink2)
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        let name = model.prefs.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    @ViewBuilder private var tonightCard: some View {
        if let t = model.tonight(), let r = model.catalog.recipe(t.recipeID), let plan = model.plan {
            let palette = DayPalette.of(t.day)
            Button { openTonight = true } label: {
                HStack(spacing: 14) {
                    PlateView(recipe: r, rim: 4, tint: palette.deep).frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TONIGHT · \(t.day.name.uppercased())").font(.caption2.weight(.bold)).foregroundStyle(Ink.onDay2)
                        Text(r.name).font(.serif(24, relativeTo: .title3)).foregroundStyle(Ink.onDay).multilineTextAlignment(.leading)
                        Text("\(r.minutes) min · \((model.cost(of: plan).perDinner[t.day] ?? 0).dollars) for everyone").font(.footnote).foregroundStyle(Ink.onDay2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Ink.onDay2)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22).fill(palette.ground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tonight: \(r.name), \(r.minutes) minutes. Open the recipe.")
        }
    }

    private func open(_ tool: HomeTool) {
        if let f = tool.feature, !subs.has(f) { lockedFor = f; return }
        switch tool {
        case .plan: tab = 0
        case .groceries: tab = 1
        case .pantry: tab = 2
        default: sheet = tool
        }
    }

    @ViewBuilder private func toolSheet(_ tool: HomeTool) -> some View {
        switch tool {
        case .foodScan: FoodScanView()
        case .barcode: ScannerView()
        case .eatOut: EatOutView()
        case .fridge: FridgeView()
        case .lunches: LunchboxView()
        case .baby: FirstFoodsView()
        case .holiday:
            if let m = HolidayMenu.bundled.first(where: { $0.inSeason() }) ?? HolidayMenu.bundled.first { HolidayMenuView(menu: m) }
        case .recipes: RecipeBrowserView()
        case .community: CommunityView()
        case .importLink: ImportRecipeView()
        case .receipt: ReceiptView()
        case .recap: RecapView()
        case .profile: NavigationStack { ProfileView() }
        default: EmptyView()
        }
    }
}

/// Everything Supperwise does, in the order a family needs it.
enum HomeTool: String, CaseIterable, Identifiable {
    case plan, recipes, groceries, pantry, foodScan, barcode, eatOut, fridge, lunches, baby, holiday, community, importLink, receipt, recap, profile
    var id: String { rawValue }

    enum Section: CaseIterable {
        case plan, health, family, more
        var title: String {
            switch self {
            case .plan: "Plan and shop"
            case .health: "Eat healthier"
            case .family: "For the whole family"
            case .more: "More ways to save"
            }
        }
        var subtitle: String {
            switch self {
            case .plan: "Dinners that work for everyone, priced by the pack, under your budget."
            case .health: "A 1–100 score for anything you eat, checked against everyone's allergies."
            case .family: "Lunches, babies, holidays and recipes from other families."
            case .more: "See what you really spend and what you've saved."
            }
        }
    }

    var section: Section {
        switch self {
        case .plan, .recipes, .groceries, .pantry, .fridge: .plan
        case .foodScan, .barcode, .eatOut: .health
        case .lunches, .baby, .holiday, .community, .importLink: .family
        case .receipt, .recap, .profile: .more
        }
    }

    var title: String {
        switch self {
        case .plan: "This week's dinners"
        case .recipes: "All recipes"
        case .groceries: "Grocery list"
        case .pantry: "What's in my kitchen"
        case .foodScan: "Scan a meal"
        case .barcode: "Scan a barcode"
        case .eatOut: "Eating out"
        case .fridge: "Cook from my fridge"
        case .lunches: "School lunches"
        case .baby: "Baby's first foods"
        case .holiday: "Holiday menus"
        case .community: "Family recipes"
        case .importLink: "Save any recipe"
        case .receipt: "Check my receipt"
        case .recap: "My week in numbers"
        case .profile: "Tastes and favorites"
        }
    }

    var detail: String {
        switch self {
        case .plan: "A week of dinners everyone can eat"
        case .recipes: "Nearly 500 dinners to search and save"
        case .groceries: "One list, one total, under budget"
        case .pantry: "Tick what you have; it comes off the bill"
        case .foodScan: "Photo → health score and calories"
        case .barcode: "Ingredients and allergens in the aisle"
        case .eatOut: "Score restaurant dishes 1–100"
        case .fridge: "Dinners from what you already have"
        case .lunches: "Nut-free boxes on the same list"
        case .baby: "106 foods, served right for their age"
        case .holiday: "Thanksgiving and Christmas, one oven"
        case .community: "Recipes shared by other families"
        case .importLink: "Paste a link; it's priced by the pack"
        case .receipt: "What you really spent vs the plan"
        case .recap: "Dinners cooked, money saved"
        case .profile: "Cuisines you love, foods to skip"
        }
    }

    var icon: String {
        switch self {
        case .plan: "calendar"
        case .recipes: "book"
        case .groceries: "cart"
        case .pantry: "refrigerator"
        case .foodScan: "camera.metering.matrix"
        case .barcode: "barcode.viewfinder"
        case .eatOut: "fork.knife"
        case .fridge: "camera.viewfinder"
        case .lunches: "bag"
        case .baby: "figure.and.child.holdinghands"
        case .holiday: "gift"
        case .community: "person.3"
        case .importLink: "link"
        case .receipt: "doc.text.viewfinder"
        case .recap: "chart.bar"
        case .profile: "heart"
        }
    }

    /// The plan a tool needs (nil = free).
    var feature: Feature? {
        switch self {
        case .plan, .recipes, .groceries, .pantry, .profile: nil
        case .foodScan, .barcode: .scanner
        case .eatOut: .eatOut
        case .fridge: .fridge
        case .lunches: .lunchbox
        case .baby: .firstFoods
        case .holiday: .holidayMenus
        case .community, .importLink: .importRecipe
        case .receipt: .receipt
        case .recap: .recap
        }
    }

    var color: Color {
        switch section {
        case .plan: Color(hex: 0xAD321C)
        case .health: Color(hex: 0x2F6B3A)
        case .family: Color(hex: 0x5E2A4F)
        case .more: Color(hex: 0x1E4D5C)
        }
    }
}

struct ToolTile: View {
    let tool: HomeTool
    var locked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: tool.icon).font(.title2).foregroundStyle(tool.color)
                    .frame(width: 44, height: 44).background(Circle().fill(tool.color.opacity(0.12)))
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Paper.ink2)
                        .accessibilityLabel("Needs \(tool.feature?.tier.name ?? "a plan")")
                }
            }
            Text(tool.title).font(.subheadline.weight(.semibold)).foregroundStyle(Paper.ink).multilineTextAlignment(.leading)
            Text(tool.detail).font(.caption).foregroundStyle(Paper.ink2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Paper.raised))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Paper.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

extension Feature: Identifiable { var id: Feature { self } }
