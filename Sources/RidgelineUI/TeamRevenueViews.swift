#if canImport(SwiftUI)
import SwiftUI
import Charts
import RidgelineCore

// MARK: - Team

/// The people who work for you: add them, give each a role, choose what they can see and do.
struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var showInvites = false

    private var invited: [TeamMember] { model.data.team.filter { $0.status == .invited } }
    private var planName: String { model.data.seatPlan == .max ? "Max" : "Pro" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "person.2.fill", title: "Team", trailing: "\(model.data.team.count) member\(model.data.team.count == 1 ? "" : "s")")
                    TeamSyncCard()                           // TeamSyncViews.swift: hidden when team sync is off
                    NavigationLink { TimesheetsView().environment(\.embeddedInStack, true).circleBack() } label: {
                        TeamRowCard(icon: "clock", tint: .green, title: "Timesheets", badge: 0, chevron: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { showInvites.toggle() } } label: {
                        TeamRowCard(icon: "person.badge.plus", tint: Theme.accent(model.data.profile.accentColor), title: "Pending invites", badge: invited.count,
                                    chevron: showInvites ? "chevron.up" : "chevron.down", showZero: true)
                    }
                    .buttonStyle(.plain)
                    if showInvites {
                        if invited.isEmpty {
                            Text("No one is waiting to sign in.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        }
                        ForEach(invited) { m in
                            Card(padding: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.headline)
                                    Text("\(m.role.title) · username \(model.data.username(forMember: m.id) ?? "") · not signed in yet").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if model.data.team.isEmpty {
                        EmptyCard(icon: "person.2", title: "No team members yet", message: "Add your first employee to this business.")
                    } else {
                        ForEach(model.data.team) { m in
                            NavigationLink { MemberDetailView(memberID: m.id).environment(\.embeddedInStack, true).circleBack() } label: {
                                Card(padding: 12) {
                                    HStack(spacing: 14) {
                                        AvatarView(name: m.name, size: 46)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.name).font(.headline).foregroundStyle(.primary)
                                            Text(m.role.title).font(.footnote).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        switch m.status {
                                        case .invited: StatusPill(text: "Invited", color: .orange)
                                        case .active: StatusPill(text: "Active", color: .green)
                                        case .disabled: StatusPill(text: "Off", color: .gray)
                                        }
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("\(model.data.employeeCount) of \(model.data.employeeLimit) employees on your \(planName) plan. Employees never pay: you pay for the plan.")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
            }
            if model.data.can(.manageTeam) {
                PrimaryBar(title: "Add team member") { showAdd = true }
                    .padding(.horizontal, 16).padding(.bottom, Look.tabBarClearance)
            } else {
                Color.clear.frame(height: Look.tabBarClearance)
            }
        }
        .sheet(isPresented: $showAdd) { AddMemberSheet() }
    }
}

private struct TeamRowCard: View {
    let icon: String
    let tint: Color
    let title: String
    let badge: Int
    let chevron: String
    var showZero = false
    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 14) {
                IconTile(icon: icon, tint: tint, size: 52)
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                if badge > 0 || showZero {
                    Text("\(badge)").font(.headline).foregroundStyle(tint).padding(.horizontal, 14).padding(.vertical, 6).background(tint.opacity(0.18), in: Capsule())
                }
                Image(systemName: chevron).foregroundStyle(.secondary)
            }
        }
    }
}

/// Add a person in three steps: who they are, their role, and the username and password you make for them.
struct AddMemberSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var rate = ""
    @State private var role: TeamRole = .crewMember
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?
    /// After saving: what to hand to the new person. The password exists only here, never in the saved data.
    @State private var created: (name: String, username: String, password: String)?
    /// True while their own-phone login is being made in the cloud (team sync on).
    @State private var cloudBusy = false

    /// What is wrong with the optional phone, email or pay on the first step, if anything.
    private var personProblem: String? {
        // Said on the first step, not after the name, role, username and password have all been typed.
        if model.data.employeeCount >= model.data.employeeLimit {
            return "Your plan allows up to \(model.data.employeeLimit) employees. "
                + (model.data.seatPlan == .max ? "Switch someone off before adding another." : "Switch someone off, or move up to the Max plan, before adding another.")
        }
        if let p = ContactValidation.phoneProblem(phone) { return p }
        if let p = ContactValidation.emailProblem(email) { return p }
        if TeamRules.hourlyRate(typed: rate) == .invalid { return "Hourly pay must be a plain amount up to $1,000, like 20 or 22.50. Or leave it empty." }
        return nil
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && personProblem == nil
        case 2: return !username.isEmpty && !password.isEmpty
        default: return true
        }
    }

    var body: some View {
        if let created { createdPage(created) } else {
            WizardScaffold(title: "Add Team Member", steps: ["Person", "Role", "Sign-in"], step: $step, canAdvance: canAdvance, onClose: { dismiss() }, onFinish: save) {
                switch step {
                case 0:
                    SectionLabel(text: "Who is joining")
                    PillField(label: "Name", required: true, placeholder: "Dana Cole", text: $name)
                    PillField(label: "Phone Number", optional: true, placeholder: "(555) 555-1234", text: $phone, kind: .phone)
                    PillField(label: "Email", optional: true, placeholder: "dana@company.com", text: $email, kind: .email)
                    PillField(label: "Hourly pay", optional: true, placeholder: "20", text: $rate, kind: .number)
                    Text("Pay is only used for the pay-owed total on timesheets.").font(.footnote).foregroundStyle(.secondary)
                    if let personProblem { Label(personProblem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
                case 1:
                    SectionLabel(text: "Their role")
                    ForEach(TeamRole.allCases, id: \.self) { r in
                        Button { role = r } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    Text(r.summary).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: role == r ? "checkmark.circle.fill" : "circle").font(.title2)
                                    .foregroundStyle(role == r ? Theme.accent(model.data.profile.accentColor) : Color.secondary)
                            }
                            .padding(16)
                            .background(Look.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(role == r ? Theme.accent(model.data.profile.accentColor) : Look.fieldStroke, lineWidth: role == r ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("You can change what this person can see and do after you add them.").font(.footnote).foregroundStyle(.secondary)
                default:
                    SectionLabel(text: "Their sign-in")
                    PillField(label: "Username", required: true, placeholder: "dana", text: $username, kind: .email)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) { Text("Password").font(.title3.weight(.medium)); Text("*").font(.title3) }
                        HStack(spacing: 10) {
                            TextField("At least \(LoginRules.minPasswordLength) characters", text: $password).font(.title3).autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .padding(.horizontal, 22).padding(.vertical, 16)
                                .background(Look.field, in: Capsule()).overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                            Button { password = model.suggestedPassword() } label: {
                                Text("Suggest").font(.title3.weight(.medium)).foregroundStyle(.primary)
                                    .padding(.horizontal, 18).padding(.vertical, 16).background(Look.pill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("You make the username and password. They use them under \"I'm an employee\". Give them to the person after you save.").font(.footnote).foregroundStyle(.secondary)
                    if cloudBusy { ProgressView("Making their login…").font(.callout) }
                    if let problem { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
                }
            }
        }
    }

    private func save() {
        // Read by the tested rule: typing "inf" or a huge number used to crash the whole-number conversion here.
        var pay: Money?
        if case .rate(let typed) = TeamRules.hourlyRate(typed: rate) { pay = typed }
        if model.teamCloudManagesLogins {
            // Team sync on: also make their login for their own phone (AppModel+TeamSync.swift). Nothing is kept if that fails.
            guard !cloudBusy else { return }
            cloudBusy = true
            problem = nil
            let who = name.trimmingCharacters(in: .whitespacesAndNewlines), r = role, user = username, secret = password
            let ph = phone.trimmingCharacters(in: .whitespacesAndNewlines), mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let hourly = pay
            Task { @MainActor in
                problem = await model.addTeamMemberWithCloud(name: who, role: r, phone: ph, email: mail, username: user, password: secret, hourlyRate: hourly)
                cloudBusy = false
                if problem == nil { created = (who, LoginRules.normalizedUsername(user), secret) }
            }
            return
        }
        problem = model.addTeamMember(name: name, role: role, phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                                      email: email.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: password, hourlyRate: pay)
        if problem == nil {
            created = (name.trimmingCharacters(in: .whitespacesAndNewlines), LoginRules.normalizedUsername(username), password)
        }
    }

    private func createdPage(_ c: (name: String, username: String, password: String)) -> some View {
        VStack(spacing: 18) {
            HStack {
                Spacer(); Text("Added").font(.title3.weight(.semibold)); Spacer()
            }
            .overlay(alignment: .trailing) { CircleButton(icon: "checkmark", label: "Done") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "\(c.name) can sign in with")
                    Card { VStack(alignment: .leading, spacing: 10) {
                        CapsLabel(text: "Username"); Text(c.username).font(.title2.weight(.semibold))
                        CapsLabel(text: "Password"); Text(c.password).font(.title2.weight(.semibold)).textSelection(.enabled)
                    } }
                    Text("Give these to \(c.name) now. For safety the app keeps only a scrambled copy of the password, so it cannot show it again. You can set a new one any time.")
                        .font(.callout).foregroundStyle(.secondary)
                    ShareLink(item: "Sign in to \(model.data.companyName.isEmpty ? "our team" : model.data.companyName) on Ridgeline Ops. Open the app, choose \"I'm an employee\" and enter. Username: \(c.username)  Password: \(c.password)") {
                        Label("Share sign-in details", systemImage: "square.and.arrow.up").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Look.pill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 16)
        .background(Look.sheet.ignoresSafeArea())
    }
}

/// The owner sets a new password for an employee, for example when they forgot theirs.
struct ResetPasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memberID: UUID
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var done: String?

    private var member: TeamMember? { model.data.team.first { $0.id == memberID } }
    /// False for someone who came back from a backup without a sign-in: they get a username here too.
    private var hasLogin: Bool { model.data.username(forMember: memberID) != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New password").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: done == nil ? "Cancel" : "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let done, let m = member {
                    CardGroup(footer: "Give the new password to \(m.name). The app keeps only a scrambled copy, so it cannot show it again.") {
                        FactRow(label: "Username", value: model.data.username(forMember: m.id) ?? "")
                        RowDivider()
                        FactRow(label: "New password", value: done)
                    }
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    }
                    ShareLink(item: "Your new Ridgeline Ops password: \(done)") {
                        Label("Share", systemImage: "square.and.arrow.up").font(.title3.weight(.medium)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Look.pill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    CardGroup(footer: "\(LoginRules.minPasswordLength) or more characters. This also lifts a lock from too many wrong tries.") {
                        if !hasLogin {
                            PillField(label: "Username", required: true, placeholder: "dana", text: $username, kind: .email)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("New password").font(.title3.weight(.medium))
                            HStack(spacing: 10) {
                                TextField("New password", text: $password)
                                    .font(.title3)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .padding(.horizontal, 22).padding(.vertical, 16)
                                    .background(Look.field, in: Capsule()).overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                                Button { password = model.suggestedPassword() } label: {
                                    Text("Suggest").font(.title3.weight(.medium)).foregroundStyle(.primary)
                                        .padding(.horizontal, 18).padding(.vertical, 16).background(Look.pill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        PrimaryActionButton(title: "Save") {
                            if hasLogin {
                                problem = model.setEmployeePassword(password, forMember: memberID)
                            } else {
                                let name = username, secret = password
                                problem = model.edit { try $0.createEmployeeLogin(username: name, password: secret, forMember: memberID, now: Date()) }
                            }
                            if problem == nil, model.teamCloudManagesLogins {
                                // Their own-phone login gets the same password (AppModel+TeamSync.swift).
                                let secret = password
                                Task { @MainActor in
                                    problem = await model.setCloudPassword(secret, forMember: memberID)
                                    done = secret
                                }
                            } else if problem == nil {
                                done = password
                            }
                        }
                        .disabled(password.isEmpty || (!hasLogin && username.isEmpty))
                        .opacity(password.isEmpty || (!hasLogin && username.isEmpty) ? 0.4 : 1)
                    }
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    }
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
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
            AppPage(title: m.name, icon: "person.fill", trailing: m.role.title) {
                CardGroup {
                    FactRow(label: "Name", value: m.name)
                    if !m.phone.isEmpty { RowDivider(); FactRow(label: "Phone", value: m.phone) }
                    if !m.email.isEmpty { RowDivider(); FactRow(label: "Email", value: m.email) }
                    RowDivider()
                    PillMenu(label: "Role", options: TeamRole.allCases.map { ($0, $0.title) }, selection: Binding(get: { m.role }, set: { new in
                        message = model.edit { try $0.setRole(new, forMember: m.id) }
                    }))
                    .disabled(!canEdit)
                    Text(m.role.summary).font(.footnote).foregroundStyle(.secondary)
                }
                // What someone is paid is between them and whoever manages the team, so other employees never see it.
                if canEdit {
                    CardGroup(title: "Pay", footer: "Used for the pay-owed total on timesheets.") {
                        PillStepper(label: "Hourly pay", value: Binding(get: { Double((m.hourlyRate?.cents ?? 0) / 100) }, set: { v in
                            message = model.edit { try $0.setHourlyRate(Int(v) == 0 ? nil : Money(dollars: Int(v)), forMember: m.id) }
                        }), range: 0...500, step: 1, format: { $0 == 0 ? "not set" : Money(dollars: Int($0)).formatted })
                    }
                }
                CardGroup(title: "What they can see and do",
                          footer: (canEdit && !canCustomize) ? "Choosing permissions one by one is part of the Max plan. Roles above work on every plan." : nil) {
                    ForEach(Array(Permission.allCases.enumerated()), id: \.offset) { i, p in
                        if i > 0 { RowDivider() }
                        Toggle(p.title, isOn: Binding(get: { m.permissions.contains(p) }, set: { on in
                            message = model.edit { try $0.setPermission(p, allowed: on, forMember: m.id) }
                        }))
                        .disabled(!canCustomize)
                    }
                }
                CardGroup(title: "Sign-in",
                          footer: m.joinedAt.map { "First signed in \(DateFormatter.make("MMM d, yyyy").string(from: $0))." } ?? "Has not signed in yet.") {
                    if !canEdit {
                        FactRow(label: "Access", value: m.status == .disabled ? "Switched off" : "On")
                    } else if let username = model.data.username(forMember: m.id) {
                        FactRow(label: "Username", value: username)
                        RowDivider()
                        SecondaryActionButton(title: "Set a new password") { resetting = true }
                    } else {
                        // Someone restored from a backup made under another owner login comes back without a sign-in.
                        Text("\(m.name) has no username and password yet, so they cannot sign in.").foregroundStyle(.secondary)
                        SecondaryActionButton(title: "Make a username and password") { resetting = true }
                    }
                }
                if canEdit && model.data.isOwnerSession && m.status != .disabled {
                    CardGroup(footer: "See exactly what this person sees. Nothing changes for them.") {
                        SecondaryActionButton(title: "Preview the app as \(m.name)") {
                            model.previewAsEmployee(m.id)
                        }
                    }
                }
                if canEdit {
                    CardGroup(footer: "Switching access off keeps their history and frees their seat.") {
                        SecondaryActionButton(title: m.status == .disabled ? "Switch access back on" : "Switch access off") {
                            message = model.edit { try $0.setMemberEnabled(m.status == .disabled, forMember: m.id) }
                        }
                        PrimaryActionButton(title: "Remove from team", destructive: true) { confirmRemove = true }
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
            }
            .sheet(isPresented: $resetting) { ResetPasswordSheet(memberID: m.id) }
            .confirmationDialog("Remove \(m.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if model.teamCloudManagesLogins {
                        // Their own-phone login goes first (AppModel+TeamSync.swift).
                        Task { @MainActor in
                            message = await model.removeTeamMemberWithCloud(m.id)
                            if message == nil { dismiss() }
                        }
                    } else {
                        message = model.edit { try $0.removeTeamMember(m.id) }
                        if message == nil { dismiss() }
                    }
                }
            } message: { Text("Their jobs become unassigned.") }
        } else {
            AppPage {
                Text("This person is no longer on the team.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
        }
    }
}

// MARK: - Revenue

/// Money received: totals, a chart over time, the latest payments, and the invoices, job costs and subscription.
struct RevenueView: View {
    @Environment(AppModel.self) private var model
    @State private var period: RevenuePeriod = .thisMonth

    var body: some View {
        let r = RevenueReport.compute(for: model.data, period: period, now: Date())
        // Real drafts only: an invoice paid on the spot and never emailed is not waiting to be sent.
        let drafts = model.data.invoices.filter { $0.status(now: Date()) == .draft }.count
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    IconTile(icon: "dollarsign.circle.fill", size: 54)
                    Text("Revenue").font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Menu {
                        ForEach(RevenuePeriod.allCases, id: \.self) { p in Button(p.title) { period = p } }
                    } label: {
                        HStack(spacing: 8) { Text(period.title).font(.callout.weight(.medium)).lineLimit(1).fixedSize(); Image(systemName: "chevron.down").font(.footnote) }
                            .foregroundStyle(.primary).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Look.card, in: Capsule()).overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 12) {
                    StatCard(title: "Total revenue", value: r.allTime.formatted, footer: "All time", footerColor: .secondary)
                    StatCard(title: period.title, value: r.periodTotal.formatted,
                             footer: r.percentChange.map { "\($0 >= 0 ? "\u{2197}" : "\u{2198}") \(String(format: "%.1f", abs($0)))% vs previous period" } ?? "No earlier period to compare",
                             footerColor: (r.percentChange ?? 0) >= 0 ? .green : .red)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Revenue Over Time").font(.title3.weight(.semibold))
                            Spacer()
                            Label("Revenue trend", systemImage: "chart.line.uptrend.xyaxis").font(.callout.weight(.medium)).foregroundStyle(.green)
                        }
                        if r.bars.isEmpty {
                            VStack(spacing: 6) {
                                Text("No revenue yet").font(.title3.weight(.semibold))
                                Text("Record a payment on an invoice to see revenue here.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            Chart(r.bars) { bar in
                                BarMark(x: .value("Date", bar.start, unit: period == .thisMonth || period == .lastMonth ? .day : .month),
                                        y: .value("Dollars", Double(bar.amount.cents) / 100))
                                    .foregroundStyle(Theme.accent(model.data.profile.accentColor).gradient)
                            }
                            .frame(height: 220)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Revenue").font(.title3.weight(.semibold))
                            Spacer()
                            Label("Latest records", systemImage: "receipt").font(.callout).foregroundStyle(.secondary)
                        }
                        if r.recent.isEmpty {
                            Text("No payments recorded yet.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
                        }
                        ForEach(r.recent) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.client.isEmpty ? e.invoiceNumber : e.client).font(.headline)
                                    Text("\(e.invoiceNumber) · \(DateFormatter.make("MMM d").string(from: e.date))").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(e.amount.formatted).font(.headline).foregroundStyle(.green)
                            }
                        }
                    }
                }
                Card(padding: 4) {
                    VStack(spacing: 0) {
                        NavigationLink { InvoicesView().environment(\.embeddedInStack, true).circleBack() } label: {
                            MoreRow(icon: "doc.text.fill", tint: Theme.accent(model.data.profile.accentColor), title: "Invoices", subtitle: drafts > 0 ? "\(drafts) draft\(drafts == 1 ? "" : "s") to look at" : "\(model.data.invoices.count) invoice\(model.data.invoices.count == 1 ? "" : "s")", badge: drafts)
                        }
                        Divider().padding(.leading, 70)
                        NavigationLink { ReportsView().environment(\.embeddedInStack, true).circleBack() } label: {
                            MoreRow(icon: "chart.bar.fill", tint: .green, title: "Job costs", subtitle: "Which sites make money", badge: 0)
                        }
                        if model.data.isOwnerSession {
                            Divider().padding(.leading, 70)
                            NavigationLink { SubscriptionView().environment(\.embeddedInStack, true).circleBack() } label: {
                                MoreRow(icon: "creditcard.fill", tint: .purple, title: "Subscription", subtitle: "Pro and Max, \(Pricing.trialDays) days free", badge: 0)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, Look.tabBarClearance + 40)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let footer: String
    let footerColor: Color
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: title)
                Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text(footer).font(.callout).foregroundStyle(footerColor)
            }
            .frame(minHeight: 96, alignment: .topLeading)
        }
    }
}

private struct MoreRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let badge: Int
    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if badge > 0 { Text("\(badge)").font(.footnote.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2).background(Color.red, in: Capsule()) }
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}
#endif
