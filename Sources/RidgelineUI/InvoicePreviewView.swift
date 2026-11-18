#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Demo of the snow billing engine with sample storms, so contract types can be compared.
public struct InvoicePreviewView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case perPush = "Per push", seasonal = "Seasonal", perInch = "Per inch", hybrid = "Hybrid", timeAndMaterials = "Time & materials"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .perPush
    @State private var perVisit = false

    public init() {}

    private var visits: [Visit] {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            Visit(stormID: "Dec 3", date: start, snowDepthInches: 3, hours: 1, materials: Money(dollars: 12)),
            Visit(stormID: "Dec 3", date: start + 0.5 * day, snowDepthInches: 4, hours: 0.5),
            Visit(stormID: "Dec 18", date: start + 15 * day, snowDepthInches: 8, hours: 1.5, materials: Money(dollars: 20)),
            Visit(stormID: "Jan 2", date: start + 30 * day, status: .skipped(reason: "Vehicle blocking drive")),
            Visit(stormID: "Jan 9", date: start + 37 * day, snowDepthInches: 14, hours: 2, materials: Money(dollars: 35)),
        ]
    }

    private var terms: ContractTerms {
        let counting: PushCounting = perVisit ? .perVisit : .perStorm
        switch kind {
        case .perPush: return .perPush(rate: Money(dollars: 60), counting: counting)
        case .seasonal: return .seasonal(total: Money(dollars: 450))
        case .perInch:
            return .perInch(tiers: [
                DepthTier(minInches: 2, rate: Money(dollars: 40)),
                DepthTier(minInches: 6, rate: Money(dollars: 70)),
                DepthTier(minInches: 12, rate: Money(dollars: 120)),
            ])
        case .hybrid: return .hybrid(seasonalBase: Money(dollars: 300), includedPushes: 2, overagePerPush: Money(dollars: 45), counting: counting)
        case .timeAndMaterials: return .timeAndMaterials(hourly: Money(dollars: 95), materialsMarkupPercent: 15)
        }
    }

    public var body: some View {
        let result = SnowBilling.bill(terms: terms, visits: visits)
        NavigationStack {
            List {
                Section("Contract") {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if kind == .perPush || kind == .hybrid {
                        Toggle("Count every return trip as a push", isOn: $perVisit)
                    }
                }
                Section("Invoice") {
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top) {
                            Text(line.description)
                            Spacer()
                            Text(line.amount.formatted)
                        }
                    }
                    HStack {
                        Text("Total").bold()
                        Spacer()
                        Text(result.total.formatted).bold()
                    }
                }
                Section {
                    Text("Pushes used: \(result.pushesUsed). Skipped visits are never billed (\(result.skippedVisitCount) skipped).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Billing preview")
        }
    }
}
#endif
