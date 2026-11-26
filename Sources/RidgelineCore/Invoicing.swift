import Foundation

public enum InvoiceStatus: String, Codable, Sendable {
    case draft, sent, partiallyPaid, paid, overdue, void
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case cash, check, card, bankTransfer, other
}

public enum InvoiceError: Error, Equatable {
    case notEditable
    case lineNotFound
    case invalidAmount
    case exceedsBalance
    case alreadyVoid
    case lateFeeAlreadyApplied
    case noLateFeeDue
}

public struct InvoiceLineItem: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var description: String
    public var amount: Money
    public var stormID: String?
    public var isLateFee: Bool

    public init(id: UUID = UUID(), description: String, amount: Money, stormID: String? = nil, isLateFee: Bool = false) {
        self.id = id
        self.description = description
        self.amount = amount
        self.stormID = stormID
        self.isLateFee = isLateFee
    }
}

/// A payment the owner records by hand (cash, check, or money received through their own account).
public struct ManualPayment: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var amount: Money
    public var date: Date
    public var method: PaymentMethod
    public var note: String

    public init(id: UUID = UUID(), amount: Money, date: Date, method: PaymentMethod, note: String = "") {
        self.id = id
        self.amount = amount
        self.date = date
        self.method = method
        self.note = note
    }
}

/// Late fees are never added automatically. The owner chooses to apply one, once, after the grace period.
/// Rule: a flat fee once the invoice is past due plus grace days, plus `monthlyPercent` of the balance for each
/// full 30 days after that, capped at `maxTotalFee` when set.
public struct LateFeePolicy: Equatable, Codable, Sendable {
    public var graceDays: Int
    public var flatFee: Money
    public var monthlyPercent: Int
    public var maxTotalFee: Money?

    public init(graceDays: Int = 14, flatFee: Money = .zero, monthlyPercent: Int = 0, maxTotalFee: Money? = nil) {
        self.graceDays = max(graceDays, 0)
        self.flatFee = flatFee
        self.monthlyPercent = max(monthlyPercent, 0)
        self.maxTotalFee = maxTotalFee
    }

    public func fee(balance: Money, dueDate: Date, now: Date) -> Money {
        guard balance.cents > 0 else { return .zero }
        let graceEnds = dueDate.addingTimeInterval(Double(graceDays) * 86_400)
        guard now > graceEnds else { return .zero }
        let monthsPast = Int(now.timeIntervalSince(graceEnds) / (30 * 86_400))
        var fee = flatFee + balance.percent(monthlyPercent) * monthsPast
        if let cap = maxTotalFee, fee > cap { fee = cap }
        return fee
    }
}

