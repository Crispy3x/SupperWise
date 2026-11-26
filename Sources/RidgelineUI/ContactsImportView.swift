#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if os(iOS) && canImport(ContactsUI)
import Contacts
import ContactsUI
#endif

/// The small "Import from Contacts" link on the Clients tab. It opens the import sheet. On a Mac it shows nothing.
struct ContactsImportButton: View {
    @State private var showing = false

    var body: some View {
        #if os(iOS) && canImport(ContactsUI)
        Button { showing = true } label: {
            Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus").font(.callout)
        }
        .padding(.top, 6)
        .sheet(isPresented: $showing) { ContactsImportView() }
        #else
        EmptyView()
        #endif
    }
}

/// Bring clients in from the phone's Contacts: pick people, check the count, add them.
/// The system picker runs outside the app, so no Contacts permission is asked and the app only sees the people picked.
/// Nobody imported is marked as having agreed to messages.
struct ContactsImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var plan: ContactImportPlan?
    /// Price per push for everyone added, in dollars. Zero means no price yet.
    @State private var rate = 0.0
    @State private var working = false
    @State private var stopRequested = false
    @State private var progress = 0
    @State private var notOnMap = 0
    @State private var result: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import from Contacts").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
                    .disabled(working).opacity(working ? 0.35 : 1)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                #if os(iOS) && canImport(ContactsUI)
                if !model.data.can(.editClients) {
                    EmptyCard(icon: "lock.fill", title: "Not available", message: "Ask the owner to let you add clients.")
                } else if let result {
                    doneCards(result)
                } else if let plan {
                    reviewCards(plan)
                } else {
                    introCards
                }
                #else
                EmptyCard(icon: "iphone", title: "Use your iPhone or iPad",
                          message: "Importing from Contacts works on iPhone and iPad. On a Mac, import a spreadsheet instead.")
                #endif
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .interactiveDismissDisabled(working)
        #if os(iOS) && canImport(ContactsUI)
        .sheet(isPresented: $picking) {
            ContactPicker(onPicked: { cards in
                picking = false
                plan = ContactImport.plan(cards, existing: model.data)
            }, onCancel: { picking = false })
            .ignoresSafeArea()
        }
        #endif
    }

    // MARK: steps

    @ViewBuilder private var introCards: some View {
        CardGroup {
            Text("Pick the people you work for.").font(.headline)
            Text("The app brings in each name, phone, email and address. It only sees the contacts you pick.")
                .font(.callout).foregroundStyle(.secondary)
        }
        PrimaryActionButton(title: "Choose contacts", icon: "person.crop.circle.badge.plus") { picking = true }
        consentNote
    }

    @ViewBuilder private func reviewCards(_ plan: ContactImportPlan) -> some View {
        let count = plan.clients.count
        CardGroup {
            Text("\(count) client\(count == 1 ? "" : "s") will be added.").font(.headline)
            if plan.alreadyHere > 0 { Text("\(plan.alreadyHere) already here, skipped.").foregroundStyle(.orange) }
            if plan.withoutName > 0 { Text("\(plan.withoutName) with no name, skipped.").foregroundStyle(.orange) }
            if plan.withoutAddress > 0 {
                Text("\(plan.withoutAddress) with no address in Contacts. They are added without a service address.").foregroundStyle(.secondary)
            }
        }
        if count > 0 {
            CardGroup(title: "Price") {
                PillStepper(label: "Price per push", value: $rate, range: 0...1000, step: 5, format: { $0 == 0 ? "None yet" : "$\(Int($0))" })
                Text("With a price, each client with an address also gets a per-push contract. With none you can add a quote later.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            CardGroup(title: "First few") {
                ForEach(Array(plan.clients.prefix(5).enumerated()), id: \.offset) { index, client in
                    if index > 0 { RowDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                        Text(client.address.isEmpty ? "No address" : client.address).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        consentNote
        if working {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding addresses on the map: \(progress) of \(count)").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // A long list takes minutes and the sheet cannot be closed meanwhile, so there has to be a way to stop.
            SecondaryActionButton(title: stopRequested ? "Stopping..." : "Stop here and keep the ones added", icon: "stop.fill") { stopRequested = true }
                .disabled(stopRequested).opacity(stopRequested ? 0.4 : 1)
        }
        PrimaryActionButton(title: working ? "Adding..." : "Add \(count) client\(count == 1 ? "" : "s")", icon: "checkmark") { runImport(plan) }
            .disabled(working || count == 0).opacity(working || count == 0 ? 0.4 : 1)
        SecondaryActionButton(title: "Choose again", icon: "arrow.uturn.backward") { picking = true }
            .disabled(working).opacity(working ? 0.4 : 1)
    }

    @ViewBuilder private func doneCards(_ line: String) -> some View {
        CardGroup {
            Label(line, systemImage: "checkmark.circle.fill").font(.headline)
            if notOnMap > 0 {
                RowDivider()
                Text("\(notOnMap) address\(notOnMap == 1 ? " was" : "es were") not found on the map. Open the client to fix the address, or it is left out of route ordering.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        consentNote
        PrimaryActionButton(title: "Done", icon: "checkmark") { dismiss() }
    }

    private var consentNote: some View {
        CardGroup {
            Text("Nobody is marked as having agreed to messages. Open each client to record that, only if they said yes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: adding

    /// Adds the clients one by one. Each address is looked up first so the site lands on the map.
    private func runImport(_ plan: ContactImportPlan) {
        guard !working else { return }
        working = true
        stopRequested = false
        progress = 0
        notOnMap = 0
        let price = Money(dollars: Int(rate))
        Task {
            var added = 0
            for client in plan.clients {
                if stopRequested { break }
                var coordinate: Coordinate?
                #if canImport(CoreLocation)
                if !client.address.isEmpty {
                    coordinate = await AddressGeocoder.coordinate(for: client.address)
                    if coordinate == nil { notOnMap += 1 }
                }
                #endif
                if price.cents > 0 && !client.address.isEmpty {
                    // The same call the Add New Client sheet makes. Consent is never set here.
                    _ = model.addCustomerWithSite(name: client.name, phone: client.phone, email: client.email, emailConsent: false,
                                                  address: client.address, priority: 3, triggerInches: model.data.profile.defaultTriggerInches,
                                                  perPushRate: price, seasonPrice: nil, coordinate: coordinate)
                } else {
                    // No price yet (or no address to price): the client is saved without a contract, like a spreadsheet import.
                    model.edit { _ = $0.addContactClient(client, coordinate: coordinate, now: Date()) }
                }
                added += 1
                progress = added
            }
            working = false
            result = ContactImport.resultLine(added: added, alreadyHere: plan.alreadyHere, withoutName: plan.withoutName)
        }
    }
}

#if os(iOS) && canImport(ContactsUI)
/// The plain details of one picked contact: full name (or the company when there is no person), phones, emails and the first address.
private func contactCard(from contact: CNContact) -> ContactCard {
    func has(_ key: String) -> Bool { contact.isKeyAvailable(key) }
    var nameParts: [String] = []
    if has(CNContactGivenNameKey) { nameParts.append(contact.givenName) }
    if has(CNContactFamilyNameKey) { nameParts.append(contact.familyName) }
    var name = nameParts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    if name.isEmpty && has(CNContactOrganizationNameKey) { name = contact.organizationName }
    let phones: [String] = has(CNContactPhoneNumbersKey) ? contact.phoneNumbers.map { $0.value.stringValue } : []
    let emails: [String] = has(CNContactEmailAddressesKey) ? contact.emailAddresses.map { $0.value as String } : []
    var address = ""
    if has(CNContactPostalAddressesKey), let first = contact.postalAddresses.first?.value {
        address = ContactImport.oneLineAddress(street: first.street, city: first.city, state: first.state, postalCode: first.postalCode)
    }
    return ContactCard(name: name, phones: phones, emails: emails, address: address)
}

/// The system contact picker with multi-select. It is shown by the system outside the app's own process,
/// so the app needs no Contacts permission.
private struct ContactPicker: UIViewControllerRepresentable {
    let onPicked: ([ContactCard]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        init(_ parent: ContactPicker) { self.parent = parent }

        // Answering the many-contacts callback (and not the one-contact one) is what turns on multi-select with a Done button.
        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let cards = contacts.map { contactCard(from: $0) }
            Task { @MainActor in self.parent.onPicked(cards) }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            Task { @MainActor in self.parent.onCancel() }
        }
    }
}
#endif
#endif
