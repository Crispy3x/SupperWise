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

    /// Open shifts first, so one never scrolls out of view, then the most recent.
    private var recent: [TimeEntry] {
        let open = model.data.timeEntries.filter { $0.end == nil }.sorted { $0.start > $1.start }
        let closed = model.data.timeEntries.filter { $0.end != nil }.sorted { $0.start > $1.start }
        return Array((open + closed).prefix(20))
    }

    private func siteName(_ id: UUID?) -> String { model.data.sites.first { $0.id == id }?.address ?? "General" }

    var body: some View {
        ScreenStack {
            AppPage {
                CardGroup(title: "Who is working", footer: message) {
                    PillField(label: "Your name", placeholder: "Name", text: $name)
                    PillMenu(label: "Job", options: [(UUID?.none, "General")] + model.data.sites.map { (UUID?.some($0.id), $0.address) }, selection: $siteID)
                    if openEntry == nil {
                        PrimaryActionButton(title: "Clock in", icon: "play.fill") { message = model.edit { try $0.clockIn(member: name, siteID: siteID, now: Date()) } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    } else {
                        PrimaryActionButton(title: "Clock out", icon: "stop.fill") { message = model.edit { try $0.clockOut(member: name, now: Date()) } }
                    }
                }
                if recent.isEmpty {
                    EmptyCard(icon: "clock", title: "No time recorded yet", message: "Clock in to start your first shift.")
                } else {
                    CardGroup(title: "Recent") {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { RowDivider() }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.memberName).font(.headline)
                                    Spacer()
                                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                                        Text("\(entry.hours(now: context.date), specifier: "%.2f") h").fontWeight(.semibold)
                                    }
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
            }
            .navigationTitle("Time clock")
        }
    }
}
#endif
