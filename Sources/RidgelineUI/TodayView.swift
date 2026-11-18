#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Crew view: tap a site to log the visit.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var stormName = "Today"
    @State private var selected: Site?

    private var sites: [Site] { model.data.sites.sorted { ($0.priority, $0.address) < ($1.priority, $1.address) } }

    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Storm name", text: $stormName) }
                Section("Sites") {
                    ForEach(sites) { site in
                        let visits = model.data.visitLog.records(forSite: site.id).filter { $0.stormID == stormName }
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
            .sheet(item: $selected) { site in VisitSheet(site: site, stormID: stormName) }
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
    @State private var before = false
    @State private var after = false
    @State private var note = ""
    @State private var arrival = Date()

    private var preview: String {
        if skipped { return NoticeTemplates.message(.skipped, company: model.data.companyName, address: site.address, reason: reason.isEmpty ? nil : reason) }
        return NoticeTemplates.message(.complete, company: model.data.companyName, address: site.address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(site.address) {
                    if !site.instructions.isEmpty { Text(site.instructions).foregroundStyle(.orange) }
                    Toggle("Could not service this visit", isOn: $skipped)
                    if skipped { TextField("Reason (customer will see this)", text: $reason) }
                }
                if !skipped {
                    Section("Work") {
                        Stepper("Snow depth: \(depth, specifier: "%.1f") in", value: $depth, in: 0...36, step: 0.5)
                        Stepper("Salt: \(Int(salt)) lb", value: $salt, in: 0...500, step: 10)
                        Toggle("Before photo taken", isOn: $before)
                        Toggle("After photo taken", isOn: $after)
                        Text("Photo capture is a placeholder in this build. These toggles log that a photo was taken.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Note") { TextField("Optional note", text: $note) }
                Section("Message to customer") { Text(preview).font(.footnote) }
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

    private func save() {
        let now = Date()
        var photos: [PhotoRef] = []
        if before && !skipped { photos.append(PhotoRef(kind: .before, filename: "placeholder-before.jpg", capturedAt: arrival, sha256: SHA256.hex(UUID().uuidString))) }
        if after && !skipped { photos.append(PhotoRef(kind: .after, filename: "placeholder-after.jpg", capturedAt: now, sha256: SHA256.hex(UUID().uuidString))) }
        let record = VisitRecord(siteID: site.id, crewMemberName: "Crew", stormID: stormID, arrival: arrival, departure: now,
                                 geofence: geofence,
                                 status: skipped ? .skipped(reason: reason) : .completed,
                                 snowDepthInches: skipped ? 0 : depth, saltPounds: skipped ? 0 : salt,
                                 photos: photos, note: note)
        model.record(record)
        dismiss()
    }
}
#endif
