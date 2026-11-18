#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Dispatcher view: set the weather, see which sites hit their trigger, and plan the order.
/// The dispatcher stays in control: priorities are strict, and the first N stops can be frozen.
struct StormView: View {
    @Environment(AppModel.self) private var model
    @State private var inches = 4.0
    @State private var ratePerHour = 0.5
    @State private var tempF = 28.0
    @State private var windMph = 10.0
    @State private var frozen = 0
    @State private var depotLat = ""
    @State private var depotLon = ""
    @State private var loading = false
    @State private var livePlan: RoutePlanResult?
    @State private var planNote = "Offline estimate of drive times."

    private let conditionsModel = ConditionsModel()

    private var conditions: WeatherConditions {
        WeatherConditions(snowfallRateInPerHour: ratePerHour, accumulationInches: inches, temperatureF: tempF, windMph: windMph)
    }
    private var hits: [Site] { TriggerEvaluator.sitesToServe(sites: model.data.sites, inches: inches) }
    private var warnings: [Site] { TriggerEvaluator.sitesNearTrigger(sites: model.data.sites, inches: inches, within: 1.5) }

    private var stops: [Stop] {
        hits.compactMap { s in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            return Stop(id: s.id, name: s.address, coordinate: Coordinate(latitude: lat, longitude: lon), priority: s.priority)
        }
    }

    private var start: Coordinate { model.data.depot ?? stops.first?.coordinate ?? Coordinate(latitude: 0, longitude: 0) }

    private var result: RoutePlanResult {
        // Offline estimate here. On a device with a server, drive times come from Google (batch) and Apple (next legs),
        // through RoutePlanner and a MatrixSource; the weather layer below stays the same.
        let provider = StormAdjustedDriveTime(base: HaversineDriveTime(), speedFactor: conditionsModel.speedFactor(conditions))
        return RouteOptimizer.optimize(stops: stops, start: start, frozenPrefix: frozen, provider: provider,
                                       serviceTimeFactor: conditionsModel.serviceTimeFactor(conditions))
    }

    /// Changes whenever anything that affects the route changes, so the live plan is refreshed.
    private var planKey: String {
        "\(hits.map(\.id))|\(inches)|\(ratePerHour)|\(tempF)|\(windMph)|\(frozen)|\(model.data.routingServerURL)"
    }

    var body: some View {
        let plan = livePlan ?? result
        NavigationStack {
            Form {
                Section("Forecast (National Weather Service, US)") {
                    if model.data.depot == nil {
                        TextField("Yard latitude, e.g. 44.98", text: $depotLat)
                        TextField("Yard longitude, e.g. -93.27", text: $depotLon)
                        Button("Save yard location") {
                            if let la = Double(depotLat), let lo = Double(depotLon), (-90...90).contains(la), (-180...180).contains(lo) {
                                model.setDepot(latitude: la, longitude: lo)
                            }
                        }
                    } else {
                        Button(loading ? "Loading..." : "Load forecast for the next 24 hours") {
                            loading = true
                            Task {
                                await model.refreshWeather(hours: 24)
                                if let s = model.forecast {
                                    inches = min(24, (s.snowfallInches * 2).rounded() / 2)
                                    ratePerHour = min(3, (s.peakSnowRateInPerHour * 4).rounded() / 4)
                                    tempF = max(-20, min(45, (s.temperatureF ?? tempF).rounded()))
                                    windMph = max(0, min(60, ((s.maxWindMph ?? 0) / 5).rounded() * 5))
                                }
                                loading = false
                            }
                        }
                        .disabled(loading)
                    }
                    if let status = model.weatherStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(model.winterAlerts.enumerated()), id: \.offset) { _, alert in
                        Label(alert.headline, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section("Weather") {
                    Slider(value: $inches, in: 0...24, step: 0.5)
                    Text("\(inches, specifier: "%.1f") inches on the ground")
                    Stepper("Falling: \(ratePerHour, specifier: "%.1f") in/hr", value: $ratePerHour, in: 0...3, step: 0.25)
                    Stepper("Temperature: \(Int(tempF))°F", value: $tempF, in: -20...45, step: 1)
                    Stepper("Wind: \(Int(windMph)) mph", value: $windMph, in: 0...60, step: 5)
                    Text("Driving ×\(conditionsModel.speedFactor(conditions), specifier: "%.2f"), time per site ×\(conditionsModel.serviceTimeFactor(conditions), specifier: "%.2f"). These start as estimates and can be tuned from your logged drives.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Stepper("Keep first \(frozen) stops fixed", value: $frozen, in: 0...20)
                }
                Section("Sites to serve (\(hits.count))") {
                    if hits.isEmpty { Text("No site has reached its trigger depth.").foregroundStyle(.secondary) }
                    ForEach(Array(plan.planned.enumerated()), id: \.offset) { index, p in
                        HStack {
                            Text("\(index + 1).").monospacedDigit()
                            VStack(alignment: .leading) {
                                Text(p.stop.name)
                                Text("Priority \(p.stop.priority)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if plan.lateStopIDs.contains(p.stop.id) {
                                Text("Late").font(.caption).foregroundStyle(.red)
                            }
                            Text("ETA \(Int(p.arrivalOffsetSeconds / 60)) min").foregroundStyle(.secondary)
                        }
                    }
                    if hits.count != stops.count {
                        Text("\(hits.count - stops.count) site(s) have no map location and are left out of the order.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section { Text(planNote).font(.footnote).foregroundStyle(.secondary) }
                if let first = plan.stops.first {
                    Section("Navigate") {
                        if let url = NavigationLinks.appleMaps(to: first.coordinate, from: start) {
                            Link("Next stop in Apple Maps", destination: url)
                        }
                        ForEach(Array(NavigationLinks.googleMaps(stops: plan.stops.map(\.coordinate), origin: start).enumerated()), id: \.offset) { i, url in
                            Link("Route part \(i + 1) in Google Maps", destination: url)
                        }
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
            .task(id: planKey) {
                let chosen = model.routePlanner()
                guard chosen.usingServer, !stops.isEmpty else {
                    livePlan = nil
                    planNote = "Offline estimate of drive times."
                    return
                }
                let live = await chosen.planner.plan(stops: stops, start: start, conditions: conditions, frozenPrefix: frozen)
                livePlan = live
                planNote = "Drive times from your routing server, adjusted for the weather."
            }
        }
    }
}
#endif
