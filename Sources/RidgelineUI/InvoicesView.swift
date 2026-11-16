#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Invoices built from the visit log. One line per storm, skipped visits are never billed.
struct InvoicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
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
                Section {
                    Text("Payment links are not built in yet. Send the invoice and use your own payment account.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Invoices")
        }
    }
}
#endif
