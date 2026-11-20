#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// One job or task as a card: time, title, client, place, status and its place in today's route.
struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: Job
    var routeNumber: Int?
    var showDate = false
    let onTap: () -> Void

    private var timeText: String {
        let f = DateFormatter.make(showDate ? "MMM d, h:mm a" : "h:mm a")
        return f.string(from: job.start)
    }

    var body: some View {
        Button(action: onTap) {
            Card(padding: 14) {
                HStack(spacing: 14) {
                    if let n = routeNumber {
                        Text("\(n)").font(.headline).foregroundStyle(.white).frame(width: 34, height: 34)
                            .background(Theme.accent(model.data.profile.accentColor), in: Circle())
                    } else {
                        IconTile(icon: job.isTask ? "checklist" : "briefcase.fill", tint: job.status.color, size: 40)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        let who = model.data.customerName(forJob: job)
                        let place = model.data.address(forJob: job)
                        Text([timeText, who, place].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: job.isTask ? "Task" : job.status.title, color: job.status.color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Change a job's status, see who is on it, navigate to it.
struct JobDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let jobID: UUID
    @State private var message: String?

    private var job: Job? { model.data.jobs.first { $0.id == jobID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(job?.title ?? "Job").font(.title3.weight(.medium)).lineLimit(1)
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            if let job {
                AppPage(clearTabBar: false) {
                    CardGroup {
                        FactRow(label: "When", value: DateFormatter.make("EEEE, MMM d, h:mm a").string(from: job.start))
                        RowDivider()
                        FactRow(label: "Length", value: "\(job.durationMinutes) min")
                        RowDivider()
                        FactRow(label: "Type", value: job.isTask ? "Reminder or task" : job.kind.title)
                        let who = model.data.customerName(forJob: job)
                        if !who.isEmpty {
                            RowDivider()
                            FactRow(label: "Client", value: who)
                        }
                        let place = model.data.address(forJob: job)
                        if !place.isEmpty {
                            RowDivider()
                            FactRow(label: "Place", value: place)
                        }
                        if let site = model.data.sites.first(where: { $0.id == job.siteID }), !site.instructions.isEmpty {
                            RowDivider()
                            Text(site.instructions).font(.footnote)
                        }
                        if !job.notes.isEmpty {
                            RowDivider()
                            Text(job.notes).font(.footnote)
                        }
                    }
                    let people = model.data.team.filter { job.assigneeIDs.contains($0.id) }
                    if !people.isEmpty {
                        CardGroup(title: "Assigned to") {
                            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                                if index > 0 { RowDivider() }
                                Text(person.name).font(.title3)
                            }
                        }
                    }
                    if let site = model.data.sites.first(where: { $0.id == job.siteID }),
                       let lat = site.latitude, let lon = site.longitude,
                       let url = NavigationLinks.appleMaps(to: Coordinate(latitude: lat, longitude: lon), from: model.data.depot) {
                        SecondaryActionButton(title: "Navigate in Apple Maps", icon: "location.fill") { openURL(url) }
                    }
                    if !job.isTask && (model.data.can(.editJobs) || model.data.can(.logVisits)) {
                        CardGroup(title: "Status") {
                            ForEach(Array(JobStatus.allCases.enumerated()), id: \.offset) { index, s in
                                if index > 0 { RowDivider() }
                                Button { message = model.setJobStatus(s, id: job.id) } label: {
                                    HStack {
                                        Text(s.title).font(.title3).foregroundStyle(.primary)
                                        Spacer()
                                        if job.status == s { Image(systemName: "checkmark").foregroundStyle(s.color) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if job.isTask {
                        SecondaryActionButton(title: job.status == .done ? "Mark not done" : "Mark done", icon: job.status == .done ? "arrow.uturn.backward" : "checkmark") {
                            message = model.setJobStatus(job.status == .done ? .scheduled : .done, id: job.id)
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    if model.data.can(.editJobs) {
                        PrimaryActionButton(title: "Delete", icon: "trash", destructive: true) {
                            message = model.deleteJob(job.id)
                            if message == nil { dismiss() }
                        }
                    }
                }
            } else {
                AppPage(clearTabBar: false) {
                    EmptyCard(icon: "briefcase", title: "Job not found", message: "This job no longer exists.")
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}

/// Create a job in three steps (client and job, when, who and notes), or a reminder or task in one.
struct JobEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialDate: Date = Date()
    var startsAsTask = false

    private enum ClientMode { case none, existing }

    @State private var step = 0
    @State private var title = ""
    @State private var kind: JobKind = .snowPlowing
    @State private var clientMode: ClientMode = .none
    @State private var customerID: UUID?
    @State private var siteID: UUID?
    @State private var start = Date()
    @State private var minutes = 60.0
    @State private var assignees: Set<UUID> = []
    @State private var notes = ""
    @State private var isTask = false
    @State private var problem: String?
    @State private var loaded = false
    @State private var showNewClient = false

    private var clients: [Customer] { model.data.customers.filter { !$0.isLead } }
    private var sitesForClient: [Site] { model.data.sites.filter { $0.customerID == customerID } }
    private var people: [TeamMember] { model.data.team.filter { $0.status != .disabled } }
    private var steps: [String] { isTask ? ["Reminder"] : ["Client & Job", "Schedule", "Crew & notes"] }
    private var canAdvance: Bool { step != 0 || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        WizardScaffold(title: isTask ? "New Reminder" : "New Job", steps: steps, step: $step, canAdvance: canAdvance, onClose: { dismiss() }, onFinish: save) {
            if step == 0 {
                PillChoice(options: [(false, "Job", "briefcase"), (true, "Reminder or task", "checklist")], selection: $isTask)
            }
            if isTask {
                SectionLabel(text: "Reminder")
                PillField(label: "What to remember", required: true, placeholder: "Call the county about the lot", text: $title)
                whenSection
                PillNotes(label: "Notes", placeholder: "Anything to remember", text: $notes)
            } else {
                switch step {
                case 0: clientAndJob
                case 1: whenSection
                default: crewAndNotes
                }
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            isTask = startsAsTask
            let cal = Calendar.current
            let c = cal.dateComponents([.year, .month, .day], from: initialDate)
            start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: cal.date(from: c) ?? initialDate) ?? initialDate
            if cal.isDateInToday(initialDate) { start = max(Date(), start) }
            if !model.data.isOwnerSession, let me = model.data.currentMember { assignees = [me.id] }
        }
        .onChange(of: isTask) { step = 0 }
        .onChange(of: customerID) { siteID = sitesForClient.count == 1 ? sitesForClient[0].id : nil }
        .sheet(isPresented: $showNewClient) {
            AddCustomerSheet { id in customerID = id; clientMode = .existing }
        }
    }

    private var clientAndJob: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionLabel(text: "Client")
            HStack(spacing: 12) {
                bigButton("New Client", icon: "person.badge.plus") { showNewClient = true }
                bigButton("Existing Client", icon: "person.crop.circle.badge.checkmark", on: clientMode == .existing) { clientMode = .existing }
            }
            if clientMode == .existing {
                if clients.isEmpty {
                    Text("You have no clients yet. Tap New Client.").font(.callout).foregroundStyle(.secondary)
                } else {
                    PillMenu(label: "Choose a client", options: [(UUID?.none, "Choose")] + clients.map { (UUID?.some($0.id), $0.name) }, selection: $customerID)
                    if sitesForClient.count > 1 {
                        PillMenu(label: "Which address", options: [(UUID?.none, "Choose")] + sitesForClient.map { (UUID?.some($0.id), $0.address) }, selection: $siteID)
                    } else if let only = sitesForClient.first {
                        Label(only.address, systemImage: "mappin.circle").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            SectionLabel(text: "Job details")
            PillField(label: "Job Title", required: true, placeholder: "e.g. Plow and salt", text: $title)
            PillMenu(label: "Type", options: JobKind.allCases.map { ($0, $0.title) }, selection: $kind)
            Text("Only jobs at a site with a map location go on the route.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(text: "When")
            Card(padding: 14) { DatePicker("Starts", selection: $start).font(.title3) }
            PillStepper(label: "Length", value: $minutes, range: 5...600, step: 5, format: { "\(Int($0)) min" })
        }
    }

    private var crewAndNotes: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !people.isEmpty {
                SectionLabel(text: "Who does it")
                ForEach(people) { p in
                    let on = assignees.contains(p.id)
                    Button { if on { assignees.remove(p.id) } else { assignees.insert(p.id) } } label: {
                        HStack {
                            Text(p.name).font(.title3).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(on ? Theme.accent(model.data.profile.accentColor) : Color.secondary)
                        }
                        .padding(.horizontal, 22).padding(.vertical, 14).background(Look.field, in: Capsule()).overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            PillNotes(label: "Notes", placeholder: "Gate code, special instructions", text: $notes)
        }
    }

    private func bigButton(_ title: String, icon: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        return Button(action: action) {
            HStack(spacing: 8) { Image(systemName: icon); Text(title).font(.title3.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7) }
                .foregroundStyle(tint).frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(on ? tint.opacity(0.16) : Look.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? tint : Look.fieldStroke, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        problem = model.addJob(title: title, kind: isTask ? .other : kind, customerID: isTask ? nil : customerID, siteID: isTask ? nil : siteID,
                               start: start, durationMinutes: Int(minutes), assigneeIDs: isTask ? [] : Array(assignees), notes: notes, isTask: isTask)
        if problem == nil { dismiss() }
    }
}
#endif
