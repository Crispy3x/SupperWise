#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Which sheet is open on top of the client profile.
private enum ClientSheet: Identifiable {
    case quickInvoice
    case invoice(String)
    case newJob
    case job(UUID, Date?)
    case measure(Site)
    case property(Site?)
    case photo(Int)

    var id: String {
        switch self {
        case .quickInvoice: return "quickInvoice"
        case .invoice(let number): return "invoice-\(number)"
        case .newJob: return "newJob"
        case .job(let id, let day): return "job-\(id.uuidString)-\(day?.timeIntervalSince1970 ?? 0)"
        case .measure(let site): return "measure-\(site.id.uuidString)"
        case .property(let site): return "property-\(site?.id.uuidString ?? "new")"
        case .photo(let index): return "photo-\(index)"
        }
    }
}

/// Everything on the profile that takes work to figure out: money, service dates, history and each property's season.
/// Built once when the screen opens and again when the saved data changes, never per row.
private struct ClientSnapshot {
    let overview: ClientOverview
    let sites: [Site]
    let statements: [UUID: SeasonStatement]
    let pageLinks: [UUID: String]
}

/// Dates the way the profile says them.
private enum ProfileText {
    static func day(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }

    static func dayAndTime(_ date: Date) -> String { DateFormatter.make("EEE, MMM d 'at' h:mm a").string(from: date) }

    /// "today", "yesterday" or "12 days ago". Empty for anything older than two months.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 60 { return "\(days) days ago" }
        return ""
    }

    static func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
}

