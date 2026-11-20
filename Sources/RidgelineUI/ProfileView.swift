#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Who you are, your account, your plan, and deleting everything.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var creatingLogin = false
    @State private var changingPassword = false

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
        AppPage(title: "Profile", icon: "person.crop.circle.fill") {
            Card {
                HStack(spacing: 14) {
                    AvatarView(name: model.data.account?.displayName.isEmpty == false ? model.data.account!.displayName : business, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(business).font(.title3.bold())
                        Text(model.data.account?.email.isEmpty == false ? model.data.account!.email : (model.data.account == nil ? "Not signed in" : "Signed in with Apple"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            CardGroup(title: "How you sign in",
                      footer: model.data.ownerIsProtected
                        ? "After you sign out, the owner screen needs your login or Apple again."
                        : "Without a login, anyone who opens the app on this device can choose \"I own the business\". Add one to protect your records.") {
                if let email = model.data.ownerEmail {
                    FactRow(label: "Login", value: email)
                    SecondaryActionButton(title: "Change password", icon: "key") { changingPassword = true }
                } else {
                    SecondaryActionButton(title: "Create a login (email and password)", icon: "person.badge.key") { creatingLogin = true }
                }
                RowDivider()
                SignInSection()
            }
            CardGroup(title: "Business") {
                NavigationLink { SettingsView().environment(\.embeddedInStack, true).circleBack() } label: {
                    CardLinkRow(icon: "gearshape", tint: .blue, title: "Settings")
                }
                .buttonStyle(.plain)
                RowDivider()
                FactRow(label: "Plan", value: planText)
            }
            CardGroup(footer: "Removes everything stored on this device: clients, invoices, visits, photos and the saved server token. Back up your data first in Settings. Backups you saved or shared elsewhere are not removed. On your server, client pages are removed 14 days after their last update and requests after 30 days (unless you changed your server's settings). To also remove Apple sign-in for this app, use Settings > your name > Sign in with Apple on your iPhone.") {
                PrimaryActionButton(title: "Delete my account and data", icon: "trash", destructive: true) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $creatingLogin) { OwnerLoginSheet(mode: .create) }
        .sheet(isPresented: $changingPassword) { OwnerLoginSheet(mode: .change) }
        .alert("Delete everything?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteAccountAndData(); confirmDelete = false }
            Button("Cancel", role: .cancel) { confirmDelete = false }
        } message: {
            Text("This cannot be undone. The app will start again from the welcome questions.")
        }
    }
}

/// Create the owner login after the fact, or change its password.
struct OwnerLoginSheet: View {
    enum Mode { case create, change }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var email = ""
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var problem: String?

    private var cannotSave: Bool {
        password.isEmpty || confirm.isEmpty || (mode == .create ? email.isEmpty : current.isEmpty)
    }

    private func save() {
        guard password == confirm else { problem = "The two passwords are not the same."; return }
        problem = mode == .create ? model.createOwnerLogin(email: email, password: password, signIn: false)
                                  : model.changeOwnerPassword(current: current, new: password)
        if problem == nil { dismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .create ? "Create login" : "Change password").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(footer: mode == .create ? "Your email is your username. Only a scrambled copy of the password is kept on this device." : nil) {
                    if mode == .create {
                        PillField(label: "Email", placeholder: "name@example.com", text: $email, kind: .email)
                    } else {
                        LoginSecureField(label: "Current password", placeholder: "Current password", text: $current)
                    }
                    LoginSecureField(label: "New password", placeholder: "At least \(LoginRules.minPasswordLength) characters", text: $password)
                    LoginSecureField(label: "Type it again", placeholder: "Type it again", text: $confirm)
                }
                if let problem {
                    Card { Text(problem).font(.footnote).foregroundStyle(.red) }
                }
                PrimaryActionButton(title: "Save", icon: "checkmark") { save() }
                    .disabled(cannotSave)
                    .opacity(cannotSave ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.sheet.ignoresSafeArea())
    }
}

/// A labelled password box in the same pill style as the other fields.
private struct LoginSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.title3.weight(.medium))
            SecureField(placeholder, text: $text)
                .font(.title3)
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
        }
    }
}
#endif
