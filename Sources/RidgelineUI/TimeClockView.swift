#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct TimeClockView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("crewMemberName") private var name = ""
    @State private var siteID: UUID?
    @State private var message: String?

    private var openEntry: TimeEntry? {
        model.data.timeEntries.first { $0.memberName == name.trimmingCharacters(in: .whitespacesAndNewlines) && $0.end == nil }
    }

    private var recent: [TimeEntry] {
        Array(model.data.timeEntries.sorted { $0.start > $1.start }.prefix(20))
    }

    private func siteName(_ id: UUID?) -> String { model.data.sites.first { $0.id == id }?.address ?? "General" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who is working") {
                    TextField("Your name", text: $name)
                    Picker("Job", selection: $siteID) {
                        Text("General").tag(UUID?.none)
                        ForEach(model.data.sites) { Text($0.address).tag(Optional($0.id)) }
                    }
                    if openEntry == nil {
                        Button("Clock in") { message = model.edit { try $0.clockIn(member: name, siteID: siteID, now: Date()) } }
                            .disabled(name.isEmpty)
                    } else {
                        Button("Clock out") { message = model.edit { try $0.clockOut(member: name, now: Date()) } }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                }
                Section("Recent") {
                    if recent.isEmpty { Text("No time recorded yet.").foregroundStyle(.secondary) }
                    ForEach(recent) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.memberName).font(.headline)
                                Spacer()
                                Text("\(entry.hours(now: Date()), specifier: "%.2f") h")
                            }
                            Text("\(siteName(entry.siteID)), \(entry.start.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote).foregroundStyle(.secondary)
                            if entry.end == nil && entry.hours(now: Date()) > 12 {
                                Text("Still clocked in after 12 hours. Check for a missed clock out.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Time clock")
        }
    }
}
#endif
