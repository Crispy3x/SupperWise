#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

// MARK: - Calendar

/// A month grid with a dot on days that have something scheduled, and the picked day's list underneath.
struct CalendarTabView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()
    @State private var selected = Date()
    @State private var showEditor = false
    @State private var openedJob: UUID?
    @State private var openedDay: Date?   // the tapped visit of a repeating job
    @State private var shareURL: URL?

    private var cal: Calendar { Calendar.current }

    private var days: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let first = cal.dateInterval(of: .weekOfMonth, for: interval.start)?.start,
              let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end),
              let lastWeek = cal.dateInterval(of: .weekOfMonth, for: lastDay) else { return [] }
        var out: [Date] = []
        var d = first
        while d < lastWeek.end { out.append(d); d = cal.date(byAdding: .day, value: 1, to: d) ?? lastWeek.end }
        return out
    }

    private var weekdayHeaders: [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols.map { String($0.prefix(3)).uppercased() }
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                shareBanner
                HStack {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left").font(.title3.bold()) }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(DateFormatter.make("LLLL yyyy").string(from: month)).font(.title2.bold())
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right").font(.title3.bold()) }
                        .accessibilityLabel("Next month")
                }
                .buttonStyle(.plain).padding(.horizontal, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                    ForEach(weekdayHeaders, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    ForEach(days, id: \.self) { day in DayCell(day: day, month: month, selected: selected) { selected = day } }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(DateFormatter.make("EEEE, MMMM d").string(from: selected).uppercased())
                        .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    let jobs = model.data.jobs(on: selected)
                    if jobs.isEmpty {
                        Text("Nothing scheduled").font(.title3).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                            .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(Look.stroke))
                    } else {
                        ForEach(jobs) { job in JobRow(job: job) { openedDay = job.start; openedJob = job.id } }
                    }
                    if model.data.can(.editJobs) {
                        Button { showEditor = true } label: {
                            Card(padding: 12) {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus").font(.title3).foregroundStyle(Theme.accent(model.data.profile.accentColor))
                                        .frame(width: 48, height: 48).background(Theme.accent(model.data.profile.accentColor).opacity(0.16), in: Circle())
                                    Text("Add job or reminder/task").font(.headline).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, Look.tabBarClearance + 40)
        }
        .sheet(isPresented: $showEditor) { JobEditorSheet(initialDate: selected) }
        .sheet(isPresented: Binding(get: { openedJob != nil }, set: { if !$0 { openedJob = nil } })) {
            if let id = openedJob { JobDetailSheet(jobID: id, occurrenceDate: openedDay) }
        }
        .task(id: model.data.jobs) { shareURL = model.scheduleFileURL() }
    }

    /// Shares the schedule as a calendar file that Apple Calendar, Google Calendar and Outlook can all open.
    @ViewBuilder private var shareBanner: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        if let shareURL {
            ShareLink(item: shareURL) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                    Text("Share to your personal calendar").font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let month: Date
    let selected: Date
    let action: () -> Void

    var body: some View {
        let cal = Calendar.current
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let tint = Theme.accent(model.data.profile.accentColor)
        let hasJobs = !model.data.jobs(on: day).isEmpty
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.weight(isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
                    .frame(width: 44, height: 44)
                    .background(isSelected ? tint : (isToday ? tint.opacity(0.25) : Color.clear), in: Circle())
                Circle().fill(hasJobs ? tint : Color.clear).frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateFormatter.make("EEEE, MMMM d").string(from: day) + (hasJobs ? ", has jobs" : ""))
    }
}

// MARK: - Jobs

private enum JobFilter: Hashable {
    case all
    case status(JobStatus)
    var title: String {
        switch self {
        case .all: return "All"
        case .status(let s): return s.title
        }
    }
}

struct JobsTabView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter: JobFilter = .all
    @State private var showEditor = false
    @State private var openedJob: UUID?

    private var allJobs: [Job] { model.data.visibleJobs.filter { !$0.isTask } }

    private func matches(_ job: Job) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return [job.title, model.data.customerName(forJob: job), model.data.address(forJob: job)].contains { $0.lowercased().contains(q) }
    }

    private func count(_ f: JobFilter) -> Int {
        switch f {
        case .all: return allJobs.count
        case .status(let s): return allJobs.filter { $0.status == s }.count
        }
    }

    private var shown: [Job] {
        let list = allJobs.filter { job in
            if case .status(let s) = filter, job.status != s { return false }
            return matches(job)
        }
        let open = list.filter { $0.status.isOpen }.sorted { $0.start < $1.start }
        let closed = list.filter { !$0.status.isOpen }.sorted { $0.start > $1.start }
        return open + closed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "briefcase.fill", title: "Jobs",
                                 trailing: "\(allJobs.filter { $0.status.isOpen }.count) active · \(allJobs.count) total")
                    SearchField(prompt: "Search jobs by title or client...", text: $query)
                    Menu {
                        Button("All (\(count(.all)))") { filter = .all }
                        ForEach(JobStatus.allCases, id: \.self) { s in Button("\(s.title) (\(count(.status(s))))") { filter = .status(s) } }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.accent(model.data.profile.accentColor))
                            Text("Filter:").foregroundStyle(.secondary)
                            Text(filter.title).bold().foregroundStyle(.primary)
                            Text("\(shown.count)").font(.callout.bold()).foregroundStyle(Theme.accent(model.data.profile.accentColor))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Theme.accent(model.data.profile.accentColor).opacity(0.18), in: Capsule())
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(.secondary)
                        }
                        .font(.title3)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Look.card, in: Capsule())
                        .overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    if allJobs.isEmpty {
                        EmptyCard(icon: "list.clipboard", title: "No jobs yet", message: "Schedule your first job to get started.")
                    } else if shown.isEmpty {
                        EmptyCard(icon: "magnifyingglass", title: "No matches", message: "Try a different search or filter.")
                    } else {
                        ForEach(shown) { job in JobRow(job: job, showDate: true) { openedJob = job.id } }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
            }
            if model.data.can(.editJobs) {
                PrimaryBar(title: "Create Job") { showEditor = true }
                    .padding(.horizontal, 16).padding(.bottom, Look.tabBarClearance)
            } else {
                Color.clear.frame(height: Look.tabBarClearance)
            }
        }
        .sheet(isPresented: $showEditor) { JobEditorSheet() }
        .sheet(isPresented: Binding(get: { openedJob != nil }, set: { if !$0 { openedJob = nil } })) {
            if let id = openedJob { JobDetailSheet(jobID: id) }
        }
    }
}

