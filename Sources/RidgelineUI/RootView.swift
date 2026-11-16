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
            SubscriptionBanner()
            TabView {
                TodayView().tabItem { Label("Crew", systemImage: "snowflake") }
                StormView().tabItem { Label("Storm", systemImage: "cloud.snow") }
                CustomersView().tabItem { Label("Customers", systemImage: "person.2") }
                InvoicesView().tabItem { Label("Invoices", systemImage: "doc.text") }
                ProofView().tabItem { Label("Proof", systemImage: "checkmark.seal") }
                PricingCalculatorView().tabItem { Label("Plans", systemImage: "dollarsign.circle") }
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
            Text("Trial ended. Pick a plan to keep editing. Your data is safe and exportable.")
                .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.orange.opacity(0.2))
        case .active:
            EmptyView()
        }
    }
}
#endif
