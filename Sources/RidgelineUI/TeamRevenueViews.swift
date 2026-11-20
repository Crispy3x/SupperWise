#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

// MARK: - Team

/// The people who work for you: add them, give each a role, choose what they can see and do.
struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false

    private var planName: String { model.data.seatPlan == .max ? "Max" : "Pro" }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.data.employeeCount) of \(model.data.employeeLimit) employees").font(.headline)
                    ProgressView(value: Double(min(model.data.employeeCount, model.data.employeeLimit)), total: Double(max(model.data.employeeLimit, 1)))
                    Text("Your \(planName) plan allows up to \(model.data.employeeLimit) employees. Employees never pay: you pay for the plan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("People") {
                if model.data.team.isEmpty {
                    Text("No one yet. Add your crew and office staff. You make each person's username and password.").foregroundStyle(.secondary)
                }
                ForEach(model.data.team) { m in
                    NavigationLink { MemberDetailView(memberID: m.id) } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: m.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.headline)
                                Text(m.role.title).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            switch m.status {
                            case .invited: StatusPill(text: "Invited", color: .orange)
                            case .active: StatusPill(text: "Active", color: .green)
                            case .disabled: StatusPill(text: "Off", color: .gray)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            if model.data.can(.manageTeam) {
                ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Label("Add person", systemImage: "person.badge.plus") } }
            }
        }
        .sheet(isPresented: $showAdd) { AddMemberSheet() }
    }
}

