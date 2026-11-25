#if canImport(SwiftUI)
import SwiftUI
import Charts
import UniformTypeIdentifiers
import RidgelineCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A spreadsheet for the share sheet, with a real file name so it arrives as "expenses-....csv".
struct CSVFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName { $0.name }
    }
}

private extension ExpenseCategory {
    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .saltAndMaterials: return "shippingbox.fill"
        case .equipment: return "wrench.and.screwdriver.fill"
        case .repairs: return "hammer.fill"
        case .insurance: return "shield.fill"
        case .subcontractors: return "person.2.fill"
        case .supplies: return "cart.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .fuel: return .orange
        case .saltAndMaterials: return .teal
        case .equipment: return .blue
        case .repairs: return .red
        case .insurance: return .indigo
        case .subcontractors: return .purple
        case .supplies: return .green
        case .other: return .gray
        }
    }
}

/// "Am I actually making money?": what came in, what went out and what is left, with the expenses behind it.
struct ProfitView: View {
    @Environment(AppModel.self) private var model
    @State private var period: ProfitPeriod = .thisMonth
    @State private var adding = false
    @State private var editing: Expense?

    /// How many expenses the list shows. The export always has all of them.
    private static let listLimit = 25

    private var periodOptions: [(value: ProfitPeriod, title: String, icon: String?)] {
        ProfitPeriod.allCases.map { p in (value: p, title: p.title, icon: nil as String?) }
    }

    var body: some View {
        ScreenStack {
            if model.data.can(.viewRevenue) {
                page
            } else {
                AppPage(title: "Profit", icon: "chart.pie.fill") {
                    EmptyCard(icon: "lock.fill", title: "Not available", message: "Ask the owner to let you see revenue and invoices.")
                }
            }
        }
    }

    private var page: some View {
        let now = Date()
        let report = ProfitReport.compute(for: model.data, period: period, now: now)
        return AppPage(title: "Profit", icon: "chart.pie.fill") {
            PillChoice(options: periodOptions, selection: $period)
            heroCard(report)
            PrimaryActionButton(title: "Add expense", icon: "plus") { adding = true }
            chartCard(report)
            spendingCard(report)
            expensesCard(report)
            exportCard(report, now: now)
        }
        .sheet(isPresented: $adding) { ExpenseSheet() }
        .sheet(item: $editing) { expense in ExpenseSheet(expense: expense) }
    }

    // MARK: the big number

