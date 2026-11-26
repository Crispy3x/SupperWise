#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The Keychain entry that holds this phone's team sync sign-in. Never in the data file, never logged.
private let teamCloudSessionKey = "teamCloudSession"

/// Team sync state that screens watch. Nothing here is saved: the link itself is `AppData.teamSync`.
@MainActor @Observable
public final class TeamSyncRuntime {
    public internal(set) var busy = false
    public internal(set) var signedIn = false
    @ObservationIgnored var cloud: TeamCloud?
    @ObservationIgnored var debounce: Task<Void, Never>?
    @ObservationIgnored var applying = false
    @ObservationIgnored var runAgain = false
    @ObservationIgnored var prepared = false

    nonisolated public init() {}
}

/// Team sync: the owner and each employee on their own phones, through the cloud (supabase/CONTRACT.md).
/// Off unless the app was built with the team sync settings in Info.plist; then nothing here runs and the app works as before.
extension AppModel {
    // MARK: setup

    static let teamCloudConfig: TeamCloudConfig? = {
        let info = Bundle.main.infoDictionary ?? [:]
        return TeamCloudConfig(url: info["RidgelineSupabaseURL"] as? String, anonKey: info["RidgelineSupabaseAnonKey"] as? String)
    }()

    /// The app was built with team sync.
    public var teamSyncAvailable: Bool { Self.teamCloudConfig != nil && ScreenshotMode.shot == nil }
    /// This phone is linked to a team sync business.
    public var teamSyncOn: Bool { teamSyncAvailable && data.teamSync != nil }
    /// People's own-phone logins are made and changed from this phone (the owner, or someone who manages the team).
    public var teamCloudManagesLogins: Bool { teamSyncOn && TeamSync.writer(for: data).permissions.contains(.manageTeam) }

    func teamCloud() -> TeamCloud? {
        if let cloud = teamSyncRuntime.cloud { return cloud }
        guard teamSyncAvailable, let config = Self.teamCloudConfig else { return nil }
        let saved = Self.loadTeamCloudSession()
        let cloud = TeamCloud(config: config, session: saved, onSessionChange: { AppModel.storeTeamCloudSession($0) })
        teamSyncRuntime.cloud = cloud
        teamSyncRuntime.signedIn = saved != nil
        return cloud
    }

    nonisolated static func loadTeamCloudSession() -> TeamCloudSession? {
        #if canImport(Security)
        guard let text = KeychainStore.load(teamCloudSessionKey), !text.isEmpty else { return nil }
        return try? JSONDecoder().decode(TeamCloudSession.self, from: Data(text.utf8))
        #else
        return nil
        #endif
    }

    nonisolated static func storeTeamCloudSession(_ session: TeamCloudSession?) {
        #if canImport(Security)
        if let session, let encoded = try? JSONEncoder().encode(session) {
            KeychainStore.save(String(decoding: encoded, as: UTF8.self), for: teamCloudSessionKey)
        } else {
            KeychainStore.save("", for: teamCloudSessionKey)
        }
        #endif
    }

    /// Once per launch. A sign-in left in the Keychain from an earlier install with no link is dropped.
    func prepareTeamSync() {
        guard !teamSyncRuntime.prepared else { return }
        teamSyncRuntime.prepared = true
        guard let cloud = teamCloud() else { return }
        if data.teamSync == nil && teamSyncRuntime.signedIn {
            teamSyncRuntime.signedIn = false
            Task { await cloud.signOut() }
        }
    }

    // MARK: rounds

    /// Saves a change that came from team sync without starting another round because of it.
    func mutateQuietly(_ change: (inout AppData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        data = copy
        teamSyncRuntime.applying = true
        save()
        teamSyncRuntime.applying = false
    }

    /// Called after every save (AppModel.save): a change made here goes out about 5 seconds later.
    func teamSyncDidSave() {
        guard !teamSyncRuntime.applying, data.teamSync != nil, teamSyncAvailable else { return }
        scheduleTeamSync(after: 5)
    }

    func scheduleTeamSync(after seconds: Double) {
        teamSyncRuntime.debounce?.cancel()
        teamSyncRuntime.debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // A fresh task, so a later change that restarts the wait never cancels a round already talking to the server.
            Task { await self.syncTeamNow() }
        }
    }