struct AddMemberSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var role: TeamRole = .crewMember
    @State private var problem: String?
    /// After saving: what to hand to the new person. The password exists only here, never in the saved data.
    @State private var created: (name: String, username: String, password: String)?

    var body: some View {
        NavigationStack {
            if let created {
                Form {
                    Section {
                        LabeledContent("Username", value: created.username)
                        LabeledContent("Password", value: created.password)
                    } header: { Text("\(created.name) can sign in with") } footer: {
                        Text("Give these to \(created.name) now. For safety the app keeps only a scrambled copy of the password, so it cannot show it again. You can set a new one any time.")
                    }
                    Section {
                        ShareLink(item: "Sign in to \(model.data.companyName.isEmpty ? "our team" : model.data.companyName) on Ridgeline Ops. Open the app, choose \"I'm an employee\" and enter. Username: \(created.username)  Password: \(created.password)") {
                            Label("Share sign-in details", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .navigationTitle("Added")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            } else {
                Form {
                    Section {
                        TextField("Name", text: $name)
                        TextField("Phone (optional)", text: $phone)
                        TextField("Email (optional)", text: $email)
                    }
                    Section {
                        Picker("Role", selection: $role) { ForEach(TeamRole.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Text(role.summary).font(.footnote).foregroundStyle(.secondary)
                    } footer: {
                        Text("You can change what this person can see and do after you add them.")
                    }
                    Section {
                        TextField("Username", text: $username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        HStack {
                            TextField("Password", text: $password).autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                            Button("Suggest") { password = model.suggestedPassword() }.buttonStyle(.bordered)
                        }
                    } header: { Text("Their sign-in") } footer: {
                        Text("You make the username and password. \(LoginRules.minPasswordLength) or more characters for the password. They use these under \"I'm an employee\".")
                    }
                    if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
                }
                .navigationTitle("Add person")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            problem = model.addTeamMember(name: name, role: role, phone: phone, email: email, username: username, password: password)
                            if problem == nil {
                                created = (name.trimmingCharacters(in: .whitespacesAndNewlines), LoginRules.normalizedUsername(username), password)
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.isEmpty || password.isEmpty)
                    }
                }
            }
        }
    }
}

/// The owner sets a new password for an employee, for example when they forgot theirs.
struct ResetPasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memberID: UUID
    @State private var password = ""
    @State private var problem: String?
    @State private var done: String?

    private var member: TeamMember? { model.data.team.first { $0.id == memberID } }

    var body: some View {
        NavigationStack {
            Form {
                if let done, let m = member {
                    Section {
                        LabeledContent("Username", value: model.data.username(forMember: m.id) ?? "")
                        LabeledContent("New password", value: done)
                    } footer: { Text("Give the new password to \(m.name). The app keeps only a scrambled copy, so it cannot show it again.") }
                    Section {
                        ShareLink(item: "Your new Ridgeline Ops password: \(done)") { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                } else {
                    Section {
                        HStack {
                            TextField("New password", text: $password).autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                            Button("Suggest") { password = model.suggestedPassword() }.buttonStyle(.bordered)
                        }
                    } footer: { Text("\(LoginRules.minPasswordLength) or more characters. This also lifts a lock from too many wrong tries.") }
                    if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
                }
            }
            .navigationTitle("New password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done == nil ? "Cancel" : "Close") { dismiss() } }
                if done == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            problem = model.setEmployeePassword(password, forMember: memberID)
                            if problem == nil { done = password }
                        }
                        .disabled(password.isEmpty)
                    }
                }
            }
        }
    }
}

struct MemberDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memberID: UUID
    @State private var message: String?
    @State private var confirmRemove = false
    @State private var resetting = false

    private var member: TeamMember? { model.data.team.first { $0.id == memberID } }
    private var canEdit: Bool { model.data.can(.manageTeam) }
    /// Choosing individual permissions is part of the Max plan. The free trial has everything.
    private var canCustomize: Bool { canEdit && model.canUse(.rolesAndReports) }

    var body: some View {
        if let m = member {
            Form {
                Section {
                    LabeledContent("Name", value: m.name)
                    if !m.phone.isEmpty { LabeledContent("Phone", value: m.phone) }
                    if !m.email.isEmpty { LabeledContent("Email", value: m.email) }
                    Picker("Role", selection: Binding(get: { m.role }, set: { new in
                        message = model.edit { try $0.setRole(new, forMember: m.id) }
                    })) {
                        ForEach(TeamRole.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(!canEdit)
                    Text(m.role.summary).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(Permission.allCases, id: \.self) { p in
                        Toggle(p.title, isOn: Binding(get: { m.permissions.contains(p) }, set: { on in
                            message = model.edit { try $0.setPermission(p, allowed: on, forMember: m.id) }
                        }))
                        .disabled(!canCustomize)
                    }
                } header: {
                    Text("What they can see and do")
                } footer: {
                    if canEdit && !canCustomize { Text("Choosing permissions one by one is part of the Max plan. Roles above work on every plan.") }
                }
                Section {
                    LabeledContent("Username", value: model.data.username(forMember: m.id) ?? "")
                    if canEdit { Button("Set a new password") { resetting = true } }
                } header: {
                    Text("Sign-in")
                } footer: {
                    Text(m.status == .invited ? "Has not signed in yet." : "Joined \(m.joinedAt.map { DateFormatter.make("MMM d").string(from: $0) } ?? "").")
                }
                if canEdit && m.status != .disabled {
                    Section {
                        Button("Preview the app as \(m.name)") {
                            model.previewAsEmployee(m.id)
                        }
                    } footer: {
                        Text("See exactly what this person sees. Nothing changes for them.")
                    }
                }
                if canEdit {
                    Section {
                        Button(m.status == .disabled ? "Switch access back on" : "Switch access off") {
                            message = model.edit { try $0.setMemberEnabled(m.status == .disabled, forMember: m.id) }
                        }
                        Button("Remove from team", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("Switching access off keeps their history and frees their seat.")
                    }
                }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle(m.name)
            .sheet(isPresented: $resetting) { ResetPasswordSheet(memberID: m.id) }
            .confirmationDialog("Remove \(m.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    message = model.edit { try $0.removeTeamMember(m.id) }
                    if message == nil { dismiss() }
                }
            } message: { Text("Their jobs become unassigned.") }
        } else {
            Text("This person is no longer on the team.").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Revenue

/// What has come in and what is still owed, plus the invoices, job costs and plans.
struct RevenueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let r = RevenueSummary.compute(for: model.data, now: Date())
        let drafts = model.data.invoices.filter { $0.sentAt == nil && !$0.isVoid }.count
        List {
            Section {
                HStack(spacing: 12) {
                    StatBox(title: "Paid this month", value: r.paidThisMonth.formatted, tint: .green)
                    StatBox(title: "Invoiced this month", value: r.invoicedThisMonth.formatted, tint: .blue)
                }
                HStack(spacing: 12) {
                    StatBox(title: "Waiting to be paid", value: r.outstanding.formatted, tint: .orange)
                    StatBox(title: "Overdue", value: "\(r.overdueCount)", tint: r.overdueCount > 0 ? .red : .gray)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            Section {
                NavigationLink { InvoicesView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "doc.text.fill", title: "Invoices", subtitle: drafts > 0 ? "\(drafts) drafts to look at" : "\(model.data.invoices.count) invoices", badge: drafts)
                }
                NavigationLink { ReportsView().environment(\.embeddedInStack, true) } label: {
                    HubRow(icon: "chart.bar.fill", title: "Job costs", subtitle: "Which sites make money", tint: .green)
                }
                if model.data.isOwnerSession {
                    NavigationLink { PricingCalculatorView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "dollarsign.circle.fill", title: "Plans and pricing", subtitle: "Pro and Max, \(Pricing.trialDays) days free", tint: .purple)
                    }
                }
            }
        }
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Look.stroke, lineWidth: 1))
    }
}
#endif
