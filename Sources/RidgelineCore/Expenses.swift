import Foundation

/// What the money was spent on. Kept short so picking one takes a second.
public enum ExpenseCategory: String, Codable, CaseIterable, Sendable {
    case fuel, saltAndMaterials, equipment, repairs, insurance, subcontractors, supplies, other

    public var title: String {
        switch self {
        case .fuel: return "Fuel"
        case .saltAndMaterials: return "Salt and materials"
        case .equipment: return "Equipment"
        case .repairs: return "Repairs"
        case .insurance: return "Insurance"
        case .subcontractors: return "Subcontractors"
        case .supplies: return "Supplies"
        case .other: return "Other"
        }
    }

    // A category this version does not know (saved by a newer one) loads as Other instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: raw) ?? .other
    }
}

/// A drive written off by the mile: "42 miles at $0.70".
public struct MileageTrip: Equatable, Codable, Sendable {
    public static let maxMiles = 100_000.0
    public static let maxCentsPerMile = 10_000.0

    public var miles: Double
    /// What one mile is worth, in cents. Not whole cents, because standard rates use half cents (72.5).
    public var centsPerMile: Double

    public init(miles: Double, centsPerMile: Double) {
        self.miles = miles.isFinite ? min(max(miles, 0), Self.maxMiles) : 0
        self.centsPerMile = centsPerMile.isFinite ? min(max(centsPerMile, 0), Self.maxCentsPerMile) : 0
    }

    /// From a rate typed in dollars ("0.70" or "0.725"), kept to a tenth of a cent.
    public init(miles: Double, dollarsPerMile: Double) {
        self.init(miles: miles, centsPerMile: dollarsPerMile.isFinite ? (dollarsPerMile * 1000).rounded() / 10 : 0)
    }

    /// Miles times the rate, to the nearest cent.
    public var amount: Money {
        let cents = (miles * centsPerMile).rounded()
        guard cents.isFinite, cents >= 0, cents < 1e15 else { return .zero }
        return Money(cents: Int(cents))
    }

    /// "$0.70", or "$0.725" when the rate has a half cent.
    public var rateText: String {
        let wholeCents = abs(centsPerMile - centsPerMile.rounded()) < 0.0001
        return String(format: wholeCents ? "$%.2f" : "$%.3f", centsPerMile / 100)
    }

    /// "42 miles at $0.70"
    public var summary: String {
        "\(String(format: "%g", miles)) mile\(miles == 1 ? "" : "s") at \(rateText)"
    }
}

/// Money the business spent: a receipt, a bill, or a drive counted by the mile.
public struct Expense: Identifiable, Equatable, Codable, Sendable {
    public static let maxAmount = Money(dollars: 10_000_000)

    public var id: UUID
    public var date: Date
    public var category: ExpenseCategory
    /// What it cost. For a mileage trip this is the miles times the rate.
    public private(set) var amount: Money
    public var vendor: String
    public var note: String
    /// File name of the receipt photo in the photo folder, when one was taken.
    public var receiptPhoto: String?
    public private(set) var mileage: MileageTrip?

    public init(id: UUID = UUID(), date: Date, category: ExpenseCategory, amount: Money, vendor: String = "", note: String = "",
                receiptPhoto: String? = nil) {
        self.id = id
        self.date = date
        self.category = category
        self.amount = amount
        self.vendor = vendor
        self.note = note
        self.receiptPhoto = receiptPhoto
        self.mileage = nil
    }

    /// An expense counted by the mile. The amount is worked out from the trip.
    public init(id: UUID = UUID(), date: Date, category: ExpenseCategory = .fuel, mileage: MileageTrip, vendor: String = "", note: String = "",
                receiptPhoto: String? = nil) {
        self.id = id
        self.date = date
        self.category = category
        self.amount = mileage.amount
        self.vendor = vendor
        self.note = note
        self.receiptPhoto = receiptPhoto
        self.mileage = mileage
    }

    /// Switches to a typed amount and drops any mileage trip.
    public mutating func setAmount(_ amount: Money) {
        self.amount = amount
        mileage = nil
    }

    /// Switches to a mileage trip. The amount follows the trip.
    public mutating func setMileage(_ trip: MileageTrip) {
        mileage = trip
        amount = trip.amount
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, category, amount, vendor, note, receiptPhoto, mileage
    }

    // Fields added later fall back to a default, so expenses saved by an older version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        category = try c.decodeIfPresent(ExpenseCategory.self, forKey: .category) ?? .other
        amount = try c.decodeIfPresent(Money.self, forKey: .amount) ?? .zero
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        receiptPhoto = try c.decodeIfPresent(String.self, forKey: .receiptPhoto)
        mileage = try c.decodeIfPresent(MileageTrip.self, forKey: .mileage)
    }
}

