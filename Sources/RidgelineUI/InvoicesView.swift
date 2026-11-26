#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Invoices built from the visit log. One line per storm, skipped visits are never billed.
struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var sendingReminders = false
    @State private var openedInvoice: String?

    /// One contract per address: the newest, which is the one every invoice is built from. An older contract for the
    /// same address (last season's, or a quote accepted twice) must not offer to bill the storms again at its old price.
    private var currentContracts: [SnowContract] {
        model.data.contracts.filter { contract in
            model.data.contracts.last(where: { $0.siteID == contract.siteID })?.id == contract.id
        }
    }

    var body: some View {
        ScreenStack {
            // Crew can reach this screen from the visit log's "Needs your attention" rows, so it checks for itself.
            if model.data.can(.viewRevenue) {
                page
            } else {
                AppPage(title: "Invoices", icon: "doc.text.fill") {
                    EmptyCard(icon: "lock.fill", title: "Not available", message: "Ask the owner to let you see revenue and invoices.")
                }
            }
        }
    }

    private var page: some View {
            AppPage(title: "Invoices", icon: "doc.text.fill") {
                InvoicesQuickInvoiceButton()   // QuickInvoiceViews.swift
                ReadyToBillCard()              // finished jobs waiting for an invoice (JobBillingViews.swift)
                if model.data.contracts.isEmpty {
                    Card { Text("No contracts yet.").foregroundStyle(.secondary) }
                }
                ForEach(currentContracts) { contract in
                    if let site = model.data.sites.first(where: { $0.id == contract.siteID }) {
                        contractCard(contract, site: site)
                    }
                }
                let reminders = model.reminderPlan()
                if !reminders.messages.isEmpty {
                    CardGroup(title: "Overdue", footer: "Only clients who agreed to messages get one. Each invoice gets at most three, a week apart.") {
                        PrimaryActionButton(title: sendingReminders ? "Sending..." : "Send \(reminders.messages.count) friendly reminder\(reminders.messages.count == 1 ? "" : "s")") {
                            Task {
                                sendingReminders = true
                                message = await model.sendReminders()
                                sendingReminders = false
                            }
                        }
                        .disabled(sendingReminders)
                    }
                }
                savedInvoices
                if let message {
                    Card { Text(message).font(.footnote) }
                }
                Text("Open an invoice to email it to the client as a PDF with your pay links. Late fees are never added automatically. Mark an invoice paid once the money arrives.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(isPresented: Binding(get: { openedInvoice != nil }, set: { if !$0 { openedInvoice = nil } })) {
                if let n = openedInvoice { InvoiceDetailSheet(number: n) }
            }
    }

    @ViewBuilder private func contractCard(_ contract: SnowContract, site: Site) -> some View {
        let visits = model.data.visitLog.records(forSite: site.id).map { $0.asBillingVisit() }
        let result = SnowBilling.bill(terms: contract.terms, visits: visits)
        CardGroup(title: "\(model.customerName(for: site)), \(site.address)") {
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top) {
                    Text(line.description).font(.footnote)
                    Spacer()
                    Text(line.amount.formatted)
                }
            }
            RowDivider()
            HStack {
                Text("Total").bold()
                Spacer()
                Text(result.total.formatted).bold()
            }
            SecondaryActionButton(title: "Create invoice for unbilled storms", icon: "doc.badge.plus") { message = model.createInvoice(for: contract) }
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

    @ViewBuilder private var savedInvoices: some View {
        CardGroup(title: "Saved invoices") {
            if model.data.invoices.isEmpty { Text("No invoices created yet.").foregroundStyle(.secondary) }
            ForEach(Array(model.data.invoices.enumerated()), id: \.offset) { index, inv in
                VStack(alignment: .leading, spacing: 14) {
                    if index > 0 { RowDivider() }
                    Button { openedInvoice = inv.number } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(inv.number).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    StatusPill(text: AccountingExport.statusTitle(inv.status(now: Date())), color: inv.isVoid ? .gray : .accentColor)
                                }
                                Text("\(model.data.customers.first { $0.id == inv.customerID }?.name ?? "Client") · total \(inv.total.formatted), balance \(inv.balance.formatted)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !model.data.invoices.isEmpty {
                RowDivider()
                // A real .csv file (ExpensesViews.swift), not the spreadsheet pasted as text into a message.
                ShareLink(item: CSVFile(name: "invoices.csv", text: model.invoicesCSV()), preview: SharePreview("invoices.csv")) {
                    Label("Export all as CSV", systemImage: "square.and.arrow.up")
                        .font(.title3.weight(.medium)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Look.pill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif
