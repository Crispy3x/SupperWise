import Foundation

public enum QuoteStatus: String, Codable, Sendable {
    case draft, sent, accepted, declined, expired
}

public enum QuoteError: Error, Equatable {
    case expired
    case alreadyDecided
    case notAccepted
}

/// A proposal for a snow contract. Accepting it produces the contract.
public struct Quote: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var number: String
    public var customerID: UUID
    public var address: String
    public var season: String
    public var terms: ContractTerms
    public var createdAt: Date
    public var validUntil: Date
    public var notes: String
    public private(set) var sentAt: Date?
    public private(set) var acceptedAt: Date?
    public private(set) var declinedAt: Date?

    public init(id: UUID = UUID(), number: String, customerID: UUID, address: String, season: String,
                terms: ContractTerms, createdAt: Date, validDays: Int = 30, notes: String = "") {
        self.id = id
        self.number = number
        self.customerID = customerID
        self.address = address
        self.season = season
        self.terms = terms
        self.createdAt = createdAt
        self.validUntil = createdAt.addingTimeInterval(Double(max(validDays, 0)) * 86_400)
        self.notes = notes
    }

    public func status(now: Date) -> QuoteStatus {
        if acceptedAt != nil { return .accepted }
        if declinedAt != nil { return .declined }
        if now > validUntil { return .expired }
        return sentAt == nil ? .draft : .sent
    }

    public mutating func markSent(at date: Date) { if sentAt == nil { sentAt = date } }

    public mutating func accept(at date: Date) throws {
        guard acceptedAt == nil, declinedAt == nil else { throw QuoteError.alreadyDecided }
        guard date <= validUntil else { throw QuoteError.expired }
        acceptedAt = date
    }

    public mutating func decline(at date: Date) throws {
        guard acceptedAt == nil, declinedAt == nil else { throw QuoteError.alreadyDecided }
        declinedAt = date
    }

    /// The contract for an accepted quote, once the site exists.
    public func makeContract(siteID: UUID) throws -> SnowContract {
        guard acceptedAt != nil else { throw QuoteError.notAccepted }
        return SnowContract(siteID: siteID, season: season, terms: terms)
    }
}

/// Plain-language season cost for a customer, so a per-push price never turns into a surprise.
/// These are estimates from assumptions the owner chooses, not a promise.
public enum SeasonEstimate {
    public struct Assumptions: Equatable, Sendable {
        public var pushes: Int
        public var averageDepthInches: Double
        public var hoursPerPush: Double
        public var materialsPerPush: Money
        public init(pushes: Int, averageDepthInches: Double = 4, hoursPerPush: Double = 0.75, materialsPerPush: Money = .zero) {
            self.pushes = max(pushes, 0)
            self.averageDepthInches = averageDepthInches
            self.hoursPerPush = hoursPerPush
            self.materialsPerPush = materialsPerPush
        }
    }

    public static func cost(_ terms: ContractTerms, _ a: Assumptions) -> Money {
        switch terms {
        case .perPush(let rate, _):
            return rate * a.pushes
        case .seasonal(let total):
            return total
        case .perInch(let tiers):
            let tier = tiers.sorted { $0.minInches < $1.minInches }.last { a.averageDepthInches >= $0.minInches }
            return (tier?.rate ?? .zero) * a.pushes
        case .hybrid(let base, let included, let overage, _):
            return base + overage * max(a.pushes - included, 0)
        case .timeAndMaterials(let hourly, let markup):
            let perPush = Money(cents: Int((Double(hourly.cents) * a.hoursPerPush).rounded())) + a.materialsPerPush.percent(100 + markup)
            return perPush * a.pushes
        }
    }

    /// Low and high season totals so a customer sees the range, for example a mild winter and a heavy one.
    public static func range(_ terms: ContractTerms, mild: Assumptions, heavy: Assumptions) -> (low: Money, high: Money) {
        let a = cost(terms, mild), b = cost(terms, heavy)
        return (min(a, b), max(a, b))
    }
}

public struct JobCost: Equatable, Sendable {
    public let revenue: Money
    public let labor: Money
    public let materials: Money
    public let subcontractors: Money
    public var totalCost: Money { labor + materials + subcontractors }
    public var margin: Money { revenue - totalCost }
    /// nil when there is no revenue to compare against.
    public var marginPercent: Double? {
        revenue.cents > 0 ? Double(margin.cents) / Double(revenue.cents) * 100 : nil
    }
}

public enum JobCosting {
    /// Margin for one site. Labor uses your cost per hour (wages and burden), not the rate you charge.
    public static func site(revenue: Money, timeEntries: [TimeEntry], laborCostPerHour: Money, now: Date,
                            saltPounds: Double, saltCostPerPound: Money, subcontractorPay: Money = .zero) -> JobCost {
        let hours = timeEntries.reduce(0) { $0 + $1.hours(now: now) }
        let labor = Money(cents: Int((Double(laborCostPerHour.cents) * hours).rounded()))
        let materials = Money(cents: Int((Double(saltCostPerPound.cents) * max(saltPounds, 0)).rounded()))
        return JobCost(revenue: revenue, labor: labor, materials: materials, subcontractors: subcontractorPay)
    }

    /// Revenue actually invoiced for a site (voided invoices excluded).
    public static func invoicedRevenue(siteID: UUID, invoices: [Invoice]) -> Money {
        invoices.filter { $0.siteID == siteID && !$0.isVoid }.reduce(.zero) { $0 + $1.total }
    }
}
