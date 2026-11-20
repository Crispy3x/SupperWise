#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// The very first screen: are you the business owner or an employee? The answer is saved so the app does not ask again.
struct WelcomeRoleView: View {
    @Environment(AppModel.self) private var model
    @State private var ownerSheet = false
    @State private var employeeSheet = false

    var body: some View {
        ZStack {
            Look.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 24)
                    IconTile(icon: "snowflake", tint: Theme.accent(model.data.profile.accentColor), size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Ridgeline Ops").font(.largeTitle.bold())
                        Text("Routes, jobs, clients and your crew in one app for snow and landscaping businesses.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Text("Who are you?").font(.headline).padding(.top, 8)
                    RoleCard(icon: "briefcase.fill", title: "I own the business",
                             message: "Set up your business, add clients, jobs and your team. Free for \(Pricing.trialDays) days.") {
                        ownerSheet = true
                    }
                    RoleCard(icon: "person.fill", title: "I'm an employee",
                             message: "Sign in with the username and password your boss made for you, on the device your boss set up. Always free for you.") {
                        employeeSheet = true
                    }
                    Text("You stay signed in on this device until you sign out.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $ownerSheet) { OwnerAccessView() }
        .sheet(isPresented: $employeeSheet) { EmployeeSignInView() }
    }
}

private struct RoleCard: View {
    let icon: String
    let title: String
    let message: String
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                IconTile(icon: icon, tint: Theme.accent(model.data.profile.accentColor), size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold()).foregroundStyle(.primary)
                    Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Owner access: sign in with Apple, sign in or create a login with an email and password, or carry on without an account.
struct OwnerAccessView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var problem: String?
    @State private var confirmErase = false

    private var hasLogin: Bool { model.data.hasOwnerLogin }

    var body: some View {
        NavigationStack {
            Form {
                if hasLogin {
                    Section("Sign in") {
                        emailField
                        SecureField("Password", text: $password)
                        Button("Sign in") { submit { model.signIn(username: email, password: password, expecting: .owner) } }
                            .disabled(email.isEmpty || password.isEmpty)
                    }
                    Section {
                        Button("Forgot your password?", role: .destructive) { confirmErase = true }
                    } footer: {
                        Text("Passwords cannot be reset by email because your records stay on this device. You can erase this device and start again, then restore a backup file from Settings.")
                    }
                } else {
                    Section {
                        emailField
                        SecureField("Password (at least \(LoginRules.minPasswordLength) characters)", text: $password)
                        SecureField("Type the password again", text: $confirm)
                        Button("Create login") {
                            if password != confirm { problem = "The two passwords are not the same." } else {
                                submit { model.createOwnerLogin(email: email, password: password, signIn: true) }
                            }
                        }
                        .disabled(email.isEmpty || password.isEmpty || confirm.isEmpty)
                    } header: { Text("Create a login") } footer: {
                        Text("Your email is your username. Next time, sign in with it and your password.")
                    }
                }
                #if canImport(AuthenticationServices)
                Section {
                    SignInWithAppleButton(.continue, onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: handleApple)
                        .frame(height: 48)
                } header: { Text("Or use Apple") }
                #endif
                if !model.data.ownerIsProtected {
                    Section {
                        Button("Continue without an account") { submit { model.startOwnerWithoutAccount() } }
                    } footer: {
                        Text("You can add a login later in Profile. Until you do, anyone who opens the app on this device can choose \"I own the business\".")
                    }
                }
                if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle("Business owner")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Erase this device?", isPresented: $confirmErase) {
                Button("Erase everything", role: .destructive) { model.deleteAccountAndData(); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your clients, jobs, invoices, team and photos from this device. It cannot be undone.")
            }
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.username)
            #endif
    }

    private func submit(_ action: () -> String?) {
        problem = action()
        if problem == nil { dismiss() }
    }

    #if canImport(AuthenticationServices)
    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
            submit { model.ownerSignInWithApple(userID: credential.user, name: name, email: credential.email ?? "") }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { problem = "Sign in with Apple did not work. Try again, or use your email login." }
        }
    }
    #endif
}

/// An employee signs in with the username and password the owner made for them.
struct EmployeeSignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                    SecureField("Password", text: $password)
                    Button("Sign in") {
                        problem = model.signIn(username: username, password: password, expecting: .employee)
                        if problem == nil { dismiss() }
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                } footer: {
                    Text("Your boss made these for you in Menu, Team. What you can see and do in the app was chosen by your boss. Forgot your password? Ask your boss to set a new one.")
                }
                if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
                Section {
                    Text("For now, employee sign-in works on the device where your boss set up the business. Signing in from your own phone arrives with team sync.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Employee sign in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
#endif
