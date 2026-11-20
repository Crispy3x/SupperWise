#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The very first screen: are you the business owner or an employee? The answer is saved so the app does not ask again.
struct WelcomeRoleView: View {
    @Environment(AppModel.self) private var model
    @State private var joining = false

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
                        model.startOwnerSession()
                    }
                    RoleCard(icon: "person.fill", title: "I'm an employee",
                             message: "Sign in with the code your boss gave you. Always free for you.") {
                        joining = true
                    }
                    Text("You stay signed in on this device until you sign out.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $joining) { EmployeeJoinView() }
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

/// An employee types the 6-letter code the owner gave them. The owner chose their role and permissions.
struct EmployeeJoinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your 6-letter code", text: $code)
                        .font(.title2.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .onChange(of: code) { _, new in code = String(TeamRules.normalizedCode(new).prefix(6)) }
                } footer: {
                    Text("Your boss finds it under Menu, Team. What you can see and do in the app was chosen by your boss.")
                }
                if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
                Section {
                    Text("For now, the code works on the device where your boss set up the business. Joining from your own phone arrives with team sync.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Employee sign in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        problem = model.joinTeam(code: code)
                        if problem == nil { dismiss() }
                    }
                    .disabled(code.count != 6)
                }
            }
        }
    }
}
#endif
