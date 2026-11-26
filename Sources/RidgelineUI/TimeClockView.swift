#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct TimeClockView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("crewMemberName") private var name = ""
    @State private var siteID: UUID?
    @State private var message: String?

    /// A signed-in employee clocks in as themselves, under the name the owner gave them, so their hours land on their
    /// own timesheet row and pay rate. Only the owner types a name.
    private var member: TeamMember? { model.data.currentMember }
    private var who: String { (member?.name ?? name).trimmingCharacters(in: .whitespacesAndNewlines) }

    private var openEntry: TimeEntry? {
        model.data.timeEntries.first { $0.memberName == who && $0.end == nil }
    }

    /// Open shifts first, so one never scrolls out of view, then the most recent.
    /// An employee who may not see the team sees only their own shifts.
    private var recent: [TimeEntry] {
        var all = model.data.timeEntries
        if member != nil && !model.data.can(.viewTeam) {
            let me = who.lowercased()
            all = all.filter { $0.memberName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == me }
        }
        let open = all.filter { $0.end == nil }.sorted { $0.start > $1.start }
        let closed = all.filter { $0.end != nil }.sorted { $0.start > $1.start }
        return Array((open + closed).prefix(20))
    }

    private func siteName(_ id: UUID?) -> String { model.data.sites.first { $0.id == id }?.address ?? "General" }

    var body: some View {
        ScreenStack {
            AppPage {
                CardGroup(title: "Who is working", footer: message) {
                    if let member {
                        FactRow(label: "Name", value: member.name)
                    } else {
                        PillField(label: "Your name", placeholder: "Name", text: $name)
                    }
                    PillMenu(label: "Job", options: [(UUID?.none, "General")] + model.data.sites.map { (UUID?.some($0.id), $0.address) }, selection: $siteID)
                    if openEntry == nil {
                        PrimaryActionButton(title: "Clock in", icon: "play.fill") { message = model.edit { try $0.clockIn(member: who, siteID: siteID, now: Date()) } }
                            .disabled(who.isEmpty)
                            .opacity(who.isEmpty ? 0.5 : 1)
                    } else {
                        PrimaryActionButton(title: "Clock out", icon: "stop.fill") { message = model.edit { try $0.clockOut(member: who, now: Date()) } }
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
