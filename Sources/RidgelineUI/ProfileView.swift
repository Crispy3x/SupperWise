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
            Section {
                if let email = model.data.ownerEmail {
                    LabeledContent("Login", value: email)
                    Button("Change password") { changingPassword = true }
                } else {
                    Button("Create a login (email and password)") { creatingLogin = true }
                }
                SignInSection()
            } header: {
                Text("How you sign in")
            } footer: {
                Text(model.data.ownerIsProtected
                     ? "After you sign out, the owner screen needs your login or Apple again."
                     : "Without a login, anyone who opens the app on this device can choose \"I own the business\". Add one to protect your records.")
            }
            Section("Business") {
                NavigationLink("Settings") { SettingsView().environment(\.embeddedInStack, true) }
                LabeledContent("Plan") { Text(planText) }
            }
            Section {
                Button("Delete my account and data", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Removes everything stored on this device: clients, invoices, visits, photos and the saved server token. Back up your data first in Settings. Backups you saved or shared elsewhere are not removed. On your server, client pages are removed 14 days after their last update and requests after 30 days (unless you changed your server's settings). To also remove Apple sign-in for this app, use Settings > your name > Sign in with Apple on your iPhone.")
            }
        }
        .navigationTitle("Profile")
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if mode == .create {
                        TextField("Email", text: $email).autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif
                    } else {
                        SecureField("Current password", text: $current)
                    }
                    SecureField("New password (at least \(LoginRules.minPasswordLength) characters)", text: $password)
                    SecureField("Type it again", text: $confirm)
                } footer: {
                    Text(mode == .create ? "Your email is your username. Only a scrambled copy of the password is kept on this device." : "")
                }
                if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle(mode == .create ? "Create login" : "Change password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard password == confirm else { problem = "The two passwords are not the same."; return }
                        problem = mode == .create ? model.createOwnerLogin(email: email, password: password, signIn: false)
                                                  : model.changeOwnerPassword(current: current, new: password)
                        if problem == nil { dismiss() }
                    }
                    .disabled(password.isEmpty || confirm.isEmpty || (mode == .create ? email.isEmpty : current.isEmpty))
                }
            }
        }
    }
}
#endif
