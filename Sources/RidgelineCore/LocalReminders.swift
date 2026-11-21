import Foundation

/// A reminder the phone shows on its own at a set time, with no server. The app plans these from the saved data and
/// replaces the whole set whenever the data changes.
public struct LocalReminder: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case jobs, invoices, storm, trial }
    /// Stable, so planning again replaces the same reminder instead of adding a second one.
    public let id: String
    public let kind: Kind
    public let fireDate: Date
    public let title: String
    public let body: String

    public init(id: String, kind: Kind, fireDate: Date, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

/// The last forecast the app loaded: total snow expected over the next `hours`, and when it was loaded.
public struct SnowOutlook: Equatable, Sendable {
    public var snowInches: Double
    public var loadedAt: Date
    public var hours: Double

    public init(snowInches: Double, loadedAt: Date, hours: Double = 24) {
        self.snowInches = snowInches
        self.loadedAt = loadedAt
        self.hours = hours
    }
}

/// Works out which phone reminders to schedule. Pure: same data and time in, same reminders out.
///
/// - Jobs: the evening before (7 PM), the first open job of the next day. Employees only hear about their own jobs.
/// - Invoices: the morning after the due date (9 AM), for sent invoices that still have a balance. Owners only.
/// - Snow: 7 PM on the day the forecast was loaded, when it shows snow at or above the lowest client trigger. Owners only.
/// - Trial: 10 AM, two days before the free trial ends, if no plan is picked. Owners only.
public enum LocalReminderPlanner {
    public static let idPrefix = "ridgeline.reminder."
    public static let eveningHour = 19
    public static let morningHour = 9
    public static let trialHour = 10
    /// Days ahead to plan job reminders.
    public static let jobDays = 7
    /// Days ahead to plan overdue-invoice reminders.
    public static let invoiceDays = 60
    /// Phones keep a limited number of waiting reminders (64 on iPhone), so stay under it.
    public static let maxReminders = 60

    public static func plan(data: AppData, now: Date, forecast: SnowOutlook? = nil, calendar: Calendar = .current) -> [LocalReminder] {
        guard data.profile.remindersOn, data.session != nil else { return [] }
        var out = jobReminders(data: data, now: now, calendar: calendar)
        if data.isOwnerSession {
            out += invoiceReminders(data: data, now: now, calendar: calendar)
            if let r = stormReminder(data: data, now: now, forecast: forecast, calendar: calendar) { out.append(r) }
            if let r = trialReminder(data: data, now: now, calendar: calendar) { out.append(r) }
        }
        out.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(out.prefix(maxReminders))
    }

    // MARK: jobs

    /// Open jobs (not tasks) this person should be reminded about: everything for the owner, only their own for an employee.
    static func remindableJobs(_ data: AppData) -> [Job] {
        let open = data.jobs.filter { !$0.isTask && $0.status.isOpen }
        if data.isOwnerSession { return open }
        guard let me = data.currentMember, me.status != .disabled else { return [] }
        return open.filter { $0.assigneeIDs.contains(me.id) }
    }

    static func jobReminders(data: AppData, now: Date, calendar: Calendar) -> [LocalReminder] {
        let jobs = remindableJobs(data)
        guard !jobs.isEmpty else { return [] }
        let employee = !data.isOwnerSession
        let today = calendar.startOfDay(for: now)
        var out: [LocalReminder] = []
        for offset in 1...jobDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let eve = calendar.date(byAdding: .day, value: -1, to: day),
                  let fire = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: eve),
                  fire > now else { continue }
            let onDay = jobs.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            guard let first = onDay.first else { continue }
            let count = onDay.count
            let jobsWord = count == 1 ? "job" : "\(count) jobs"
            let noun = employee ? "your " + jobsWord : (count == 1 ? "1 job" : jobsWord)
            let title = "Tomorrow: \(noun), first at \(time(first.start, calendar))"
            var body = "First: \(first.title)"
            let place = data.address(forJob: first)
            if !place.isEmpty { body += " at \(place)" }
            let who = data.customerName(forJob: first)
            if !who.isEmpty && who != first.title { body += " for \(who)" }
            body += "."
            out.append(LocalReminder(id: idPrefix + "jobs." + dayKey(day, calendar), kind: .jobs, fireDate: fire, title: title, body: body))
        }
        return out
    }

    // MARK: invoices

    static func invoiceReminders(data: AppData, now: Date, calendar: Calendar) -> [LocalReminder] {
        let limit = now.addingTimeInterval(Double(invoiceDays) * 86_400)
        var byFire: [Date: [Invoice]] = [:]
        for inv in data.invoices {
            guard !inv.isVoid, inv.sentAt != nil, inv.balance.cents > 0, inv.dueDate > now else { continue }
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: inv.dueDate)),
                  let fire = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: next),
                  fire > now, fire <= limit else { continue }
            byFire[fire, default: []].append(inv)
        }
        return byFire.keys.sorted().map { fire in
            let invoices = byFire[fire, default: []].sorted { $0.number < $1.number }
            let total = invoices.reduce(Money.zero) { $0 + $1.balance }
            let names = invoices.map { inv in data.customers.first { $0.id == inv.customerID }?.name ?? "A client" }
            let title: String
            let body: String
            if invoices.count == 1, let inv = invoices.first {
                title = "Invoice \(inv.number) is overdue"
                body = "\(names[0]) owes \(total.formatted). It was due yesterday."
            } else {
                title = "\(invoices.count) invoices are overdue"
                let shown = names.prefix(2).joined(separator: ", ")
                let more = names.count > 2 ? " and \(names.count - 2) more" : ""
                body = "\(shown)\(more). \(total.formatted) in all."
            }
            return LocalReminder(id: idPrefix + "invoices." + dayKey(fire, calendar), kind: .invoices, fireDate: fire, title: title, body: body)
        }
    }

    // MARK: snow

    /// The lowest trigger depth among clients' sites (leads not counted). Nil when there are no sites.
    static func lowestTrigger(_ data: AppData) -> Double? {
        let clientIDs = Set(data.customers.filter { !$0.isLead }.map(\.id))
        return data.sites.filter { clientIDs.contains($0.customerID) }.map(\.triggerInches).min()
    }

    static func stormReminder(data: AppData, now: Date, forecast: SnowOutlook?, calendar: Calendar) -> LocalReminder? {
        guard let f = forecast, f.snowInches > 0, f.snowInches.isFinite, let trigger = lowestTrigger(data), f.snowInches >= trigger,
              let fire = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: f.loadedAt),
              fire >= f.loadedAt, fire > now, fire < f.loadedAt.addingTimeInterval(f.hours * 3600) else { return nil }
        let depth = String(format: "%.1f", f.snowInches)
        let trig = String(format: "%g", trigger)
        return LocalReminder(id: idPrefix + "storm", kind: .storm, fireDate: fire,
                             title: "Snow coming: about \(depth) in",
                             body: "That is at or above your \(trig) in trigger. Get trucks, salt and fuel ready tonight.")
    }

    // MARK: trial

    static func trialReminder(data: AppData, now: Date, calendar: Calendar) -> LocalReminder? {
        guard data.subscription.plan == nil, let end = data.subscription.trialEnd, end > now,
              let fire = calendar.date(bySettingHour: trialHour, minute: 0, second: 0, of: end.addingTimeInterval(-2 * 86_400)),
              fire > now, fire < end else { return nil }
        return LocalReminder(id: idPrefix + "trial", kind: .trial, fireDate: fire,
                             title: "Your free trial ends in 2 days",
                             body: "Pick Pro or Max in Settings to keep everything working.")
    }

    // MARK: text

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
