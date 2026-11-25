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
                HomeSummaryCard(openScreen: openScreen, openRoute: openSmartRoute)   // HomeSummary.swift
                if model.data.activeStormRun != nil { StormModeSection(onHome: true, openRoute: openSmartRoute) }   // StormModeViews.swift
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's jobs").font(.title2.bold())
                        Spacer()
                        if !model.data.plannerStops(on: Date()).isEmpty || model.data.can(.editJobs) {
                            Button { openSmartRoute() } label: {
                                Label("Plan route", systemImage: "map.fill").font(.callout.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 9).background(Look.sparkle, in: Capsule())
                            }
                            .buttonStyle(.plain)
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
                JobsMap(points: points, height: 280, onExpand: openSmartRoute)   // opens the route planner
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
                HomeInvoiceCard()   // QuickInvoiceViews.swift
                if model.data.activeStormRun == nil { StormModeSection(onHome: true, openRoute: openSmartRoute) }
                if !model.isHintDismissed("tour") {
                    BannerRow(icon: "safari", title: "New here? Take a quick tour", onClose: { model.dismissHint("tour") }, action: startTour)
                }
                if model.data.isOwnerSession && !model.isHintDismissed("form") && model.data.broadcastSettings.portalBaseURL.isEmpty {
                    BannerRow(icon: "link", title: "Set up your service request form", onClose: nil) { openScreen(.settings) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, Look.tabBarClearance + 40)
        }
        .sheet(isPresented: $showNewJob) { JobEditorSheet() }
        .sheet(isPresented: $showNewClient) { AddCustomerSheet() }
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
