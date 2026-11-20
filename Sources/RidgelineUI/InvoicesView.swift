#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Invoices built from the visit log. One line per storm, skipped visits are never billed.
struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var sendingReminders = false
    @State private var openedInvoice: String?

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
                        Button { openedInvoice = inv.number } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(inv.number).font(.headline)
                                    Spacer()
                                    Text(inv.isVoid ? "Void" : inv.status(now: Date()).rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(model.data.customers.first { $0.id == inv.customerID }?.name ?? "Client") · total \(inv.total.formatted), balance \(inv.balance.formatted)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !model.data.invoices.isEmpty {
                        ShareLink(item: model.invoicesCSV()) { Label("Export all as CSV", systemImage: "square.and.arrow.up") }
                    }
                }
                if let message { Section { Text(message).font(.footnote) } }
                Section {
                    Text("Open an invoice to email it to the client as a PDF with your pay links. Late fees are never added automatically. Mark an invoice paid once the money arrives.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Invoices")
            .sheet(isPresented: Binding(get: { openedInvoice != nil }, set: { if !$0 { openedInvoice = nil } })) {
                if let n = openedInvoice { InvoiceDetailSheet(number: n) }
            }
        }
    }
}
#endif
