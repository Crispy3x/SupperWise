import Foundation

/// How often a job comes back: weekly mowing, every-2-weeks service, a monthly visit.
public enum RepeatFrequency: String, Codable, CaseIterable, Sendable {
    case never, weekly, everyTwoWeeks, everyFourWeeks, monthly

    public var title: String {
        switch self {
        case .never: return "Does not repeat"
        case .weekly: return "Every week"
        case .everyTwoWeeks: return "Every 2 weeks"
        case .everyFourWeeks: return "Every 4 weeks"
        case .monthly: return "Every month"
        }
    }

    /// Weeks between visits. Nil for never and monthly.
    public var weeks: Int? {
        switch self {
        case .weekly: return 1
        case .everyTwoWeeks: return 2
        case .everyFourWeeks: return 4
        case .never, .monthly: return nil
        }
    }
}

/// A job's repeat setting. Visits are worked out when asked for, so a weekly job never makes thousands of copies.
public struct RepeatRule: Equatable, Codable, Sendable {
    public var frequency: RepeatFrequency
    /// The last day a visit can fall on. Nil keeps it going.
    public var endDate: Date?

    public init(frequency: RepeatFrequency, endDate: Date? = nil) {
        self.frequency = frequency
        self.endDate = endDate
    }

    public var repeats: Bool { frequency != .never }

    /// "Repeats every week", "Repeats every 2 weeks", "Repeats every month".
    public var summary: String {
        repeats ? "Repeats " + frequency.title.lowercased() : frequency.title
    }
}

extension Job {
    public var repeats: Bool { repeatRule?.repeats ?? false }

    /// The key a single visit is stored under, like "2027-01-15", in the given calendar.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func monthsBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int? {
        let x = calendar.dateComponents([.year, .month], from: a), y = calendar.dateComponents([.year, .month], from: b)
        guard let xy = x.year, let xm = x.month, let yy = y.year, let ym = y.month else { return nil }
        return (yy - xy) * 12 + (ym - xm)
    }

    private func isPastEnd(_ date: Date, calendar: Calendar) -> Bool {
        guard let end = repeatRule?.endDate else { return false }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: end)
    }

    /// When the visit on `day` starts, or nil if this job does not fall on that day.
    /// Monthly visits keep the first visit's day; on the 29th to 31st they move to the last day of shorter months.
    public func occurrenceStart(on day: Date, calendar: Calendar = .current) -> Date? {
        guard let rule = repeatRule, rule.repeats else {
            return calendar.isDate(start, inSameDayAs: day) ? start : nil
        }
        let first = calendar.startOfDay(for: start)
        let target = calendar.startOfDay(for: day)
        guard target >= first, !isPastEnd(target, calendar: calendar) else { return nil }
        if let weeks = rule.frequency.weeks {
            guard let days = calendar.dateComponents([.day], from: first, to: target).day, days >= 0, days % (7 * weeks) == 0 else { return nil }
            return calendar.date(byAdding: .day, value: days, to: start)
        }
        // Monthly: always counted from the first visit, so the 31st never drifts to the 28th for good.
        guard let months = Job.monthsBetween(start, day, calendar: calendar), months >= 0,
              let candidate = calendar.date(byAdding: .month, value: months, to: start),
              calendar.isDate(candidate, inSameDayAs: day) else { return nil }
        return candidate
    }

    /// The status of one visit. Done or skipped visits are stored by day; every other visit is scheduled.
    public func occurrenceStatus(on day: Date, calendar: Calendar = .current) -> JobStatus {
        guard repeats else { return status }
        if status == .cancelled { return .cancelled }
        return occurrenceStatuses?[Job.dayKey(day, calendar: calendar)] ?? .scheduled
    }

    /// This job as it looks on `day`: same id, the visit's start time and the visit's own status. Nil if it is not on that day.
    public func occurrence(on day: Date, calendar: Calendar = .current) -> Job? {
        guard let at = occurrenceStart(on: day, calendar: calendar) else { return nil }
        guard repeats else { return self }
        var copy = self
        copy.start = at
        copy.status = occurrenceStatus(on: at, calendar: calendar)
        return copy
    }

    /// The first visit on or after `day`, or nil when the job has ended.
    public func nextOccurrence(onOrAfter day: Date, calendar: Calendar = .current) -> Date? {
        let target = calendar.startOfDay(for: day)
        guard let rule = repeatRule, rule.repeats else {
            return calendar.startOfDay(for: start) >= target ? start : nil
        }
        let first = calendar.startOfDay(for: start)
        var candidate: Date?
        if let weeks = rule.frequency.weeks {
            let days = max(0, calendar.dateComponents([.day], from: first, to: target).day ?? 0)
            let step = 7 * weeks
            candidate = calendar.date(byAdding: .day, value: (days + step - 1) / step * step, to: start)
        } else {
            let months = max(0, Job.monthsBetween(start, target, calendar: calendar) ?? 0)
            for m in months...(months + 1) {
                if let c = calendar.date(byAdding: .month, value: m, to: start), calendar.startOfDay(for: c) >= target {
                    candidate = c
                    break
                }
            }
        }
        guard let c = candidate, !isPastEnd(c, calendar: calendar) else { return nil }
        return c
    }

    /// The repeat line for a calendar file, like "FREQ=WEEKLY;INTERVAL=2;UNTIL=20270301T235959Z". Nil when the job happens once.
    /// A monthly job on the 31st uses the last day of each month, as the app does.
    public func icsRepeatRule(calendar: Calendar = .current) -> String? {
        guard let rule = repeatRule, rule.repeats else { return nil }
        var parts: [String]
        if let weeks = rule.frequency.weeks {
            parts = ["FREQ=WEEKLY", "INTERVAL=\(weeks)"]
        } else {
            let day = calendar.component(.day, from: start)
            parts = ["FREQ=MONTHLY", "BYMONTHDAY=\(day == 31 ? -1 : day)"]
        }
        if let end = rule.endDate {
            let lastSecond = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) ?? end
            parts.append("UNTIL=\(CalendarExport.utc(lastSecond))")
        }
        return parts.joined(separator: ";")
    }

    /// Days of the month containing `date` that have a visit of this job.
    public func occurrenceDays(inMonthOf date: Date, calendar: Calendar = .current) -> Set<Int> {
        guard repeats else {
            guard calendar.isDate(start, equalTo: date, toGranularity: .month) else { return [] }
            return Set([calendar.component(.day, from: start)])
        }
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        var out = Set<Int>()
        var d = month.start
        while d < month.end {
            if occurrenceStart(on: d, calendar: calendar) != nil { out.insert(calendar.component(.day, from: d)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d), next > d else { break }
            d = next
        }
        return out
    }
}

