#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore
#if canImport(MapKit)
import MapKit
#endif
#if canImport(VisionKit) && os(iOS)
import VisionKit
#endif

// The route planner: a full-screen map with a pin per stop, and a panel over it with search, the day, route setup
// (start, finish, break), the stops, and one big button: Optimize route, then Start route.

extension View {
    /// Opens the route planner over everything: full screen on iPhone and iPad, a large sheet on a Mac.
    @ViewBuilder func routePlannerCover(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { RoutePlannerView() }
        #else
        sheet(isPresented: isPresented) { RoutePlannerView() }
        #endif
    }
}

/// What Apple Maps measured while planning, so the note under the route can say so.
private final class PlannerReportBox: @unchecked Sendable { var report: SampledReport? }

extension AppModel {
    /// Orders `day`'s stops (client jobs and one-off stops) to drive the least, counting the drive to the finish, with
    /// drive times from Apple Maps or the routing server when available, otherwise the offline estimate.
    /// Also returns the drive times, so the screen can re-time the route when stops are dragged.
    func optimizeRoute(on day: Date) async -> (plan: RouteDayPlan?, provider: any DriveTimeProvider, note: String) {
        await fillMissingLocations()
        let stops = data.plannerStops(on: day)
        guard let first = stops.first else {
            return (nil, HaversineDriveTime(), "No stops that day. Search above to add one.")
        }
        let start = data.routeStartCoordinate ?? first.coordinate
        let end = data.routeFinishCoordinate(start: start)
        var points = [start] + stops.map(\.coordinate)
        if let end, end != start { points.append(end) }
        let box = PlannerReportBox()
        let chosen = routePlanner(onReport: { box.report = $0 })
        let provider = await chosen.planner.driveTimes(for: points)
        let startTime = data.routeStartTime(on: day)
        let breakRule = data.routeSettings.defaultBreak
        let plan = await Task.detached(priority: .userInitiated) {
            RouteDayPlanner.optimize(stops: stops, start: start, end: end, startTime: startTime, breakRule: breakRule, provider: provider)
        }.value
        var note: String
        if !chosen.isLive {
            note = "Drive times are an offline estimate."
        } else if let report = box.report, report.measured == 0 {
            note = "\(chosen.label) gave no answers, so drive times are an estimate."
        } else {
            note = "Drive times from \(chosen.label)."
        }
        if data.routeStartCoordinate == nil { note += " Set where you start for better times." }
        return (plan, provider, note)
    }
}

/// Everything the screen shows for one day, worked out once per redraw.
private struct DayRoute {
    let stops: [Stop]
    let start: Coordinate?
    let finish: Coordinate?
    let plan: RouteDayPlan?
    let order: SavedRouteOrder?
    let jobs: [UUID: Job]
    let adHoc: [UUID: AdHocStop]

    /// Numbers show once the route has an order (optimized, or dragged by hand).
    var numbered: Bool { order != nil && !stops.isEmpty }
    /// Every stop is in the saved order, so the route is ready to drive.
    var ready: Bool {
        guard let order, !stops.isEmpty else { return false }
        return Set(stops.map(\.id)).isSubset(of: Set(order.stopIDs))
    }

    func timed(_ id: UUID) -> TimedStop? { plan?.stops.first { $0.stop.id == id } }