public struct Invoice: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var number: String
    public var customerID: UUID
    public var siteID: UUID
    public var issueDate: Date
    public var dueDate: Date
    public private(set) var lines: [InvoiceLineItem]
    public private(set) var payments: [ManualPayment]
    public private(set) var sentAt: Date?
    public private(set) var isVoid: Bool
    public private(set) var lateFeeApplied: Bool
    public var notes: String

    public init(id: UUID = UUID(), number: String, customerID: UUID, siteID: UUID, issueDate: Date, dueDate: Date,
                lines: [InvoiceLineItem] = [], notes: String = "") {
        self.id = id
        self.number = number
        self.customerID = customerID
        self.siteID = siteID
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.lines = lines
        self.payments = []
        self.sentAt = nil
        self.isVoid = false
        self.lateFeeApplied = false
        self.notes = notes
    }

    /// Builds a draft from the billing engine's result (zero-amount lines are dropped).
    public static func fromBilling(_ result: BillingResult, number: String, customerID: UUID, siteID: UUID,
                                   issueDate: Date, netDays: Int = 14) -> Invoice {
        let lines = result.lines.filter { $0.amount.cents != 0 }
            .map { InvoiceLineItem(description: $0.description, amount: $0.amount, stormID: $0.stormID) }
        return Invoice(number: number, customerID: customerID, siteID: siteID, issueDate: issueDate,
                       dueDate: issueDate.addingTimeInterval(Double(max(netDays, 0)) * 86_400), lines: lines)
    }

    public var total: Money { lines.reduce(.zero) { $0 + $1.amount } }
    public var paid: Money { payments.reduce(.zero) { $0 + $1.amount } }
    public var balance: Money { total - paid }

    /// Lines can be edited until the first payment is recorded or the invoice is voided.
    public var isEditable: Bool { !isVoid && payments.isEmpty }

    /// True once the due day is over. An invoice that says "due Nov 15" can be paid all of Nov 15, so it is late
    /// from the start of Nov 16, not from the hour of day it was created.
    public func isPastDue(now: Date, calendar: Calendar = .current) -> Bool {
        let dueDay = calendar.startOfDay(for: dueDate)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: dueDay) ?? dueDay.addingTimeInterval(86_400)
        return now >= dayAfter
    }

    public func status(now: Date, calendar: Calendar = .current) -> InvoiceStatus {
        if isVoid { return .void }
        if balance.cents <= 0 && !lines.isEmpty { return .paid }
        let late = isPastDue(now: now, calendar: calendar)
        if !payments.isEmpty { return late && balance.cents > 0 ? .overdue : .partiallyPaid }
        if sentAt == nil { return .draft }
        return late ? .overdue : .sent
    }

    // MARK: edits

    public mutating func addLine(_ line: InvoiceLineItem) throws {
        guard isEditable else { throw InvoiceError.notEditable }
        lines.append(line)
    }

    public mutating func removeLine(id: UUID) throws {
        guard isEditable else { throw InvoiceError.notEditable }
        guard let i = lines.firstIndex(where: { $0.id == id }) else { throw InvoiceError.lineNotFound }
        lines.remove(at: i)
    }

    public mutating func updateLine(id: UUID, description: String? = nil, amount: Money? = nil) throws {
        guard isEditable else { throw InvoiceError.notEditable }
        guard let i = lines.firstIndex(where: { $0.id == id }) else { throw InvoiceError.lineNotFound }
        if let description { lines[i].description = description }
        if let amount { lines[i].amount = amount }
    }

    public mutating func markSent(at date: Date) throws {
        guard !isVoid else { throw InvoiceError.alreadyVoid }
        if sentAt == nil { sentAt = date }
    }

    /// Records a payment. Payments over the balance are rejected so a typo cannot overpay an invoice.
    public mutating func record(_ payment: ManualPayment) throws {
        guard !isVoid else { throw InvoiceError.alreadyVoid }
        guard payment.amount.cents > 0 else { throw InvoiceError.invalidAmount }
        guard payment.amount <= balance else { throw InvoiceError.exceedsBalance }
        payments.append(payment)
        // A client who paid has the bill, so it is no longer a draft waiting to be sent (it would count as one forever).
        if sentAt == nil { sentAt = payment.date }
    }

    public mutating func void() { isVoid = true }

    /// The owner decides to charge the late fee. Adds one clearly labelled line, once.
    public mutating func applyLateFee(policy: LateFeePolicy, now: Date) throws {
        guard !isVoid else { throw InvoiceError.alreadyVoid }
        guard !lateFeeApplied else { throw InvoiceError.lateFeeAlreadyApplied }
        let fee = policy.fee(balance: balance, dueDate: dueDate, now: now)
        guard fee.cents > 0 else { throw InvoiceError.noLateFeeDue }
        lines.append(InvoiceLineItem(description: "Late fee", amount: fee, isLateFee: true))
        lateFeeApplied = true
    }
}

public enum InvoiceNumbering {
    /// Next number after the highest existing one with the same prefix, for example INV-0007 -> INV-0008.
    public static func next(existing: [String], prefix: String = "INV-", width: Int = 4) -> String {
        let highest = existing.compactMap { number -> Int? in
            guard number.hasPrefix(prefix) else { return nil }
            return Int(number.dropFirst(prefix.count))
        }.max() ?? 0
        let n = String(highest + 1)
        return prefix + String(repeating: "0", count: max(width - n.count, 0)) + n
    }
}

