#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Which sites make money: sent invoices against labor and salt, worst margin first.
struct ReportsView: View {
    @Environment(AppModel.self) private var model

    private struct Row: Identifiable {
        let site: Site
        let cost: JobCost
        var id: UUID { site.id }
    }

    private var rows: [Row] {
        model.data.sites
            .map { Row(site: $0, cost: model.data.jobCost(for: $0, now: Date())) }
            .sorted { $0.cost.margin < $1.cost.margin }
    }

    var body: some View {
        ScreenStack {
            AppPage(title: "Job costs", icon: "chart.bar.fill") {
                if model.data.laborCostPerHour.cents == 0 || model.data.saltCostPerPound.cents == 0 {
                    Card {
                        Text("Set your crew cost per hour and salt cost in Settings. Until then margins leave those costs out and look better than they are.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if rows.isEmpty {
                    Card { Text("No sites yet.").foregroundStyle(.secondary) }
                }
                ForEach(rows) { row in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.site.address).font(.title3.weight(.semibold))
                                Spacer()
                                Text(row.cost.margin.formatted).fontWeight(.semibold)
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
                notes
            }
        }
    }

    @ViewBuilder private var notes: some View {
        let loose = model.data.unassignedHours(now: Date())
        VStack(alignment: .leading, spacing: 8) {
            Text("Only invoices marked sent count as revenue. Subcontractor pay is not included yet.")
                .font(.footnote).foregroundStyle(.secondary)
            if loose > 0 {
                Text("\(loose, specifier: "%.1f") hours of crew time are not tied to a site and are not counted above.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
