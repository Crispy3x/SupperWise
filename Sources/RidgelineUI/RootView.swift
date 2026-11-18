#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Top-level screen for iPhone, iPad and Mac. In your Xcode app target use:
///     WindowGroup { RidgelineRootView() }
public struct RidgelineRootView: View {
    @State private var model = AppModel()

    public init() {}

    /// The welcome questions show once, for a new install. An install that already has clients skips them.
    private var needsWelcome: Bool {
        model.data.profile.onboardingCompletedAt == nil && model.data.customers.isEmpty && model.loadNotice == nil
    }

    public var body: some View {
        Group {
            if needsWelcome {
                WelcomeFlowView()
            } else {
                mainApp
            }
        }
        .environment(model)
        .tint(Theme.accent(model.data.profile.accentColor))
        .task { await model.checkAppleCredential() }
    }

    private var mainApp: some View {
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
            if let note = model.notice {
                HStack {
                    Text(note).font(.footnote)
                    Spacer()
                    Button("OK") { model.notice = nil }.font(.footnote).buttonStyle(.bordered)
                }
                .padding(8).background(.green.opacity(0.15))
            }
            SubscriptionBanner()
            TabView {
                TodayView().tabItem { Label("Today", systemImage: "snowflake") }
                StormView().tabItem { Label("Storm", systemImage: "cloud.snow") }
                ClientsHubView().tabItem { Label("Clients", systemImage: "person.2") }
                MoneyHubView().tabItem { Label("Money", systemImage: "dollarsign.circle") }
                MoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
        }
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
