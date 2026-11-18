#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Who you are, your account, your plan, and deleting everything.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    private var business: String {
        let n = model.data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Your business" : n
    }

    private var planText: String {
        switch model.subscriptionState {
        case .trial(let days): return "Free trial, \(days) day\(days == 1 ? "" : "s") left"
        case .active(let tier): return tier == .pro ? "Pro" : "Max"
        case .expired: return "Trial ended"
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AvatarView(name: model.data.account?.displayName.isEmpty == false ? model.data.account!.displayName : business, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(business).font(.title3.bold())
                        Text(model.data.account?.email.isEmpty == false ? model.data.account!.email : (model.data.account == nil ? "Not signed in" : "Signed in with Apple"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Account") {
                SignInSection()
                if model.data.account != nil {
                    Button("Sign out") { model.signOut() }
                }
            }
            Section("Business") {
                NavigationLink("Settings") { SettingsView().environment(\.embeddedInStack, true) }
                LabeledContent("Plan") { Text(planText) }
            }
            Section {
                Button("Delete my account and data", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Removes everything stored on this device: clients, invoices, visits, photos and the saved server token. Back up your data first in Settings. Client pages and requests on your server expire on their own within 14 to 30 days. To also remove Apple sign-in for this app, use Settings > your name > Sign in with Apple on your iPhone.")
            }
        }
        .navigationTitle("Profile")
        .alert("Delete everything?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteAccountAndData(); confirmDelete = false }
            Button("Cancel", role: .cancel) { confirmDelete = false }
        } message: {
            Text("This cannot be undone. The app will start again from the welcome questions.")
        }
    }
}
#endif
