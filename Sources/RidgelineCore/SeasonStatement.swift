import Foundation

/// One site's winter at a glance: how many pushes, what the contract covers, what has been billed and what is owed.
public struct SeasonStatement: Equatable, Sendable {
    public let contractSummary: String
    public let stormsServiced: Int
    public let skippedVisits: Int
    /// Pushes counted against the contract (depends on whether returns count as pushes).
    public let pushesUsed: Int
    /// For a contract with a cap, how many pushes it includes.
    public let includedPushes: Int?
    public let billed: Money
    public let paid: Money
    public var outstanding: Money { billed - paid }

    /// "5 of 8 included pushes used" or nil when there is no cap.
    public var capLine: String? {
        guard let included = includedPushes else { return nil }
        let over = max(pushesUsed - included, 0)
        return "\(min(pushesUsed, included)) of \(included) included pushes used" + (over > 0 ? ", \(over) beyond the cap" : "")
    }

    public static func build(data: AppData, siteID: UUID, now: Date, windowDays: Int = 200) -> SeasonStatement? {
        guard let contract = data.contracts.last(where: { $0.siteID == siteID }) else { return nil }
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let records = data.visitLog.records(forSite: siteID).filter { $0.arrival >= since }
        let completed = records.filter { $0.status == .completed }
        let skipped = records.count - completed.count
        let pushes = SnowBilling.bill(terms: contract.terms, visits: completed.map { $0.asBillingVisit() }, includeSeasonalBase: false).pushesUsed
        var included: Int?
        if case .hybrid(_, let n, _, _) = contract.terms { included = n }
        let invoices = data.invoices.filter { $0.siteID == siteID && !$0.isVoid && $0.sentAt != nil && $0.issueDate >= since }
        return SeasonStatement(contractSummary: contract.terms.summary,
                               stormsServiced: Set(completed.map(\.stormID)).count,
                               skippedVisits: skipped, pushesUsed: pushes, includedPushes: included,
                               billed: invoices.reduce(.zero) { $0 + $1.total },
                               paid: invoices.reduce(.zero) { $0 + $1.paid })
    }
}