    static func make(_ d: AppData, day: Date, provider: any DriveTimeProvider) -> DayRoute {
        let stops = d.orderedPlannerStops(on: day)
        let start = d.routeStartCoordinate ?? stops.first?.coordinate
        let finish = d.routeFinishCoordinate(start: start)
        let plan = start.map {
            RouteDayPlanner.timeline(order: stops, start: $0, end: finish, startTime: d.routeStartTime(on: day),
                                     breakRule: d.routeSettings.defaultBreak, provider: provider)
        }
        return DayRoute(stops: stops, start: start, finish: finish, plan: plan, order: d.routeOrder(on: day),
                        jobs: Dictionary(d.jobs(on: day).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                        adHoc: Dictionary(d.adHocStops(on: day).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
    }
}

private enum PlannerSheet: Identifiable, Equatable {
    case day, start, finish, rest, scan, stop(UUID)
    var id: String {
        switch self {
        case .day: return "day"
        case .start: return "start"
        case .finish: return "finish"
        case .rest: return "break"
        case .scan: return "scan"
        case .stop(let id): return "stop-" + id.uuidString
        }
    }
}

private func clockText(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

// MARK: - The screen

struct RoutePlannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var day = Date()
    @State private var loaded = false
    @State private var sheet: PlannerSheet?
    @State private var detent: PresentationDetent = .medium
    @State private var note: String?
    /// Drive times from the last Optimize. Until then, the offline estimate.
    @State private var provider: any DriveTimeProvider = HaversineDriveTime()
    @State private var working = false
    @State private var showPanel = true
    @State private var closing = false
    @State private var satellite = false
    #if canImport(MapKit)
    @State private var camera: MapCameraPosition = .automatic
    #endif

    private var tint: Color { Theme.accent(model.data.profile.accentColor) }

    var body: some View {
        let r = DayRoute.make(model.data, day: day, provider: provider)
        content(r)
            .task { await load() }
            .onChange(of: day) {
                provider = HaversineDriveTime()
                note = nil
                recenter()
            }
            .onChange(of: r.stops.map(\.id)) { recenter() }
    }

    @ViewBuilder private func content(_ r: DayRoute) -> some View {
        #if os(iOS)
        mapArea(r)
            .sheet(isPresented: $showPanel, onDismiss: { if closing { dismiss() } }) {
                panel
                    .presentationDetents([.height(220), .medium, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationBackground(Look.page)
                    .presentationCornerRadius(28)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        #else
        HStack(spacing: 0) {
            mapArea(r)
            panel.frame(width: 400).background(Look.page)
        }
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }

    private var panel: some View {
        RoutePlannerPanel(day: $day, sheet: $sheet, detent: $detent, note: $note, provider: provider, working: working,
                          onOptimize: { Task { await optimize() } }, onStart: startRoute, onClose: close)
    }

    // MARK: map

    private func mapArea(_ r: DayRoute) -> some View {
        ZStack(alignment: .top) {
            mapLayer(r).ignoresSafeArea()
            HStack(alignment: .top) {
                Button(action: close) { floating(icon: "chevron.down") }
                    .buttonStyle(.plain).accessibilityLabel("Close")
                Spacer()
                VStack(spacing: 10) {
                    Button { satellite.toggle() } label: { floating(icon: satellite ? "map" : "globe.americas.fill") }
                        .buttonStyle(.plain).accessibilityLabel(satellite ? "Standard map" : "Satellite map")
                    Button(action: recenter) { floating(icon: "scope") }
                        .buttonStyle(.plain).accessibilityLabel("Show the whole route")
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private func floating(icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
            .frame(width: 46, height: 46)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Look.stroke, lineWidth: 1))
    }

    @ViewBuilder private func mapLayer(_ r: DayRoute) -> some View {
        #if canImport(MapKit)
        Map(position: $camera) {
            UserAnnotation()
            if r.numbered, let start = r.start {
                MapPolyline(coordinates: routeLine(r, start: start))
                    .stroke(tint.opacity(0.75), lineWidth: 4)
            }
            if let start = r.start, model.data.routeStartCoordinate != nil {
                Annotation("", coordinate: start.mapPoint, anchor: .center) {
                    PlacePin(icon: "house.fill", tint: .green).accessibilityLabel("Start")
                }
            }
            if let finish = r.finish, finish != r.start {
                Annotation("", coordinate: finish.mapPoint, anchor: .center) {
                    PlacePin(icon: "flag.checkered", tint: .orange).accessibilityLabel("Finish")
                }
            }
            ForEach(Array(r.stops.enumerated()), id: \.element.id) { i, s in
                Annotation("", coordinate: s.coordinate.mapPoint, anchor: .center) {
                    Button { sheet = .stop(s.id) } label: {
                        StopPin(text: pinText(r, index: i, stop: s), tint: tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.name)
                }
            }
        }
        .mapStyle(satellite ? .imagery(elevation: .realistic) : .standard(elevation: .realistic))
        #if os(iOS)
        .safeAreaPadding(.bottom, 240)
        #endif
        #else
        Look.page
        #endif
    }

    #if canImport(MapKit)
    private func routeLine(_ r: DayRoute, start: Coordinate) -> [CLLocationCoordinate2D] {
        var points = [start] + r.stops.map(\.coordinate)
        if let finish = r.finish { points.append(finish) }
        return points.map(\.mapPoint)
    }
    #endif

    private func pinText(_ r: DayRoute, index: Int, stop: Stop) -> String {
        if r.numbered { return "\(index + 1)" }
        let label = stopLabel(model.data, r, stop)
        return label.isEmpty ? "•" : label
    }

    private func recenter() {
        #if canImport(MapKit)
        withAnimation { camera = .automatic }
        #endif
    }

    // MARK: actions

    private func load() async {
        guard !loaded else { return }
        loaded = true
        day = model.nextRouteDay(from: Date())
        await model.fillMissingLocations()
    }

    private func optimize() async {
        guard !working else { return }
        working = true
        note = nil
        let planned = day
        let began = Date()
        let outcome = await model.optimizeRoute(on: planned)
        // A short pause so the change is easy to follow.
        let elapsed = Date().timeIntervalSince(began)
        if elapsed < 0.6 { try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000)) }
        working = false
        guard planned == day else { return }
        provider = outcome.provider
        note = outcome.note
        guard let plan = outcome.plan else { return }
        _ = model.edit { $0.setRouteOrder(plan.stops.map(\.stop.id), on: planned, optimized: true) }
        if Calendar.current.isDateInToday(planned) { model.plannedRoute = plan.result }
        recenter()
    }

    private func startRoute(_ r: DayRoute) {
        guard let first = r.stops.first, let url = NavigationLinks.appleMaps(to: first.coordinate) else { return }
        openURL(url)
    }

    private func close() {
        #if os(iOS)
        closing = true
        showPanel = false
        #else
        dismiss()
        #endif
    }
}

/// The short tinted label on the right of a stop before the route has an order: the client's initials.
private func stopLabel(_ d: AppData, _ r: DayRoute, _ stop: Stop) -> String {
    if let job = r.jobs[stop.id] {
        let who = d.customerName(forJob: job)
        return RouteText.initials(who.isEmpty ? job.title : who)
    }
    return RouteText.initials(RouteText.addressLines(stop.name).street)
}

// MARK: - The panel

private struct RoutePlannerPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var day: Date
    @Binding var sheet: PlannerSheet?
    @Binding var detent: PresentationDetent
    @Binding var note: String?
    let provider: any DriveTimeProvider
    let working: Bool
    let onOptimize: () -> Void
    let onStart: (DayRoute) -> Void
    let onClose: () -> Void

    @State private var search = ""
    @State private var adding = false
    @State private var completer = AddressCompleter()
    @FocusState private var searchFocused: Bool
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    #if canImport(Speech) && os(iOS)
    @State private var speech = SpeechInput()
    #endif

    private var d: AppData { model.data }
    private var tint: Color { Theme.accent(d.profile.accentColor) }
    private var canPlan: Bool { d.can(.editJobs) || d.can(.logVisits) }
    private var canAddClientStops: Bool { d.can(.editJobs) && d.can(.viewClients) }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }

    @MainActor private var canScan: Bool {
        #if canImport(VisionKit) && os(iOS)
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
        return false
        #endif
    }

    private var speechProblem: String? {
        #if canImport(Speech) && os(iOS)
        return speech.problem
        #else
        return nil
        #endif
    }

    var body: some View {
        let r = DayRoute.make(d, day: day, provider: provider)
        VStack(spacing: 0) {
            searchBar(r).padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            if let problem = speechProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.bottom, 6)
            }
            if isSearching { suggestions(r) } else { routeList(r) }
        }
        .background(Look.page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isSearching { bottomBar(r) }
        }
        .sheet(item: $sheet) { which in sheetContent(which) }
        .onChange(of: search) { _, text in completer.update(text) }
        .onChange(of: searchFocused) { _, focused in if focused { detent = .large } }
        #if canImport(Speech) && os(iOS)
        .onChange(of: speech.transcript) { _, text in if speech.isListening { search = text } }
        #endif
        .onAppear { completer.near(d.routeStartCoordinate) }
    }

    // MARK: search

    private func searchBar(_ r: DayRoute) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(canPlan ? "Add or find stops" : "Find stops", text: $search)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { submitSearch(r) }
                if adding {
                    ProgressView().controlSize(.small)
                } else if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear")
                }
                if canPlan && canScan {
                    Button { sheet = .scan } label: { Image(systemName: "text.viewfinder").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Scan an address")
                }
                #if canImport(Speech) && os(iOS)
                Button { Task { await speech.toggle() } } label: {
                    Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.fill")
                        .foregroundStyle(speech.isListening ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel(speech.isListening ? "Stop listening" : "Say an address")
                #endif
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Look.card, in: Capsule())
            .overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
            moreMenu(r)
        }
    }

    private func moreMenu(_ r: DayRoute) -> some View {
        Menu {
            if r.numbered {
                Button(action: onOptimize) { Label("Optimize again", systemImage: "arrow.triangle.2.circlepath") }
            }
            Button { sheet = .day } label: { Label("Pick a day", systemImage: "calendar") }
            if canPlan {
                Picker(selection: Binding(get: { d.routeSettings.defaultServiceMinutes }, set: { m in
                    _ = model.edit { data in
                        var s = data.routeSettings
                        s.defaultServiceMinutes = m
                        data.setRouteSettings(s)
                    }
                })) {
                    ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { m in Text("\(m) min").tag(m) }
                } label: {
                    Label("Time per new stop", systemImage: "timer")
                }
                .pickerStyle(.menu)
            }
            Divider()
            Button(action: onClose) { Label("Close planner", systemImage: "xmark") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 48, height: 48).background(Look.card, in: Circle())
                .overlay(Circle().stroke(Look.stroke, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
    }

    private struct SiteMatch: Identifiable {
        let site: Site
        let client: String
        var id: UUID { site.id }
    }

    private func stopMatches(_ r: DayRoute) -> [Stop] {
        Array(r.stops.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(5))
    }

    private func siteMatches(_ r: DayRoute) -> [SiteMatch] {
        guard query.count >= 2, canAddClientStops else { return [] }
        let onRoute = Set(r.jobs.values.filter { $0.status.isOpen }.compactMap(\.siteID))
        let names = Dictionary(d.customers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let q = query
        let found = d.sites.filter { s in
            !onRoute.contains(s.id) && (s.address.localizedCaseInsensitiveContains(q) || (names[s.customerID] ?? "").localizedCaseInsensitiveContains(q))
        }
        return found.prefix(6).map { SiteMatch(site: $0, client: names[$0.customerID] ?? "") }
    }

    private func suggestions(_ r: DayRoute) -> some View {
        let stops = stopMatches(r)
        let sites = siteMatches(r)
        let places = canPlan ? completer.results : []
        return List {
            if !stops.isEmpty {
                sectionTitle("On this route").plannerRow()
                ForEach(stops) { s in
                    suggestionRow(icon: "mappin", tint: tint, title: RouteText.addressLines(s.name).street,
                                  detail: RouteText.addressLines(s.name).rest) { sheet = .stop(s.id) }
                }
            }
            if !sites.isEmpty {
                sectionTitle("Clients").plannerRow()
                ForEach(sites) { m in
                    suggestionRow(icon: "person.fill", tint: .green, title: m.client.isEmpty ? m.site.address : m.client,
                                  detail: m.site.address) { addSite(m.site) }
                }
            }
            if !places.isEmpty {
                sectionTitle("Addresses").plannerRow()
                ForEach(places) { p in
                    suggestionRow(icon: "plus", tint: .orange, title: p.title, detail: p.subtitle) {
                        Task { await addAddress(p.text) }
                    }
                }
            }
            if stops.isEmpty && sites.isEmpty && places.isEmpty {
                Text(canPlan ? "No matches yet. Keep typing the address, then press Search to add it." : "No stops match.")
                    .font(.callout).foregroundStyle(.secondary).plannerRow()
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).plannerRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func suggestionRow(icon: String, tint: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(icon: icon, tint: tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plannerRow()
    }

    private func submitSearch(_ r: DayRoute) {
        guard !query.isEmpty, !adding else { return }
        if let m = siteMatches(r).first { addSite(m.site); return }
        guard canPlan else { return }
        let text = completer.results.first?.text ?? query
        Task { await addAddress(text) }
    }

    /// A client site: adds a job there for this day, the same way New Job does.
    private func addSite(_ site: Site) {
        let last = d.jobs.last { $0.siteID == site.id && !$0.isTask }
        let client = d.customers.first { $0.id == site.customerID }?.name ?? ""
        let title = last?.title ?? (client.isEmpty ? "Visit" : client)
        // An employee who does not see every job only sees jobs assigned to them.
        let mine: [UUID] = d.isOwnerSession ? [] : (d.currentMember.map { [$0.id] } ?? [])
        if let problem = model.addJob(title: title, kind: last?.kind ?? .other, customerID: site.customerID, siteID: site.id,
                                      start: d.routeStartTime(on: day), durationMinutes: d.routeSettings.defaultServiceMinutes,
                                      assigneeIDs: mine, notes: "", isTask: false) {
            note = problem
            return
        }
        finishAdding()
        if site.latitude == nil || site.longitude == nil {
            // The job is saved, but only a site with a map location is a stop. Say so instead of showing nothing.
            let siteID = site.id
            let place = site.address.isEmpty ? "that site" : site.address
            Task {
                await model.fillMissingLocations()
                if let s = model.data.sites.first(where: { $0.id == siteID }), s.latitude == nil || s.longitude == nil {
                    note = "The job at \(place) was added, but the address was not found on the map, so it is not on the route. Check the address in the client's details."
                }
            }
        }
    }

    /// Any other address: a one-off stop for this day.
    private func addAddress(_ text: String) async {
        guard canPlan, !adding else { return }
        adding = true
        let planned = day
        let found = await AddressCompleter.coordinate(for: text)
        adding = false
        guard let point = found else {
            note = "Could not find \"\(text)\" on the map. Try the full address."
            return
        }
        if let problem = model.edit({ _ = try $0.addAdHocStop(address: text, coordinate: point, on: planned, now: Date()) }) {
            note = problem
            return
        }
        finishAdding()
    }

    private func finishAdding() {
        search = ""
        searchFocused = false
        note = nil
        detent = .medium
    }

    // MARK: the route

    private func routeList(_ r: DayRoute) -> some View {
        List {
            header(r).plannerRow()
            sectionTitle("Route setup").plannerRow()
            setupRows(r)
            HStack {
                sectionTitle("Stops")
                Spacer()
                if r.numbered && !working {
                    Button("Optimize again", action: onOptimize).font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                }
                #if os(iOS)
                if r.stops.count > 1 {
                    Button(editMode == .active ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                }
                #endif
            }
            .plannerRow()
            if r.stops.isEmpty {
                Text(canPlan ? "No stops this day. Search above to add a client or any address." : "No stops this day.")
                    .font(.callout).foregroundStyle(.secondary).plannerRow()
            }
            ForEach(Array(r.stops.enumerated()), id: \.element.id) { i, s in
                stopRow(r, index: i, stop: s).plannerRow(Look.card)
            }
            .onMove { from, to in move(r, from: from, to: to) }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).plannerRow()
            }
            if let plan = r.plan, r.numbered {
                NextStopTextButton(plan: plan.result, day: day).plannerRow()   // ClientTextViews.swift
            }
            #if canImport(CoreLocation)
            if Calendar.current.isDateInToday(day) {
                AutoCheckInCard().plannerRow()   // AutoCheckInViews.swift
            }
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    private func header(_ r: DayRoute) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.stops.isEmpty ? "No stops yet" : (r.plan.map(RouteText.summary) ?? "\(r.stops.count) stops"))
                .font(.subheadline).foregroundStyle(.secondary)
            Button { sheet = .day } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(day.formatted(.dateTime.weekday(.wide))).font(.largeTitle.bold()).foregroundStyle(.primary)
                    Text(day.formatted(.dateTime.month(.abbreviated).day())).font(.title3).foregroundStyle(.secondary)
                    Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Pick another day")
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 10)
    }

    @ViewBuilder private func setupRows(_ r: DayRoute) -> some View {
        let s = d.routeSettings
        let startTime = d.routeStartTime(on: day)
        let startTitle: String = {
            if s.startKind == .custom, s.startCoordinate != nil, !s.startAddress.isEmpty { return RouteText.addressLines(s.startAddress).street }
            return d.depot == nil ? "Set where you start" : "Start at the yard"
        }()
        setupRow(leading: clockText(startTime), title: startTitle, detail: "Leave at \(clockText(startTime))",
                 icon: "house.fill", tint: .green) { sheet = .start }
        let finishTitle: String = {
            switch s.finishKind {
            case .returnToStart: return "Finish back at the start"
            case .endAtLastStop: return "Finish at the last stop"
            case .custom: return s.finishAddress.isEmpty ? "Set where you finish" : "Finish at \(RouteText.addressLines(s.finishAddress).street)"
            }
        }()
        let finishDetail: String? = r.stops.isEmpty ? nil : r.plan.map { "Done about \(clockText($0.endTime))" }
        setupRow(leading: nil, title: finishTitle, detail: finishDetail, icon: "flag.checkered", tint: .orange) { sheet = .finish }
        if let b = s.defaultBreak {
            let at = r.plan?.breakStart.map { " at \(clockText($0))" } ?? ""
            setupRow(leading: nil, title: "\(b.minutes) min break\(at)", detail: "After \(String(format: "%g", b.afterHours)) h of work",
                     icon: "cup.and.saucer.fill", tint: .brown) { sheet = .rest }
        } else {
            setupRow(leading: nil, title: "No break set", detail: "Set a default break", icon: "cup.and.saucer.fill", tint: .brown) { sheet = .rest }
        }
    }

    private func setupRow(leading: String?, title: String, detail: String?, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(tint).frame(width: 8, height: 8)
                if let leading {
                    Text(leading).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPlan)
        .plannerRow(Look.card)
    }

    private func stopRow(_ r: DayRoute, index: Int, stop: Stop) -> some View {
        let lines = RouteText.addressLines(stop.name)
        let timed = r.timed(stop.id)
        let label = r.numbered ? "\(index + 1)" : stopLabel(d, r, stop)
        return Button { sheet = .stop(stop.id) } label: {
            HStack(spacing: 12) {
                Circle().fill(tint).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    if let timed, timed.breakBefore, let b = d.routeSettings.defaultBreak {
                        Label("\(b.minutes) min break first", systemImage: "cup.and.saucer.fill").font(.caption).foregroundStyle(.brown)
                    }
                    Text(lines.street).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    if !lines.rest.isEmpty { Text(lines.rest).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    HStack(spacing: 8) {
                        if stop.serviceMinutes > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text("\(Int(stop.serviceMinutes)) min")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                        }
                        if r.adHoc[stop.id] != nil {
                            Text("One-off").font(.caption).foregroundStyle(.secondary)
                        }
                        if r.numbered, let timed {
                            Text("Arrive \(clockText(timed.arrival))").font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(label.isEmpty ? "•" : label).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(tint)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The user dragged a stop: keep their order until they tap Optimize again.
    private func move(_ r: DayRoute, from: IndexSet, to: Int) {
        var ids = r.stops.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        let planned = day
        _ = model.edit { $0.setRouteOrder(ids, on: planned, optimized: false) }
        if Calendar.current.isDateInToday(planned), let plan = DayRoute.make(model.data, day: planned, provider: provider).plan {
            model.plannedRoute = plan.result
        }
    }

    private func bottomBar(_ r: DayRoute) -> some View {
        let ready = r.ready
        return Button {
            if ready { onStart(r) } else { onOptimize() }
        } label: {
            HStack(spacing: 10) {
                if working {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: ready ? "location.fill" : "arrow.triangle.2.circlepath")
                }
                Text(working ? "Optimizing..." : (ready ? "Start route" : "Optimize route"))
            }
            .font(.title3.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(tint, in: Capsule())
            .opacity(r.stops.isEmpty ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(working || r.stops.isEmpty)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(Look.page)
    }

    // MARK: sheets

    @ViewBuilder private func sheetContent(_ which: PlannerSheet) -> some View {
        switch which {
        case .day:
            DayPickerSheet(day: $day).presentationDetents([.medium, .large])
        case .start:
            RouteStartSheet().presentationDetents([.medium, .large])
        case .finish:
            RouteFinishSheet().presentationDetents([.medium, .large])
        case .rest:
            RouteBreakSheet().presentationDetents([.medium, .large])
        case .scan:
            #if canImport(VisionKit) && os(iOS)
            AddressScanSheet { text in
                search = text
                searchFocused = true
            }
            #else
            EmptyView()
            #endif
        case .stop(let id):
            let r = DayRoute.make(d, day: day, provider: provider)
            let index = r.stops.firstIndex { $0.id == id }
            PlannerStopSheet(stopID: id, day: day, number: r.numbered ? index.map { $0 + 1 } : nil,
                             arrival: r.numbered ? r.timed(id)?.arrival : nil)
                .presentationDetents([.medium, .large])
        }
    }
}

private extension View {
    /// A row in the planner's list: no separator, even insets, and the panel's background (or a card color).
    func plannerRow(_ background: Color = .clear) -> some View {
        self.listRowBackground(background)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

// MARK: - Pins

private struct StopPin: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Color.white)
            .padding(.horizontal, text.count > 2 ? 6 : 0)
            .frame(minWidth: 30, minHeight: 30)
            .background(tint, in: Capsule())
            .overlay(Capsule().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

private struct PlacePin: View {
    let icon: String
    let tint: Color
    var body: some View {
        Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .background(tint, in: Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

#if canImport(MapKit)
private extension Coordinate {
    var mapPoint: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Address suggestions while typing, from Apple Maps.
@MainActor @Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        var text: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
    }

    private(set) var results: [Suggestion] = []
    @ObservationIgnored private let engine = MKLocalSearchCompleter()

    override init() {
        super.init()
        engine.delegate = self
        engine.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3 else {
            results = []
            return
        }
        engine.queryFragment = t
    }

    /// Prefer places near where the route starts.
    func near(_ c: Coordinate?) {
        guard let c else { return }
        engine.region = MKCoordinateRegion(center: c.mapPoint, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    private func refresh() {
        results = engine.results.prefix(6).map { Suggestion(title: $0.title, subtitle: $0.subtitle) }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// The map position of an address or place name, from Apple Maps, then Apple's geocoder.
    static func coordinate(for text: String) async -> Coordinate? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = clean
        if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
            let c = item.placemark.coordinate
            return Coordinate(latitude: c.latitude, longitude: c.longitude)
        }
        #if canImport(CoreLocation)
        return await AddressGeocoder.coordinate(for: clean)
        #else
        return nil
        #endif
    }
}
#endif

// MARK: - Small sheets

/// A small sheet in the app's style: a title, a close button, then cards.
private struct PlannerSheetScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) { content }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}

/// One choice with a tick on the right.
private struct PlannerChoiceRow: View {
    let title: String
    var detail: String?
    let on: Bool
    let action: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(on ? Theme.accent(model.data.profile.accentColor) : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DayPickerSheet: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PlannerSheetScaffold(title: "Pick a day") {
            Card {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }
            PrimaryActionButton(title: "Done", icon: "checkmark") { dismiss() }
        }
    }
}

private struct RouteStartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: RouteSettings.StartKind = .yard
    @State private var address = ""
    @State private var coordinate: Coordinate?
    /// The address text the coordinate was found for. Typing something else means it has to be found again.
    @State private var foundFor = ""
    @State private var time = Date()
    @State private var problem: String?
    @State private var working = false
    @State private var loaded = false
    #if canImport(CoreLocation)
    @State private var locator = LocationFetcher()
    #endif

    var body: some View {
        PlannerSheetScaffold(title: "Start") {
            CardGroup(title: "Leave at") {
                DatePicker("Start time", selection: $time, displayedComponents: .hourAndMinute)
            }
            CardGroup(title: "Start from") {
                PlannerChoiceRow(title: "The yard", detail: model.data.depot == nil ? "No yard set yet. Set it in Settings." : nil,
                                 on: kind == .yard) { kind = .yard }
                RowDivider()
                #if canImport(CoreLocation)
                PlannerChoiceRow(title: "Where I am now", detail: nil, on: false) { useHere() }
                RowDivider()
                #endif
                PlannerChoiceRow(title: "Another address", detail: nil, on: kind == .custom) { kind = .custom }
                if kind == .custom {
                    TextField("Street, town", text: $address).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
            }
            if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            PrimaryActionButton(title: working ? "Finding..." : "Save", icon: "checkmark") { Task { await save() } }
                .disabled(working)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = model.data.routeSettings
            kind = s.startKind
            address = s.startAddress
            coordinate = s.startCoordinate
            foundFor = s.startAddress
            time = model.data.routeStartTime(on: Date())
        }
    }

    #if canImport(CoreLocation)
    private func useHere() {
        working = true
        problem = nil
        Task {
            if let here = await locator.currentLocation() {
                kind = .custom
                address = "My location"
                foundFor = address
                coordinate = here
            } else {
                problem = "Could not get your location. Check the location permission."
            }
            working = false
        }
    }
    #endif

    private func save() async {
        var s = model.data.routeSettings
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        s.startMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
        s.startKind = kind
        if kind == .custom {
            let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { problem = "Type the address first."; return }
            var found = foundFor == text ? coordinate : nil
            if found == nil {
                working = true
                found = await AddressCompleter.coordinate(for: text)
                working = false
            }
            guard let point = found else { problem = "Could not find that address on the map."; return }
            s.startAddress = text
            s.startCoordinate = point
        }
        _ = model.edit { $0.setRouteSettings(s) }
        dismiss()
    }
}

private struct RouteFinishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: RouteSettings.FinishKind = .returnToStart
    @State private var address = ""
    @State private var coordinate: Coordinate?
    @State private var foundFor = ""
    @State private var problem: String?
    @State private var working = false
    @State private var loaded = false

    var body: some View {
        PlannerSheetScaffold(title: "Finish") {
            CardGroup(title: "Where the day ends", footer: "Optimize counts the drive to the finish, so the last stops end up close to it.") {
                PlannerChoiceRow(title: "Back to the start", on: kind == .returnToStart) { kind = .returnToStart }
                RowDivider()
                PlannerChoiceRow(title: "At the last stop", on: kind == .endAtLastStop) { kind = .endAtLastStop }
                RowDivider()
                PlannerChoiceRow(title: "Another address", on: kind == .custom) { kind = .custom }
                if kind == .custom {
                    TextField("Street, town", text: $address).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
            }
            if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            PrimaryActionButton(title: working ? "Finding..." : "Save", icon: "checkmark") { Task { await save() } }
                .disabled(working)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = model.data.routeSettings
            kind = s.finishKind
            address = s.finishAddress
            coordinate = s.finishCoordinate
            foundFor = s.finishAddress
        }
    }

    private func save() async {
        var s = model.data.routeSettings
        s.finishKind = kind
        if kind == .custom {
            let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { problem = "Type the address first."; return }
            var found = foundFor == text ? coordinate : nil
            if found == nil {
                working = true
                found = await AddressCompleter.coordinate(for: text)
                working = false
            }
            guard let point = found else { problem = "Could not find that address on the map."; return }
            s.finishAddress = text
            s.finishCoordinate = point
        }
        _ = model.edit { $0.setRouteSettings(s) }
        dismiss()
    }
}

private struct RouteBreakSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var on = false
    @State private var minutes = 30.0
    @State private var after = 4.0
    @State private var loaded = false

    var body: some View {
        PlannerSheetScaffold(title: "Break") {
            CardGroup(footer: "The break goes in after the stop where the work time (driving and time on site) passes this many hours.") {
                Toggle("Take a break", isOn: $on).font(.body.weight(.medium))
            }
            if on {
                PillStepper(label: "Length", value: $minutes, range: 5...120, step: 5, format: { "\(Int($0)) min" })
                PillStepper(label: "After", value: $after, range: 0.5...10, step: 0.5, format: { String(format: "%g h", $0) })
            }
            PrimaryActionButton(title: "Save", icon: "checkmark") {
                var s = model.data.routeSettings
                s.defaultBreak = on ? RouteBreak(minutes: Int(minutes), afterHours: after) : nil
                _ = model.edit { $0.setRouteSettings(s) }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let b = model.data.routeSettings.defaultBreak {
                on = true
                minutes = Double(b.minutes)
                after = b.afterHours
            }
        }
    }
}

/// One stop: time on site, a note, navigate, text the client, or take it off this day.
private struct PlannerStopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let stopID: UUID
    let day: Date
    let number: Int?
    let arrival: Date?

    @State private var minutes = 20.0
    @State private var note = ""
    @State private var loaded = false
    @State private var removed = false
    @State private var problem: String?

    private var d: AppData { model.data }
    private var job: Job? { d.jobs(on: day).first { $0.id == stopID } }
    private var adHoc: AdHocStop? { d.adHocStops.first { $0.id == stopID } }
    private var site: Site? { job?.siteID.flatMap { id in d.sites.first { $0.id == id } } }
    private var canEdit: Bool { adHoc != nil ? (d.can(.editJobs) || d.can(.logVisits)) : d.can(.editJobs) }
    private var coordinate: Coordinate? {
        if let a = adHoc { return a.coordinate }
        guard let site, let lat = site.latitude, let lon = site.longitude else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    var body: some View {
        let address = adHoc?.address ?? site?.address ?? job?.title ?? "Stop"
        let lines = RouteText.addressLines(address)
        PlannerSheetScaffold(title: number.map { "Stop \($0)" } ?? "Stop") {
            if job == nil && adHoc == nil {
                EmptyCard(icon: "mappin.slash", title: "Not on this day", message: "This stop was removed or finished.")
            } else {
                CardGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lines.street).font(.title3.weight(.semibold))
                        if !lines.rest.isEmpty { Text(lines.rest).foregroundStyle(.secondary) }
                    }
                    if let job {
                        RowDivider()
                        let who = d.customerName(forJob: job)
                        if !who.isEmpty { FactRow(label: "Client", value: who) }
                        FactRow(label: "Job", value: job.title)
                    }
                    if let arrival {
                        RowDivider()
                        FactRow(label: "Arrive about", value: clockText(arrival))
                    }
                    if let site, !site.instructions.isEmpty {
                        RowDivider()
                        Text(site.instructions).font(.callout)
                    }
                    if let job, !job.notes.isEmpty {
                        RowDivider()
                        Text(job.notes).font(.callout).foregroundStyle(.secondary)
                    }
                }
                PillStepper(label: "Time on site", value: $minutes, range: 5...240, step: 5, format: { "\(Int($0)) min" })
                    .disabled(!canEdit).opacity(canEdit ? 1 : 0.6)
                if adHoc != nil {
                    PillNotes(label: "Note", placeholder: "What to do here", text: $note).disabled(!canEdit)
                }
                if let c = coordinate, let url = NavigationLinks.appleMaps(to: c) {
                    PrimaryActionButton(title: "Navigate", icon: "location.fill") { openURL(url) }
                }
                if let job { ClientTextSection(job: job) }   // ClientTextViews.swift: "On my way" for today's client jobs
                if canEdit {
                    SecondaryActionButton(title: adHoc != nil ? "Remove stop" : "Skip this visit", icon: "minus.circle") { remove() }
                }
                if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            minutes = Double(adHoc?.serviceMinutes ?? job?.durationMinutes ?? d.routeSettings.defaultServiceMinutes)
            note = adHoc?.note ?? ""
        }
        .onDisappear(perform: commit)
    }

    /// Saves the time on site and note when the sheet closes.
    private func commit() {
        guard canEdit, !removed else { return }
        let m = Int(minutes)
        if let a = adHoc {
            if a.serviceMinutes != m || a.note != note { _ = model.edit { try $0.updateAdHocStop(id: a.id, serviceMinutes: m, note: note) } }
        } else if let j = job, j.durationMinutes != m {
            _ = model.edit { try $0.setJobServiceMinutes(m, id: j.id) }
        }
    }

    private func remove() {
        let result: String?
        if let a = adHoc {
            result = model.edit { try $0.removeAdHocStop(id: a.id) }
        } else if let j = job {
            result = model.edit { try $0.skipOccurrence(id: j.id, on: day) }
        } else {
            result = nil
        }
        if let result { problem = result; return }
        removed = true
        dismiss()
    }
}

#if canImport(VisionKit) && os(iOS)
/// Point the camera at a sign, a work order or a letter, then tap the address.
private struct AddressScanSheet: View {
    let onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            TextScannerView { text in
                onText(text)
                dismiss()
            }
            .ignoresSafeArea()
            HStack {
                Text("Tap the address").font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(16)
        }
    }
}

private struct TextScannerView: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item { onText(text.transcript) }
        }
    }
}
#endif
#endif
