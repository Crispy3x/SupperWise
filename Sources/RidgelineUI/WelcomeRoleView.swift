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
        VStack(spacing: 0) {
            HStack {
                Text("Business owner").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if hasLogin {
                    CardGroup(title: "Sign in") {
                        emailField
                        WelcomeSecureField(label: "Password", placeholder: "Password", text: $password)
                        PrimaryActionButton(title: "Sign in") { submit { model.signIn(username: email, password: password, expecting: .owner) } }
                            .disabled(email.isEmpty || password.isEmpty)
                            .opacity(email.isEmpty || password.isEmpty ? 0.4 : 1)
                    }
                    CardGroup(footer: "Passwords cannot be reset by email because your records stay on this device. You can erase this device and start again, then restore a backup file from Settings.") {
                        SecondaryActionButton(title: "Forgot your password?") { confirmErase = true }
                    }
                } else {
                    CardGroup(title: "Create a login", footer: "Your email is your username. Next time, sign in with it and your password.") {
                        emailField
                        WelcomeSecureField(label: "Password", placeholder: "At least \(LoginRules.minPasswordLength) characters", text: $password)
                        WelcomeSecureField(label: "Type the password again", placeholder: "Type it again", text: $confirm)
                        PrimaryActionButton(title: "Create login") {
                            if password != confirm { problem = "The two passwords are not the same." } else {
                                submit { model.createOwnerLogin(email: email, password: password, signIn: true) }
                            }
                        }
                        .disabled(email.isEmpty || password.isEmpty || confirm.isEmpty)
                        .opacity(email.isEmpty || password.isEmpty || confirm.isEmpty ? 0.4 : 1)
                    }
                }
                #if canImport(AuthenticationServices)
                CardGroup(title: "Or use Apple") {
                    SignInWithAppleButton(.continue, onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: handleApple)
                        .frame(height: 52)
                }
                #endif
                if !model.data.ownerIsProtected {
                    CardGroup(footer: "You can add a login later in Profile. Until you do, anyone who opens the app on this device can choose \"I own the business\".") {
                        SecondaryActionButton(title: "Continue without an account") { submit { model.startOwnerWithoutAccount() } }
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .alert("Erase this device?", isPresented: $confirmErase) {
            Button("Erase everything", role: .destructive) { model.deleteAccountAndData(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your clients, jobs, invoices, team and photos from this device. It cannot be undone.")
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Email").font(.title3.weight(.medium))
            TextField("name@company.com", text: $email)
                .font(.title3)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                #endif
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
        }
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

    private var canSignIn: Bool { !username.isEmpty && !password.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Employee sign in").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(footer: "Your boss made these for you in Menu, Team. What you can see and do in the app was chosen by your boss. Forgot your password? Ask your boss to set a new one.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Username").font(.title3.weight(.medium))
                        TextField("Username", text: $username)
                            .font(.title3)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .textContentType(.username)
                            #endif
                            .padding(.horizontal, 22).padding(.vertical, 16)
                            .background(Look.field, in: Capsule())
                            .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                    }
                    WelcomeSecureField(label: "Password", placeholder: "Password", text: $password)
                    PrimaryActionButton(title: "Sign in") {
                        problem = model.signIn(username: username, password: password, expecting: .employee)
                        if problem == nil { dismiss() }
                    }
                    .disabled(!canSignIn)
                    .opacity(canSignIn ? 1 : 0.4)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
                Text("For now, employee sign-in works on the device where your boss set up the business. Signing in from your own phone arrives with team sync.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}

/// A labelled password box in the same pill style as the other fields.
private struct WelcomeSecureField: View {
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
