import Foundation

public struct ImportedClient: Equatable, Sendable {
    public let name: String
    public let address: String
    public let phone: String
    public let email: String
}

public struct ImportSkip: Equatable, Sendable {
    public let row: Int
    public let reason: String
}

public struct ImportReport: Equatable, Sendable {
    public let clients: [ImportedClient]
    public let skipped: [ImportSkip]
    /// Set when the file cannot be used at all.
    public let problem: String?
}

/// Brings clients in from a spreadsheet saved as CSV. Nobody is ever imported as having agreed to messages:
/// consent has to be recorded for each client afterwards.
public enum ClientImport {
    public static let maxRows = 2000

    /// A small CSV reader: quoted fields, commas and line breaks inside quotes, doubled quotes, a leading byte-order mark.
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }; row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == "," {
                endField()
            } else if c == "\n" || c == "\r\n" {          // "\r\n" is one Character in Swift
                endRow()
            } else if c == "\r" {
                endRow()
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func column(_ header: [String], _ names: [String]) -> Int? {
        header.firstIndex { h in names.contains(h.trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    static func clean(_ s: String, _ max: Int) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(max).description
    }

    public static func clients(from text: String, existing: AppData) -> ImportReport {
        let rows = parseCSV(text)
        guard let header = rows.first else { return ImportReport(clients: [], skipped: [], problem: "The file is empty.") }
        guard let nameCol = column(header, ["name", "client", "customer", "full name", "client name", "customer name"]),
              let addressCol = column(header, ["address", "service address", "street", "street address", "site", "property"]) else {
            return ImportReport(clients: [], skipped: [], problem: "The first row needs columns named Name and Address.")
        }
        let phoneCol = column(header, ["phone", "mobile", "cell", "telephone", "phone number"])
        let emailCol = column(header, ["email", "e-mail", "email address"])
        guard rows.count - 1 <= maxRows else {
            return ImportReport(clients: [], skipped: [], problem: "The file has more than \(maxRows) rows. Split it and import in parts.")
        }

        var seen = Set(existing.sites.compactMap { site -> String? in
            guard let c = existing.customers.first(where: { $0.id == site.customerID }) else { return nil }
            return key(c.name, site.address)
        })
        var out: [ImportedClient] = []
        var skipped: [ImportSkip] = []
        for (offset, r) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            func cell(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let name = clean(cell(nameCol), 120), address = clean(cell(addressCol), 200)
            if name.isEmpty || address.isEmpty { skipped.append(ImportSkip(row: rowNumber, reason: "Missing a name or an address")); continue }
            if !seen.insert(key(name, address)).inserted { skipped.append(ImportSkip(row: rowNumber, reason: "Already in your list")); continue }
            var email = clean(cell(emailCol), 254)
            if !email.isEmpty && !ContactValidation.isValidEmail(email) { email = "" }       // keep the client, drop an address that cannot work
            out.append(ImportedClient(name: name, address: address, phone: clean(cell(phoneCol), 30), email: email))
        }
        return ImportReport(clients: out, skipped: skipped, problem: nil)
    }

    static func key(_ name: String, _ address: String) -> String {
        func norm(_ s: String) -> String { s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        return norm(name) + "|" + norm(address)
    }
}

extension AppData {
    /// Adds the imported clients with the profile's default trigger depth. With a price they also get a per-push contract.
    /// Nobody is marked as having agreed to messages.
    @discardableResult
    public mutating func importClients(_ clients: [ImportedClient], perPush: Money?, now: Date) -> Int {
        let season = {
            let cal = Calendar.current
            let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
            let start = m >= 7 ? y : y - 1
            return "\(start)-\(String(format: "%02d", (start + 1) % 100))"
        }()
        for c in clients {
            let customer = Customer(name: c.name, phone: c.phone, email: c.email)
            let site = Site(customerID: customer.id, address: c.address, priority: 3, triggerInches: profile.defaultTriggerInches)
            customers.append(customer)
            sites.append(site)
            if let rate = perPush, rate.cents > 0 {
                contracts.append(SnowContract(siteID: site.id, season: season, terms: .perPush(rate: rate)))
            }
        }
        ensurePortalLinks(now: now)
        return clients.count
    }
}
