import Foundation

/// How a snow customer is billed.
public enum ContractTerms: Equatable, Sendable, Codable {
    /// Flat rate per push. See `PushCounting` for what counts as a push.
    case perPush(rate: Money, counting: PushCounting = .perStorm)
    /// One season price. Billed once, regardless of visits.
    case seasonal(total: Money)
    /// Price by snowfall depth. A storm is billed at the highest tier its deepest visit reached.
    case perInch(tiers: [DepthTier])
    /// Seasonal base covering a number of pushes, then a per-push overage.
    case hybrid(seasonalBase: Money, includedPushes: Int, overagePerPush: Money, counting: PushCounting = .perStorm)
    /// Hours at an hourly rate plus materials with optional markup percent (e.g. 15 for +15%).
    case timeAndMaterials(hourly: Money, materialsMarkupPercent: Int)
}

/// What counts as one "push" when a crew returns to a site during the same storm.
public enum PushCounting: String, Equatable, Sendable, Codable {
    /// One push per storm however many times the crew returns (default, fewest billing disputes).
    case perStorm
    /// Every completed visit is a push.
    case perVisit
}

public struct DepthTier: Equatable, Sendable, Codable {
    public let minInches: Double
    public let rate: Money
    public init(minInches: Double, rate: Money) {
        self.minInches = minInches
        self.rate = rate
    }
}

public enum VisitStatus: Equatable, Sendable, Codable {
    case completed
    /// Never billed. Reason is kept for the customer record.
    case skipped(reason: String)
}

public struct Visit: Equatable, Sendable {
    public let id: UUID
    public let stormID: String
    public let date: Date
    public let status: VisitStatus
    public let snowDepthInches: Double
    public let hours: Double
    public let materials: Money

    public init(id: UUID = UUID(), stormID: String, date: Date, status: VisitStatus = .completed,
                snowDepthInches: Double = 0, hours: Double = 0, materials: Money = .zero) {
        self.id = id
        self.stormID = stormID
        self.date = date
        self.status = status
        self.snowDepthInches = snowDepthInches
        self.hours = hours
        self.materials = materials
    }
}

public struct InvoiceLine: Equatable, Sendable {
    public let description: String
    public let stormID: String?
    public let amount: Money
}

public struct BillingResult: Equatable, Sendable {
    public let lines: [InvoiceLine]
    public var total: Money { lines.reduce(.zero) { $0 + $1.amount } }
    /// Completed pushes counted against the contract this season.
    public let pushesUsed: Int
    /// For hybrid contracts: true once the included pushes are used up.
    public let capReached: Bool
    public let skippedVisitCount: Int
}

/// Builds invoice lines for a season. One line per storm, skipped visits are never billed.
public enum SnowBilling {
    /// - Parameters:
    ///   - visits: all visits this season for one site, any order.
    ///   - includeSeasonalBase: add the seasonal/hybrid base line (set false once it has been invoiced).
    ///   - alreadyUsedPushes: pushes counted in earlier invoices this season (for hybrid caps).
    public static func bill(terms: ContractTerms,
                            visits: [Visit],
                            includeSeasonalBase: Bool = true,
                            alreadyUsedPushes: Int = 0) -> BillingResult {
        let sorted = visits.sorted { $0.date < $1.date }
        let completed = sorted.filter { $0.status == .completed }
        let skipped = sorted.count - completed.count
        let storms = groupByStorm(completed)

        var lines: [InvoiceLine] = []
        var capReached = false
        var pushesThisInvoice = completed.count   // default for contracts without push counting

        switch terms {
        case .perPush(let rate, let counting):
            pushesThisInvoice = 0
            for storm in storms {
                let qty = pushes(in: storm, counting)
                pushesThisInvoice += qty
                lines.append(InvoiceLine(description: "Snow removal, storm \(storm.id): \(qty) push\(qty == 1 ? "" : "es") x \(rate.formatted)",
                                         stormID: storm.id, amount: rate * qty))
            }

        case .seasonal(let total):
            if includeSeasonalBase {
                lines.append(InvoiceLine(description: "Seasonal snow contract", stormID: nil, amount: total))
            }

        case .perInch(let tiers):
            let ordered = tiers.sorted { $0.minInches < $1.minInches }
            for storm in storms {
                let depth = storm.visits.map(\.snowDepthInches).max() ?? 0
                if let tier = ordered.last(where: { depth >= $0.minInches }) {
                    lines.append(InvoiceLine(description: "Snow removal, storm \(storm.id): \(trim(depth)) in",
                                             stormID: storm.id, amount: tier.rate))
                }
                // Below the lowest tier: no charge (trigger depth not reached).
            }

        case .hybrid(let base, let included, let overage, let counting):
            pushesThisInvoice = 0
            if includeSeasonalBase {
                lines.append(InvoiceLine(description: "Seasonal base (includes \(included) pushes)", stormID: nil, amount: base))
            }
            var used = alreadyUsedPushes
            for storm in storms {
                var over = 0
                for _ in 0..<pushes(in: storm, counting) {
                    used += 1
                    pushesThisInvoice += 1
                    if used > included { over += 1 }
                }
                if over > 0 {
                    lines.append(InvoiceLine(description: "Storm \(storm.id): \(over) push\(over == 1 ? "" : "es") over cap x \(overage.formatted)",
                                             stormID: storm.id, amount: overage * over))
                }
            }
            capReached = used >= included

        case .timeAndMaterials(let hourly, let markup):
            for storm in storms {
                let hours = storm.visits.reduce(0) { $0 + $1.hours }
                let labor = Money(cents: Int((Double(hourly.cents) * hours).rounded()))
                let mats = storm.visits.reduce(Money.zero) { $0 + $1.materials }.percent(100 + markup)
                let amount = labor + mats
                if amount.cents != 0 {
                    lines.append(InvoiceLine(description: "Storm \(storm.id): \(trim(hours)) h + materials",
                                             stormID: storm.id, amount: amount))
                }
            }
        }

        return BillingResult(lines: lines,
                             pushesUsed: alreadyUsedPushes + pushesThisInvoice,
                             capReached: capReached,
                             skippedVisitCount: skipped)
    }

    // MARK: helpers

    private static func pushes(in storm: Storm, _ counting: PushCounting) -> Int {
        switch counting {
        case .perStorm: return storm.visits.isEmpty ? 0 : 1
        case .perVisit: return storm.visits.count
        }
    }

    private struct Storm { let id: String; let visits: [Visit] }

    private static func groupByStorm(_ visits: [Visit]) -> [Storm] {
        var order: [String] = []
        var map: [String: [Visit]] = [:]
        for v in visits {
            if map[v.stormID] == nil { order.append(v.stormID) }
            map[v.stormID, default: []].append(v)
        }
        return order.map { Storm(id: $0, visits: map[$0] ?? []) }
    }

    private static func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}
