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
            Section("Needs your attention") {
                if pendingRequests > 0 {
                    NavigationLink { RequestsView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "tray.full.fill", title: "\(pendingRequests) client request\(pendingRequests == 1 ? "" : "s")", subtitle: "Waiting for your answer", badge: pendingRequests, tint: .orange)
                    }
                }
                if drafts > 0 {
                    NavigationLink { InvoicesView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "doc.text.fill", title: "\(drafts) draft invoice\(drafts == 1 ? "" : "s")", subtitle: "Look them over and send", badge: drafts)
                    }
                }
                if overdue > 0 {
                    NavigationLink { InvoicesView().environment(\.embeddedInStack, true) } label: {
                        HubRow(icon: "exclamationmark.circle.fill", title: "\(overdue) overdue invoice\(overdue == 1 ? "" : "s")", subtitle: model.reminderPlan().messages.isEmpty ? "Past their due date" : "You can send friendly reminders", badge: overdue, tint: .red)
                    }
                }
            }
        }
    }

    @ViewBuilder private var setupSection: some View {
        let items = SetupChecklist.items(for: model.data, serverConfigured: model.serverConfigured)
        let progress = SetupChecklist.progress(items)
        let remaining = items.filter { !$0.done }
        if progress.done < progress.total {
            Section {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                ForEach(remaining) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title + (item.optional ? " (optional)" : "")).font(.subheadline.bold())
                        Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Finish setup: \(progress.done) of \(progress.total)")
            }
        }
    }

    private var sites: [Site] { model.data.sites.sorted { ($0.priority, $0.address) < ($1.priority, $1.address) } }

    var body: some View {
        ScreenStack {
            List {
                attentionSection
                setupSection
                Section { TextField("Storm name", text: stormNameBinding) }
                Section("Sites") {
                    ForEach(sites) { site in
                        let visits = model.data.visitLog.records(forSite: site.id).filter { $0.stormID == model.stormName }
                        Button { selected = site } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(site.address).foregroundStyle(.primary)
                                    if !site.instructions.isEmpty {
                                        Text(site.instructions).font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if let last = visits.last {
                                    Image(systemName: last.status == .completed ? "checkmark.circle.fill" : "minus.circle.fill")
                                        .foregroundStyle(last.status == .completed ? .green : .orange)
                                }
                            }
                        }
                    }
                }
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
    @State private var salt = 0.0
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

    var body: some View {
        NavigationStack {
            Form {
                Section(site.address) {
                    if !site.instructions.isEmpty { Text(site.instructions).foregroundStyle(.orange) }
                    Toggle("Could not service this visit", isOn: $skipped)
                    if skipped { TextField("Reason (saved in the proof record and the message preview)", text: $reason) }
                }
                Section("Who and where") {
                    TextField("Your name", text: $crewName)
                    HStack {
                        Text(locationText)
                        Spacer()
                        #if canImport(CoreLocation)
                        Button(findingLocation ? "Finding..." : "Check location") { checkLocation() }
                            .buttonStyle(.bordered)
                            .font(.footnote)
                            .disabled(findingLocation)
                        #endif
                    }
                    if site.latitude == nil {
                        Text("This site has no map location, so arrival cannot be checked.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !locationProblem.isEmpty {
                        Text(locationProblem).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !skipped {
                    Section("Work") {
                        Stepper("Snow depth: \(depth, specifier: "%.1f") in", value: $depth, in: 0...36, step: 0.5)
                        Stepper("Salt: \(Int(salt)) lb", value: $salt, in: 0...500, step: 10)
                    }
                }
                Section(skipped ? "Photos of the problem" : "Photos") {
                    if skipped {
                        PhotoCaptureRow(title: "What blocked the visit", kind: .other, photos: $problemPhotos)
                    } else {
                        PhotoCaptureRow(title: "Before", kind: .before, photos: $beforePhotos)
                        PhotoCaptureRow(title: "After", kind: .after, photos: $afterPhotos)
                    }
                }
                Section("Note") { TextField("Optional note", text: $note) }
                Section("Message to customer (preview only, messages are not sent yet)") {
                    Text(preview).font(.footnote)
                    if !skipped && afterPhotos.isEmpty {
                        Text("No after photo yet. The proof of service is stronger with one.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Log visit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(skipped && reason.isEmpty)
                }
            }
        }
    }

    private func checkLocation() {
        #if canImport(CoreLocation)
        findingLocation = true
        Task {
            let here = await locator.currentLocation()
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
                                 snowDepthInches: skipped ? 0 : depth, saltPounds: skipped ? 0 : salt,
                                 photos: skipped ? problemPhotos : beforePhotos + afterPhotos, note: note)
        model.record(record)
        dismiss()
    }
}
#endif