public enum ExpenseError: Error, Equatable {
    /// The amount is zero, negative or far too large to be real.
    case invalidAmount
    case notFound
}

extension AppData {
    /// Adds the expense, or replaces the saved one with the same id. The vendor and note are trimmed and kept short.
    public mutating func saveExpense(_ expense: Expense) throws {
        guard expense.amount.cents > 0, expense.amount <= Expense.maxAmount else { throw ExpenseError.invalidAmount }
        var clean = expense
        clean.vendor = String(expense.vendor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        clean.note = String(expense.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        if let i = expenses.firstIndex(where: { $0.id == expense.id }) { expenses[i] = clean } else { expenses.append(clean) }
    }

    public mutating func removeExpense(id: UUID) throws {
        guard expenses.contains(where: { $0.id == id }) else { throw ExpenseError.notFound }
        expenses.removeAll { $0.id == id }
    }
}

/// Reads what someone typed into an amount or miles box.
public enum ExpenseInput {
    /// A plain number from "12", "12.5", "$1,234.50" or "12,50" (a comma followed by one or two digits is a decimal mark).
    /// Nil when it is not a number.
    public static func number(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: " ", with: "")
        if !t.contains("."), t.filter({ $0 == "," }).count == 1, let comma = t.firstIndex(of: ",") {
            let digitsAfter = t.distance(from: comma, to: t.endIndex) - 1
            if digitsAfter == 1 || digitsAfter == 2 {
                t = String(t[t.startIndex..<comma]) + "." + String(t[t.index(after: comma)...])
            }
        }
        t = t.replacingOccurrences(of: ",", with: "")
        guard !t.isEmpty, t.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }), let value = Double(t), value.isFinite else { return nil }
        return value
    }

    /// Money from typed text, to the cent. Nil unless it is above zero and not absurdly large.
    public static func money(_ text: String) -> Money? {
        guard let value = number(text), value > 0, value <= Double(Expense.maxAmount.cents) / 100 else { return nil }
        let money = Money(cents: Int((value * 100).rounded()))
        return money.cents > 0 ? money : nil
    }
}

// MARK: - Profit

/// The span the profit screen adds up.
public enum ProfitPeriod: String, CaseIterable, Sendable {
    case thisWeek, thisMonth, season, thisYear

    /// Short, for the picker.
    public var title: String {
        switch self {
        case .thisWeek: return "Week"
        case .thisMonth: return "Month"
        case .season: return "Season"
        case .thisYear: return "Year"
        }
    }

    public var phrase: String {
        switch self {
        case .thisWeek: return "this week"
        case .thisMonth: return "this month"
        case .season: return "this season"
        case .thisYear: return "this year"
        }
    }

    public var previousPhrase: String {
        switch self {
        case .thisWeek: return "last week"
        case .thisMonth: return "last month"
        case .season: return "last season"
        case .thisYear: return "last year"
        }
    }

    /// The span and the one just before it. The start counts and the end does not.
    /// A season runs July 1 to June 30, so one winter stays in one season.
    public func intervals(now: Date, calendar: Calendar = .current) -> (current: DateInterval, previous: DateInterval) {
        func pair(_ unit: Calendar.Component) -> (current: DateInterval, previous: DateInterval) {
            let current = calendar.dateInterval(of: unit, for: now) ?? DateInterval(start: now, duration: 0)
            let previous = calendar.dateInterval(of: unit, for: current.start.addingTimeInterval(-3600))
                ?? DateInterval(start: current.start, duration: 0)
            return (current, previous)
        }
        switch self {
        case .thisWeek: return pair(.weekOfYear)
        case .thisMonth: return pair(.month)
        case .thisYear: return pair(.year)
        case .season:
            let year = calendar.component(.year, from: now), month = calendar.component(.month, from: now)
            let first = month >= 7 ? year : year - 1
            func july(_ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: 7, day: 1)) ?? now }
            func span(_ a: Date, _ b: Date) -> DateInterval { DateInterval(start: min(a, b), end: max(a, b)) }
            return (span(july(first), july(first + 1)), span(july(first - 1), july(first)))
        }
    }
}

public struct ExpenseCategoryTotal: Equatable, Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: ExpenseCategory
    public let total: Money
    public let count: Int
}

/// "Am I actually making money?": what came in, what went out, and what is left, for one span of time.
public struct ProfitReport: Equatable, Sendable {
    public let interval: DateInterval
    /// Payments received on invoices that are not void.
    public let moneyIn: Money
    /// Spending per category, largest first. Categories with nothing are left out.
    public let byCategory: [ExpenseCategoryTotal]
    public let expensesTotal: Money
    /// Clocked hours per person, with pay worked out for the people who have an hourly rate.
    public let labor: [TimesheetRow]
    public let laborHours: Double
    public let laborCost: Money
    /// People with clocked hours but no hourly rate. Their time is not in the labor cost.
    public let missingRates: [String]
    /// The expenses in the span, newest first.
    public let expenses: [Expense]
    public let previousMoneyIn: Money
    public let previousMoneyOut: Money

