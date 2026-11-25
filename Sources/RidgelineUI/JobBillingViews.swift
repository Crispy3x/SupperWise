#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The price on a job card, and whether a finished visit is billed. Only people who may see money get it.
struct JobPriceTag: View {
    @Environment(AppModel.self) private var model
    /// The job, or for a repeating job the visit on the card.
    let job: Job

    private var text: String {
        let price = job.priceTotal.formatted
        guard job.status == .done else { return price }
        if let invoice = model.data.invoice(forJobVisit: job.id, on: job.start) { return "\(price) · Invoice \(invoice.number)" }
        return "\(price) · Ready to bill"
    }

    var body: some View {
        if !job.isTask && job.hasPrice && model.data.can(.viewRevenue) {
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
        }
    }
}

/// Pick what a job costs: tap services from the price list and set how many, or type an amount.
/// Used in the new job steps and when changing the price of a job.
struct JobPriceSection: View {
    @Environment(AppModel.self) private var model
    @Binding var lines: [JobPriceLine]
    @Binding var customAmount: String
    /// A typed amount goes on the invoice under the job's title.
    var jobTitle = ""
    var repeats = false
    var hasClient = true

    private struct Choice: Identifiable {
        let id: String
        let name: String
        let price: Money
        let detail: String
    }

    private var tint: Color { Theme.accent(model.data.profile.accentColor) }

