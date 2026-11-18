#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Dispatcher view: set the snowfall, see which sites hit their trigger, and plan the order by drive time.
/// The dispatcher stays in control: priorities are strict, and the first N stops can be frozen.
/// Routes are ordered by drive time only. Weather decides which sites need service, not how the route is driven.
/// Holds what one planning run measured, so it is shown only with the plan it belongs to.
private final class ReportBox: @unchecked Sendable {
    var report: SampledReport?
}

struct StormView: View {
    @Environment(AppModel.self) private var model
    @State private var inches = 4.0
    @State private var frozen = 0
    @State private var depotLat = ""
    @State private var depotLon = ""
    @State private var loading = false
    @State private var livePlan: RoutePlanResult?
    @State private var planReport: SampledReport?
    @State private var planNote = "Offline estimate of drive times."

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
        // Offline estimate, shown until the chosen source (Apple Maps or the routing server) answers.
        return RouteOptimizer.optimize(stops: stops, start: start, frozenPrefix: frozen, provider: HaversineDriveTime())
    }

    /// Changes whenever anything that affects the route changes, so the live plan is refreshed.
    private var planKey: String {
        "\(hits.map(\.id))|\(frozen)|\(model.data.routingServerURL)|\(model.data.routingProvider.rawValue)"
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
                Section("Snowfall") {
                    Slider(value: $inches, in: 0...24, step: 0.5)
                    Text("\(inches, specifier: "%.1f") inches")
                    Text("Sites whose trigger depth is reached are listed below, ordered by priority and then by drive time.")
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
                Section {
                    Text(planNote).font(.footnote).foregroundStyle(.secondary)
                    if model.data.routingProvider == .appleMaps, let r = planReport, livePlan != nil {
                        Text("Apple Maps measured \(r.measured) of the \(r.totalPairs) legs; the rest are estimated from those.\(r.stoppedEarly ? " Apple Maps stopped answering part way, so more of this is estimated." : "")")
                            .font(.footnote).foregroundStyle(r.stoppedEarly ? .orange : .secondary)
                    }
                }
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
                // Drop the old plan at once so the list never shows an order that belongs to other sites.
                livePlan = nil
                planReport = nil
                if stops.isEmpty {
                    planNote = "No sites to order yet."
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)   // let the sliders settle, so each tweak is not a new lookup
                if Task.isCancelled { return }
                let box = ReportBox()
                let chosen = model.routePlanner(onReport: { box.report = $0 })
                guard chosen.isLive else {
                    planNote = "Drive times are the offline estimate."
                    return
                }
                planNote = "Asking \(chosen.label)..."
                let live = await chosen.planner.plan(stops: stops, start: start, frozenPrefix: frozen)
                if Task.isCancelled { return }
                livePlan = live
                planReport = box.report
                if let r = box.report, r.measured == 0 {
                    planNote = "\(chosen.label) gave no answers, so these drive times are the offline estimate."
                } else {
                    planNote = "Drive times from \(chosen.label)."
                }
            }
        }
    }
}
#endif