// MARK: - Clients

struct ClientsTabView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showNewClient = false
    @State private var showNewLead = false
    @State private var showSeasonLinks = false

    private var clients: [Customer] { model.data.customers.filter { !$0.isLead } }
    private var leads: [Customer] { model.data.customers.filter { $0.isLead } }

    private func addresses(_ c: Customer) -> [String] { model.data.sites.filter { $0.customerID == c.id }.map(\.address) }

    private var shown: [Customer] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = q.isEmpty ? clients : clients.filter { c in
            ([c.name, c.phone, c.email] + addresses(c)).contains { $0.lowercased().contains(q) }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        ScreenHeader(icon: "person.2.fill", title: "Clients", trailing: "\(clients.count) total · \(shown.count) shown")
                        SearchField(prompt: "Search by name, phone, or email...", text: $query)
                        NavigationLink { LeadsView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                            Card(padding: 12) {
                                HStack(spacing: 14) {
                                    IconTile(icon: "leaf.fill", tint: .teal, size: 48)
                                    Text("Leads").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    if !leads.isEmpty {
                                        Text("\(leads.count)").font(.callout.bold()).foregroundStyle(.teal)
                                            .padding(.horizontal, 10).padding(.vertical, 3).background(Color.teal.opacity(0.18), in: Capsule())
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if clients.isEmpty {
                            EmptyCard(icon: "person.2", title: "No clients yet", message: "Add your first client to get started.")
                            if model.data.customers.isEmpty && model.data.contracts.isEmpty && model.data.isOwnerSession {
                                Button("Load sample clients to try the app") { model.loadDemoData() }.buttonStyle(.bordered)
                            }
                        } else if shown.isEmpty {
                            EmptyCard(icon: "magnifyingglass", title: "No matches", message: "Try a different search.")
                        } else {
                            ForEach(shown) { c in
                                NavigationLink { ClientDetailView(customerID: c.id).circleBack().pageBackground() } label: {
                                    Card(padding: 12) {
                                        HStack(spacing: 14) {
                                            AvatarView(name: c.name, size: 46)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(c.name).font(.headline).foregroundStyle(.primary)
                                                Text(([addresses(c).first, c.phone.isEmpty ? nil : c.phone].compactMap { $0 }).joined(separator: " · "))
                                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if model.data.can(.editClients) {
                            Button { showSeasonLinks = true } label: {
                                Card(padding: 12) {
                                    HStack(spacing: 14) {
                                        IconTile(icon: "paperplane.fill", tint: .purple, size: 48)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Send winter page links").font(.headline).foregroundStyle(.primary)
                                            Text("Each client's private page for the whole season").font(.footnote).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            ContactsImportButton()      // iPhone and iPad only (ContactsImportView.swift)
                            NavigationLink { CustomersView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                                Label("Import clients from a spreadsheet (CSV)", systemImage: "square.and.arrow.down").font(.callout)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
                }
                if model.data.can(.editClients) {
                    PrimaryBar(title: "Create Client") { showNewClient = true }
                        .padding(.horizontal, 16).padding(.bottom, Look.tabBarClearance)
                } else {
                    Color.clear.frame(height: Look.tabBarClearance)
                }
            }
            .background(Look.page)
            .hideNavBar()
            .sheet(isPresented: $showNewClient) { AddCustomerSheet() }
            .sheet(isPresented: $showSeasonLinks) { SeasonLinksSheet() }
        }
    }
}

/// People who asked about your service but are not clients yet. Turn one into a client when they say yes.
struct LeadsView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false
    private var leads: [Customer] { model.data.customers.filter { $0.isLead } }

    var body: some View {
        AppPage(title: "Leads", icon: "leaf.fill", trailing: "\(leads.count) total") {
            SecondaryActionButton(title: "Add lead", icon: "plus") { showNew = true }
            if leads.isEmpty {
                EmptyCard(icon: "leaf", title: "No leads yet", message: "Add someone who has asked about your service.")
            }
            ForEach(leads) { lead in
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lead.name).font(.headline)
                        if !lead.phone.isEmpty || !lead.email.isEmpty { Text([lead.phone, lead.email].filter { !$0.isEmpty }.joined(separator: " \u{B7} ")).font(.footnote).foregroundStyle(.secondary) }
                        if !lead.notes.isEmpty { Text(lead.notes).font(.footnote) }
                        HStack(spacing: 12) {
                            PrimaryActionButton(title: "Make a client") { model.edit { d in if let i = d.customers.firstIndex(where: { $0.id == lead.id }) { d.customers[i].isLead = false } } }
                            SecondaryActionButton(title: "Remove", icon: "trash") { model.edit { d in d.customers.removeAll { $0.id == lead.id } } }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) { AddLeadSheet() }
    }
}

struct AddLeadSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New lead").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(title: "Contact") {
                    PillField(label: "Name", required: true, placeholder: "Lead name", text: $name)
                    PillField(label: "Phone", optional: true, placeholder: "Phone number", text: $phone, kind: .phone)
                    PillField(label: "Email", optional: true, placeholder: "name@email.com", text: $email, kind: .email)
                }
                CardGroup {
                    PillNotes(label: "What they asked for", placeholder: "Details", text: $notes)
                }
                PrimaryActionButton(title: "Save", icon: "checkmark") {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.edit { $0.customers.append(Customer(name: String(clean.prefix(80)), phone: String(phone.prefix(40)),
                                                              email: String(email.prefix(120)), notes: String(notes.prefix(500)), isLead: true)) }
                    dismiss()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}
#endif
