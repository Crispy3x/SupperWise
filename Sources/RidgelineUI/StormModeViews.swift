#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Storm mode on Home and in the Storm planner: "Start a storm" when no storm is running, otherwise the progress
/// banner with the route and "Finish storm". Sheets hang on this section, so they stay open when the storm ends.
struct StormModeSection: View {
    @Environment(AppModel.self) private var model
    /// On Home the start card only shows for snow businesses, and stands out when the forecast says snow.
    var onHome = false
    /// Opens the route. When nil, the route opens in its own sheet here.
    var openRoute: (() -> Void)?

    @State private var showStart = false
    @State private var showFinish = false
    @State private var showRoute = false

    private var d: AppData { model.data }
    private var doesSnow: Bool {
        let snowWork: Set<ServiceKind> = [.snowPlowing, .salting, .shoveling]
        return !d.profile.services.isDisjoint(with: snowWork)
    }
    private var canStart: Bool { d.can(.editJobs) && !d.sites.isEmpty && (!onHome || doesSnow) }
    private var canSeeProgress: Bool { d.can(.editJobs) || d.can(.logVisits) || d.can(.viewAllJobs) }

    var body: some View {
        VStack(spacing: 16) {
            if let run = d.activeStormRun {
                if canSeeProgress {
                    StormInProgressCard(run: run,
                                        onRoute: { if let openRoute { openRoute() } else { showRoute = true } },
                                        onFinish: { showFinish = true })
                }
            } else if canStart {
                StormStartCard(onHome: onHome) { showStart = true }
            }
        }
        .sheet(isPresented: $showStart) { StartStormSheet() }
        .sheet(isPresented: $showFinish) { FinishStormSheet() }
        .routePlannerCover(isPresented: $showRoute)   // RoutePlannerView.swift
    }
}

/// "Snow on the way" when the forecast says so, otherwise a quiet row so the owner can start one any time.
private struct StormStartCard: View {
    @Environment(AppModel.self) private var model
    let onHome: Bool
    let start: () -> Void
    @State private var triedForecast = false

    private var snowExpected: Bool {
        StormMode.forecastSaysSnow(forecastInches: model.forecast?.snowfallInches, hasWinterAlert: !model.winterAlerts.isEmpty, sites: model.data.sites)
    }

    private var forecastLine: String {
        if let alert = model.winterAlerts.first { return alert.headline }
        if let f = model.forecast { return "The forecast shows \(SnowEstimateText.describe(forecastInches: f.snowfallInches)) in the next 24 hours." }
        return ""
    }

