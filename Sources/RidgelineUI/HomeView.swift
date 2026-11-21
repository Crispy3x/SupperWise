#if canImport(SwiftUI)
import SwiftUI
import MapKit
import RidgelineCore

/// A job on the Home map: where it is and, once the route is planned, its number in the order.
struct MapPoint: Identifiable, Equatable {
    let id: UUID
    let label: String
    let coordinate: CLLocationCoordinate2D
    static func == (a: MapPoint, b: MapPoint) -> Bool { a.id == b.id && a.label == b.label }
}

/// The home screen: tips, today's map with the planned route, quick actions and today's jobs.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let startTour: () -> Void
    let openScreen: (ShellScreen) -> Void
    let openSmartRoute: () -> Void

    @State private var showNewJob = false
    @State private var showNewClient = false
    @State private var showMap = false
    @State private var openedJob: UUID?

    private var today: [Job] { model.data.jobs(on: Date()) }

    /// The planned route counts only while it still matches today's jobs.
    private var order: [UUID: Int] {
        let current = Set(model.data.routeStops(on: Date()).map(\.id))
        // Subset, not equal: stops marked done along the way (auto check-in) leave the rest of the numbers in place.
        guard let plan = model.plannedRoute, current.isSubset(of: Set(plan.stops.map(\.id))), !current.isEmpty else { return [:] }
        return Dictionary(uniqueKeysWithValues: plan.stops.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    private var points: [MapPoint] {
        let numbers = order
        let stops = model.data.routeStops(on: Date())
        let ordered = numbers.isEmpty ? stops : stops.sorted { (numbers[$0.id] ?? 0) < (numbers[$1.id] ?? 0) }
        return ordered.map { s in
            MapPoint(id: s.id, label: model.autoCheckInLabel(numbers[s.id].map(String.init) ?? s.name, for: s.id),   // AutoCheckInViews.swift
                     coordinate: CLLocationCoordinate2D(latitude: s.coordinate.latitude, longitude: s.coordinate.longitude))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.isHintDismissed("tour") {
                    BannerRow(icon: "safari", title: "New here? Take a quick tour", onClose: { model.dismissHint("tour") }, action: startTour)
                }
                if model.data.isOwnerSession && !model.isHintDismissed("form") && model.data.broadcastSettings.portalBaseURL.isEmpty {
                    BannerRow(icon: "link", title: "Set up your service request form", onClose: nil) { openScreen(.settings) }
                }
                HomeInvoiceCard()   // QuickInvoiceViews.swift
                StormModeSection(onHome: true, openRoute: openSmartRoute)   // StormModeViews.swift
                JobsMap(points: points, height: 380, onExpand: { showMap = true })
                if model.serverConfigured && model.data.can(.logVisits) { ShareLocationCard() }
                #if canImport(CoreLocation)
                AutoCheckInCard()   // AutoCheckInViews.swift: hides itself when there is nothing to check in to
                #endif
                if model.data.can(.editJobs) || model.data.can(.editClients) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick actions").font(.title2.bold())
                        HStack(spacing: 12) {
                            if model.data.can(.editJobs) { QuickAction(icon: "list.clipboard", title: "New Job") { showNewJob = true } }
                            if model.data.can(.editClients) { QuickAction(icon: "person.badge.plus", title: "New Client") { showNewClient = true } }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's jobs").font(.title2.bold())
                        Spacer()
                        if model.data.routeStops(on: Date()).count > 1 {
                            Button { openSmartRoute() } label: { Label("Smart route", systemImage: "sparkles") }
                                .buttonStyle(.bordered).tint(Look.sparkle)
                        }
                    }
                    if today.isEmpty {
                        EmptyCard(icon: "calendar", title: "Nothing today", message: "Schedule a job to see it here.")
                    } else {
                        ForEach(today) { job in
                            JobRow(job: job, routeNumber: order[job.id]) { openedJob = job.id }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, Look.tabBarClearance + 40)
        }
        .sheet(isPresented: $showNewJob) { JobEditorSheet() }
        .sheet(isPresented: $showNewClient) { AddCustomerSheet() }
        .sheet(isPresented: $showMap) { FullMapSheet(points: points) }
        .sheet(isPresented: Binding(get: { openedJob != nil }, set: { if !$0 { openedJob = nil } })) {
            if let id = openedJob { JobDetailSheet(jobID: id) }
        }
    }
}

private struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(icon: icon, tint: Theme.accent(model.data.profile.accentColor), size: 46)
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Look.card, in: Capsule())
            .overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Apple Maps with today's jobs. Numbers show the planned order.
struct JobsMap: View {
    let points: [MapPoint]
    var height: CGFloat?
    var onExpand: (() -> Void)?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(points) { p in
                Marker(p.label, coordinate: p.coordinate).tint(.blue)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: height)
        .frame(maxHeight: height == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            if points.isEmpty {
                Text("No jobs on the map today").font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule()).padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.primary)
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).padding(12).accessibilityLabel("Expand map")
            }
        }
        .onChange(of: points) { _, new in fit(new) }
        .onAppear { fit(points) }
    }

    private func fit(_ pts: [MapPoint]) {
        guard !pts.isEmpty else { position = .userLocation(fallback: .automatic); return }
        let lats = pts.map(\.coordinate.latitude), lons = pts.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.02),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.02))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct FullMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let points: [MapPoint]
    var body: some View {
        NavigationStack {
            JobsMap(points: points, height: nil)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Today's map")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Smart route

/// Puts today's jobs in the quickest order to drive, using real drive times from Apple Maps on this device.
/// This is route optimization (nearest stop first, then improved by swapping), not a chat assistant.
struct SmartRouteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: RoutePlanResult?
    @State private var note = "Planning..."
    @State private var working = true

    @State private var day = Date()
    private var stops: [Stop] { model.data.routeStops(on: day) }
    private var start: Coordinate { model.data.depot ?? stops.first?.coordinate ?? Coordinate(latitude: 0, longitude: 0) }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Smart route").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if working && plan == nil {
                    Card { HStack(spacing: 12) { ProgressView(); Text("Finding the quickest order...") } }
                } else if stops.isEmpty {
                    EmptyCard(icon: "map", title: "No route yet",
                              message: "Create a job for a client with an address, and it will show up here. If you just added one, check the client's address.")
                } else if let plan {
                    CardGroup(title: Calendar.current.isDateInToday(day) ? "Drive in this order, today" : "Drive in this order, \(day.formatted(.dateTime.weekday(.wide).month().day()))") {
                        ForEach(Array(plan.planned.enumerated()), id: \.offset) { i, p in
                            HStack {
                                Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                                Text(p.stop.name)
                                Spacer()
                                Text("\(Int(p.arrivalOffsetSeconds / 60)) min").foregroundStyle(.secondary).monospacedDigit()
                            }
                            RowDivider()
                        }
                        FactRow(label: "Total driving", value: "\(Int(plan.totalDriveSeconds / 60)) min")
                    }
                    if let first = plan.stops.first, let url = NavigationLinks.appleMaps(to: first.coordinate, from: start) {
                        PrimaryActionButton(title: "Start in Apple Maps", icon: "location.fill") { openURL(url) }
                    }
                    NextStopTextButton(plan: plan, day: day)   // ClientTextViews.swift
                    #if canImport(CoreLocation)
                    if Calendar.current.isDateInToday(day) { AutoCheckInCard() }   // AutoCheckInViews.swift
                    #endif
                }
                Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .task { await run() }
    }

    private func run() async {
        await model.fillMissingLocations()
        day = model.nextRouteDay(from: Date())
        guard !stops.isEmpty else {
            note = (await model.planRoute(on: day)).note
            working = false
            return
        }
        let result = await model.planRoute(on: day)
        if Task.isCancelled { return }
        plan = result.plan
        note = result.note
        if let p = result.plan { model.plannedRoute = p }
        working = false
    }
}

/// Lets clients waiting for service see this truck on their page. It only runs while the app is open.
struct ShareLocationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if canImport(CoreLocation)
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { model.truckSharer.isSharing }, set: { on in if on { model.startSharing() } else { model.stopSharing() } })) {
                    Label("Show this truck to clients", systemImage: "location.fill").font(.headline)
                }
                if !model.truckSharer.isSharing {
                    TextField("Truck name clients see", text: Binding(get: { model.sharingLabel }, set: { model.sharingLabel = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                Text(model.truckSharer.isSharing ? model.truckSharer.note
                     : "Clients still waiting for service see this truck's position on their own page while this is on. Turn it off when the route is done. It works while the app is open.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        #endif
    }
}
#endif
