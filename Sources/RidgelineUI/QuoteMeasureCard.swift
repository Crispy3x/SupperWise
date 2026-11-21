#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The "Property size" card on a new quote: type an area or measure it on the map, and see a suggested price.
struct QuoteMeasureCard: View {
    let address: String
    @Binding var areaText: String
    /// Called with a suggested price per push in whole dollars.
    let onSuggest: (Int) -> Void

    @State private var measuring = false

    private var area: Double? { PropertyMeasure.parseSquareFeet(areaText) }
    private var plowDollars: Int? { area.map { AreaPricing.roundedDollars(AreaPricing.plowing(squareFeet: $0)) } }

    var body: some View {
        CardGroup(title: "Property size", footer: "Starting rates: plowing \(centsText) cents per sq ft, mowing \(AreaPricing.defaultMowingPerThousandSqFt.formatted) per 1,000 sq ft.") {
            SecondaryActionButton(title: "Measure on map", icon: "map") { measuring = true }
            PillField(label: "Area in sq ft", optional: true, placeholder: "12,400", text: $areaText, kind: .number)
            if let area, let plowDollars {
                RowDivider()
                FactRow(label: "Size", value: PropertyMeasure.describe(squareFeet: area))
                FactRow(label: "Plowing, per push", value: "$\(plowDollars)")
                FactRow(label: "Mowing, per cut", value: "$\(AreaPricing.roundedDollars(AreaPricing.mowing(squareFeet: area)))")
                SecondaryActionButton(title: "Use $\(plowDollars) per push", icon: "checkmark") { onSuggest(plowDollars) }
            }
        }
        .sheet(isPresented: $measuring) {
            MeasureSheet(address: address) { m in
                areaText = String(Int(m.squareFeet.rounded()))
                onSuggest(AreaPricing.roundedDollars(AreaPricing.plowing(squareFeet: m.squareFeet)))
            }
        }
    }

    private var centsText: String { String(format: "%g", AreaPricing.defaultPlowingCentsPerSqFt) }
}
#endif