    /// One round: push what changed here, then pull what changed elsewhere. Never blocks the screen. Offline, it notes
    /// that and the next launch, return to the app, change or "Sync now" tries again.
    public func syncTeamNow() async {
        prepareTeamSync()
        guard let cloud = teamCloud(), data.teamSync != nil, data.session != nil, !savingIsBlocked else { return }
        let runtime = teamSyncRuntime
        guard !runtime.busy else { runtime.runAgain = true; return }
        guard await cloud.isSignedIn else { runtime.signedIn = false; return }
        runtime.busy = true
        do {
            try await teamSyncRound(cloud)
        } catch {
            recordTeamSyncError(error)
        }
        runtime.busy = false
        if runtime.runAgain {
            runtime.runAgain = false
            scheduleTeamSync(after: 1)
        }
    }

    private func teamSyncRound(_ cloud: TeamCloud) async throws {
        guard let start = data.teamSync else { return }
        let businessID = start.businessID
        // Employees: membership first, for current permissions and to notice being switched off or removed.
        if !start.isOwner {
            let memberships = try await cloud.myMembership()
            guard let m = memberships.first(where: { $0.businessID == businessID }) else {
                endEmployeeCloudSession("You are no longer on this team. Ask the owner.")
                return
            }
            if m.disabled {
                endEmployeeCloudSession("Your access was turned off. Ask the owner.")
                return
            }
            mutateQuietly { TeamSync.applyMembership(m, to: &$0, now: Date()) }
        }
        // Push first, so a change made here is never overwritten by an older one from the cloud.
        let snapshot = data
        let out = await Task.detached(priority: .utility) { TeamSync.outgoing(snapshot) }.value
        mutateQuietly { d in
            guard var s = d.teamSync, s.businessID == businessID else { return }
            TeamSync.recordTombstones(out, in: &s, now: Date())
            d.teamSync = s
        }
        var refused: [String] = []
        if !out.rows.isEmpty { refused = try await cloud.push(out.rows) }
        mutateQuietly { d in
            guard var s = d.teamSync, s.businessID == businessID else { return }
            TeamSync.markPushed(out, refused: refused, in: &s)
            d.teamSync = s
        }
        let pushProblem = data.teamSync?.lastError
        let accessProblem = await sendTeamAccessChanges(cloud)
        // Then pull.
        guard let current = data.teamSync, current.businessID == businessID else { return }
        let rows = try await cloud.pull(businessID: businessID, after: TeamSync.cursor(for: current))
        mutateQuietly { d in
            guard d.teamSync?.businessID == businessID else { return }
            TeamSync.apply(rows, to: &d)
            d.teamSync?.lastSyncAt = Date()
            d.teamSync?.lastError = pushProblem ?? accessProblem
        }
        teamSyncRuntime.signedIn = true
    }

    private func recordTeamSyncError(_ error: Error) {
        let cloudError = error as? TeamCloudError
        if cloudError == .signedOut { teamSyncRuntime.signedIn = false }
        let text = cloudError?.message ?? "Team sync did not finish. It will try again."
        mutateQuietly { $0.teamSync?.lastError = text }
    }

    func teamCloudMessage(_ error: Error) -> String {
        (error as? TeamCloudError)?.message ?? "Try again later."
    }

    /// Role, permission and on/off changes reach the person's own-phone login.
    private func sendTeamAccessChanges(_ cloud: TeamCloud) async -> String? {
        guard let state = data.teamSync, TeamSync.writer(for: data).permissions.contains(.manageTeam) else { return nil }
        var problem: String?
        for (member, username) in TeamSync.accessChanges(data) {
            let key = member.id.uuidString
            do {
                try await cloud.team(.setAccess(username: username, role: member.role, permissions: member.permissions,
                                                disabled: member.status == .disabled), businessID: state.businessID)
                mutateQuietly { $0.teamSync?.accessSent[key] = TeamSync.accessFingerprint(member) }
            } catch TeamCloudError.notFound(_) {
                mutateQuietly { $0.teamSync?.cloudLogins[key] = nil; $0.teamSync?.accessSent[key] = nil }
            } catch {
                problem = "Could not update \(member.name)'s access on their own phone. \(teamCloudMessage(error))"
            }
        }
        return problem
    }

