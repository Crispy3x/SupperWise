#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Invoices built from the visit log. One line per storm, skipped visits are never billed.
struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var sendingReminders = false

    var body: some View {
        ScreenStack {
            List {
                if model.data.contracts.isEmpty {
                    Text("No contracts yet.").foregroundStyle(.secondary)
                }
                ForEach(model.data.contracts) { contract in
                    if let site = model.data.sites.first(where: { $0.id == contract.siteID }) {
                        let visits = model.data.visitLog.records(forSite: site.id).map { $0.asBillingVisit() }
                        let result = SnowBilling.bill(terms: contract.terms, visits: visits)
                        Section("\(model.customerName(for: site)), \(site.address)") {
                            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top) {
                                    Text(line.description).font(.footnote)
                                    Spacer()
                                    Text(line.amount.formatted)
                                }
                            }
                            HStack {
                                Text("Total").bold()
                                Spacer()
                                Text(result.total.formatted).bold()
                            }
                            Button("Create invoice for unbilled storms") { message = model.createInvoice(for: contract) }
                                .font(.footnote)
                            if result.capReached {
                                Label("Included pushes used up: further pushes bill as overage", systemImage: "exclamationmark.circle")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            if result.skippedVisitCount > 0 {
                                Text("\(result.skippedVisitCount) skipped visit(s) not billed")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                let reminders = model.reminderPlan()
                if !reminders.messages.isEmpty {
                    Section {
                        Button(sendingReminders ? "Sending..." : "Send \(reminders.messages.count) friendly reminder\(reminders.messages.count == 1 ? "" : "s")") {
                            Task {
                                sendingReminders = true
                                message = await model.sendReminders()
                                sendingReminders = false
                            }
                        }
                        .disabled(sendingReminders)
                    } header: {
                        Text("Overdue")
                    } footer: {
                        Text("Only clients who agreed to messages get one. Each invoice gets at most three, a week apart.")
                    }
                }
                Section("Saved invoices") {
                    if model.data.invoices.isEmpty { Text("No invoices created yet.").foregroundStyle(.secondary) }
                    ForEach(model.data.invoices) { inv in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(inv.number).font(.headline)
                                Spacer()
                                Text(inv.status(now: Date()).rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Total \(inv.total.formatted), paid \(inv.paid.formatted), balance \(inv.balance.formatted)").font(.footnote)
                            HStack {
                                if inv.sentAt == nil && !inv.isVoid {
                                    Button("Mark sent") { message = model.updateInvoice(id: inv.id) { try $0.markSent(at: Date()) } }
                                }
                                if inv.balance.cents > 0 && !inv.isVoid {
                                    Button("Record payment in full") {
                                        message = model.updateInvoice(id: inv.id) {
                                            try $0.record(ManualPayment(amount: $0.balance, date: Date(), method: .other))
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.footnote)
                        }
                    }
                    if !model.data.invoices.isEmpty {
                        ShareLink(item: model.invoicesCSV()) { Label("Export all as CSV", systemImage: "square.and.arrow.up") }
                    }
                }
                if let message { Section { Text(message).font(.footnote) } }
                Section {
                    Text("Late fees are never added automatically. Payment links are not built in yet. Send the invoice and use your own payment account.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Invoices")
        }
    }
}
#endif
