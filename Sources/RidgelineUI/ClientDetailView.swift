#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// One client: contact details, whether they agreed to messages, and their private page.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    let customerID: UUID

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var loaded = false
    @State private var note: String?
    @State private var measuringSite: Site?

    private var customer: Customer? { model.data.customers.first { $0.id == customerID } }
    private var sites: [Site] { model.data.sites.filter { $0.customerID == customerID } }

    private func pageURL(for site: Site) -> String? {
        let base = model.data.broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoutingServerSettings.validatedURL(base) != nil,
              let token = model.data.portalLinks.first(where: { $0.siteID == site.id })?.token else { return nil }
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/c/" + token
    }

    private var upcomingJobs: [Job] {
        let siteIDs = Set(sites.map(\.id))
        return model.data.visibleJobs.filter { !$0.isTask && $0.status.isOpen && ($0.customerID == customerID || ($0.siteID.map(siteIDs.contains) ?? false)) }
            .sorted { $0.start < $1.start }
    }

    private func quickAction(_ title: String, _ icon: String, _ url: URL?) -> some View {
        Group {
            if let url {
                Link(destination: url) {
                    VStack(spacing: 6) {
                        Image(systemName: icon).font(.title3)
                        Text(title).font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Look.pill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                actions
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "Contact")
                        PillField(label: "Name", placeholder: "Client name", text: $name)
                        PillField(label: "Phone", optional: true, placeholder: "Phone number", text: $phone, kind: .phone)
                        PillField(label: "Email", optional: true, placeholder: "name@email.com", text: $email, kind: .email)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Messages")
                        Toggle("Agreed to storm and invoice emails", isOn: $agreed)
                            .disabled(!ContactValidation.isValidEmail(email) || customer?.optedOutAt != nil)
                        if let c = customer {
                            if c.optedOutAt != nil {
                                Label("This client asked to stop messages.", systemImage: "hand.raised.fill").foregroundStyle(.orange)
                            } else if c.emailConsent, let when = c.consentRecordedAt {
                                Text("Agreed \(when.formatted(date: .abbreviated, time: .omitted)). \(c.consentSource)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Text("Only turn this on if the client said yes. They can stop at any time.").font(.footnote).foregroundStyle(.secondary)
                        if let c = customer, c.optedOutAt == nil {
                            Button("Client asked to stop messages", role: .destructive) {
                                note = model.edit { try $0.optOut(customerID: customerID, now: Date()) } ?? "Marked as stopped. They will not get messages."
                                agreed = false
                            }
                            .font(.footnote)
                        }
                    }
                }
                if !upcomingJobs.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Upcoming jobs")
                            ForEach(upcomingJobs.prefix(5)) { job in
                                HStack {
                                    Text(job.title).font(.headline)
                                    Spacer()
                                    Text(job.start.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(sites) { site in siteCard(site) }
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                PrimaryBar(title: "Save changes") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Delete this client", role: .destructive) { confirmDelete = true }
                    .font(.callout).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, Look.tabBarClearance)
        }
        .background(Look.page.ignoresSafeArea())
        .sheet(item: $measuringSite) { site in
            MeasureSheet(title: "Measure this property", start: site.latitude.flatMap { lat in site.longitude.map { Coordinate(latitude: lat, longitude: $0) } },
                         address: site.address, useTitle: "Save this area") { m in
                note = model.edit { data in
                    guard let i = data.sites.firstIndex(where: { $0.id == site.id }) else { throw OperationError.notFound }
                    data.sites[i].lawnAreaSqFt = m.squareFeet.rounded()
                } ?? "Saved. This property is \(PropertyMeasure.describe(squareFeet: m.squareFeet))."
            }
        }
        .confirmationDialog("Delete this client?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete client, sites and jobs", role: .destructive) {
                if let problem = model.edit({ try $0.deleteCustomer(customerID) }) { note = problem } else { dismiss() }
            }
        } message: {
            Text("Their sites, jobs and requests are removed. Clients with invoices cannot be deleted, because invoices are your records.")
        }
        .onAppear {
            guard !loaded, let c = customer else { return }
            name = c.name; phone = c.phone; email = c.email; agreed = c.emailConsent && c.optedOutAt == nil; loaded = true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(icon: "person.fill", size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Client" : name).font(.title.bold()).lineLimit(2)
                if let c = customer {
                    if c.optedOutAt != nil { StatusPill(text: "Stopped messages", color: .orange) }
                    else if c.emailConsent { StatusPill(text: "Agreed to messages", color: .green) }
                }
            }
            Spacer()
        }
    }

    private var actions: some View {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let mailOK = ContactValidation.isValidEmail(email)
        let site = sites.first
        return HStack(spacing: 10) {
            quickAction("Call", "phone.fill", digits.count >= 7 ? URL(string: "tel:\(digits)") : nil)
            quickAction("Text", "message.fill", digits.count >= 7 ? URL(string: "sms:\(digits)") : nil)
            quickAction("Email", "envelope.fill", mailOK ? URL(string: "mailto:\(email)") : nil)
            quickAction("Directions", "location.fill", site.flatMap { s in
                s.latitude.flatMap { lat in s.longitude.flatMap { lon in NavigationLinks.appleMaps(to: Coordinate(latitude: lat, longitude: lon), from: model.data.depot) } }
            })
        }
    }

    private func siteCard(_ site: Site) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: site.address.isEmpty ? "Site" : site.address)
                if let st = SeasonStatement.build(data: model.data, siteID: site.id, now: Date()) {
                    Text(st.contractSummary).font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Storms serviced") { Text("\(st.stormsServiced)") }
                    if st.skippedVisits > 0 { LabeledContent("Visits skipped") { Text("\(st.skippedVisits)") } }
                    if let cap = st.capLine { Text(cap).font(.subheadline) }
                    LabeledContent("Billed") { Text(st.billed.formatted) }
                    LabeledContent("Paid") { Text(st.paid.formatted) }
                    LabeledContent("Still owed") { Text(st.outstanding.formatted).foregroundStyle(st.outstanding.cents > 0 ? .orange : .secondary) }
                }
                if let area = site.lawnAreaSqFt { FactRow(label: "Measured area", value: PropertyMeasure.describe(squareFeet: area)) }
                SecondaryActionButton(title: site.lawnAreaSqFt == nil ? "Measure this property" : "Measure again", icon: "map") { measuringSite = site }
                Divider()
                if let url = pageURL(for: site) {
                    ShareLink(item: url) { Label("Share this client's page link", systemImage: "link") }.font(.subheadline.weight(.semibold))
                } else {
                    Text("Set the client page address in Settings to get a link.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
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
            data.customers[i].phone = phone
            data.customers[i].email = trimmedEmail
            guard !optedOut else { return }                       // a client who asked to stop is never changed here
            if keepConsent != wasConsenting {
                try data.recordConsent(customerID: customerID, email: keepConsent, sms: false,
                                       source: keepConsent ? "Owner confirmed the client agreed" : ((emailChanged && wasConsenting) ? "The email address changed, so consent was cleared" : "Owner turned messages off"), now: Date())
            }
        } ?? ((emailChanged && wasConsenting && agreed) ? "Saved. The email changed, so confirm the client agreed to messages at the new address." : "Saved.")
        if emailChanged && wasConsenting { agreed = false }
    }
}
#endif