    @ViewBuilder private func heroCard(_ r: ProfitReport) -> some View {
        let color: Color = r.isEmpty ? .primary : (r.profit.cents < 0 ? .red : .green)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Profit \(period.phrase)")
                Text(r.profit.formatted)
                    .font(.system(size: 44, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(color)
                Text(marginLine(r)).font(.callout).foregroundStyle(.secondary)
                changeLine(r)
                Text(rangeText(r.interval)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func marginLine(_ r: ProfitReport) -> String {
        if r.isEmpty { return "Nothing in or out yet \(period.phrase)." }
        guard let margin = r.marginPercent else { return "No payments received \(period.phrase)." }
        let percent = String(format: "%g", margin)
        return margin < 0 ? "\(percent)% margin. You spent more than came in." : "\(percent)% margin"
    }

    @ViewBuilder private func changeLine(_ r: ProfitReport) -> some View {
        if r.hasPrevious {
            let up = r.profitChange.cents >= 0
            let amount = Money(cents: abs(r.profitChange.cents)).formatted
            Text("\(up ? "\u{2197}" : "\u{2198}") \(amount) \(up ? "more" : "less") than \(period.previousPhrase)")
                .font(.callout.weight(.medium)).foregroundStyle(up ? Color.green : Color.red)
        } else {
            Text("Nothing \(period.previousPhrase) to compare with").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// "Jan 1 to Jan 31", with the years when the span crosses New Year.
    private func rangeText(_ span: DateInterval) -> String {
        let lastDay = max(span.start, span.end.addingTimeInterval(-1))
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: span.start) == calendar.component(.year, from: lastDay)
        let f = DateFormatter.make(sameYear ? "MMM d" : "MMM d, yyyy")
        return "\(f.string(from: span.start)) to \(f.string(from: lastDay))"
    }

    // MARK: money in and out

    private struct FlowBar: Identifiable {
        let label: String
        let amount: Money
        let color: Color
        var id: String { label }
    }

    @ViewBuilder private func chartCard(_ r: ProfitReport) -> some View {
        let bars = [FlowBar(label: "Money in", amount: r.moneyIn, color: .green),
                    FlowBar(label: "Expenses", amount: r.expensesTotal, color: .orange),
                    FlowBar(label: "Crew pay", amount: r.laborCost, color: .purple)]
        CardGroup(title: "Money in and out") {
            if r.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing to show yet").font(.title3.weight(.semibold))
                    Text("Record a payment on an invoice, or add an expense.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Kind", bar.label), y: .value("Dollars", Double(bar.amount.cents) / 100))
                        .foregroundStyle(bar.color.gradient)
                        .cornerRadius(6)
                }
                .frame(height: 200)
            }
            RowDivider()
            FactRow(label: "Money in", value: r.moneyIn.formatted, valueColor: .green)
            FactRow(label: "Money out", value: r.moneyOut.formatted, valueColor: r.moneyOut.cents > 0 ? .red : .primary)
        }
    }

    // MARK: where it went

    @ViewBuilder private func spendingCard(_ r: ProfitReport) -> some View {
        CardGroup(title: "Where the money went", footer: laborFooter(r)) {
            if r.byCategory.isEmpty && r.laborHours <= 0 {
                Text("Nothing spent \(period.phrase).").foregroundStyle(.secondary)
            }
            ForEach(Array(r.byCategory.enumerated()), id: \.element.id) { index, line in
                if index > 0 { RowDivider() }
                SpendRow(icon: line.category.icon, tint: line.category.tint, title: line.category.title,
                         detail: "\(line.count) expense\(line.count == 1 ? "" : "s")", amount: line.total)
            }
            if r.laborHours > 0 {
                if !r.byCategory.isEmpty { RowDivider() }
                SpendRow(icon: "clock.fill", tint: .purple, title: "Crew pay",
                         detail: "\(String(format: "%.1f", r.laborHours)) hours on the clock", amount: r.laborCost)
            }
        }
    }

    private func laborFooter(_ r: ProfitReport) -> String? {
        if !r.missingRates.isEmpty {
            return "Set hourly pay in Team to count pay for \(r.missingRates.joined(separator: ", "))."
        }
        return r.laborHours > 0 ? "Crew pay is clocked hours times each person's hourly pay." : nil
    }

    // MARK: the expenses

    @ViewBuilder private func expensesCard(_ r: ProfitReport) -> some View {
        let shown = Array(r.expenses.prefix(Self.listLimit))
        CardGroup(title: "Expenses", footer: expensesFooter(shown: shown.count, all: r.expenses.count)) {
            if shown.isEmpty {
                Text("No expenses \(period.phrase). Add fuel, salt, repairs and other costs to see your real profit.").foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, expense in
                if index > 0 { RowDivider() }
                Button { editing = expense } label: {
                    SpendRow(icon: expense.mileage == nil ? expense.category.icon : "car.fill", tint: expense.category.tint,
                             title: expense.vendor.isEmpty ? expense.category.title : expense.vendor,
                             detail: detail(expense), amount: expense.amount, chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func expensesFooter(shown: Int, all: Int) -> String? {
        if all == 0 { return nil }
        if all > shown { return "Showing the latest \(shown) of \(all). The export has them all." }
        return "Tap an expense to change or delete it."
    }

    private func detail(_ e: Expense) -> String {
        var parts: [String] = []
        if !e.vendor.isEmpty { parts.append(e.category.title) }
        parts.append(DateFormatter.make("MMM d").string(from: e.date))
        if let trip = e.mileage { parts.append(trip.summary) }
        if e.receiptPhoto != nil { parts.append("receipt saved") }
        return parts.joined(separator: " \u{B7} ")
    }

    // MARK: for the accountant

    @ViewBuilder private func exportCard(_ r: ProfitReport, now: Date) -> some View {
        let expenses = CSVFile(name: fileName("expenses", r.interval), text: ExpenseCSV.export(r.expenses))
        let invoices = CSVFile(name: fileName("invoices", r.interval), text: AccountingExport.invoicesCSV(model.data, in: r.interval, now: now))
        let payments = CSVFile(name: fileName("payments", r.interval), text: AccountingExport.paymentsCSV(model.data, in: r.interval))
        CardGroup(title: "Export for accountant",
                  footer: "Spreadsheet files for \(rangeText(r.interval)). They import into QuickBooks, Xero or any spreadsheet.") {
            ShareLink(item: expenses, preview: SharePreview(expenses.name)) {
                CardLinkRow(icon: "cart.fill", tint: .orange, title: "Expenses", detail: "Date, category, vendor, amount, note")
            }
            RowDivider()
            ShareLink(item: invoices, preview: SharePreview(invoices.name)) {
                CardLinkRow(icon: "doc.text.fill", tint: .blue, title: "Invoices", detail: "Number, dates, client, total, paid, balance")
            }
            RowDivider()
            ShareLink(item: payments, preview: SharePreview(payments.name)) {
                CardLinkRow(icon: "banknote.fill", tint: .green, title: "Payments", detail: "Date, invoice, client, amount, method")
            }
        }
        .buttonStyle(.plain)
    }

    /// "expenses-2027-01-01-to-2027-01-31.csv"
    private func fileName(_ kind: String, _ span: DateInterval) -> String {
        let f = DateFormatter.make("yyyy-MM-dd")
        f.locale = Locale(identifier: "en_US_POSIX")
        let lastDay = max(span.start, span.end.addingTimeInterval(-1))
        return "\(kind)-\(f.string(from: span.start))-to-\(f.string(from: lastDay)).csv"
    }
}

/// One line of spending: an icon, what it was, a short detail and the amount.
private struct SpendRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let amount: Money
    var chevron = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Text(amount.formatted).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
    }
}

/// Add an expense, or change or delete one: a typed amount or a drive counted by the mile, with an optional receipt photo.
struct ExpenseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The expense being changed. Nil adds a new one.
    var expense: Expense?

    @State private var loaded = false
    @State private var byMile = false
    @State private var amountText = ""
    @State private var milesText = ""
    @State private var rateText = ""
    @State private var category: ExpenseCategory = .fuel
    @State private var date = Date()
    @State private var vendor = ""
    @State private var note = ""
    /// The receipt photo, as the photo row saves it. Only the newest one is kept.
    @State private var receipts: [PhotoRef] = []
    @State private var receiptPreview: Image?
    @State private var problem: String?
    @State private var confirmDelete = false

    private var trip: MileageTrip? {
        guard let miles = ExpenseInput.number(milesText), miles > 0,
              let rate = ExpenseInput.number(rateText), rate > 0 else { return nil }
        return MileageTrip(miles: miles, dollarsPerMile: rate)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(expense == nil ? "Add expense" : "Edit expense").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                PillChoice(options: [(false, "Amount", "dollarsign.circle"), (true, "Mileage", "car.fill")], selection: $byMile)
                amountCard
                detailsCard
                receiptCard
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryActionButton(title: "Save expense", icon: "checkmark") { save() }
                if expense != nil {
                    PrimaryActionButton(title: "Delete expense", icon: "trash", destructive: true) { confirmDelete = true }
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .onAppear { load() }
        .onChange(of: receipts.count) {
            if receipts.count > 1, let newest = receipts.last { receipts = [newest] }
        }
        .task(id: receipts.last?.filename) { receiptPreview = loadReceipt() }
        .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder private var amountCard: some View {
        if byMile {
            CardGroup(title: "Mileage", footer: "Miles times the rate is the amount. Ask your accountant which rate to use.") {
                PillField(label: "Miles driven", required: true, placeholder: "42", text: $milesText, kind: .number)
                PillField(label: "Rate per mile", required: true, placeholder: "0.70", text: $rateText, kind: .number)
                if let trip = trip {
                    RowDivider()
                    FactRow(label: trip.summary, value: trip.amount.formatted)
                }
            }
        } else {
            CardGroup(title: "Amount") {
                PillField(label: "Amount", required: true, placeholder: "45.00", text: $amountText, kind: .number)
            }
        }
    }

    private var detailsCard: some View {
        CardGroup(title: "Details") {
            PillMenu(label: "Category", options: ExpenseCategory.allCases.map { ($0, $0.title) }, selection: $category)
            DatePicker("Date", selection: $date, displayedComponents: .date).font(.title3)
            PillField(label: "Paid to", optional: true, placeholder: "Gas station, supplier, shop", text: $vendor)
            PillNotes(label: "Note", placeholder: "What it was for", text: $note)
        }
    }

    private var receiptCard: some View {
        CardGroup(title: "Receipt", footer: "Optional. The photo stays on this device.") {
            PhotoCaptureRow(title: "Receipt photo", kind: .other, photos: $receipts)
            if let receiptPreview {
                receiptPreview.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Receipt photo")
            }
            if !receipts.isEmpty {
                SecondaryActionButton(title: "Remove photo", icon: "trash") { receipts = [] }
            }
        }
    }

    // MARK: actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        // Start from the rate used last time, so it is typed once.
        let lastRate = model.data.expenses.last(where: { $0.mileage != nil })?.mileage?.centsPerMile ?? 70
        rateText = Self.rateString(lastRate)
        guard let e = expense else { return }
        category = e.category
        date = e.date
        vendor = e.vendor
        note = e.note
        if let trip = e.mileage {
            byMile = true
            milesText = String(format: "%g", trip.miles)
            rateText = Self.rateString(trip.centsPerMile)
        } else {
            amountText = "\(e.amount.cents / 100).\(String(format: "%02d", abs(e.amount.cents) % 100))"
        }
        if let name = e.receiptPhoto {
            receipts = [PhotoRef(kind: .other, filename: name, capturedAt: e.date, sha256: "")]
        }
    }

    /// "0.70", or "0.725" for a rate with a half cent.
    private static func rateString(_ centsPerMile: Double) -> String {
        let wholeCents = abs(centsPerMile - centsPerMile.rounded()) < 0.0001
        return String(format: wholeCents ? "%.2f" : "%.3f", centsPerMile / 100)
    }

    private func loadReceipt() -> Image? {
        guard let name = receipts.last?.filename, let storage = model.photoStorage else { return nil }
        // Only ever a file inside the photo folder, whatever name a restored backup carries.
        let url = storage.directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }

    private func save() {
        let id = expense?.id ?? UUID()
        let receipt = receipts.last?.filename
        let draft: Expense
        if byMile {
            guard let trip = trip, trip.amount.cents > 0 else {
                problem = "Enter the miles and the rate per mile."
                return
            }
            draft = Expense(id: id, date: date, category: category, mileage: trip, vendor: vendor, note: note, receiptPhoto: receipt)
        } else {
            guard let amount = ExpenseInput.money(amountText) else {
                problem = "Enter the amount, like 45.00."
                return
            }
            draft = Expense(id: id, date: date, category: category, amount: amount, vendor: vendor, note: note, receiptPhoto: receipt)
        }
        if model.edit({ try $0.saveExpense(draft) }) != nil {
            problem = "That amount does not look right. Check it and try again."
            return
        }
        dismiss()
    }

    private func remove() {
        if let id = expense?.id { model.edit { try $0.removeExpense(id: id) } }
        dismiss()
    }
}
#endif