    public var moneyOut: Money { expensesTotal + laborCost }
    public var profit: Money { moneyIn - moneyOut }
    public var previousProfit: Money { previousMoneyIn - previousMoneyOut }
    /// How much more (or less, when negative) profit than the span before.
    public var profitChange: Money { profit - previousProfit }
    /// False when the span before had no money in or out, so there is nothing to compare with.
    public var hasPrevious: Bool { previousMoneyIn.cents != 0 || previousMoneyOut.cents != 0 }
    /// True when nothing came in and nothing went out.
    public var isEmpty: Bool { moneyIn.cents == 0 && moneyOut.cents == 0 }

    /// Profit as a share of the money that came in, to one decimal. Nil when nothing came in.
    public var marginPercent: Double? {
        guard moneyIn.cents > 0 else { return nil }
        return (Double(profit.cents) / Double(moneyIn.cents) * 1000).rounded() / 10
    }

    public static func compute(for data: AppData, period: ProfitPeriod, now: Date, calendar: Calendar = .current) -> ProfitReport {
        let spans = period.intervals(now: now, calendar: calendar)
        return compute(for: data, interval: spans.current, previous: spans.previous, now: now)
    }

    public static func compute(for data: AppData, interval: DateInterval, previous: DateInterval?, now: Date) -> ProfitReport {
        let current = Totals(data, interval, now: now)
        let before = previous.map { Totals(data, $0, now: now) }
        return ProfitReport(interval: interval, moneyIn: current.moneyIn, byCategory: current.byCategory, expensesTotal: current.expensesTotal,
                            labor: current.labor.rows, laborHours: current.labor.totalHours, laborCost: current.labor.payOwed,
                            missingRates: current.labor.missingRates, expenses: current.expenses,
                            previousMoneyIn: before?.moneyIn ?? .zero,
                            previousMoneyOut: before.map { $0.expensesTotal + $0.labor.payOwed } ?? .zero)
    }

    /// Everything added up for one span.
    private struct Totals {
        let moneyIn: Money
        let expenses: [Expense]
        let byCategory: [ExpenseCategoryTotal]
        let expensesTotal: Money
        let labor: TimesheetReport

        init(_ data: AppData, _ span: DateInterval, now: Date) {
            func inSpan(_ date: Date) -> Bool { date >= span.start && date < span.end }
            var received = 0
            for invoice in data.invoices where !invoice.isVoid {
                for payment in invoice.payments where inSpan(payment.date) { received += payment.amount.cents }
            }
            moneyIn = Money(cents: received)
            let mine = data.expenses.filter { inSpan($0.date) }.sorted { $0.date > $1.date }
            expenses = mine
            // Largest first. Equal totals keep the order of the category list, so the screen never reshuffles.
            let order = ExpenseCategory.allCases
            let perCategory = order.compactMap { category -> ExpenseCategoryTotal? in
                let list = mine.filter { $0.category == category }
                guard !list.isEmpty else { return nil }
                return ExpenseCategoryTotal(category: category, total: list.reduce(.zero) { $0 + $1.amount }, count: list.count)
            }
            byCategory = perCategory.sorted { a, b in
                if a.total != b.total { return a.total > b.total }
                return (order.firstIndex(of: a.category) ?? 0) < (order.firstIndex(of: b.category) ?? 0)
            }
            expensesTotal = mine.reduce(.zero) { $0 + $1.amount }
            // Labor uses the same sums as the timesheets screen, so the two always agree.
            var clocked = data
            clocked.timeEntries = data.timeEntries.filter { inSpan($0.start) }
            labor = TimesheetReport.compute(for: clocked, interval: span, now: now)
        }
    }
}

// MARK: - Spreadsheet for the accountant

public enum ExpenseCSV {
    public static let columns = ["Date", "Category", "Vendor", "Amount", "Note"]

    /// One row per expense, oldest first. Dates are YYYY-MM-DD in the given time zone. A mileage trip is spelled out in the note.
    public static func export(_ expenses: [Expense], timeZone: TimeZone = .current) -> String {
        let day = AccountingCSV.dayFormatter(timeZone)
        let rows = expenses.sorted { $0.date < $1.date }.map { e -> [String] in
            var note = e.note
            if let trip = e.mileage { note = note.isEmpty ? trip.summary : "\(note) (\(trip.summary))" }
            return [AccountingCSV.plain(day.string(from: e.date)), AccountingCSV.text(e.category.title), AccountingCSV.text(e.vendor),
                    AccountingCSV.plain(AccountingCSV.amount(e.amount)), AccountingCSV.text(note)]
        }
        return AccountingCSV.file(header: columns, rows: rows)
    }
}
