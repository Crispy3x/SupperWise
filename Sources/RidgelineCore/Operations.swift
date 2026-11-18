import Foundation

public enum OperationError: Error, Equatable {
    case notFound
    case alreadyClockedIn
    case notClockedIn
    case emptyName
}

/// Everyday actions on the saved data. They live here, not in the screens, so they can be tested.
extension AppData {
    // MARK: quotes

    /// Accepts a quote and creates the site (if this customer has none at that address) and the contract.
    /// Accepting twice does nothing the second time.
    @discardableResult
    public mutating func acceptQuote(id: UUID, now: Date) throws -> SnowContract {
        guard let i = quotes.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        var quote = quotes[i]
        if quote.status(now: now) == .accepted,
           let existing = contracts.first(where: { c in sites.first { $0.id == c.siteID }.map { $0.customerID == quote.customerID && $0.address == quote.address && c.season == quote.season } ?? false }) {
            return existing
        }
        try quote.accept(at: now)
        let siteID: UUID
        if let site = sites.first(where: { $0.customerID == quote.customerID && $0.address == quote.address }) {
            siteID = site.id
        } else {
            let site = Site(customerID: quote.customerID, address: quote.address)
            sites.append(site)
            siteID = site.id
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

    /// Margin for one site from invoices, time entries on that site and salt logged in visits.
    public func jobCost(for site: Site, now: Date) -> JobCost {
        let entries = timeEntries.filter { $0.siteID == site.id }
        let salt = visitLog.records(forSite: site.id).reduce(0) { $0 + $1.saltPounds }
        return JobCosting.site(revenue: JobCosting.invoicedRevenue(siteID: site.id, invoices: invoices),
                               timeEntries: entries, laborCostPerHour: laborCostPerHour, now: now,
                               saltPounds: salt, saltCostPerPound: saltCostPerPound)
    }
}
