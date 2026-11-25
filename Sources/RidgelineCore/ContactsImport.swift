import Foundation

/// One person picked from the phone's Contacts, as plain text, so the import rules can be tested without the Contacts framework.
public struct ContactCard: Equatable, Sendable {
    /// The person's full name, or the company name when the card has no person.
    public var name: String
    public var phones: [String]
    public var emails: [String]
    /// The first postal address on one line, or empty when the card has none.
    public var address: String

    public init(name: String, phones: [String] = [], emails: [String] = [], address: String = "") {
        self.name = name
        self.phones = phones
        self.emails = emails
        self.address = address
    }
}

/// What picking a set of contacts would add, worked out before anything is saved.
public struct ContactImportPlan: Equatable, Sendable {
    /// New clients to add. The address is empty for a contact that has none.
    public let clients: [ImportedClient]
    /// Contacts left out because that client is already in the list (or was picked twice).
    public let alreadyHere: Int
    /// Contacts left out because the card has no name.
    public let withoutName: Int

    public var withoutAddress: Int { clients.filter { $0.address.isEmpty }.count }
}

/// Turns picked contacts into clients, with the same clean-up and duplicate rules as the spreadsheet import.
/// Nobody is ever imported as having agreed to messages.
public enum ContactImport {
    public static let maxContacts = ClientImport.maxRows

    /// A postal address on one line: "14 Elm Ave, Apt 2, Minneapolis, MN 55401". Empty parts are left out.
    public static func oneLineAddress(street: String, city: String, state: String, postalCode: String) -> String {
        func tidy(_ s: String) -> String {
            s.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let region = [tidy(state), tidy(postalCode)].filter { !$0.isEmpty }.joined(separator: " ")
        return [tidy(street), tidy(city), region].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The client a card becomes: its name, first phone, first email that can work, and its address. Nil when there is no name.
    public static func row(from card: ContactCard) -> ImportedClient? {
        let name = ClientImport.clean(card.name, 120)
        guard !name.isEmpty else { return nil }
        let phone = card.phones.map { ClientImport.clean($0, 30) }.first { !$0.isEmpty } ?? ""
        let email = card.emails.map { ClientImport.clean($0, 254) }.first { ContactValidation.isValidEmail($0) } ?? ""
        let address = ClientImport.clean(oneLineAddress(street: card.address, city: "", state: "", postalCode: ""), 200)
        return ImportedClient(name: name, address: address, phone: phone, email: email)
    }

    /// Leaves out cards with no name and clients who are already here: the same name at the same address (the spreadsheet rule),
    /// or the same name when either side has no address to compare.
    public static func plan(_ cards: [ContactCard], existing: AppData) -> ContactImportPlan {
        let names = Dictionary(existing.customers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var seen = Set(existing.sites.compactMap { site -> String? in
            names[site.customerID].map { ClientImport.key($0, site.address) }
        })
        let withSite = Set(existing.sites.map(\.customerID))
        var anyName = Set(existing.customers.map { ClientImport.key($0.name, "") })
        var nameWithoutAddress = Set(existing.customers.filter { !withSite.contains($0.id) }.map { ClientImport.key($0.name, "") })

        var out: [ImportedClient] = []
        var alreadyHere = 0, withoutName = 0
        for card in cards.prefix(maxContacts) {
            guard let client = row(from: card) else { withoutName += 1; continue }
            let nameKey = ClientImport.key(client.name, "")
            let duplicate = client.address.isEmpty
                ? anyName.contains(nameKey)
                : nameWithoutAddress.contains(nameKey) || seen.contains(ClientImport.key(client.name, client.address))
            if duplicate { alreadyHere += 1; continue }
            anyName.insert(nameKey)
            if client.address.isEmpty { nameWithoutAddress.insert(nameKey) } else { seen.insert(ClientImport.key(client.name, client.address)) }
            out.append(client)
        }
        return ContactImportPlan(clients: out, alreadyHere: alreadyHere, withoutName: withoutName)
    }

    /// "Added 12 clients, skipped 2 already here"
    public static func resultLine(added: Int, alreadyHere: Int, withoutName: Int = 0) -> String {
        let addedText = added == 0 ? "No clients added" : "Added \(added) client\(added == 1 ? "" : "s")"
        var skips: [String] = []
        if alreadyHere > 0 { skips.append("\(alreadyHere) already here") }
        if withoutName > 0 { skips.append("\(withoutName) with no name") }
        return skips.isEmpty ? addedText : addedText + ", skipped " + skips.joined(separator: " and ")
    }
}

extension AppData {
    /// Adds one picked contact as a client with no price yet: no contract, so nothing is billed until one is added.
    /// With an address they also get a site, and its map location when one was found. Never marked as having agreed to messages.
    @discardableResult
    public mutating func addContactClient(_ client: ImportedClient, coordinate: Coordinate? = nil, now: Date) -> UUID {
        let customer = Customer(name: client.name, phone: client.phone, email: client.email)
        customers.append(customer)
        if !client.address.isEmpty {
            sites.append(Site(customerID: customer.id, address: client.address, latitude: coordinate?.latitude,
                              longitude: coordinate?.longitude, priority: 3, triggerInches: profile.defaultTriggerInches))
            ensurePortalLinks(now: now)
        }
        return customer.id
    }
}
