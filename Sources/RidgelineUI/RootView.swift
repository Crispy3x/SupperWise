#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Top-level screen for iPhone, iPad and Mac. In your Xcode app target use:
///     WindowGroup { RidgelineRootView() }
///
/// The first screen asks whether you own the business or work for it. The choice is saved, so the app stays
/// signed in until you sign out.
public struct RidgelineRootView: View {
    @State private var model = AppModel.launch()

    public init() {}

    /// The owner's setup questions show once, for a new install. An install that already has clients skips them.
    private var needsOwnerSetup: Bool {
        model.data.profile.onboardingCompletedAt == nil && model.data.customers.isEmpty && model.loadNotice == nil
    }

    /// The app only locks when a plan can actually be bought. Until the plans are on sale, an ended trial locks nothing.
    private var trialOverAndPlansOnSale: Bool {
        #if canImport(StoreKit)
        guard ScreenshotMode.shot == nil, model.purchases.isAvailable, model.data.isOwnerSession else { return false }   // employees never pay
        if case .expired = model.subscriptionState { return true }
        return false
        #else
        return false
        #endif
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
            if let shot = ScreenshotMode.shot, ScreenshotMode.standalone.contains(shot), shot != "welcome", shot != "onboarding" {
                ScreenshotMode.standaloneView(model)
            } else if model.data.session == nil {
                WelcomeRoleView()
            } else if model.data.session?.role == .owner && needsOwnerSetup {
                WelcomeFlowView()
            } else if trialOverAndPlansOnSale {
                PaywallGate()
            } else {
                MainShell()
            }
        }
        .environment(model)
        .localReminders(model)
        .teamSync(model)                                     // AppModel+TeamSync.swift: does nothing when team sync is off
        .tint(Theme.accent(model.data.profile.accentColor))
        .buttonBorderShape(.capsule)                         // the few system-style buttons match the app's rounded look
        .preferredColorScheme(colorScheme)
        .task { await model.checkAppleCredential() }
        #if canImport(StoreKit)
        .task { model.purchases.start() }
        #endif
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
                Text("Your free trial ended. Open Menu, Settings, Subscription to pick a plan. Your data stays on this device.")
                    .font(.footnote).frame(maxWidth: .infinity).padding(6).background(.orange.opacity(0.2))
            case .active:
                EmptyView()
            }
        }
    }
}
#endif
