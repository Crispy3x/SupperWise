#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Signing in as an owner or an employee, the team, the schedule and the tips. All saved with the rest of the data.
extension AppModel {
    // MARK: session

    /// Opens the app as owner with no login. Only possible until the owner adds a login or links Apple.
    public func startOwnerWithoutAccount() -> String? {
        edit { try $0.startOwnerSessionWithoutLogin(now: Date()) }
    }

    /// The owner makes their login (email and password) and is signed in. The password is stored only as a salted hash.
    public func createOwnerLogin(email: String, password: String, signIn: Bool) -> String? {
        edit { data in
            try data.createOwnerLogin(email: email, password: password, now: Date())
            if signIn { data.session = AppSession(role: .owner, startedAt: Date()) }
        }
    }

    public func ownerSignInWithApple(userID: String, name: String, email: String) -> String? {
        edit { try $0.signInOwnerWithApple(appleUserID: userID, displayName: name, email: email, now: Date()) }
    }

    /// Signs in with a username and password. `expecting` keeps an owner login out of the employee screen and the other way round.
    public func signIn(username: String, password: String, expecting: SessionRole) -> String? {
        var outcome: SignInOutcome = .wrongCredentials
        let problem = edit { outcome = $0.attemptSignIn(username: username, password: password, now: Date()) }
        if let problem { return problem }
        switch outcome {
        case .signedIn(let role):
            if role == expecting { return nil }
            edit { $0.session = nil }
            return role == .owner
                ? "That is an owner login. Go back and choose \"I own the business\"."
                : "That is an employee login. Go back and choose \"I'm an employee\"."
        case .wrongCredentials:
            return "That username or password is not right."
        case .lockedOut(let until):
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            return "Too many tries. Try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        case .accessOff:
            return "Your boss has switched your access off. Ask them to turn it back on."
        }
    }

    /// Signs out of the app on this device. Business data stays; the next person picks owner or employee again.
    public func signOutOfApp() {
        stopSharing()
        assistantLines = []; assistantHistory = []; assistantUpdates = []
        previewingEmployee = false
        edit { $0.session = nil }
    }

    /// The owner looks at the app the way an employee sees it. Nothing is changed for that person.
    public func previewAsEmployee(_ memberID: UUID) {
        guard data.isOwnerSession, let member = data.team.first(where: { $0.id == memberID }), member.status != .disabled else { return }
        previewingEmployee = true
        edit { $0.session = AppSession(role: .employee, memberID: memberID, startedAt: Date()) }
    }

    public func exitPreview() {
        previewingEmployee = false
        edit { $0.session = AppSession(role: .owner, startedAt: Date()) }
    }

    // MARK: tips and walkthrough

    public func hasSeenTutorial(_ role: SessionRole) -> Bool { data.tutorialsSeen.contains(role.rawValue) }

    public func markTutorialSeen(_ role: SessionRole) {
        guard !hasSeenTutorial(role) else { return }
        edit { $0.tutorialsSeen.append(role.rawValue) }
    }

    public func isHintDismissed(_ id: String) -> Bool { data.dismissedHints.contains(id) }

    public func dismissHint(_ id: String) {
        guard !isHintDismissed(id) else { return }
        edit { $0.dismissedHints.append(id) }
    }

    // MARK: team and jobs

    @discardableResult
    public func addTeamMember(name: String, role: TeamRole, phone: String, email: String, username: String, password: String, hourlyRate: Money? = nil) -> String? {
        edit { _ = try $0.addTeamMember(name: name, role: role, phone: phone, email: email, username: username, password: password, hourlyRate: hourlyRate, now: Date()) }
    }

    public func setEmployeePassword(_ password: String, forMember id: UUID) -> String? {
        edit { try $0.setEmployeePassword(password, forMember: id, now: Date()) }
    }

    public func changeOwnerPassword(current: String, new: String) -> String? {
        edit { try $0.changeOwnerPassword(current: current, new: new, now: Date()) }
    }

    /// A readable password the owner can give to an employee.
    public func suggestedPassword() -> String {
        var g = SystemRandomNumberGenerator()
        return LoginRules.suggestedPassword(using: &g)
    }

    public func addJob(title: String, kind: JobKind, customerID: UUID?, siteID: UUID?, start: Date, durationMinutes: Int,
                       assigneeIDs: [UUID], notes: String, isTask: Bool) -> String? {
        edit { _ = try $0.addJob(title: title, kind: kind, customerID: customerID, siteID: siteID, start: start,
                                 durationMinutes: durationMinutes, assigneeIDs: assigneeIDs, notes: notes, isTask: isTask, now: Date()) }
    }

    public func setJobStatus(_ status: JobStatus, id: UUID) -> String? { edit { try $0.setJobStatus(status, id: id) } }
    public func deleteJob(_ id: UUID) -> String? { edit { try $0.deleteJob(id) } }

    /// A calendar file with the schedule that this person can see, in a temporary place, ready to share.
    public func scheduleFileURL() -> URL? {
        let text = CalendarExport.ics(jobs: data.visibleJobs, data: data, company: data.companyName, now: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ridgeline-schedule.ics")
        do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
#endif
