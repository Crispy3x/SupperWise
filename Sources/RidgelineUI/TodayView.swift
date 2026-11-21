#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Crew view: tap a site to log the visit.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Site?

    private var stormNameBinding: Binding<String> { Binding(get: { model.stormName }, set: { model.stormName = $0 }) }

    private var pendingRequests: Int { model.data.serviceRequests.filter { $0.status == .pending && $0.kind != .thanks }.count }
    private var drafts: Int { model.data.invoices.filter { $0.sentAt == nil && !$0.isVoid }.count }
    private var overdue: Int { model.data.invoices.filter { $0.status(now: Date()) == .overdue }.count }

    @ViewBuilder private var attentionSection: some View {
        if pendingRequests + drafts + overdue > 0 {
            CardGroup(title: "Needs your attention") {
                if pendingRequests > 0 {
                    NavigationLink { RequestsView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                        CardLinkRow(icon: "tray.full.fill", tint: .orange, title: "\(pendingRequests) client request\(pendingRequests == 1 ? "" : "s")", detail: "Waiting for your answer", badge: pendingRequests)
                    }
                    .buttonStyle(.plain)
                }
                if drafts > 0 {
                    if pendingRequests > 0 { RowDivider() }
                    NavigationLink { InvoicesView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                        CardLinkRow(icon: "doc.text.fill", title: "\(drafts) draft invoice\(drafts == 1 ? "" : "s")", detail: "Look them over and send", badge: drafts)
                    }
                    .buttonStyle(.plain)
                }
                if overdue > 0 {
                    if pendingRequests + drafts > 0 { RowDivider() }
                    NavigationLink { InvoicesView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                        CardLinkRow(icon: "exclamationmark.circle.fill", tint: .red, title: "\(overdue) overdue invoice\(overdue == 1 ? "" : "s")", detail: model.reminderPlan().messages.isEmpty ? "Past their due date" : "You can send friendly reminders", badge: overdue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var setupSection: some View {
        let items = SetupChecklist.items(for: model.data, serverConfigured: model.serverConfigured)
        let progress = SetupChecklist.progress(items)
        let remaining = items.filter { !$0.done }
        if progress.done < progress.total {
            CardGroup(title: "Finish setup: \(progress.done) of \(progress.total)") {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                ForEach(remaining) { item in
                    RowDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title + (item.optional ? " (optional)" : "")).font(.subheadline.bold())
                        Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sites: [Site] { model.data.sites.sorted { ($0.priority, $0.address) < ($1.priority, $1.address) } }

    @ViewBuilder private var sitesSection: some View {
        if sites.isEmpty {
            EmptyCard(icon: "mappin.and.ellipse", title: "No sites yet", message: "Add a client with an address to start logging visits.")
        } else {
            CardGroup(title: "Sites") {
                ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                    let visits = model.data.visitLog.records(forSite: site.id).filter { $0.stormID == model.stormName }
                    if index > 0 { RowDivider() }
                    Button { selected = site } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.address).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                if !site.instructions.isEmpty {
                                    Text(site.instructions).font(.footnote).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if let last = visits.last {
                                Image(systemName: last.status == .completed ? "checkmark.circle.fill" : "minus.circle.fill")
                                    .foregroundStyle(last.status == .completed ? .green : .orange)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        ScreenStack {
            AppPage {
                attentionSection
                setupSection
                CardGroup(title: "Storm") {
                    PillField(label: "Storm name", placeholder: "Storm name", text: stormNameBinding)
                }
                sitesSection
            }
            .navigationTitle("Crew")
            .sheet(item: $selected) { site in VisitSheet(site: site, stormID: model.stormName) }
        }
    }
}

struct VisitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let site: Site
    let stormID: String

    @State private var skipped = false
    @State private var reason = ""
    @State private var depth = 3.0
    @State private var material: MaterialType = .none
    @State private var materialAmount = 0.0
    @State private var weather = ""
    @State private var here: Coordinate?
    @State private var beforePhotos: [PhotoRef] = []
    @State private var afterPhotos: [PhotoRef] = []
    @State private var problemPhotos: [PhotoRef] = []
    @State private var note = ""
    @State private var arrival = Date()
    @State private var geofence: GeofenceStatus = .unknown
    @State private var locationProblem = ""
    @AppStorage("crewMemberName") private var crewName = ""
    @State private var findingLocation = false
    #if canImport(CoreLocation)
    @State private var locator = LocationFetcher()
    #endif

    private var company: String { model.data.companyName.isEmpty ? "Your crew" : model.data.companyName }

    private var preview: String {
        if skipped { return NoticeTemplates.message(.skipped, company: company, address: site.address, reason: reason.isEmpty ? nil : reason) }
        return NoticeTemplates.message(.complete, company: company, address: site.address)
    }

    private var locationText: String {
        switch geofence {
        case .inside: return "At the site"
        case .outside: return "Not at the site"
        case .unknown: return "Location not checked"
        }
    }

    /// What gets burned into each photo when it is saved.
    private var stampLines: (Date) -> [String] {
        let address = site.address, coordinate = here, note = weather
        return { PhotoStamp.lines(capturedAt: $0, address: address, coordinate: coordinate, weatherNote: note) }
    }

    @ViewBuilder private var materialRows: some View {
        PillMenu(label: "Material", options: MaterialType.allCases.map { ($0, $0.title) }, selection: $material)
        if material != MaterialType.none {
            let unit = material.unit
            PillStepper(label: unit == .gallons ? "Gallons" : "Pounds", value: $materialAmount, range: 0...5000,
                        step: unit == .gallons ? 5 : 10, format: { MaterialFormat.amount($0, unit: unit) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log visit").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(title: site.address, footer: skipped ? "The reason is saved in the proof record and the message preview." : nil) {
                    if !site.instructions.isEmpty { Text(site.instructions).foregroundStyle(.orange) }
                    Toggle("Could not service this visit", isOn: $skipped)
                    if skipped { PillField(label: "Reason", required: true, placeholder: "Why the visit was skipped", text: $reason) }
                }
                CardGroup(title: "Who and where") {
                    PillField(label: "Your name", placeholder: "Name", text: $crewName)
                    FactRow(label: "Arrival", value: locationText)
                    #if canImport(CoreLocation)
                    SecondaryActionButton(title: findingLocation ? "Finding..." : "Check location", icon: "location") { checkLocation() }
                        .disabled(findingLocation)
                        .opacity(findingLocation ? 0.5 : 1)
                    #endif
                    if site.latitude == nil {
                        Text("This site has no map location, so arrival cannot be checked.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !locationProblem.isEmpty {
                        Text(locationProblem).font(.footnote).foregroundStyle(.secondary)
                    }
                    PillField(label: "Weather", optional: true, placeholder: "Light snow, 25°F", text: $weather)
                }
                if !skipped {
                    CardGroup(title: "Work") {
                        PillStepper(label: "Snow depth", value: $depth, range: 0...36, step: 0.5, format: { String(format: "%.1f in", $0) })
                        materialRows
                    }
                }
                CardGroup(title: skipped ? "Photos of the problem" : "Photos") {
                    if skipped {
                        PhotoCaptureRow(title: "What blocked the visit", kind: .other, photos: $problemPhotos, stamp: stampLines)
                    } else {
                        PhotoCaptureRow(title: "Before", kind: .before, photos: $beforePhotos, stamp: stampLines)
                        RowDivider()
                        PhotoCaptureRow(title: "After", kind: .after, photos: $afterPhotos, stamp: stampLines)
                    }
                    Text(here == nil ? "Photos are stamped with the time, address and weather. Check location first to add GPS."
                                     : "Photos are stamped with the time, address, GPS and weather.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                CardGroup {
                    PillNotes(label: "Note", placeholder: "Optional note", text: $note)
                }
                CardGroup(title: "Message to customer", footer: "Preview only, messages are not sent yet.") {
                    Text(preview).font(.footnote)
                    if !skipped && afterPhotos.isEmpty {
                        Text("No after photo yet. The proof of service is stronger with one.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                PrimaryActionButton(title: "Save", icon: "checkmark") { save() }
                    .disabled(skipped && reason.isEmpty)
                    .opacity(skipped && reason.isEmpty ? 0.5 : 1)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }

    private func checkLocation() {
        #if canImport(CoreLocation)
        findingLocation = true
        Task {
            let here = await locator.currentLocation()
            if let here { self.here = here }
            geofence = ArrivalCheck.status(device: here, site: site)
            locationProblem = here == nil ? "Could not get your location. Check the location permission in Settings." : ""
            findingLocation = false
        }
        #endif
    }

    private func save() {
        let now = Date()
        let record = VisitRecord(siteID: site.id, crewMemberName: crewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Name not entered" : crewName.trimmingCharacters(in: .whitespacesAndNewlines), stormID: stormID, arrival: arrival, departure: now,
                                 geofence: geofence,
                                 status: skipped ? .skipped(reason: reason) : .completed,
                                 snowDepthInches: skipped ? 0 : depth,
                                 weatherNote: weather.trimmingCharacters(in: .whitespacesAndNewlines),
                                 saltPounds: !skipped && material.isSalt ? materialAmount : 0,
                                 photos: skipped ? problemPhotos : beforePhotos + afterPhotos, note: note,
                                 material: skipped ? nil : material,
                                 materialAmount: skipped || material == MaterialType.none ? nil : materialAmount)
        model.record(record)
        dismiss()
    }
}
#endif