/// One client, everything in one place: who they are, what they owe, their service, properties, photos and history.
/// It opens as a profile to read. Changing contact details is one tap away, lower down.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let customerID: UUID

    // Contact details being changed, behind "Edit contact".
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var loaded = false
    @State private var editingContact = false
    @State private var note: String?
    @State private var confirmDelete = false

    @State private var notes = ""
    @State private var propertyNote: String?
    @State private var snapshot: ClientSnapshot?
    @State private var sheet: ClientSheet?
    @State private var showInvoices = false
    @State private var showAllInvoices = false
    @State private var showAllSites = false
    @State private var showAllHistory = false

    private static let photosShown = 24

    private var customer: Customer? { model.data.customers.first { $0.id == customerID } }
    private var canEdit: Bool { model.data.can(.editClients) }
    private var showMoney: Bool { model.data.can(.viewRevenue) }
    private var tint: Color { Theme.accent(model.data.profile.accentColor) }

    private func pageURL(for site: Site) -> String? {
        let base = model.data.broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoutingServerSettings.validatedURL(base) != nil,
              let token = model.data.portalLinks.first(where: { $0.siteID == site.id })?.token else { return nil }
        // The owner's own website page (Settings, Put it on your website) when one is saved; the server page otherwise.
        if let own = EmbedSnippets.clientLink(websitePage: model.data.profile.websiteTrackingPage, token: token) { return own }
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/c/" + token
    }

    private func makeSnapshot() -> ClientSnapshot? {
        let now = Date()
        guard let overview = model.data.clientOverview(customerID: customerID, now: now) else { return nil }
        let sites = model.data.sites.filter { $0.customerID == customerID }
        var statements: [UUID: SeasonStatement] = [:]
        var links: [UUID: String] = [:]
        for site in sites {
            if let statement = SeasonStatement.build(data: model.data, siteID: site.id, now: now) { statements[site.id] = statement }
            if let link = pageURL(for: site) { links[site.id] = link }
        }
        return ClientSnapshot(overview: overview, sites: sites, statements: statements, pageLinks: links)
    }

    /// Directions to a property: to its map location when it has one, otherwise to its address.
    private func directionsURL(_ site: Site) -> URL? {
        if let lat = site.latitude, let lon = site.longitude {
            return NavigationLinks.appleMaps(to: Coordinate(latitude: lat, longitude: lon), from: model.data.depot)
        }
        let address = site.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: "d")]
        return parts?.url
    }

    var body: some View {
        let snap = snapshot ?? makeSnapshot()
        AppPage {
            if let c = customer, let snap {
                Group {
                    header(c, snap)
                    if showMoney { moneyCard(snap.overview) }
                    serviceCard(snap.overview)
                }
                Group {
                    propertyCards(snap)
                    photosCard(snap.overview)
                    notesCard(c)
                }
                Group {
                    historyCard(snap.overview)
                    contactCard(c)
                    if canEdit {
                        CardGroup(title: "Reviews") { ReviewAskButton(customerID: customerID) }
                        Button("Delete this client", role: .destructive) { confirmDelete = true }
                            .font(.callout).padding(.top, 4)
                    }
                }
            } else {
                EmptyCard(icon: "person.crop.circle.badge.xmark", title: "Client not found", message: "This client is no longer in your list.")
            }
        }
        .sheet(item: $sheet) { sheetView($0) }
        .confirmationDialog("Delete this client?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete client, sites and jobs", role: .destructive) {
                if let problem = model.edit({ try $0.deleteCustomer(customerID) }) {
                    note = problem
                } else {
                    dismiss()
                }
            }
        } message: {
            Text("Their sites, jobs and requests are removed. Clients with invoices cannot be deleted, because invoices are your records.")
        }
        .onAppear {
            load()
            snapshot = makeSnapshot()
        }
        .onChange(of: model.data) { snapshot = makeSnapshot() }
        .task(id: notes) {
            // Notes save on their own, a moment after the typing stops.
            guard loaded, canEdit else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            saveNotes()
        }
        .onDisappear { saveNotes() }
    }

    private func load() {
        guard !loaded, let c = customer else { return }
        name = c.name
        phone = c.phone
        email = c.email
        agreed = c.emailConsent && c.optedOutAt == nil
        notes = c.notes
        loaded = true
    }

    // MARK: header

    private func header(_ c: Customer, _ snap: ClientSnapshot) -> some View {
        let contactLine = [c.phone, c.email].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " \u{B7} ")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(name: c.name, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name.isEmpty ? "Client" : c.name).font(.largeTitle.bold()).lineLimit(2).minimumScaleFactor(0.6)
                    if !contactLine.isEmpty {
                        Text(contactLine).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                StatusPill(text: c.isLead ? "Lead" : "Client", color: c.isLead ? .teal : .blue)
                if c.optedOutAt != nil {
                    StatusPill(text: "Stopped messages", color: .orange)
                } else if c.emailConsent {
                    StatusPill(text: "Agreed to messages", color: .green)
                }
                if snap.overview.isOverdue { StatusPill(text: "Overdue", color: .red) }
                Spacer(minLength: 0)
            }
            quickActions(c, snap.sites)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func quickActions(_ c: Customer, _ sites: [Site]) -> some View {
        let digits = c.phone.filter { $0.isNumber || $0 == "+" }
        let callURL = digits.count >= 7 ? URL(string: "tel:\(digits)") : nil
        let textURL = digits.count >= 7 ? URL(string: "sms:\(digits)") : nil
        let mailURL = ContactValidation.isValidEmail(c.email) ? URL(string: "mailto:\(c.email)") : nil
        let mapURL = sites.first.flatMap { directionsURL($0) }
        if callURL != nil || textURL != nil || mailURL != nil || mapURL != nil {
            HStack(alignment: .top, spacing: 8) {
                if let callURL { roundAction("Call", "phone.fill", callURL) }
                if let textURL { roundAction("Text", "message.fill", textURL) }
                if let mailURL { roundAction("Email", "envelope.fill", mailURL) }
                if let mapURL { roundAction("Directions", "location.fill", mapURL) }
            }
        } else if canEdit {
            Text("Add a phone number, an email or an address to call, message or get directions.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func roundAction(_ title: String, _ icon: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 58, height: 58).background(tint.opacity(0.16), in: Circle())
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: money

    private static func statusLabel(_ invoice: Invoice, now: Date) -> (text: String, color: Color) {
        switch invoice.status(now: now) {
        case .draft: return ("Not sent", .gray)
        case .sent: return ("Sent", .blue)
        case .partiallyPaid: return ("Part paid", .blue)
        case .paid: return ("Paid", .green)
        case .overdue: return ("Overdue", .orange)
        case .void: return ("Void", .gray)
        }
    }

    private func figure(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func moneyCard(_ o: ClientOverview) -> some View {
        CardGroup(title: "Money") {
            HStack(alignment: .top, spacing: 12) {
                figure("Balance owed", o.balanceOwed.formatted, o.balanceOwed.cents > 0 ? Color.orange : Color.primary)
                figure("Paid this year", o.paidThisYear.formatted, Color.primary)
            }
            if o.isOverdue {
                Label("\(o.overdueAmount.formatted) is overdue (\(ProfileText.plural(o.overdueInvoiceCount, "invoice")))", systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
            }
            if o.draftInvoiceCount > 0 {
                Text("\(ProfileText.plural(o.draftInvoiceCount, "invoice")) not sent yet (\(o.draftTotal.formatted)). It counts as owed once you send it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            PrimaryActionButton(title: "Quick invoice", icon: "bolt.fill") { sheet = .quickInvoice }
            SecondaryActionButton(title: showInvoices ? "Hide invoices" : "See invoices (\(o.invoiceCount))", icon: "doc.text") {
                showInvoices.toggle()
            }
            if showInvoices { invoiceList(o) }
        }
    }

    @ViewBuilder private func invoiceList(_ o: ClientOverview) -> some View {
        if o.invoices.isEmpty {
            Text("No invoices yet. Tap Quick invoice to bill this client.").foregroundStyle(.secondary)
        } else {
            let shown = showAllInvoices ? o.invoices : Array(o.invoices.prefix(6))
            ForEach(shown) { invoice in
                RowDivider()
                Button { sheet = .invoice(invoice.number) } label: { invoiceRow(invoice) }
                    .buttonStyle(.plain)
            }
            if o.invoices.count > shown.count {
                SecondaryActionButton(title: "Show all \(o.invoices.count) invoices") { showAllInvoices = true }
            }
        }
    }

    private func invoiceRow(_ invoice: Invoice) -> some View {
        let status = Self.statusLabel(invoice, now: Date())
        let owes = !invoice.isVoid && invoice.balance.cents > 0 && invoice.paid.cents > 0
        let line = "\(ProfileText.day(invoice.issueDate)) \u{B7} \(invoice.total.formatted)" + (owes ? ", \(invoice.balance.formatted) left" : "")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(invoice.number).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    StatusPill(text: status.text, color: status.color)
                }
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: service

    private func lastServiceText(_ o: ClientOverview) -> String {
        guard let last = o.lastServiceDate else { return "None yet" }
        let ago = ProfileText.ago(last)
        return ProfileText.day(last) + (ago.isEmpty ? "" : " (\(ago))")
    }

    @ViewBuilder private func serviceCard(_ o: ClientOverview) -> some View {
        CardGroup(title: "Service") {
            FactRow(label: "Last service", value: lastServiceText(o))
            RowDivider()
            FactRow(label: "Next job", value: o.nextJob.map { ProfileText.dayAndTime($0.start) } ?? "Nothing scheduled")
            if !o.upcomingJobs.isEmpty {
                RowDivider()
                CapsLabel(text: "Open jobs")
                ForEach(o.upcomingJobs.prefix(5)) { job in
                    Button { sheet = .job(job.id, job.repeats ? job.start : nil) } label: { jobRow(job) }
                        .buttonStyle(.plain)
                }
                if o.upcomingJobs.count > 5 {
                    Text("And \(o.upcomingJobs.count - 5) more on the Jobs tab.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.data.can(.editJobs) {
                SecondaryActionButton(title: "Add a job", icon: "plus") { sheet = .newJob }
            }
        }
    }

    private func jobRow(_ job: Job) -> some View {
        let when = ProfileText.dayAndTime(job.start) + (job.repeats ? " \u{B7} repeats" : "")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Text(when).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusPill(text: job.status.title, color: job.status.color)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: properties

    @ViewBuilder private func propertyCards(_ snap: ClientSnapshot) -> some View {
        let sites = snap.sites
        let shown = showAllSites ? sites : Array(sites.prefix(3))
        if sites.isEmpty {
            CardGroup(title: "Properties") {
                Text("No address yet. Add one so jobs, routes and invoices know where to go.").foregroundStyle(.secondary)
                if canEdit {
                    SecondaryActionButton(title: "Add a property", icon: "plus") { sheet = .property(nil) }
                }
            }
        } else {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, site in
                let title: String? = index > 0 ? nil : (sites.count == 1 ? "Property" : "Properties (\(sites.count))")
                CardGroup(title: title) {
                    propertyPlace(site)
                    propertySeason(snap.statements[site.id])
                    propertyCrewNotes(site)
                    propertyActions(site, link: snap.pageLinks[site.id])
                }
            }
            if sites.count > shown.count {
                SecondaryActionButton(title: "Show all \(sites.count) properties", icon: "chevron.down") { showAllSites = true }
            }
            if canEdit {
                SecondaryActionButton(title: "Add another property", icon: "plus") { sheet = .property(nil) }
            }
        }
        if let propertyNote {
            Text(propertyNote).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The address, a small map and directions.
    @ViewBuilder private func propertyPlace(_ site: Site) -> some View {
        Label(site.address.isEmpty ? "No address" : site.address, systemImage: "mappin.circle.fill")
            .font(.title3.weight(.semibold)).textSelection(.enabled)
        #if canImport(MapKit)
        if let lat = site.latitude, let lon = site.longitude {
            SiteMapSnapshot(coordinate: Coordinate(latitude: lat, longitude: lon))
        }
        #endif
        if site.latitude == nil || site.longitude == nil {
            Text(canEdit ? "Not on the map yet, so it is left out of routes. Tap Change address to look it up again."
                         : "Not on the map yet, so it is left out of routes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let url = directionsURL(site) {
            SecondaryActionButton(title: "Directions", icon: "location.fill") { openURL(url) }
        }
    }

    /// The contract and this season's numbers for one property.
    @ViewBuilder private func propertySeason(_ statement: SeasonStatement?) -> some View {
        if let st = statement {
            RowDivider()
            if showMoney { Text(st.contractSummary).font(.footnote).foregroundStyle(.secondary) }
            FactRow(label: "Storms serviced", value: "\(st.stormsServiced)")
            if st.skippedVisits > 0 { FactRow(label: "Visits skipped", value: "\(st.skippedVisits)") }
            if let cap = st.capLine { Text(cap).font(.subheadline) }
            if showMoney {
                FactRow(label: "Billed", value: st.billed.formatted)
                FactRow(label: "Paid", value: st.paid.formatted)
                FactRow(label: "Still owed", value: st.outstanding.formatted, valueColor: st.outstanding.cents > 0 ? Color.orange : Color.secondary)
            }
        } else if showMoney {
            RowDivider()
            Text("No contract on this property yet.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Gate code and standing instructions, which the crew also sees on every job here.
    @ViewBuilder private func propertyCrewNotes(_ site: Site) -> some View {
        RowDivider()
        VStack(alignment: .leading, spacing: 6) {
            Label("Gate code and instructions", systemImage: "key.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if site.instructions.isEmpty {
                Text("None yet.").foregroundStyle(.secondary)
            } else {
                Text(site.instructions).textSelection(.enabled)
            }
        }
        if let area = site.lawnAreaSqFt {
            RowDivider()
            FactRow(label: "Measured area", value: PropertyMeasure.describe(squareFeet: area))
        }
    }

    @ViewBuilder private func propertyActions(_ site: Site, link: String?) -> some View {
        if canEdit {
            RowDivider()
            SecondaryActionButton(title: site.instructions.isEmpty ? "Add gate code or change address" : "Change address or instructions", icon: "pencil") {
                sheet = .property(site)
            }
            SecondaryActionButton(title: site.lawnAreaSqFt == nil ? "Measure this property" : "Measure again", icon: "map") {
                sheet = .measure(site)
            }
            if let link {
                ShareLink(item: link) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                        Text("Share page link").font(.title3.weight(.medium))
                    }
                    .foregroundStyle(.primary).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Look.pill, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Set the client page address in Settings to get a link.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: photos and notes

    @ViewBuilder private func photosCard(_ o: ClientOverview) -> some View {
        if !o.photos.isEmpty, model.photoStorage != nil {
            let shown = Array(o.photos.prefix(Self.photosShown))
            CardGroup(title: "Photos", footer: o.photos.count > shown.count ? "The latest \(shown.count) of \(o.photos.count) photos. Tap one to see it larger." : "Tap a photo to see it larger.") {
                ClientPhotoStrip(photos: shown) { index in sheet = .photo(index) }
            }
        }
    }

    private func cleanNotes(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }

    @ViewBuilder private func notesCard(_ c: Customer) -> some View {
        if canEdit {
            CardGroup(title: "Notes", footer: "Only you and your team see these notes.") {
                PillNotes(label: "About this client", placeholder: "Dog in the yard. Pays by check. Call before plowing.", text: $notes)
                if cleanNotes(notes) != cleanNotes(c.notes) {
                    Label("Saves when you stop typing", systemImage: "pencil").font(.footnote).foregroundStyle(.secondary)
                } else if !c.notes.isEmpty {
                    Label("Saved", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else if !c.notes.isEmpty {
            CardGroup(title: "Notes") { Text(c.notes) }
        }
    }

    private func saveNotes() {
        guard loaded, canEdit, let c = customer else { return }
        let typed = notes
        guard cleanNotes(typed) != cleanNotes(c.notes) else { return }
        if let problem = model.edit({ try $0.setCustomerNotes(customerID: customerID, notes: typed) }) { note = problem }
    }

    // MARK: history

    @ViewBuilder private func historyCard(_ o: ClientOverview) -> some View {
        CardGroup(title: "History") {
            if o.timeline.isEmpty {
                Text("Nothing yet. Jobs, visits, invoices and requests show up here.").foregroundStyle(.secondary)
            } else {
                let shown = showAllHistory ? o.timeline : Array(o.timeline.prefix(15))
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { RowDivider() }
                        historyRow(event)
                    }
                }
                if o.timeline.count > shown.count {
                    SecondaryActionButton(title: "Show all (\(o.timeline.count))", icon: "clock.arrow.circlepath") { showAllHistory = true }
                }
            }
        }
    }

    @ViewBuilder private func historyRow(_ event: ClientEvent) -> some View {
        if let number = event.invoiceNumber, showMoney {
            Button { sheet = .invoice(number) } label: { ClientHistoryRow(event: event, showsChevron: true) }
                .buttonStyle(.plain)
        } else {
            ClientHistoryRow(event: event)
        }
    }

    // MARK: contact and messages

    private func messagesText(_ c: Customer) -> String {
        if c.optedOutAt != nil { return "Asked to stop" }
        return c.emailConsent ? "Agreed to emails" : "Has not agreed"
    }

    @ViewBuilder private func contactCard(_ c: Customer) -> some View {
        CardGroup(title: "Contact and messages") {
            FactRow(label: "Phone", value: c.phone.isEmpty ? "None" : c.phone)
            RowDivider()
            FactRow(label: "Email", value: c.email.isEmpty ? "None" : c.email)
            RowDivider()
            FactRow(label: "Messages", value: messagesText(c), valueColor: c.optedOutAt != nil ? Color.orange : Color.primary)
            if canEdit {
                SecondaryActionButton(title: editingContact ? "Close without saving" : "Edit contact", icon: editingContact ? "chevron.up" : "pencil") {
                    if !editingContact {
                        // Open with what is saved now, not with what was typed and abandoned the last time.
                        name = c.name
                        phone = c.phone
                        email = c.email
                        agreed = c.emailConsent && c.optedOutAt == nil
                        note = nil
                    }
                    editingContact.toggle()
                }
                if editingContact { contactEditor(c) }
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func contactEditor(_ c: Customer) -> some View {
        RowDivider()
        PillField(label: "Name", placeholder: "Client name", text: $name)
        PillField(label: "Phone", optional: true, placeholder: "Phone number", text: $phone, kind: .phone)
        PillField(label: "Email", optional: true, placeholder: "name@email.com", text: $email, kind: .email)
        RowDivider()
        Toggle("Agreed to storm and invoice emails", isOn: $agreed)
            .disabled(!ContactValidation.isValidEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) || c.optedOutAt != nil)
        if c.optedOutAt != nil {
            Label("This client asked to stop messages.", systemImage: "hand.raised.fill").foregroundStyle(.orange)
        } else if c.emailConsent, let when = c.consentRecordedAt {
            Text("Agreed \(when.formatted(date: .abbreviated, time: .omitted)). \(c.consentSource)").font(.footnote).foregroundStyle(.secondary)
        }
        Text("Only turn this on if the client said yes. They can stop at any time.").font(.footnote).foregroundStyle(.secondary)
        PrimaryActionButton(title: "Save changes", icon: "checkmark") { save() }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        if c.optedOutAt == nil {
            Button("Client asked to stop messages", role: .destructive) {
                note = model.edit { try $0.optOut(customerID: customerID, now: Date()) } ?? "Marked as stopped. They will not get messages."
                agreed = false
            }
            .font(.footnote)
        }
    }

    private func save() {
        // A phone or email that cannot work is turned down here, not saved and then quietly never used.
        if let problem = ContactValidation.phoneProblem(phone) ?? ContactValidation.emailProblem(email) {
            note = problem
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChanged = trimmedEmail != (customer?.email ?? "")
        let wasConsenting = customer?.emailConsent ?? false
        let optedOut = customer?.optedOutAt != nil
        let wantsConsent = agreed && ContactValidation.isValidEmail(trimmedEmail) && !optedOut
        // Consent was given for a particular address, so a new address needs a fresh yes.
        let keepConsent = wantsConsent && !(emailChanged && wasConsenting)
        note = model.edit { data in
            guard let i = data.customers.firstIndex(where: { $0.id == customerID }) else { throw OperationError.notFound }
            data.customers[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            data.customers[i].phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            data.customers[i].email = trimmedEmail
            guard !optedOut else { return }                       // a client who asked to stop is never changed here
            if keepConsent != wasConsenting {
                try data.recordConsent(customerID: customerID, email: keepConsent, sms: false,
                                       source: keepConsent ? "Owner confirmed the client agreed" : ((emailChanged && wasConsenting) ? "The email address changed, so consent was cleared" : "Owner turned messages off"), now: Date())
            }
        } ?? ((emailChanged && wasConsenting && agreed) ? "Saved. The email changed, so confirm the client agreed to messages at the new address." : "Saved.")
        if emailChanged && wasConsenting { agreed = false }
        if note == "Saved." { editingContact = false }            // anything else needs another look, so the fields stay open
    }

    // MARK: sheets

    @ViewBuilder private func sheetView(_ which: ClientSheet) -> some View {
        switch which {
        case .quickInvoice:
            QuickInvoiceSheet(startCustomerID: customerID)
        case .invoice(let number):
            InvoiceDetailSheet(number: number)
        case .newJob:
            JobEditorSheet(startCustomerID: customerID)
        case .job(let id, let day):
            JobDetailSheet(jobID: id, occurrenceDate: day)
        case .measure(let site):
            MeasureSheet(title: "Measure this property", start: site.latitude.flatMap { lat in site.longitude.map { Coordinate(latitude: lat, longitude: $0) } },
                         address: site.address, useTitle: "Save this area") { m in
                propertyNote = model.edit { data in
                    guard let i = data.sites.firstIndex(where: { $0.id == site.id }) else { throw OperationError.notFound }
                    data.sites[i].lawnAreaSqFt = m.squareFeet.rounded()
                } ?? "Saved. This property is \(PropertyMeasure.describe(squareFeet: m.squareFeet))."
            }
        case .property(let site):
            PropertyEditorSheet(customerID: customerID, site: site) { message in propertyNote = message }
        case .photo(let index):
            ClientPhotoViewer(photos: Array((snapshot?.overview.photos ?? []).prefix(Self.photosShown)), index: index)
        }
    }
}
#endif