/// Splits a seasonal contract price into equal invoices with exact cents (the remainder goes on the last one).
public enum InstallmentPlan {
    public struct Installment: Equatable, Sendable {
        public let dueDate: Date
        public let amount: Money
    }

    public static func split(total: Money, count: Int, firstDue: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Installment] {
        guard count > 0, total.cents >= 0 else { return [] }
        let base = total.cents / count
        let remainder = total.cents - base * count
        return (0..<count).map { i in
            let due = calendar.date(byAdding: .month, value: i, to: firstDue) ?? firstDue
            return Installment(dueDate: due, amount: Money(cents: base + (i == count - 1 ? remainder : 0)))
        }
    }
}

public enum InvoiceCSV {
    /// One row per invoice line, for spreadsheets and accounting imports. Cells that start with a formula
    /// character get a leading apostrophe so a hostile customer name cannot run a formula in Excel.
    public static func export(_ invoices: [Invoice], customerName: (UUID) -> String, now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        var rows = ["Invoice Number,Customer,Invoice Date,Due Date,Description,Amount,Status"]
        for inv in invoices {
            for line in inv.lines {
                let cents = abs(line.amount.cents)
                let amount = "\(line.amount.cents < 0 ? "-" : "")\(cents / 100).\(String(format: "%02d", cents % 100))"
                // Text cells are guarded against spreadsheet formulas. The amount is a number we built, so it is not.
                rows.append([cell(inv.number), cell(customerName(inv.customerID)), cell(f.string(from: inv.issueDate)),
                             cell(f.string(from: inv.dueDate)), cell(line.description), cell(amount, guardFormula: false),
                             cell(inv.status(now: now).rawValue)].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    static func cell(_ raw: String, guardFormula: Bool = true) -> String {
        var text = raw
        if guardFormula, let first = text.first, "=+-@\t\r".contains(first) { text = "'" + text }
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            text = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}

/// Works out what is still unbilled for a site so creating an invoice twice never bills a storm twice.
public enum InvoicePlanner {
    public struct NextBilling: Equatable, Sendable {
        /// New lines to invoice.
        public let result: BillingResult
        /// Completed visits recorded after their storm was already invoiced (for example a return trip). They are
        /// not billed automatically; the owner can add a line by hand.
        public let heldBack: [Visit]
    }

    public static func nextBilling(terms: ContractTerms, visits: [Visit], existing: [Invoice], includeSeasonalBase: Bool = true) -> NextBilling {
        let active = existing.filter { !$0.isVoid }
        var invoicedStormIssue: [String: Date] = [:]
        for inv in active {
            for line in inv.lines where !line.isLateFee {
                if let storm = line.stormID {
                    invoicedStormIssue[storm] = min(invoicedStormIssue[storm] ?? inv.issueDate, inv.issueDate)
                }
            }
        }
        // Only a seasonal line counts. Other lines with no storm (a Quick invoice, a mowing job at the same address)
        // must not make the season price look billed, or it could never be invoiced.
        let baseAlreadyBilled = active.contains { $0.lines.contains { $0.stormID == nil && !$0.isLateFee && isSeasonalLine($0.description) } }
        let earlier = visits.filter { invoicedStormIssue[$0.stormID] != nil }
        let fresh = visits.filter { invoicedStormIssue[$0.stormID] == nil }
        let earlierPushes = SnowBilling.bill(terms: terms, visits: earlier, includeSeasonalBase: false).pushesUsed
        let result = SnowBilling.bill(terms: terms, visits: fresh, includeSeasonalBase: !baseAlreadyBilled && includeSeasonalBase, alreadyUsedPushes: earlierPushes)
        let held = earlier.filter { v in
            if case .completed = v.status, let issued = invoicedStormIssue[v.stormID] { return v.date > issued }
            return false
        }
        return NextBilling(result: result, heldBack: held)
    }

    /// The season price lines SnowBilling writes ("Seasonal snow contract", "Seasonal base (includes 8 pushes)"), and a
    /// season price billed by hand from the price list ("Seasonal driveway").
    static func isSeasonalLine(_ description: String) -> Bool {
        description.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("seasonal")
    }
}
