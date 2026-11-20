import Foundation

public struct TutorialStep: Equatable, Identifiable, Sendable {
    public let id: String
    /// An SF Symbol name.
    public let icon: String
    public let title: String
    public let body: String
}

/// The short walkthrough after sign-in. Owners and employees see different ones.
public enum Tutorials {
    public static func steps(for role: SessionRole) -> [TutorialStep] {
        switch role {
        case .owner:
            return [
                TutorialStep(id: "route", icon: "map.fill", title: "Your route, planned for you",
                             body: "Today's jobs appear on the map on Home. Tap Smart route and they are put in the fastest order by drive time, using Apple Maps."),
                TutorialStep(id: "clients", icon: "person.crop.circle.badge.plus", title: "Add clients and jobs",
                             body: "Use New Client and New Job on Home. Clients can also ask for service from their own private page, and it lands in Requests."),
                TutorialStep(id: "team", icon: "person.2.fill", title: "Build your team",
                             body: "Open the menu and choose Team. Add people, give each a role, and choose what they can see. Pro includes up to \(TeamRules.employeeLimit(for: .pro)) employees and Max up to \(TeamRules.employeeLimit(for: .max))."),
                TutorialStep(id: "trial", icon: "gift.fill", title: "\(Pricing.trialDays) days free",
                             body: "Everything is unlocked for \(Pricing.trialDays) days. Pick Pro or Max before the trial ends. You pay for the plan. Your employees never pay."),
            ]
        case .employee:
            return [
                TutorialStep(id: "today", icon: "map.fill", title: "Your jobs for today",
                             body: "Home shows the jobs your boss gave you, on a map and in the order to drive them."),
                TutorialStep(id: "work", icon: "checkmark.circle.fill", title: "Log your work",
                             body: "Clock in, mark a job done and add photos. Your boss sees it right away."),
                TutorialStep(id: "free", icon: "heart.fill", title: "Free for you",
                             body: "Your boss pays for the plan. You never pay. What you can see and do was set by your boss."),
            ]
        }
    }
}

public struct AppNotification: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case request, invoice, job, trial, team }
    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
}

public enum Notifications {
    /// Things that need a look, for this person. Only what they are allowed to see.
    public static func items(for data: AppData, now: Date, calendar: Calendar = .current) -> [AppNotification] {
        var out: [AppNotification] = []
        let todays = data.jobs(on: now, calendar: calendar).filter { !$0.isTask && $0.status.isOpen }
        if !todays.isEmpty {
            out.append(AppNotification(id: "jobs-today", kind: .job, title: "\(todays.count) job\(todays.count == 1 ? "" : "s") today",
                                       detail: "Open Home to see them on the map."))
        }
        if data.can(.answerRequests) {
            let pending = data.serviceRequests.filter { $0.status == .pending }.count
            if pending > 0 {
                out.append(AppNotification(id: "requests", kind: .request, title: "\(pending) client request\(pending == 1 ? "" : "s")",
                                           detail: "Waiting for your answer."))
            }
        }
        if data.can(.viewRevenue) {
            let overdue = data.invoices.filter { !$0.isVoid && $0.sentAt != nil && $0.status(now: now) == .overdue }.count
            if overdue > 0 {
                out.append(AppNotification(id: "overdue", kind: .invoice, title: "\(overdue) overdue invoice\(overdue == 1 ? "" : "s")",
                                           detail: "Past their due date."))
            }
            let drafts = data.invoices.filter { $0.sentAt == nil && !$0.isVoid }.count
            if drafts > 0 {
                out.append(AppNotification(id: "drafts", kind: .invoice, title: "\(drafts) draft invoice\(drafts == 1 ? "" : "s")",
                                           detail: "Look them over and send."))
            }
        }
        if data.isOwnerSession {
            if case .trial(let days) = data.subscription.state(now: now), days <= 3 {
                out.append(AppNotification(id: "trial", kind: .trial, title: "Free trial ends in \(days) day\(days == 1 ? "" : "s")",
                                           detail: "Pick Pro or Max to keep going."))
            }
            let waiting = data.team.filter { $0.status == .invited }.count
            if waiting > 0 {
                out.append(AppNotification(id: "invited", kind: .team, title: "\(waiting) invite\(waiting == 1 ? "" : "s") not used yet",
                                           detail: "Share each person's code from Team."))
            }
        }
        return out
    }
}

/// Money in and out for the Revenue screen.
public struct RevenueSummary: Equatable, Sendable {
    public let paidThisMonth: Money
    public let invoicedThisMonth: Money
    public let outstanding: Money
    public let overdueCount: Int

    public static func compute(for data: AppData, now: Date, calendar: Calendar = .current) -> RevenueSummary {
        var paid = Money.zero, invoiced = Money.zero, outstanding = Money.zero, overdue = 0
        for inv in data.invoices where !inv.isVoid {
            for p in inv.payments where calendar.isDate(p.date, equalTo: now, toGranularity: .month) { paid = paid + p.amount }
            guard inv.sentAt != nil else { continue }
            if calendar.isDate(inv.issueDate, equalTo: now, toGranularity: .month) { invoiced = invoiced + inv.total }
            outstanding = outstanding + inv.balance
            if inv.status(now: now) == .overdue { overdue += 1 }
        }
        return RevenueSummary(paidThisMonth: paid, invoicedThisMonth: invoiced, outstanding: outstanding, overdueCount: overdue)
    }
}
