import SwiftUI

@main
struct SupperwiseApp: App {
    @State private var model = Demo.isOn ? Demo.model() : AppModel()
    @State private var subs = Subscriptions()
    @State private var account = Account()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(subs)
                .environment(account)
                .task { await subs.load() }
                .onOpenURL { url in if let problem = account.handle(url) { model.reportProblem(problem) } }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(\.scenePhase) private var phase
    @State private var tab = ["today": 0, "groceries": 1, "kitchen": 2, "lunchbox": 2, "firstfoods": 2][Demo.screen ?? ""] ?? 3
    @State private var demoSheet = ["lunchbox", "firstfoods", "plans", "scanner", "recipes", "profile", "fridge"].contains(Demo.screen ?? "") ? Demo.screen : nil

    var body: some View {
        Group {
            if !model.onboarded || model.plan == nil || (!model.seenOffer && !subs.isSubscribed) {
                OnboardingFlow()
            } else {
                TabView(selection: $tab) {
                    HomeView(tab: $tab)
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(3)
                    TodayView()
                        .tabItem { Label("Week", systemImage: "calendar") }
                        .tag(0)
                    GroceriesView()
                        .tabItem { Label("Groceries", systemImage: "cart") }
                        .tag(1)
                    KitchenView()
                        .tabItem { Label("Kitchen", systemImage: "refrigerator") }
                        .tag(2)
                }
                .tint(DayPalette.of(model.tonight()?.day ?? .wed).ground)
            }
        }
        .environment(\.todayAccent, DayPalette.of(model.tonight()?.day ?? .wed).ground)
        .sheet(isPresented: Binding(get: { demoSheet != nil && model.plan != nil }, set: { if !$0 { demoSheet = nil } })) {
            switch demoSheet ?? "" {
            case "lunchbox": LunchboxView()
            case "firstfoods": FirstFoodsView()
            case "scanner": ScannerView()
            case "recipes": RecipeBrowserView()
            case "profile": NavigationStack { ProfileView() }
            case "fridge": FridgeView()
            default: PlansSheet()
            }
        }
        .onChange(of: phase) { _, new in
            if new == .active { model.rollWeekIfNeeded() }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