extension AppData {
    /// Sets or clears how often a job repeats. An end date before the first visit ends it after that first visit.
    public mutating func setJobRepeat(_ rule: RepeatRule?, id: UUID, calendar: Calendar = .current) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        guard var rule = rule, rule.repeats else {
            jobs[i].repeatRule = nil
            return
        }
        if let end = rule.endDate, calendar.startOfDay(for: end) < calendar.startOfDay(for: jobs[i].start) {
            rule.endDate = jobs[i].start
        }
        jobs[i].repeatRule = rule
    }

    /// Marks one visit of a repeating job (done, skipped, in progress) without touching the other visits.
    /// For a job that does not repeat, this changes the job itself.
    public mutating func setOccurrenceStatus(_ status: JobStatus, id: UUID, on day: Date, calendar: Calendar = .current) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        guard jobs[i].repeats else {
            jobs[i].status = status
            if status == .done { autoInvoice(afterJobDone: id, on: day, now: Date(), calendar: calendar) }   // JobBilling.swift
            return
        }
        guard jobs[i].occurrenceStart(on: day, calendar: calendar) != nil else { throw OperationError.notFound }
        let key = Job.dayKey(day, calendar: calendar)
        var map = jobs[i].occurrenceStatuses ?? [:]
        map[key] = status == .scheduled ? nil : status
        jobs[i].occurrenceStatuses = map.isEmpty ? nil : map
        if status == .done { autoInvoice(afterJobDone: id, on: day, now: Date(), calendar: calendar) }   // JobBilling.swift
    }

    /// Skips one visit of a repeating job. The rest stay on the schedule.
    public mutating func skipOccurrence(id: UUID, on day: Date, calendar: Calendar = .current) throws {
        try setOccurrenceStatus(.cancelled, id: id, on: day, calendar: calendar)
    }
}