    /// "Synced 2 min ago", "Syncing…" or "Paused".
    public var teamSyncStatus: String {
        guard let s = data.teamSync else { return "" }
        if teamSyncRuntime.busy { return "Syncing…" }
        if !teamSyncRuntime.signedIn { return "Paused" }
        return TeamSync.syncedText(s.lastSyncAt, now: Date())
    }

    // MARK: owner

    /// The owner turns on team sync: signs in (or makes the cloud account), makes the business, and sends everything up.
    /// Also used to sign in again after signing out. Returns a message, or nil when it worked.
    public func turnOnTeamSync(email: String, password: String) async -> String? {
        guard let cloud = teamCloud() else { return "Team sync is not available in this version of the app." }
        guard data.isOwnerSession, !previewingEmployee, data.teamSync?.isOwner ?? true else { return "Only the owner can turn this on." }
        let mail = LoginRules.normalizedUsername(email)
        guard ContactValidation.isValidEmail(mail) else { return "Enter a valid email address." }
        guard (LoginRules.minPasswordLength...TeamCloud.maxPasswordLength).contains(password.count) else {
            return "Use \(LoginRules.minPasswordLength) to \(TeamCloud.maxPasswordLength) characters for the password."
        }
        guard !teamSyncRuntime.busy else { return "Team sync is busy. Try again in a moment." }
        teamSyncRuntime.busy = true
        let problem = await linkOwner(cloud, email: mail, password: password)
        teamSyncRuntime.busy = false
        if problem == nil { await syncTeamNow() }
        return problem
    }

    private func linkOwner(_ cloud: TeamCloud, email: String, password: String) async -> String? {
        do {
            do {
                try await cloud.signIn(email: email, password: password)
            } catch TeamCloudError.wrongLogin {
                try await cloud.signUp(email: email, password: password)
            }
            let memberships = try await cloud.myMembership()
            let businessID: UUID
            let name: String
            if let own = memberships.first(where: { $0.isOwner }) {
                businessID = own.businessID
                name = own.businessName
            } else if !memberships.isEmpty {
                await cloud.signOut()
                return "This email belongs to someone else's team, so it cannot run this business."
            } else {
                let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
                name = company.isEmpty ? "My business" : company
                businessID = try await cloud.createBusiness(name: name)
            }
            mutateQuietly { d in
                if var same = d.teamSync, same.businessID == businessID {
                    same.login = email
                    same.lastError = nil
                    d.teamSync = same
                } else {
                    d.teamSync = TeamSyncState(businessID: businessID, businessName: name, role: "owner", login: email)
                }
            }
            teamSyncRuntime.signedIn = true
            return nil
        } catch TeamCloudError.wrongLogin {
            return "That email or password is not right."
        } catch {
            return teamCloudMessage(error)
        }
    }

    /// After the owner signs in on this phone with the same email and password as team sync, team sync signs in too.
    public func resumeTeamSync(email: String, password: String) {
        guard let state = data.teamSync, state.isOwner, !teamSyncRuntime.signedIn, let cloud = teamCloud(),
              LoginRules.normalizedUsername(email) == state.login else { return }
        Task { [weak self] in
            guard (try? await cloud.signIn(email: state.login, password: password)) != nil, let self else { return }
            self.teamSyncRuntime.signedIn = true
            await self.syncTeamNow()
        }
    }

