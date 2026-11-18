#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Top-level screen for iPhone, iPad and Mac. In your Xcode app target use:
///     WindowGroup { RidgelineRootView() }
public struct RidgelineRootView: View {
    @State private var model = AppModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let notice = model.loadNotice {
                VStack(spacing: 4) {
                    Text(notice).font(.footnote)
                    if !model.savingIsBlocked {
                        Button("Dismiss") { model.dismissLoadNotice() }.font(.footnote).buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity).padding(6).background(.red.opacity(0.2))
            }
            if let problem = model.saveError {
                Text(problem)
                    .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.red.opacity(0.2))
            }
            SubscriptionBanner()
            TabView {
                Group {
                    TodayView().tabItem { Label("Crew", systemImage: "snowflake") }
                    StormView().tabItem { Label("Storm", systemImage: "cloud.snow") }
                    CustomersView().tabItem { Label("Customers", systemImage: "person.2") }
                    QuotesView().tabItem { Label("Quotes", systemImage: "text.badge.plus") }
                    InvoicesView().tabItem { Label("Invoices", systemImage: "doc.text") }
                }
                Group {
                    RoutesView().tabItem { Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                    TimeClockView().tabItem { Label("Time clock", systemImage: "clock") }
                    ReportsView().tabItem { Label("Job costs", systemImage: "chart.bar") }
                    ProofView().tabItem { Label("Proof", systemImage: "checkmark.seal") }
                    PricingCalculatorView().tabItem { Label("Plans", systemImage: "dollarsign.circle") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .environment(model)
    }
}

struct SubscriptionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.subscriptionState {
        case .trial(let days):
            Text("Free trial: \(days) day\(days == 1 ? "" : "s") left. All features unlocked.")
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.blue.opacity(0.15))
        case .expired:
            Text("Trial ended. Buying a plan is not connected in this build yet, so nothing is locked. Your data stays on this device.")
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.orange.opacity(0.2))
        case .active:
            EmptyView()
        }
    }
}
#endif
