import Foundation

/// Small pieces shared by the accountant files: plain numbers, calendar dates and safely quoted cells.
enum AccountingCSV {
    /// "1234.50": no currency sign and no thousands separator, so a spreadsheet reads it as a number.
    static func amount(_ m: Money) -> String {
        let c = abs(m.cents)
        return "\(m.cents < 0 ? "-" : "")\(c / 100).\(c % 100 < 10 ? "0" : "")\(c % 100)"
    }

    /// Dates as YYYY-MM-DD, the one format every accounting import reads the same way.
    static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// A text cell: line breaks become spaces (many imports stop at them), then commas and quotes are quoted,
    /// and a cell that starts like a formula gets a leading apostrophe.
    static func text(_ raw: String) -> String {
        let flat = raw.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return InvoiceCSV.cell(flat)
    }

    /// A cell the app built itself (a number or a date), so it is not guarded against formulas.
    static func plain(_ raw: String) -> String { InvoiceCSV.cell(raw, guardFormula: false) }

    static func file(header: [String], rows: [[String]]) -> String {
        ([header.map(text).joined(separator: ",")] + rows.map { $0.joined(separator: ",") }).joined(separator: "\r\n") + "\r\n"
    }

    /// True when the date is in the range. The start counts, the end does not, so two ranges side by side never share a record.
    static func contains(_ range: DateInterval?, _ date: Date) -> Bool {
        guard let range else { return true }
        return date >= range.start && date < range.end
    }
}

/// Invoices and payments as two spreadsheets an accountant can open or import into QuickBooks or Xero.
/// Void invoices are left out of both files, because they are not income.
public enum AccountingExport {
    public static let invoiceColumns = ["Invoice Number", "Invoice Date", "Due Date", "Client", "Description", "Total", "Paid", "Balance", "Status"]
    public static let paymentColumns = ["Date", "Invoice Number", "Client", "Amount", "Method"]

    /// One row per invoice dated in the range (every invoice when there is no range), oldest first.
    /// The lines of an invoice are joined into one description.
    public static func invoicesCSV(_ data: AppData, in range: DateInterval? = nil, now: Date, timeZone: TimeZone = .current) -> String {
        let day = AccountingCSV.dayFormatter(timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone                              // "Overdue" follows the same days the date columns show
        let names = clientNames(data)
        let rows = data.invoices
            .filter { !$0.isVoid && AccountingCSV.contains(range, $0.issueDate) }
            .sorted { $0.issueDate != $1.issueDate ? $0.issueDate < $1.issueDate : $0.number < $1.number }
            .map { inv -> [String] in
                let description = inv.lines.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.joined(separator: "; ")
                return [AccountingCSV.text(inv.number), AccountingCSV.plain(day.string(from: inv.issueDate)),
                        AccountingCSV.plain(day.string(from: inv.dueDate)), AccountingCSV.text(names[inv.customerID] ?? ""),
                        AccountingCSV.text(description), AccountingCSV.plain(AccountingCSV.amount(inv.total)),
                        AccountingCSV.plain(AccountingCSV.amount(inv.paid)), AccountingCSV.plain(AccountingCSV.amount(inv.balance)),
                        AccountingCSV.text(statusTitle(inv.status(now: now, calendar: calendar)))]
            }
        return AccountingCSV.file(header: invoiceColumns, rows: rows)
    }

    /// One row per payment received in the range (every payment when there is no range), oldest first.
    public static func paymentsCSV(_ data: AppData, in range: DateInterval? = nil, timeZone: TimeZone = .current) -> String {
        let day = AccountingCSV.dayFormatter(timeZone)
        let names = clientNames(data)
        var found: [(date: Date, number: String, client: String, payment: ManualPayment)] = []
        for inv in data.invoices where !inv.isVoid {
            for p in inv.payments where AccountingCSV.contains(range, p.date) {
                found.append((p.date, inv.number, names[inv.customerID] ?? "", p))
            }
        }
        found.sort { $0.date != $1.date ? $0.date < $1.date : $0.number < $1.number }
        let rows = found.map { f -> [String] in
            [AccountingCSV.plain(day.string(from: f.date)), AccountingCSV.text(f.number), AccountingCSV.text(f.client),
             AccountingCSV.plain(AccountingCSV.amount(f.payment.amount)), AccountingCSV.text(methodTitle(f.payment.method))]
        }
        return AccountingCSV.file(header: paymentColumns, rows: rows)
    }

    public static func statusTitle(_ status: InvoiceStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .partiallyPaid: return "Partly paid"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .void: return "Void"
        }
    }

    public static func methodTitle(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: return "Cash"
        case .check: return "Check"
        case .card: return "Card"
        case .bankTransfer: return "Bank transfer"
        case .other: return "Other"
        }
    }

    private static func clientNames(_ data: AppData) -> [UUID: String] {
        Dictionary(data.customers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}
