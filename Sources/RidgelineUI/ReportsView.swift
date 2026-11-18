#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Which sites make money: invoiced revenue against labor, salt and sub pay, worst margin first.
struct ReportsView: View {
    @Environment(AppModel.self) private var model

    private var rows: [(site: Site, cost: JobCost)] {
        model.data.sites
            .map { ($0, model.data.jobCost(for: $0, now: Date())) }
            .sorted { $0.1.margin < $1.1.margin }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.data.laborCostPerHour.cents == 0 {
                    Section {
                        Text("Set what an hour of crew time costs you in Settings. Until then margins leave labor out and look better than they are.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if rows.isEmpty {
                    Section { Text("No sites yet.").foregroundStyle(.secondary) }
                }
                ForEach(rows, id: \.site.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.site.address).font(.headline)
                            Spacer()
                            Text(row.cost.margin.formatted)
                                .foregroundStyle(row.cost.margin.cents < 0 ? .red : .green)
                        }
                        Text("Invoiced \(row.cost.revenue.formatted), labor \(row.cost.labor.formatted), salt \(row.cost.materials.formatted)")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let pct = row.cost.marginPercent {
                            Text("Margin \(pct, specifier: "%.0f")%").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Nothing invoiced yet.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Job costs")
        }
    }
}
#endif
