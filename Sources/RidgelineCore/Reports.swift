import Foundation

// MARK: - Timesheets

public enum TimesheetPeriod: String, CaseIterable, Sendable {
    case thisWeek, lastWeek, month, custom

    public var title: String {
        switch self {
        case .thisWeek: return "This week"
        case .lastWeek: return "Last week"
        case .month: return "Month"
        case .custom: return "Custom"
        }
    }

    /// The span of time to total up. A week runs from the calendar's first weekday.
    public func interval(now: Date, calendar: Calendar = .current, custom: ClosedRange<Date>? = nil) -> DateInterval {
        switch self {
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86_400)
        case .lastWeek:
            let this = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let lastDay = this.addingTimeInterval(-3600)
            return calendar.dateInterval(of: .weekOfYear, for: lastDay) ?? DateInterval(start: this.addingTimeInterval(-7 * 86_400), duration: 7 * 86_400)
        case .month: return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 30 * 86_400)
        case .custom:
            guard let c = custom else { return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86_400) }
            let start = calendar.startOfDay(for: c.lowerBound)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: c.upperBound)) ?? c.upperBound
            return DateInterval(start: start, end: max(end, start.addingTimeInterval(86_400)))
        }
    }
}

public struct TimesheetRow: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let hours: Double
    public let rate: Money?
    /// Hours times rate, to the cent. Zero when no rate is set.
    public let pay: Money
}

public struct TimesheetReport: Equatable, Sendable {
    public let rows: [TimesheetRow]
    public let entries: [TimeEntry]
    public var totalHours: Double { rows.reduce(0) { $0 + $1.hours } }
    public var payOwed: Money { rows.reduce(.zero) { $0 + $1.pay } }
    /// People with hours but no hourly rate, so their pay is not counted yet.
    public var missingRates: [String] { rows.filter { $0.rate == nil && $0.hours > 0 }.map(\.name) }

    public static func compute(for data: AppData, interval: DateInterval, now: Date) -> TimesheetReport {
        let mine = data.timeEntries.filter { $0.start >= interval.start && $0.start < interval.end }.sorted { $0.start > $1.start }   // the end is the next period's start
        // One row per person, whatever capitals they typed their name with.
        var order: [String] = [], shown: [String: String] = [:], hours: [String: Double] = [:]
        for e in mine {
            let key = e.memberName.trimmingCharacters(in: .whitespaces).lowercased()
            if hours[key] == nil { order.append(key); shown[key] = e.memberName }
            hours[key, default: 0] += e.hours(now: now)
        }
        let rows = order.map { key -> TimesheetRow in
            let member = data.team.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }
            let name = member?.name ?? shown[key] ?? key                     // the team member's own spelling when there is one
            let h = hours[key] ?? 0
            let rate = member?.hourlyRate
            let pay = rate.map { Money(cents: Int((Double($0.cents) * h).rounded())) } ?? .zero
            return TimesheetRow(name: name, hours: h, rate: rate, pay: pay)
        }
        return TimesheetReport(rows: rows, entries: mine)
    }
}

// MARK: - Revenue

public enum RevenuePeriod: String, CaseIterable, Sendable {
    case thisMonth, lastMonth, thisYear, allTime

    public var title: String {
        switch self {
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }

    /// The span, and the span just before it to compare with. All time has nothing to compare with.
    func intervals(now: Date, calendar: Calendar) -> (current: DateInterval?, previous: DateInterval?) {
        switch self {
        case .thisMonth:
            let cur = calendar.dateInterval(of: .month, for: now)
            let prev = cur.flatMap { calendar.dateInterval(of: .month, for: $0.start.addingTimeInterval(-3600)) }
            return (cur, prev)
        case .lastMonth:
            let this = calendar.dateInterval(of: .month, for: now)
            let cur = this.flatMap { calendar.dateInterval(of: .month, for: $0.start.addingTimeInterval(-3600)) }
            let prev = cur.flatMap { calendar.dateInterval(of: .month, for: $0.start.addingTimeInterval(-3600)) }
            return (cur, prev)
        case .thisYear:
            let cur = calendar.dateInterval(of: .year, for: now)
            let prev = cur.flatMap { calendar.dateInterval(of: .year, for: $0.start.addingTimeInterval(-3600)) }
            return (cur, prev)
        case .allTime: return (nil, nil)
        }
    }
}

public struct RevenueEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let invoiceNumber: String
    public let client: String
    public let amount: Money
}

public struct RevenueBar: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let amount: Money
}

public struct RevenueReport: Equatable, Sendable {
    public let allTime: Money
    public let thisMonth: Money
    public let periodTotal: Money
    /// How much more or less than the span before, in percent. Nil when there is nothing to compare with.
    public let percentChange: Double?
    public let bars: [RevenueBar]
    public let recent: [RevenueEntry]

    /// Revenue is money received: payments recorded on invoices that are not void.
    public static func compute(for data: AppData, period: RevenuePeriod, now: Date, calendar: Calendar = .current) -> RevenueReport {
        var all: [RevenueEntry] = []
        for inv in data.invoices where !inv.isVoid {
            let who = data.customers.first { $0.id == inv.customerID }?.name ?? ""
            for p in inv.payments { all.append(RevenueEntry(id: p.id, date: p.date, invoiceNumber: inv.number, client: who, amount: p.amount)) }
        }
        func total(_ list: [RevenueEntry]) -> Money { list.reduce(.zero) { $0 + $1.amount } }
        // The start counts and the end does not, so a payment at midnight on the 1st is in one month, not two.
        func within(_ span: DateInterval, _ date: Date) -> Bool { date >= span.start && date < span.end }
        let spans = period.intervals(now: now, calendar: calendar)
        let inPeriod = spans.current.map { s in all.filter { within(s, $0.date) } } ?? all
        let monthSpan = calendar.dateInterval(of: .month, for: now)
        let thisMonth = monthSpan.map { s in total(all.filter { within(s, $0.date) }) } ?? .zero
        var change: Double?
        if let prev = spans.previous {
            let before = total(all.filter { within(prev, $0.date) })
            if before.cents > 0 { change = (Double(total(inPeriod).cents - before.cents) / Double(before.cents) * 100 * 10).rounded() / 10 }
            else if total(inPeriod).cents == 0 { change = 0 }
        }
        // Bars: one per day for a month, one per month for a year or all time.
        let byDay = period == .thisMonth || period == .lastMonth
        var buckets: [Date: Int] = [:]
        for e in inPeriod {
            let key = byDay ? calendar.startOfDay(for: e.date)
                            : (calendar.dateInterval(of: .month, for: e.date)?.start ?? e.date)
            buckets[key, default: 0] += e.amount.cents
        }
        let bars = buckets.keys.sorted().map { RevenueBar(start: $0, amount: Money(cents: buckets[$0] ?? 0)) }
        return RevenueReport(allTime: total(all), thisMonth: thisMonth, periodTotal: total(inPeriod), percentChange: change,
                             bars: bars, recent: Array(all.sorted { $0.date > $1.date }.prefix(10)))
    }
}
