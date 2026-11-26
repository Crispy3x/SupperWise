import Foundation

public struct ReminderRecord: Equatable, Codable, Sendable {
    public let invoiceNumber: String
    public let sentAt: Date
}

public struct ReminderPlan: Equatable, Sendable {
    public let messages: [PlannedMessage]
    /// Invoice numbers behind each message, in the same order, so only the ones that really went out are recorded.
    public let invoiceNumbers: [String]
}

/// Gentle reminders for invoices past due. Same rules as every message: only to clients who agreed, never to anyone who
/// asked to stop, quiet hours respected, and no nagging (a pause between reminders and a limit per invoice).
public enum ReminderPlanner {
    public static let maxRemindersPerInvoice = 3

    public static func plan(data: AppData, now: Date, minDaysBetween: Int = 7, calendar: Calendar = .current) -> ReminderPlan {
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your snow crew" : data.companyName
        let base = data.broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseOK = RoutingServerSettings.validatedURL(base) != nil
        let sendAfter = data.broadcastSettings.quietHours.nextAllowed(after: now, calendar: calendar)
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")

        var messages: [PlannedMessage] = []
        var numbers: [String] = []
        for inv in data.invoices.sorted(by: { $0.dueDate < $1.dueDate }) {
            guard !inv.isVoid, inv.sentAt != nil, inv.status(now: now, calendar: calendar) == .overdue, inv.balance.cents > 0 else { continue }
            guard let customer = data.customers.first(where: { $0.id == inv.customerID }),
                  customer.optedOutAt == nil, customer.emailConsent, ContactValidation.isValidEmail(customer.email),
                  let site = data.sites.first(where: { $0.id == inv.siteID }) else { continue }
            let past = data.reminderLog.filter { $0.invoiceNumber == inv.number }
            if past.count >= maxRemindersPerInvoice { continue }
            if let last = past.map(\.sentAt).max(), now.timeIntervalSince(last) < Double(minDaysBetween) * 86_400 { continue }

            var lines = ["Hello \(customer.name),", "",
                         "A friendly reminder that invoice \(inv.number) for \(site.address) was due on \(f.string(from: inv.dueDate)). The balance is \(inv.balance.formatted).",
                         "If you have already paid, thank you, and please ignore this note."]
            let pay = data.profile.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pay.isEmpty { lines.append("How to pay: \(pay)") }
            if let link = data.profile.payLink.flatMap(PayLink.clean) { lines.append("Pay online: \(link)") }
            if baseOK, let token = data.portalLinks.first(where: { $0.siteID == site.id })?.token {
                lines.append("")
                lines.append("See all your bills: \(base.hasSuffix("/") ? String(base.dropLast()) : base)/c/\(token)")
            }
            lines.append("")
            lines.append(company)
            lines.append("You are getting this because you agreed to messages from \(company). To stop them, tell \(company) and they will turn them off.")
            let subject = StormBroadcast.clean("Reminder: invoice \(inv.number) was due \(f.string(from: inv.dueDate))")
            messages.append(PlannedMessage(siteID: site.id, customerID: customer.id, channel: .email, to: customer.email, subject: subject,
                                           body: lines.joined(separator: "\n"), sendAfter: sendAfter))
            numbers.append(inv.number)
        }
        return ReminderPlan(messages: messages, invoiceNumbers: numbers)
    }
}

extension AppData {
    public mutating func recordReminders(_ invoiceNumbers: [String], at date: Date) {
        for n in invoiceNumbers { reminderLog.append(ReminderRecord(invoiceNumber: n, sentAt: date)) }
    }
}