    /// Adds the person here, then makes the same login in the cloud so they can sign in on their own phone.
    /// If the cloud refuses (for example the username is taken by someone in another business), nothing is kept.
    public func addTeamMemberWithCloud(name: String, role: TeamRole, phone: String, email: String, username: String,
                                       password: String, hourlyRate: Money?) async -> String? {
        guard password.count <= TeamCloud.maxPasswordLength else { return "Use at most \(TeamCloud.maxPasswordLength) characters." }
        if let problem = addTeamMember(name: name, role: role, phone: phone, email: email, username: username, password: password,
                                       hourlyRate: hourlyRate) { return problem }
        let user = LoginRules.normalizedUsername(username)
        guard let state = data.teamSync, let cloud = teamCloud(),
              let member = data.team.first(where: { data.username(forMember: $0.id) == user }) else { return nil }
        do {
            try await cloud.team(.create(memberID: member.id, username: user, password: password, role: member.role,
                                         permissions: member.permissions), businessID: state.businessID)
            noteCloudLogin(member, username: user, accessSent: true)
            scheduleTeamSync(after: 0.5)          // their member row should be in the cloud before they sign in
            return nil
        } catch {
            edit { try $0.removeTeamMember(member.id) }
            return "\(member.name) was not added. \(teamCloudMessage(error))"
        }
    }

    /// After a new password was set on this phone: the person's own-phone login gets it too, and is made if they had none
    /// (for example people added before team sync was turned on).
    public func setCloudPassword(_ password: String, forMember id: UUID) async -> String? {
        guard teamCloudManagesLogins, let state = data.teamSync, let cloud = teamCloud(),
              let member = data.team.first(where: { $0.id == id }),
              let username = state.cloudLogins[id.uuidString] ?? data.username(forMember: id) else { return nil }
        guard password.count <= TeamCloud.maxPasswordLength else {
            return "Saved on this phone. For their own phone, use at most \(TeamCloud.maxPasswordLength) characters."
        }
        let create = TeamAction.create(memberID: id, username: username, password: password, role: member.role, permissions: member.permissions)
        do {
            if state.cloudLogins[id.uuidString] != nil {
                do {
                    try await cloud.team(.resetPassword(username: username, password: password), businessID: state.businessID)
                    noteCloudLogin(member, username: username, accessSent: false)
                } catch TeamCloudError.notFound(_) {
                    try await cloud.team(create, businessID: state.businessID)
                    noteCloudLogin(member, username: username, accessSent: true)
                }
            } else {
                do {
                    try await cloud.team(create, businessID: state.businessID)
                    noteCloudLogin(member, username: username, accessSent: true)
                } catch TeamCloudError.conflict(_) {
                    // They already have a login (made from another phone or before a reinstall): set its password.
                    try await cloud.team(.resetPassword(username: username, password: password), businessID: state.businessID)
                    noteCloudLogin(member, username: username, accessSent: false)
                }
            }
            return nil
        } catch {
            return "Saved on this phone, but their own phone sign-in did not change. \(teamCloudMessage(error))"
        }
    }

    /// Removes the person's own-phone login first, then removes them here. If the cloud cannot be reached, nothing changes.
    public func removeTeamMemberWithCloud(_ id: UUID) async -> String? {
        if teamCloudManagesLogins, let state = data.teamSync, let username = state.cloudLogins[id.uuidString], let cloud = teamCloud() {
            do {
                try await cloud.team(.remove(username: username), businessID: state.businessID)
            } catch TeamCloudError.notFound(_) {
                // Already gone in the cloud.
            } catch {
                return "Could not remove their login on their own phone, so nothing was changed. \(teamCloudMessage(error))"
            }
        }
        let problem = edit { try $0.removeTeamMember(id) }
        if problem == nil {
            mutateQuietly { $0.teamSync?.cloudLogins[id.uuidString] = nil; $0.teamSync?.accessSent[id.uuidString] = nil }
        }
        return problem
    }

    /// `accessSent`: the call carried the role and permissions (create), so only an off switch is still to send.
    private func noteCloudLogin(_ member: TeamMember, username: String, accessSent: Bool) {
        var sent = member
        sent.status = .active
        let key = member.id.uuidString
        mutateQuietly { d in
            d.teamSync?.cloudLogins[key] = username
            d.teamSync?.accessSent[key] = accessSent ? TeamSync.accessFingerprint(sent) : nil
        }
    }

    // MARK: employee on their own phone

    /// True when this username has no login on this phone and the app can ask the cloud instead.
    public func usesCloudSignIn(for username: String) -> Bool {
        let name = LoginRules.normalizedUsername(username)
        return teamSyncAvailable && !data.logins.contains { $0.username == name }
    }