    /// The price list, then any line already on the job that is not on the list (an amount typed earlier, or a service that was renamed).
    private var choices: [Choice] {
        var seen = Set<String>()
        var out: [Choice] = []
        for s in model.data.priceList {
            let name = String(s.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            out.append(Choice(id: s.id.uuidString, name: name, price: s.price, detail: "\(s.price.formatted) \(s.unit.title)"))
        }
        for line in lines where seen.insert(line.name).inserted {
            out.append(Choice(id: line.id.uuidString, name: line.name, price: line.unitPrice, detail: "Only on this job"))
        }
        return out
    }

    private var total: Money {
        JobBilling.total(JobBilling.lines(picked: lines, customAmount: customAmount, customName: jobTitle))
    }

    private var amountIsUnreadable: Bool {
        !customAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && JobBilling.cents(fromDollars: customAmount) == nil
    }

    private var afterDone: String {
        let start = repeats ? "Every visit costs this much. " : ""
        if model.data.profile.invoiceAutomation == .off {
            return start + "When the job is done, it shows under Ready to bill in Invoices."
        }
        return start + "When you mark the job done, a draft invoice is made for you to check and send."
    }

    var body: some View {
        CardGroup(title: "Price", footer: "Tap what this job includes. You can change the price for this job only.") {
            if choices.isEmpty {
                Text("No services on your price list yet. Type an amount below, or add services in Settings > Your services and prices.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                if index > 0 { RowDivider() }
                row(choice)
            }
        }
        CardGroup(footer: afterDone) {
            PillField(label: "Or type an amount", optional: true, placeholder: "0.00", text: $customAmount, kind: .number)
            if amountIsUnreadable {
                Text("Type a number, like 45 or 45.50.").font(.footnote).foregroundStyle(.orange)
            }
            RowDivider()
            FactRow(label: repeats ? "Total for each visit" : "Total", value: total.formatted)
        }
        if total.cents > 0 && !hasClient {
            Label("This job has no client yet. Pick one so it can be invoiced.", systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func row(_ choice: Choice) -> some View {
        let line = lines.first { $0.name == choice.name }
        let on = line != nil
        Button {
            if on {
                lines.removeAll { $0.name == choice.name }
            } else {
                lines.append(JobPriceLine(name: choice.name, quantity: 1, unitPrice: choice.price))
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(on ? tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text(choice.detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if let line {
                    Text(line.total.formatted).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        if on {
            PillStepper(label: "How many", value: quantityBinding(choice.name), range: 1...99, step: 1, format: { "\(Int($0))" })
            PillStepper(label: "Price each", value: priceBinding(choice.name), range: 0...20_000, step: 5, format: { QuickInvoiceSheet.money($0).formatted })
        }
    }

    private func quantityBinding(_ name: String) -> Binding<Double> {
        Binding(get: { Double(lines.first { $0.name == name }?.quantity ?? 1) },
                set: { value in
                    guard let i = lines.firstIndex(where: { $0.name == name }) else { return }
                    lines[i].quantity = max(Int(value.rounded()), 1)
                })
    }

    private func priceBinding(_ name: String) -> Binding<Double> {
        Binding(get: { Double(lines.first { $0.name == name }?.unitPriceCents ?? 0) / 100 },
                set: { value in
                    guard let i = lines.firstIndex(where: { $0.name == name }) else { return }
                    lines[i].unitPriceCents = QuickInvoiceSheet.money(value).cents
                })
    }
}

/// Add or change the price of a job that already exists.
struct JobPriceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let jobID: UUID
    @State private var lines: [JobPriceLine] = []
    @State private var customAmount = ""
    @State private var loaded = false
    @State private var problem: String?

    private var job: Job? { model.data.jobs.first { $0.id == jobID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Job price").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let job {
                    JobPriceSection(lines: $lines, customAmount: $customAmount, jobTitle: job.title, repeats: job.repeats,
                                    hasClient: model.data.billingCustomerID(forJob: job) != nil)
                    if job.repeats {
                        Text("Visits already on an invoice keep the old price.").font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    PrimaryActionButton(title: "Save price", icon: "checkmark") { save() }
                } else {
                    EmptyCard(icon: "briefcase", title: "Job not found", message: "This job no longer exists.")
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            lines = job?.priceLines ?? []
        }
    }

    private func save() {
        let cleaned = JobBilling.lines(picked: lines, customAmount: customAmount, customName: job?.title ?? "")
        problem = model.setJobPrice(cleaned, id: jobID)
        if problem == nil { dismiss() }
    }
}

/// On the job screen: what the job costs and where its invoice stands. A finished visit can be invoiced from here.
struct JobBillingSection: View {
    @Environment(AppModel.self) private var model
    /// The job, or for a repeating job the visit on screen.
    let job: Job
    @State private var opened: Opened?
    @State private var problem: String?

    private enum Opened: Identifiable {
        case invoice(String)
        case price

        var id: String {
            switch self {
            case .invoice(let number): return "invoice-" + number
            case .price: return "price"
            }
        }
    }

    private var canEdit: Bool { model.data.can(.editJobs) }

    var body: some View {
        if model.data.can(.viewRevenue) && !job.isTask {
            Group {
                if job.hasPrice {
                    priceCard
                } else if canEdit {
                    SecondaryActionButton(title: "Add a price", icon: "dollarsign.circle") { opened = .price }
                }
            }
            .sheet(item: $opened) { which in
                switch which {
                case .invoice(let number): InvoiceDetailSheet(number: number)
                case .price: JobPriceSheet(jobID: job.id)
                }
            }
        }
    }

    @ViewBuilder private var priceCard: some View {
        let invoice = model.data.invoice(forJobVisit: job.id, on: job.start)
        CardGroup(title: "Price", footer: footer(invoiced: invoice != nil)) {
            ForEach(job.priceLines ?? []) { line in
                FactRow(label: line.label, value: line.total.formatted)
            }
            RowDivider()
            FactRow(label: job.repeats ? "Total for this visit" : "Total", value: job.priceTotal.formatted)
            if let invoice {
                RowDivider()
                Button { opened = .invoice(invoice.number) } label: {
                    CardLinkRow(icon: "doc.text.fill", tint: Theme.accent(model.data.profile.accentColor),
                                title: "Invoice \(invoice.number)", detail: "\(statusText(invoice)) · \(invoice.total.formatted)")
                }
                .buttonStyle(.plain)
            } else if job.status == .done {
                PrimaryActionButton(title: "Create invoice", icon: "doc.badge.plus") { createInvoice() }
            }
            if canEdit && (job.repeats || invoice == nil) {
                SecondaryActionButton(title: "Change price", icon: "pencil") { opened = .price }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private func footer(invoiced: Bool) -> String? {
        if invoiced || job.status == .cancelled { return nil }
        if job.status == .done { return "This visit is finished and not on an invoice yet." }
        if model.data.profile.invoiceAutomation == .off { return "Mark it done, then create the invoice here or in Invoices." }
        return "A draft invoice is made when you mark this done."
    }

    private func statusText(_ invoice: Invoice) -> String {
        switch invoice.status(now: Date()) {
        case .draft: return "Draft, not sent yet"
        case .sent: return "Sent"
        case .partiallyPaid: return "Partly paid"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .void: return "Void"
        }
    }

    private func createInvoice() {
        let result = model.createInvoice(forJobVisit: job.id, on: job.start)
        problem = result.problem
        if let number = result.number { opened = .invoice(number) }
    }
}

/// Invoices: clients with finished, priced jobs that are not on an invoice yet. One tap makes a draft invoice per client.
struct ReadyToBillCard: View {
    @Environment(AppModel.self) private var model
    @State private var note: String?
    @State private var openedInvoice: String?

    var body: some View {
        if model.data.can(.viewRevenue) {
            let work = model.data.uninvoicedWork()
            Group {
                if !work.isEmpty || note != nil {
                    CardGroup(title: "Ready to bill",
                              footer: work.isEmpty ? nil : "Finished jobs with a price that are not on an invoice yet. Each client gets one draft invoice with a line for every job. Nothing is sent until you send it.") {
                        ForEach(Array(work.enumerated()), id: \.element.id) { index, client in
                            if index > 0 { RowDivider() }
                            clientRow(client)
                        }
                        if work.count > 1 {
                            RowDivider()
                            PrimaryActionButton(title: "Invoice all", icon: "doc.on.doc.fill") { invoiceAll() }
                        }
                        if let note {
                            if !work.isEmpty { RowDivider() }
                            Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { openedInvoice != nil }, set: { if !$0 { openedInvoice = nil } })) {
                if let n = openedInvoice { InvoiceDetailSheet(number: n) }
            }
        }
    }

    private func clientRow(_ client: ClientUninvoicedWork) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.customerName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text("\(client.visits.count) finished job\(client.visits.count == 1 ? "" : "s") · \(client.total.formatted)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button { invoiceOne(client) } label: {
                Text("Invoice").font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Look.pill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Invoice \(client.customerName)")
        }
    }

    private func invoiceOne(_ client: ClientUninvoicedWork) {
        let result = model.billFinishedWork(forClient: client.customerID)
        if let made = result.invoices.first {
            note = "Draft invoice \(made.number) created for \(client.customerName): \(made.total.formatted)."
            openedInvoice = made.number
        } else {
            note = result.summary
        }
    }

    private func invoiceAll() {
        let result = model.billFinishedWork()
        var text = result.summary
        if !result.invoices.isEmpty && result.problems.isEmpty { text += " They are under Saved invoices below. Nothing was sent." }
        note = text
    }
}
#endif
