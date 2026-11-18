#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Sign in with Apple. It is optional: the app works without an account, and records stay on this device either way.
struct SignInSection: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let account = model.data.account {
                Label(account.displayName.isEmpty ? "Signed in with Apple" : "Signed in as \(account.displayName)",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                #if canImport(AuthenticationServices)
                SignInWithAppleButton(.signIn, onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: handle)
                    .frame(height: 48)
                #endif
                Text("Optional. Signing in identifies you. Your records stay on this device either way.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
    }

    #if canImport(AuthenticationServices)
    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
            message = model.signIn(appleUserID: credential.user, name: name, email: credential.email ?? "")
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                message = "Sign in did not work. You can keep using the app without an account."
            }
        }
    }
    #endif
}
#endif
