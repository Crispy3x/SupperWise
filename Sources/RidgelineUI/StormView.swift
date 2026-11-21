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
    @State private var routeStart = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
    @State private var showingMessage = false
    @State private var depotLat = ""
    @State private var depotLon = ""
    @State private var loading = false
    @State private var livePlan: RoutePlanResult?
    @State private var planReport: SampledReport?
    @State private var planNote = "Offline estimate of drive times."

    /// Sites at their trigger depth, plus sites with an accepted request, minus sites whose skip was accepted.
    private var hits: [Site] {
        let stormID = model.data.storms.first { $0.name == model.stormName }?.id
        return DispatchRules.effectiveSites(sites: model.data.sites, inches: inches, stormID: stormID, requests: model.data.serviceRequests)
    }
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
        let offsets = Dictionary(plan.planned.map { ($0.stop.id, $0.arrivalOffsetSeconds) }, uniquingKeysWith: { first, _ in first })
        ScreenStack {
            AppPage {
                StormModeSection()   // StormModeViews.swift: start a storm with jobs, progress, finish and bill
                CardGroup(title: "Forecast (National Weather Service, US)") {
                    if model.data.depot == nil {
                        PillField(label: "Yard latitude", placeholder: "e.g. 44.98", text: $depotLat)
                        PillField(label: "Yard longitude", placeholder: "e.g. -93.27", text: $depotLon)
                        SecondaryActionButton(title: "Save yard location", icon: "mappin.and.ellipse") {
                            if let la = Double(depotLat), let lo = Double(depotLon), (-90...90).contains(la), (-180...180).contains(lo) {
                                model.setDepot(latitude: la, longitude: lo)
                            }
                        }
                    } else {
                        SecondaryActionButton(title: loading ? "Loading..." : "Load forecast for the next 24 hours", icon: "cloud.sun") {
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
                CardGroup(title: "Snowfall",
                          footer: "Sites whose trigger depth is reached are listed below, ordered by priority and then by drive time.") {
                    Slider(value: $inches, in: 0...24, step: 0.5)
                    Text("\(inches, specifier: "%.1f") inches").font(.title3.weight(.semibold))
                    PillStepper(label: "Keep first stops fixed",
                                value: Binding(get: { Double(frozen) }, set: { frozen = Int($0.rounded()) }),
                                range: 0...20, step: 1, format: { "\(Int($0))" })
                }
                CardGroup(title: "Sites to serve (\(hits.count))") {
                    if hits.isEmpty { Text("No site has reached its trigger depth.").foregroundStyle(.secondary) }
                    ForEach(Array(plan.planned.enumerated()), id: \.offset) { index, p in
                        VStack(alignment: .leading, spacing: 14) {
                            if index > 0 { RowDivider() }
                            HStack(spacing: 10) {
                                Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.stop.name).font(.headline)
                                    Text("Priority \(p.stop.priority)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if plan.lateStopIDs.contains(p.stop.id) {
                                    StatusPill(text: "Late", color: .red)
                                }
                                Text("ETA \(Int(p.arrivalOffsetSeconds / 60)) min").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if hits.count != stops.count {
                        Text("\(hits.count - stops.count) site(s) have no map location and are left out of the order.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(planNote).font(.footnote).foregroundStyle(.secondary)
                        if model.data.routingProvider == .appleMaps, let r = planReport, livePlan != nil {
                            Text("Apple Maps measured \(r.measured) of the \(r.totalPairs) legs; the rest are estimated from those.\(r.stoppedEarly ? " Apple Maps stopped answering part way, so more of this is estimated." : "")")
                                .font(.footnote).foregroundStyle(r.stoppedEarly ? .orange : .secondary)
                        }
                    }
                }
                CardGroup(title: "This storm: \(model.stormName)",
                          footer: "Each storm keeps its own messages, requests and visits. Renaming a storm makes it a new one, so clients could be messaged again.") {
                    if model.data.activeStormRun == nil {   // during a storm the crew keeps logging under its name
                        SecondaryActionButton(title: "Start a new storm", icon: "plus.circle") { model.startNewStorm() }
                    } else {
                        Text("This storm is in progress. Finish it before starting another.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.data.profile.stormMessagesOn {
                    CardGroup(title: "Clients",
                              footer: "Each client's page shows an estimated arrival window from this start time and your route. You review the messages before anything is sent.") {
                        DatePicker("Crews start at", selection: $routeStart, displayedComponents: [.date, .hourAndMinute])
                        SecondaryActionButton(title: "Message clients about this storm", icon: "envelope") { showingMessage = true }
                    }
                }
                if let first = plan.stops.first {
                    let appleURL = NavigationLinks.appleMaps(to: first.coordinate, from: start)
                    CardGroup(title: "Navigate") {
                        if let url = appleURL {
                            Link(destination: url) {
                                CardLinkRow(icon: "map", tint: .blue, title: "Next stop in Apple Maps")
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(Array(NavigationLinks.googleMaps(stops: plan.stops.map(\.coordinate), origin: start).enumerated()), id: \.offset) { i, url in
                            VStack(alignment: .leading, spacing: 14) {
                                if i > 0 || appleURL != nil { RowDivider() }
                                Link(destination: url) {
                                    CardLinkRow(icon: "arrow.triangle.turn.up.right.diamond", tint: .green, title: "Route part \(i + 1) in Google Maps")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !warnings.isEmpty {
                    CardGroup(title: "Close to trigger") {
                        ForEach(warnings) { s in
                            Text("\(s.address) triggers at \(s.triggerInches, specifier: "%.1f") in")
                        }
                    }
                }
                if !model.canUse(.stormAutomation) {
                    Card { Text("Storm automation (weather-triggered dispatch) is part of the Max plan.").font(.footnote) }
                }
            }
            .sheet(isPresented: $showingMessage) { StormMessageSheet(inches: inches, routeStart: routeStart, offsets: offsets) }
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
