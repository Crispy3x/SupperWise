import Foundation

public enum OperationError: Error, Equatable {
    case notFound
    case alreadyClockedIn
    case notClockedIn
    case emptyName
    case hasInvoices
}

/// Everyday actions on the saved data. They live here, not in the screens, so they can be tested.
extension AppData {
    /// Addresses match ignoring case, extra spaces and line breaks.
    static func normalizedAddress(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: quotes

    /// Accepts a quote and creates the site (if this customer has none at that address) and the contract.
    /// Accepting twice does nothing the second time.
    @discardableResult
    public mutating func acceptQuote(id: UUID, now: Date) throws -> SnowContract {
        guard let i = quotes.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        var quote = quotes[i]
        if quote.status(now: now) == .accepted,
           let existing = contracts.first(where: { c in sites.first { $0.id == c.siteID }.map { $0.customerID == quote.customerID && Self.normalizedAddress($0.address) == Self.normalizedAddress(quote.address) && c.season == quote.season } ?? false }) {
            return existing
        }
        try quote.accept(at: now)
        let siteID: UUID
        if let site = sites.first(where: { $0.customerID == quote.customerID && Self.normalizedAddress($0.address) == Self.normalizedAddress(quote.address) }) {
            siteID = site.id
        } else {
            let site = Site(customerID: quote.customerID, address: quote.address)
            sites.append(site)
            siteID = site.id
            ensurePortalLinks(now: now)
        }
        let contract = try quote.makeContract(siteID: siteID)
        contracts.append(contract)
        quotes[i] = quote
        return contract
    }

    // MARK: time clock

    public mutating func clockIn(member: String, siteID: UUID? = nil, now: Date) throws {
        let name = member.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw OperationError.emptyName }
        guard !timeEntries.contains(where: { $0.memberName == name && $0.end == nil }) else { throw OperationError.alreadyClockedIn }
        timeEntries.append(TimeEntry(memberName: name, start: now, siteID: siteID))
    }

    public mutating func clockOut(member: String, now: Date) throws {
        let name = member.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = timeEntries.firstIndex(where: { $0.memberName == name && $0.end == nil }) else { throw OperationError.notClockedIn }
        timeEntries[i].end = max(now, timeEntries[i].start)
    }

    // MARK: routes

    public mutating func addRoute(name: String, crewID: UUID? = nil, weekday: Int? = nil) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OperationError.emptyName }
        routes.append(Route(name: clean, crewID: crewID, weekday: weekday))
    }

    public mutating func addCrew(name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OperationError.emptyName }
        crews.append(Crew(name: clean))
    }

    // MARK: costs

    /// Hours of crew time not tied to any site, so reports can say what they leave out.
    public func unassignedHours(now: Date) -> Double {
        timeEntries.filter { $0.siteID == nil }.reduce(0) { $0 + $1.hours(now: now) }
    }

    /// Margin for one site from sent invoices (drafts are not revenue yet), time entries on that site and salt
    /// logged in visits. Subcontractor pay is not included.
    public func jobCost(for site: Site, now: Date) -> JobCost {
        let entries = timeEntries.filter { $0.siteID == site.id }
        let salt = visitLog.records(forSite: site.id).reduce(0) { $0 + $1.saltPounds }
        return JobCosting.site(revenue: JobCosting.invoicedRevenue(siteID: site.id, invoices: invoices.filter { $0.sentAt != nil }),
                               timeEntries: entries, laborCostPerHour: laborCostPerHour, now: now,
                               saltPounds: salt, saltCostPerPound: saltCostPerPound)
    }
}

extension AppData {
    /// Removes a client with their sites, contracts, page links, jobs and requests. A client with invoices stays,
    /// because invoices are your financial records.
    public mutating func deleteCustomer(_ id: UUID) throws {
        guard customers.contains(where: { $0.id == id }) else { throw OperationError.notFound }
        let siteIDs = Set(sites.filter { $0.customerID == id }.map(\.id))
        if invoices.contains(where: { $0.customerID == id || siteIDs.contains($0.siteID) }) { throw OperationError.hasInvoices }
        customers.removeAll { $0.id == id }
        sites.removeAll { siteIDs.contains($0.id) }
        contracts.removeAll { siteIDs.contains($0.siteID) }
        portalLinks.removeAll { siteIDs.contains($0.siteID) }
        serviceRequests.removeAll { siteIDs.contains($0.siteID) }
        jobs.removeAll { $0.customerID == id || ($0.siteID.map(siteIDs.contains) ?? false) }
        quotes.removeAll { $0.customerID == id }
    }
}

// MARK: sample clients

extension AppData {
    /// The made-up clients that "Load sample clients" adds, by name and address. They all share the phone number below.
    public static let sampleClients: [(name: String, address: String)] = [
        ("Lakeside Clinic", "100 Lake St"), ("Oak Ridge HOA", "22 Oak Ridge Rd"), ("Pat Miller", "14 Elm Ave"),
        ("Sam's Auto", "410 Industrial Pkwy"), ("Dana Reyes", "7 Birch Ct"), ("Maple Plaza", "900 Maple Blvd"),
    ]
    public static let samplePhone = "555-0100"
    /// The yard location and business name the sample set fills in when there is none yet.
    public static let sampleYard = Coordinate(latitude: 44.9778, longitude: -93.2650)
    public static let sampleCompanyName = "Demo Plowing"

    /// Sample clients still in the list: the same name, phone number and address the sample set uses.
    public var sampleCustomerIDs: [UUID] {
        customers.filter { c in
            c.phone == Self.samplePhone && Self.sampleClients.contains { sample in
                sample.name == c.name && sites.contains { $0.customerID == c.id && $0.address == sample.address }
            }
        }
        .map(\.id)
    }

    /// Takes the sample clients out again (with their sites, contracts, jobs and page links), so they never mix with a real
    /// business. A sample client that was invoiced stays, because invoices are records, and is counted in `kept`.
    /// The sample yard location and business name go too, unless they were changed.
    @discardableResult
    public mutating func removeSampleClients() -> (removed: Int, kept: Int) {
        var removed = 0, kept = 0
        for id in sampleCustomerIDs {
            do { try deleteCustomer(id); removed += 1 } catch { kept += 1 }
        }
        if depot == Self.sampleYard { depot = nil }
        if companyName == Self.sampleCompanyName { companyName = "" }
        return (removed, kept)
    }
}