    var body: some View {
        Group {
            if snowExpected {
                CardGroup(title: "Snow on the way") {
                    HStack(spacing: 12) {
                        IconTile(icon: "cloud.snow.fill", tint: .blue, size: 44)
                        Text(forecastLine).font(.callout)
                    }
                    PrimaryActionButton(title: "Start a storm", icon: "snowflake") { start() }
                }
            } else {
                Card(padding: 14) {
                    Button(action: start) {
                        CardLinkRow(icon: "cloud.snow", tint: .blue, title: "Start a storm",
                                    detail: "Snowing? Pick the sites and add today's jobs in one tap.")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            // Home checks the free National Weather Service forecast once, so the card can say when snow is coming.
            guard onHome, !triedForecast, model.forecast == nil, model.data.depot != nil else { return }
            triedForecast = true
            await model.refreshWeather(hours: 24)
        }
    }
}

/// "Storm in progress: 7 of 18 done", with the route and Finish storm.
private struct StormInProgressCard: View {
    @Environment(AppModel.self) private var model
    let run: StormRun
    let onRoute: () -> Void
    let onFinish: () -> Void

    private var canFinish: Bool { model.data.can(.editJobs) && model.data.can(.viewRevenue) }

    var body: some View {
        let p = StormMode.progress(run: run, data: model.data)
        let started = run.startedAt.formatted(date: .omitted, time: .shortened)
        let detail = "\(p.remaining) left" + (p.skipped > 0 ? ", \(p.skipped) could not be done" : "") + ". Started \(started)."
        CardGroup(title: "Storm \(run.stormName)") {
            HStack(spacing: 12) {
                IconTile(icon: "snowflake", tint: .blue, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storm in progress: \(p.text)").font(.title3.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(p.done + p.skipped), total: Double(max(p.total, 1)))
                .accessibilityLabel("Storm progress, \(p.text)")
            PrimaryActionButton(title: "Open route", icon: "map") { onRoute() }
            if canFinish {
                SecondaryActionButton(title: "Finish storm", icon: "flag.checkered") { onFinish() }
            }
        }
    }
}

/// Enter the expected snow, tick the sites, and one tap makes the storm and a job for today at each site.
struct StartStormSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var inches = 2.0
    @State private var name = ""
    @State private var chosen: Set<UUID> = []
    @State private var messageClients = true
    @State private var problem: String?
    @State private var loaded = false
    @State private var showMessage = false
    @State private var startedInches = 0.0

    private var suggested: [Site] { StormMode.suggestedSites(data: model.data, inches: inches, stormName: name) }
    private var others: [Site] {
        let ids = Set(suggested.map(\.id))
        return model.data.sites.filter { !ids.contains($0.id) }.sorted { ($0.triggerInches, $0.address) < ($1.triggerInches, $1.address) }
    }
    private var canMessage: Bool { model.data.profile.stormMessagesOn && model.serverConfigured }
    private var tint: Color { Theme.accent(model.data.profile.accentColor) }

    private var forecastNote: String {
        if let f = model.forecast { return "Forecast for the next 24 hours: \(SnowEstimateText.describe(forecastInches: f.snowfallInches))." }
        return "No forecast loaded. Enter the snow you expect."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Start a storm").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(title: "Expected snow", footer: forecastNote) {
                    PillStepper(label: "Inches", value: $inches, range: 0...36, step: 0.5, format: { String(format: "%.1f in", $0) })
                    PillField(label: "Storm name", placeholder: "Storm name", text: $name)
                }
                CardGroup(title: "Sites to plow (\(suggested.filter { chosen.contains($0.id) }.count) of \(suggested.count))",
                          footer: "Ticked: the trigger is at or below \(String(format: "%g", inches)) in, or the client asked for service. Tap a site to change it.") {
                    if suggested.isEmpty { Text("No site triggers at this depth.").foregroundStyle(.secondary) }
                    ForEach(Array(suggested.enumerated()), id: \.element.id) { i, site in
                        if i > 0 { RowDivider() }
                        siteRow(site)
                    }
                }
                if !others.isEmpty {
                    CardGroup(title: "Below their trigger") {
                        ForEach(Array(others.enumerated()), id: \.element.id) { i, site in
                            if i > 0 { RowDivider() }
                            siteRow(site)
                        }
                    }
                }
                if model.data.profile.stormMessagesOn {
                    CardGroup(footer: canMessage
                              ? "You see the messages before anything goes out. Only clients who agreed get one."
                              : "Messages to clients need your server, set up in Settings. The storm and jobs work without it.") {
                        Toggle("Message clients who agreed", isOn: $messageClients).disabled(!canMessage)
                    }
                }
                PrimaryActionButton(title: "Start storm with \(chosen.count) site\(chosen.count == 1 ? "" : "s")", icon: "snowflake") { start() }
                    .disabled(chosen.isEmpty)
                    .opacity(chosen.isEmpty ? 0.4 : 1)
                Text("Adds a plowing job for today at each ticked site, so they show on the map, the route and the calendar.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red).padding(.horizontal, 6) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.sheet.ignoresSafeArea())
        .onAppear(perform: load)
        .onChange(of: inches) { _, _ in chosen = Set(suggested.map(\.id)) }
        .sheet(isPresented: $showMessage, onDismiss: { dismiss() }) {
            StormMessageSheet(inches: startedInches, routeStart: Date(), offsets: [:])
        }
    }

    private func siteRow(_ site: Site) -> some View {
        let on = chosen.contains(site.id)
        let customer = model.customerName(for: site)
        return Button {
            if on { chosen.remove(site.id) } else { chosen.insert(site.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(on ? tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.address.isEmpty ? customer : site.address).font(.headline).foregroundStyle(.primary)
                    Text("\(customer) · trigger \(String(format: "%g", site.triggerInches)) in").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if site.latitude == nil || site.longitude == nil { StatusPill(text: "Not on map", color: .orange) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let current = model.stormName
        name = model.data.stormRuns.contains { $0.stormName == current }
            ? StormNaming.uniqueName(base: current, existing: model.data.storms.map(\.name))
            : current
        inches = StormMode.prefillInches(forecast: model.forecast?.snowfallInches, fallback: model.data.profile.defaultTriggerInches)
        chosen = Set(suggested.map(\.id))
    }

    private func start() {
        if let p = model.startStormMode(name: name, inches: inches, siteIDs: Array(chosen)) {
            problem = p
            return
        }
        if canMessage && messageClients {
            startedInches = inches
            showMessage = true
        } else {
            dismiss()
        }
    }
}

/// Sums up the storm's visits, makes draft invoices by contract, then offers to review them.
struct FinishStormSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var preview: StormFinishResult?
    @State private var finished: StormFinishResult?
    @State private var showInvoices = false

    private var canFinish: Bool { model.data.can(.editJobs) && model.data.can(.viewRevenue) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(finished == nil ? "Finish storm" : "Storm finished").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let r = finished ?? preview {
                    summaryCard(r.summary)
                    if model.data.can(.viewRevenue) { billingCard(r.invoices, done: finished != nil) }
                    let count = r.invoices.created.count
                    let plural = count == 1 ? "" : "s"
                    if finished == nil {
                        if canFinish {
                            PrimaryActionButton(title: count == 0 ? "Finish storm" : "Finish storm and make \(count) draft\(plural)", icon: "flag.checkered") { finish() }
                        } else {
                            Text("Ask the owner to finish the storm.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        if count > 0 {
                            PrimaryActionButton(title: "Review \(count) draft invoice\(plural)", icon: "doc.text") { showInvoices = true }
                        }
                        SecondaryActionButton(title: "Done", icon: "checkmark") { dismiss() }
                    }
                } else {
                    EmptyCard(icon: "snowflake", title: "No storm in progress", message: "Start a storm from Home or the Storm planner.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.sheet.ignoresSafeArea())
        .onAppear { if preview == nil && finished == nil { preview = model.data.previewFinishStorm(now: Date()) } }
        .sheet(isPresented: $showInvoices) { DraftInvoicesSheet() }
    }

    private func inchesText(_ value: Double) -> String { String(format: "%.1f in", value) }

    @ViewBuilder private func summaryCard(_ s: StormSummary) -> some View {
        CardGroup(title: "Visits logged, storm \(s.stormName)") {
            FactRow(label: "Sites done", value: "\(s.sitesServiced) of \(s.sitesPlanned)")
            FactRow(label: "Pushes", value: "\(s.pushes)")
            if s.skippedVisits > 0 { FactRow(label: "Could not service", value: "\(s.skippedVisits)", valueColor: .orange) }
            FactRow(label: "Deepest snow", value: s.deepestInches.map { inchesText($0) } ?? "Not logged")
            if let avg = s.averageDepthInches { FactRow(label: "Average depth", value: inchesText(avg)) }
            if s.materials.isEmpty {
                FactRow(label: "Salt and material", value: s.saltPounds > 0 ? "Salt, \(MaterialFormat.amount(s.saltPounds, unit: .pounds))" : "None logged")
            } else {
                ForEach(s.materials, id: \.material) { m in
                    FactRow(label: m.material.title, value: MaterialFormat.amount(m.amount, unit: m.material.unit))
                }
            }
            if !s.sitesNotVisited.isEmpty {
                let n = s.sitesNotVisited.count
                Text("\(n) site\(n == 1 ? " has" : "s have") no visit logged. \(n == 1 ? "Its job stays" : "Their jobs stay") on the schedule.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func billingCard(_ o: StormInvoiceOutcome, done: Bool) -> some View {
        CardGroup(title: "Billing",
                  footer: "Each client is billed by their contract: per push, by depth, by the hour, or pushes over a seasonal plan. Seasonal prices are not billed per storm. Drafts are not sent until you send them.") {
            FactRow(label: done ? "Draft invoices made" : "Draft invoices to make", value: "\(o.created.count)")
            if !o.created.isEmpty { FactRow(label: "Total", value: o.total.formatted) }
            if !o.alreadyInvoiced.isEmpty { FactRow(label: "Already invoiced for this storm", value: "\(o.alreadyInvoiced.count)") }
            if !o.nothingToBill.isEmpty { FactRow(label: "Covered by contract", value: "\(o.nothingToBill.count)") }
            if !o.noContract.isEmpty { FactRow(label: "No contract, not billed", value: "\(o.noContract.count)", valueColor: .orange) }
        }
    }

    private func finish() {
        guard let result = model.finishStormMode() else {
            preview = nil
            return
        }
        finished = result
    }
}

/// The invoices screen in a sheet, opened from "Review draft invoices".
private struct DraftInvoicesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Draft invoices").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            InvoicesView()
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}
#endif
