#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Shows Pro and Max prices for a number of crews, monthly or annual.
public struct PricingCalculatorView: View {
    @State private var crews = 3
    @State private var annual = false

    public init() {}

    public var body: some View {
        ScreenStack {
            Form {
                Section("Your crews") {
                    Stepper("Crews: \(crews)", value: $crews, in: 1...50)
                    Picker("Billing", selection: $annual) {
                        Text("Monthly").tag(false)
                        Text("Annual (20% off)").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Pricing") {
                    ForEach(PlanTier.allCases, id: \.self) { tier in
                        HStack {
                            Text(tier == .pro ? "Pro" : "Max").font(.headline)
                            Spacer()
                            Text("\(Pricing.price(tier, crews: crews, period: annual ? .annual : .monthly).formatted) / mo")
                        }
                    }
                }
                Section {
                    Text("\(Pricing.trialDays)-day free trial. Office seats are always free. Cancel any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ridgeline Ops")
        }
    }
}
#endif
