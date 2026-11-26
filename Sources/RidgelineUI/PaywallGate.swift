#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Shown when the free trial is over and no plan is active. Nothing is deleted: the records stay on the device,
/// and picking a plan (or restoring one) opens the app again.
struct PaywallGate: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your free trial has ended").font(.title.bold())
                    Text(model.data.isOwnerSession
                         ? "Pick a plan to keep using Ridgeline Ops. Everything you entered is safe on this device."
                         : "Ask the business owner to pick a plan. Everything is safe on this device, and you never pay.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
                if model.data.isOwnerSession { SubscriptionView() } else { Spacer() }
                Button("Sign out") { model.signOutOfApp() }
                    .font(.callout.weight(.semibold)).padding(.vertical, 14)
            }
            .background(Look.page.ignoresSafeArea())
            .hideNavBar()
        }
    }
}
#endif