    /// An employee signs in on their own phone with the username and password the owner made. Returns a message, or nil.
    public func signInEmployeeWithCloud(username: String, password: String) async -> String? {
        let wrong = "That username or password is not right."
        guard let cloud = teamCloud() else { return wrong }
        let user = LoginRules.normalizedUsername(username)
        guard TeamCloud.isValidUsername(user) else { return wrong }
        do {
            try await cloud.signIn(username: user, password: password)
            let memberships = try await cloud.myMembership()
            guard let m = memberships.first else {
                await cloud.signOut()
                return "This login is not on a team. Ask the owner to add you again."
            }
            if m.isOwner {
                await cloud.signOut()
                return "That is an owner login. Go back and choose \"I own the business\"."
            }
            if m.disabled {
                await cloud.signOut()
                return "Your access was turned off. Ask the owner."
            }
            guard let memberID = m.memberID else {
                await cloud.signOut()
                return "This login is not finished. Ask the owner to set a new password for you."
            }
            if let problem = TeamSync.linkProblem(data, businessID: m.businessID) {
                await cloud.signOut()
                return problem
            }
            mutateQuietly { d in
                if d.teamSync?.businessID != m.businessID {
                    d.teamSync = TeamSyncState(businessID: m.businessID, businessName: m.businessName, role: m.role, memberID: memberID, login: user)
                }
                d.teamSync?.login = user
                d.teamSync?.lastError = nil
                if d.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { d.companyName = m.businessName }
                TeamSync.applyMembership(m, to: &d, now: Date())
                d.session = AppSession(role: .employee, memberID: memberID, startedAt: Date())
            }
            teamSyncRuntime.signedIn = true
            await syncTeamNow()
            return nil
        } catch TeamCloudError.wrongLogin {
            return wrong
        } catch {
            return teamCloudMessage(error)
        }
    }

    /// The owner switched this employee off or removed them: sign out here, with a note.
    private func endEmployeeCloudSession(_ message: String) {
        let cloud = teamSyncRuntime.cloud
        mutateQuietly { d in
            if d.session?.role == .employee { d.session = nil }
            d.teamSync?.lastError = message
        }
        notice = message
        teamSyncRuntime.signedIn = false
        Task { await cloud?.signOut() }
    }

    // MARK: signing out and deleting

    /// App sign-out (AppModel+Team.swift): anything not pushed yet goes out first, best effort, then this phone signs out
    /// of team sync. The link and the records stay, so the next sign-in carries on.
    func teamSyncSignOut() {
        teamSyncRuntime.debounce?.cancel()
        guard data.teamSync != nil || teamSyncRuntime.signedIn, let cloud = teamCloud() else { return }
        let snapshot = data
        let businessID = snapshot.teamSync?.businessID
        teamSyncRuntime.signedIn = false
        Task { [weak self] in
            let user = await cloud.userID
            if snapshot.teamSync != nil {
                let out = TeamSync.outgoing(snapshot)
                if !out.rows.isEmpty, let refused = try? await cloud.push(out.rows) {
                    self?.mutateQuietly { d in
                        guard var s = d.teamSync, s.businessID == businessID else { return }
                        TeamSync.markPushed(out, refused: refused, in: &s)
                        d.teamSync = s
                    }
                }
            }
            await cloud.signOut(onlyIfUserID: user)
        }
    }

    /// Deleting the account and data on this phone (AppModel.deleteAccountAndData) also deletes the cloud login, as the
    /// App Store requires. For the owner that removes the business, its records and every employee login; for a crew
    /// member only their own login goes, never the business.
    func teamSyncForget() {
        teamSyncRuntime.debounce?.cancel()
        teamSyncRuntime.signedIn = false
        let cloud = teamSyncRuntime.cloud ?? teamCloud()
        Task {
            try? await cloud?.deleteMe()
            await cloud?.signOut()
            Self.storeTeamCloudSession(nil)
        }
    }
}

/// Syncs on launch and whenever the app comes back to the front. Put once on the root view.
struct TeamSyncModifier: ViewModifier {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await model.syncTeamNow() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await model.syncTeamNow() } }
            }
    }
}

extension View {
    func teamSync(_ model: AppModel) -> some View { modifier(TeamSyncModifier(model: model)) }
}
#endif
