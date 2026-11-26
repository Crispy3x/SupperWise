#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The owner's "Team logins on their own phones" card, on the Team screen and in Settings. Hidden when the app was
/// built without team sync, so the app looks exactly as before.
struct TeamSyncCard: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var working = false
    @State private var prefilled = false

    private var visible: Bool {
        model.teamSyncAvailable && model.data.isOwnerSession && !model.previewingEmployee && (model.data.teamSync?.isOwner ?? true)
    }

    var body: some View {
        if visible {
            CardGroup(title: "Team logins on their own phones", footer: model.data.teamSync == nil
                      ? "You still make each person's username and password in Team. Their phones only get the jobs and clients you allow."
                      : nil) {
                if model.data.teamSync == nil {
                    turnOnForm
                } else if !model.teamSyncRuntime.signedIn && !model.teamSyncRuntime.busy {
                    signInAgainForm
                } else {
                    status
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
            }
            .onAppear {
                guard !prefilled else { return }
                prefilled = true
                let account = model.data.account?.email ?? ""
                email = model.data.teamSync?.login ?? model.data.ownerEmail ?? (account.isEmpty ? "" : account)
            }
        }
    }

    @ViewBuilder private var turnOnForm: some View {
        Text("Let your team sign in on their own phones. Jobs, clients, visits and hours stay in sync through the cloud.")
            .font(.callout).foregroundStyle(.secondary)
        PillField(label: "Your email", placeholder: "name@company.com", text: $email, kind: .email)
        TeamSyncPasswordField(label: "Password", placeholder: "At least \(LoginRules.minPasswordLength) characters", text: $password)
        PrimaryActionButton(title: working ? "Turning on…" : "Turn on", icon: "icloud") { submit() }
            .disabled(working || email.isEmpty || password.isEmpty)
            .opacity(working || email.isEmpty || password.isEmpty ? 0.4 : 1)
    }

    @ViewBuilder private var signInAgainForm: some View {
        Text("Team sync is paused on this phone. Sign in again to keep your team up to date.")
            .font(.callout).foregroundStyle(.secondary)
        PillField(label: "Email", placeholder: "name@company.com", text: $email, kind: .email)
        TeamSyncPasswordField(label: "Password", placeholder: "Password", text: $password)
        PrimaryActionButton(title: working ? "Signing in…" : "Sign in") { submit() }
            .disabled(working || email.isEmpty || password.isEmpty)
            .opacity(working || email.isEmpty || password.isEmpty ? 0.4 : 1)
    }

    @ViewBuilder private var status: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            FactRow(label: "Team sync", value: model.teamSyncStatus)
        }
        if let error = model.data.teamSync?.lastError {
            Text(error).font(.footnote).foregroundStyle(.orange)
        }
        let waiting = TeamSync.membersWithoutCloudLogin(model.data)
        if !waiting.isEmpty {
            Text(waitingText(waiting)).font(.footnote).foregroundStyle(.secondary)
        }
        SecondaryActionButton(title: model.teamSyncRuntime.busy ? "Syncing…" : "Sync now", icon: "arrow.triangle.2.circlepath") {
            Task { await model.syncTeamNow() }
        }
        .disabled(model.teamSyncRuntime.busy)
    }

    private func waitingText(_ people: [TeamMember]) -> String {
        let who = people.count == 1 ? "\(people[0].name) needs" : (people.count == 2 ? "\(people[0].name) and \(people[1].name) need" : "\(people.count) people need")
        return "\(who) a new password before signing in on their own phone. Open each person and tap Set a new password."
    }

    private func submit() {
        working = true
        problem = nil
        let mail = email, secret = password
        Task { @MainActor in
            problem = await model.turnOnTeamSync(email: mail, password: secret)
            working = false
            if problem == nil { password = "" }
        }
    }
}

/// Team sync status for an employee on their own phone, in Profile.
struct EmployeeTeamSyncCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.teamSyncAvailable, let link = model.data.teamSync, !link.isOwner, !model.data.isOwnerSession {
            CardGroup(title: "Team sync", footer: model.teamSyncRuntime.signedIn ? nil : "Sign out and sign in again to keep syncing.") {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    FactRow(label: "Status", value: model.teamSyncStatus)
                }
                if let error = link.lastError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                SecondaryActionButton(title: model.teamSyncRuntime.busy ? "Syncing…" : "Sync now", icon: "arrow.triangle.2.circlepath") {
                    Task { await model.syncTeamNow() }
                }
                .disabled(model.teamSyncRuntime.busy || !model.teamSyncRuntime.signedIn)
            }
        }
    }
}

/// A labelled password box in the same pill style as the other fields.
private struct TeamSyncPasswordField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.title3.weight(.medium))
            SecureField(placeholder, text: $text)
                .font(.title3)
                #if os(iOS)
                .textContentType(.password)
                #endif
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
        }
    }
}
#endif
