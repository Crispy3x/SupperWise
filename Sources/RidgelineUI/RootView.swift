#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Top-level screen for iPhone, iPad and Mac. In your Xcode app target use:
///     WindowGroup { RidgelineRootView() }
///
/// The first screen asks whether you own the business or work for it. The choice is saved, so the app stays
/// signed in until you sign out.
public struct RidgelineRootView: View {
    @State private var model = AppModel()

    public init() {}

    /// The owner's setup questions show once, for a new install. An install that already has clients skips them.
    private var needsOwnerSetup: Bool {
        model.data.profile.onboardingCompletedAt == nil && model.data.customers.isEmpty && model.loadNotice == nil
    }

    private var colorScheme: ColorScheme? {
        switch model.data.profile.appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

    public var body: some View {
        Group {
            if model.data.session == nil {
                WelcomeRoleView()
            } else if model.data.session?.role == .owner && needsOwnerSetup {
                WelcomeFlowView()
            } else {
                MainShell()
            }
        }
        .environment(model)
        .tint(Theme.accent(model.data.profile.accentColor))
        .preferredColorScheme(colorScheme)
        .task { await model.checkAppleCredential() }
    }
}

struct SubscriptionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Employees never pay, so they never see plan messages.
        if model.data.isOwnerSession {
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
}
#endif
