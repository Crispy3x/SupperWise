#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Dispatcher view: set the snowfall, see which sites hit their trigger, and plan the order.
/// The dispatcher stays in control: priorities are strict, and the first N stops can be frozen.
struct StormView: View {
    @Environment(AppModel.self) private var model
    @State private var inches = 4.0
    @State private var speedFactor = 0.7
    @State private var frozen = 0

    private var hits: [Site] { TriggerEvaluator.sitesToServe(sites: model.data.sites, inches: inches) }
    private var warnings: [Site] { TriggerEvaluator.sitesNearTrigger(sites: model.data.sites, inches: inches, within: 1.5) }

    private var stops: [Stop] {
        hits.compactMap { s in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            return Stop(id: s.id, name: s.address, coordinate: Coordinate(latitude: lat, longitude: lon), priority: s.priority)
        }
    }

    private var planned: [PlannedStop] {
        let provider = StormAdjustedDriveTime(base: HaversineDriveTime(), speedFactor: speedFactor)
        let start = model.data.depot ?? stops.first?.coordinate ?? Coordinate(latitude: 0, longitude: 0)
        let ordered = RouteSequencer.resequence(stops: stops, start: start, frozenPrefix: frozen, provider: provider)
        return RouteSequencer.plan(stops: ordered, start: start, provider: provider)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Snowfall") {
                    Slider(value: $inches, in: 0...24, step: 0.5)
                    Text("\(inches, specifier: "%.1f") inches")
                    Stepper("Storm driving speed: \(Int(speedFactor * 100))%", value: $speedFactor, in: 0.3...1.0, step: 0.1)
                    Stepper("Keep first \(frozen) stops fixed", value: $frozen, in: 0...20)
                }
                Section("Sites to serve (\(hits.count))") {
                    if hits.isEmpty { Text("No site has reached its trigger depth.").foregroundStyle(.secondary) }
                    ForEach(Array(planned.enumerated()), id: \.offset) { index, p in
                        HStack {
                            Text("\(index + 1).").monospacedDigit()
                            VStack(alignment: .leading) {
                                Text(p.stop.name)
                                Text("Priority \(p.stop.priority)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("ETA \(Int(p.arrivalOffsetSeconds / 60)) min").foregroundStyle(.secondary)
                        }
                    }
                    if hits.count != stops.count {
                        Text("\(hits.count - stops.count) site(s) have no map location and are left out of the order.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if !warnings.isEmpty {
                    Section("Close to trigger") {
                        ForEach(warnings) { s in
                            Text("\(s.address) triggers at \(s.triggerInches, specifier: "%.1f") in")
                        }
                    }
                }
                if !model.canUse(.stormAutomation) {
                    Section { Text("Storm automation (weather-triggered dispatch) is part of the Max plan.").font(.footnote) }
                }
            }
            .navigationTitle("Storm")
        }
    }
}
#endif
