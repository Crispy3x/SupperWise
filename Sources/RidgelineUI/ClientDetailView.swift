#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// One client: contact details, whether they agreed to messages, and their private page.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var model
    let customerID: UUID

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var loaded = false
    @State private var note: String?

    private var customer: Customer? { model.data.customers.first { $0.id == customerID } }
    private var sites: [Site] { model.data.sites.filter { $0.customerID == customerID } }

    private func pageURL(for site: Site) -> String? {
        let base = model.data.broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoutingServerSettings.validatedURL(base) != nil,
              let token = model.data.portalLinks.first(where: { $0.siteID == site.id })?.token else { return nil }
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/c/" + token
    }

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $name)
                TextField("Phone", text: $phone)
                TextField("Email", text: $email)
            }
            Section {
                Toggle("Agreed to storm and invoice emails", isOn: $agreed)
                    .disabled(!ContactValidation.isValidEmail(email) || customer?.optedOutAt != nil)
                if let c = customer {
                    if c.optedOutAt != nil {
                        Label("This client asked to stop messages.", systemImage: "hand.raised.fill").foregroundStyle(.orange)
                    } else if c.emailConsent, let when = c.consentRecordedAt {
                        Text("Agreed \(when.formatted(date: .abbreviated, time: .omitted)). \(c.consentSource)").font(.footnote).foregroundStyle(.secondary)
                    }
                    if c.optedOutAt == nil {
                        Button("Client asked to stop messages", role: .destructive) {
                            note = model.edit { try $0.optOut(customerID: customerID, now: Date()) } ?? "Marked as stopped. They will not get messages."
                            agreed = false
                        }
                    }
                }
            } header: {
                Text("Messages")
            } footer: {
                Text("Only turn this on if the client said yes. They can stop at any time.")
            }
            Section("Sites and client pages") {
                ForEach(sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.address)
                        if let url = pageURL(for: site) {
                            ShareLink(item: url) { Label("Share this client's page link", systemImage: "link") }.font(.footnote)
                        } else {
                            Text("Set the client page address in Settings to get a link.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(name.isEmpty ? "Client" : name)
        .onAppear {
            guard !loaded, let c = customer else { return }
            name = c.name; phone = c.phone; email = c.email; agreed = c.emailConsent && c.optedOutAt == nil; loaded = true
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
                                       source: keepConsent ? "Owner confirmed the client agreed" : "Owner turned messages off", now: Date())
            }
        } ?? ((emailChanged && wasConsenting && agreed) ? "Saved. The email changed, so confirm the client agreed to messages at the new address." : "Saved.")
        if emailChanged && wasConsenting { agreed = false }
    }
}
#endif
