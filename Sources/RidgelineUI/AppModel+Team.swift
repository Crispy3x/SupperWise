#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Signing in as an owner or an employee, the team, the schedule and the tips. All saved with the rest of the data.
extension AppModel {
    // MARK: session

    /// The business owner starts (or resumes) using the app. The session is saved, so the app stays signed in.
    public func startOwnerSession() {
        edit { $0.session = AppSession(role: .owner, startedAt: Date()) }
    }

    /// An employee joins with the code the owner gave them. Returns a message when it did not work.
    public func joinTeam(code: String) -> String? {
        var failure: String?
        let problem = edit { data in
            do { try data.join(code: code, now: Date()) } catch let e as TeamError {
                switch e {
                case .invalidCode:
                    failure = "That code was not found on this device. Ask your boss to add you under Team, then use the 6-letter code they give you."
                case .disabled:
                    failure = "Your boss has switched this access off. Ask them to turn it back on."
                default: failure = "Could not join."
                }
                throw e
            }
        }
        return failure ?? problem
    }

    /// Signs out of the app on this device. Business data stays; the next person picks owner or employee again.
    public func signOutOfApp() {
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
    public func addTeamMember(name: String, role: TeamRole, phone: String, email: String) -> String? {
        edit { _ = try $0.addTeamMember(name: name, role: role, phone: phone, email: email, now: Date()) }
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
