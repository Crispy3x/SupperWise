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
                        if let rule = job.repeatRule, rule.repeats {
                            Label(rule.summary, systemImage: "repeat").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        JobPriceTag(job: job)   // the price, for people who may see money (JobBillingViews.swift)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: job.isTask ? "Task" : (job.repeats && job.status == .cancelled ? "Skipped" : job.status.title), color: job.status.color)
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
    /// For a repeating job: the visit that was tapped. Nil shows the next visit from today.
    var occurrenceDate: Date? = nil
    @State private var message: String?

    /// The job, or for a repeating job the one visit this sheet is about (its own date and status).
    private var job: Job? {
        guard let series = model.data.jobs.first(where: { $0.id == jobID }) else { return nil }
        guard series.repeats else { return series }
        let day = occurrenceDate ?? series.nextOccurrence(onOrAfter: Date()) ?? series.start
        return series.occurrence(on: day) ?? series
    }

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
                        if let rule = job.repeatRule, rule.repeats {
                            RowDivider()
                            Label(rule.fullSummary, systemImage: "repeat").font(.footnote).foregroundStyle(.secondary)
                        }
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
                    ClientTextSection(job: job)   // "On my way" and "Job done" texts (ClientTextViews.swift)
                    if !job.isTask && (model.data.can(.editJobs) || model.data.can(.logVisits)) {
                        CardGroup(title: job.repeats ? "This visit" : "Status", footer: job.repeats ? "Only this visit changes. The others stay scheduled." : nil) {
                            ForEach(Array(JobStatus.allCases.enumerated()), id: \.offset) { index, s in
                                if index > 0 { RowDivider() }
                                // For a job that does not repeat this sets the job's own status.
                                Button { message = model.setOccurrenceStatus(s, id: job.id, on: job.start) } label: {
                                    HStack {
                                        Text(job.repeats && s == .cancelled ? "Skipped" : s.title).font(.title3).foregroundStyle(.primary)
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
                            message = model.setOccurrenceStatus(job.status == .done ? .scheduled : .done, id: job.id, on: job.start)
                        }
                    }
                    JobBillingSection(job: job)   // the price, and the invoice for a finished visit (JobBillingViews.swift)
                    if model.data.can(.editJobs), let rule = job.repeatRule, rule.repeats {
                        SecondaryActionButton(title: "Stop repeating after this visit", icon: "stop.circle") {
                            message = model.setJobRepeat(RepeatRule(frequency: rule.frequency, endDate: job.start), id: job.id)
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    if model.data.can(.editJobs) {
                        PrimaryActionButton(title: job.repeats ? "Delete all visits" : "Delete", icon: "trash", destructive: true) {
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

/// Create a job in a few steps (client and job, when, price, who and notes), or a reminder or task in one.
struct JobEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialDate: Date = Date()
    var startsAsTask = false
    /// Opens with this client already chosen (from the client profile).
    var startCustomerID: UUID? = nil

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
    @State private var repeatFrequency: RepeatFrequency = .never
    @State private var repeatHasEnd = false
    @State private var repeatEnd = Date()
    @State private var priceLines: [JobPriceLine] = []
    @State private var customPrice = ""

    private var clients: [Customer] { model.data.customers.filter { !$0.isLead } }
    private var sitesForClient: [Site] { model.data.sites.filter { $0.customerID == customerID } }
    private var people: [TeamMember] { model.data.team.filter { $0.status != .disabled } }
    /// The Price step is only for people who may see money.
    private var showsPrice: Bool { model.data.can(.viewRevenue) }
    private var steps: [String] {
        if isTask { return ["Reminder"] }
        return showsPrice ? ["Client & Job", "Schedule", "Price", "Crew & notes"] : ["Client & Job", "Schedule", "Crew & notes"]
    }
    private var canAdvance: Bool { step != 0 || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        WizardScaffold(title: isTask ? "New Reminder" : "New Job", steps: steps, step: $step, canAdvance: canAdvance, onClose: { dismiss() }, onFinish: save) {
            if step == 0 {
                PillChoice(options: [(false, "Job", "briefcase"), (true, "Reminder", "checklist")], selection: $isTask)
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
                default:
                    if showsPrice && step == 2 {
                        JobPriceSection(lines: $priceLines, customAmount: $customPrice, jobTitle: title,
                                        repeats: repeatFrequency != .never, hasClient: customerID != nil)   // JobBillingViews.swift
                    } else {
                        crewAndNotes
                    }
                }
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            isTask = startsAsTask
            if let startCustomerID, model.data.customers.contains(where: { $0.id == startCustomerID }) { customerID = startCustomerID; clientMode = .existing }
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
            PillMenu(label: "Repeat", options: RepeatFrequency.allCases.map { ($0, $0.title) }, selection: $repeatFrequency)
            if repeatFrequency != .never {
                PillChoice(options: [(false, "Keeps going", "infinity"), (true, "Ends on a date", "calendar")], selection: $repeatHasEnd)
                if repeatHasEnd {
                    Card(padding: 14) { DatePicker("Last visit", selection: $repeatEnd, in: start..., displayedComponents: .date).font(.title3) }
                }
                if repeatFrequency == .monthly && Calendar.current.component(.day, from: start) > 28 {
                    Text("In shorter months it goes on the last day.").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Mark each visit done or skipped on its own. The others stay scheduled.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: repeatHasEnd) {
            if repeatHasEnd && repeatEnd < start { repeatEnd = Calendar.current.date(byAdding: .month, value: 3, to: start) ?? start }
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
                               start: start, durationMinutes: Int(minutes), assigneeIDs: isTask ? [] : Array(assignees), notes: notes, isTask: isTask,
                               repeatRule: repeatFrequency == .never ? nil : RepeatRule(frequency: repeatFrequency, endDate: repeatHasEnd ? repeatEnd : nil),
                               priceLines: showsPrice && !isTask ? JobBilling.lines(picked: priceLines, customAmount: customPrice, customName: title) : [])
        if problem == nil { dismiss() }
    }
}
#endif
