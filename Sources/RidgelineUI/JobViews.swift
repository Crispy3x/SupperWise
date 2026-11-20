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
    let jobID: UUID
    @State private var message: String?

    private var job: Job? { model.data.jobs.first { $0.id == jobID } }

    var body: some View {
        NavigationStack {
            Group {
            if let job {
                List {
                    Section {
                        LabeledContent("When", value: DateFormatter.make("EEEE, MMM d, h:mm a").string(from: job.start))
                        LabeledContent("Length", value: "\(job.durationMinutes) min")
                        LabeledContent("Type", value: job.isTask ? "Reminder or task" : job.kind.title)
                        let who = model.data.customerName(forJob: job)
                        if !who.isEmpty { LabeledContent("Client", value: who) }
                        let place = model.data.address(forJob: job)
                        if !place.isEmpty { LabeledContent("Place", value: place) }
                        if let site = model.data.sites.first(where: { $0.id == job.siteID }), !site.instructions.isEmpty {
                            Text(site.instructions).font(.footnote)
                        }
                        if !job.notes.isEmpty { Text(job.notes).font(.footnote) }
                    }
                    let people = model.data.team.filter { job.assigneeIDs.contains($0.id) }
                    if !people.isEmpty {
                        Section("Assigned to") { ForEach(people) { Text($0.name) } }
                    }
                    if let site = model.data.sites.first(where: { $0.id == job.siteID }),
                       let lat = site.latitude, let lon = site.longitude,
                       let url = NavigationLinks.appleMaps(to: Coordinate(latitude: lat, longitude: lon), from: model.data.depot) {
                        Section { Link(destination: url) { Label("Navigate in Apple Maps", systemImage: "location.fill") } }
                    }
                    if !job.isTask && (model.data.can(.editJobs) || model.data.can(.logVisits)) {
                        Section("Status") {
                            ForEach(JobStatus.allCases, id: \.self) { s in
                                Button { message = model.setJobStatus(s, id: job.id) } label: {
                                    HStack {
                                        Text(s.title).foregroundStyle(.primary)
                                        Spacer()
                                        if job.status == s { Image(systemName: "checkmark").foregroundStyle(s.color) }
                                    }
                                }
                            }
                        }
                    } else if job.isTask {
                        Section {
                            Button(job.status == .done ? "Mark not done" : "Mark done") {
                                message = model.setJobStatus(job.status == .done ? .scheduled : .done, id: job.id)
                            }
                        }
                    }
                    if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
                    if model.data.can(.editJobs) {
                        Section {
                            Button("Delete", role: .destructive) {
                                message = model.deleteJob(job.id)
                                if message == nil { dismiss() }
                            }
                        }
                    }
                }
                .navigationTitle(job.title)
            } else {
                Text("This job no longer exists.").foregroundStyle(.secondary)
            }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Create a job, or a reminder or task.
struct JobEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialDate: Date = Date()
    var startsAsTask = false

    @State private var title = ""
    @State private var kind: JobKind = .snowPlowing
    @State private var customerID: UUID?
    @State private var siteID: UUID?
    @State private var start = Date()
    @State private var minutes = 60
    @State private var assignees: Set<UUID> = []
    @State private var notes = ""
    @State private var isTask = false
    @State private var problem: String?
    @State private var loaded = false

    private var sitesForClient: [Site] { model.data.sites.filter { $0.customerID == customerID } }
    private var people: [TeamMember] { model.data.team.filter { $0.status != .disabled } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isTask) {
                        Text("Job").tag(false)
                        Text("Reminder or task").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField(isTask ? "What to remember" : "Job title, for example Plow and salt", text: $title)
                    if !isTask {
                        Picker("Service", selection: $kind) { ForEach(JobKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    }
                }
                Section("When") {
                    DatePicker("Starts", selection: $start)
                    Stepper("Length: \(minutes) min", value: $minutes, in: 5...600, step: 5)
                }
                if !isTask {
                    Section("Where") {
                        Picker("Client", selection: $customerID) {
                            Text("No client").tag(UUID?.none)
                            ForEach(model.data.customers.filter { !$0.isLead }) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        if customerID != nil {
                            Picker("Site", selection: $siteID) {
                                Text("No site").tag(UUID?.none)
                                ForEach(sitesForClient) { Text($0.address).tag(UUID?.some($0.id)) }
                            }
                        }
                        Text("Only jobs with a site that has a map location go on the route.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !people.isEmpty {
                        Section("Who does it") {
                            ForEach(people) { p in
                                Toggle(p.name, isOn: Binding(get: { assignees.contains(p.id) },
                                                             set: { on in if on { assignees.insert(p.id) } else { assignees.remove(p.id) } }))
                            }
                        }
                    }
                }
                Section("Notes") { TextField("Gate code, special instructions", text: $notes, axis: .vertical).lineLimit(2...5) }
                if let problem { Section { Text(problem).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle(isTask ? "New reminder" : "New job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        problem = model.addJob(title: title, kind: isTask ? .other : kind, customerID: isTask ? nil : customerID,
                                               siteID: isTask ? nil : siteID, start: start, durationMinutes: minutes,
                                               assigneeIDs: isTask ? [] : Array(assignees), notes: notes, isTask: isTask)
                        if problem == nil { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: customerID) { siteID = nil }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                isTask = startsAsTask
                // The picked day, at a sensible hour if that day has no time yet.
                let cal = Calendar.current
                let c = cal.dateComponents([.year, .month, .day], from: initialDate)
                start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: cal.date(from: c) ?? initialDate) ?? initialDate
                if cal.isDateInToday(initialDate) { start = max(Date(), start) }
                if !people.isEmpty, !model.data.isOwnerSession, let me = model.data.currentMember { assignees = [me.id] }
            }
        }
    }
}
#endif
