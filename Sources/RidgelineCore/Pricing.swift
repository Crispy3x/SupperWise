import Foundation

public enum PlanTier: String, Codable, CaseIterable, Sendable {
    case pro, max
}

public enum BillingPeriod: String, Codable, Sendable {
    case monthly, annual
}

/// Pricing for Ridgeline Ops. Priced per crew (one field device); office seats are free.
/// Numbers come from PLAN.md ("Verified pricing and revised prices"). Change them here only.
public enum Pricing {
    public struct Schedule: Sendable {
        public let base: Money          // includes the first crew
        public let extraCrew2to5: Money
        public let extraCrew6plus: Money
    }

    public static let annualDiscountPercent = 20
    public static let trialDays = 14

    public static func schedule(for tier: PlanTier) -> Schedule {
        switch tier {
        case .pro: return Schedule(base: Money(dollars: 29), extraCrew2to5: Money(dollars: 19), extraCrew6plus: Money(dollars: 12))
        case .max: return Schedule(base: Money(dollars: 79), extraCrew2to5: Money(dollars: 29), extraCrew6plus: Money(dollars: 19))
        }
    }

    /// Monthly price for a number of crews (minimum 1).
    public static func monthly(_ tier: PlanTier, crews: Int) -> Money {
        let n = max(crews, 1)
        let s = schedule(for: tier)
        let tier2to5 = min(max(n - 1, 0), 4)   // crews 2...5
        let tier6plus = max(n - 5, 0)          // crews 6...
        return s.base + s.extraCrew2to5 * tier2to5 + s.extraCrew6plus * tier6plus
    }

    /// Effective price per month when billed annually (20% off).
    public static func annualPerMonth(_ tier: PlanTier, crews: Int) -> Money {
        monthly(tier, crews: crews).percent(100 - annualDiscountPercent)
    }

    /// Total charged per year when billed annually.
    public static func annualTotal(_ tier: PlanTier, crews: Int) -> Money {
        annualPerMonth(tier, crews: crews) * 12
    }

    public static func price(_ tier: PlanTier, crews: Int, period: BillingPeriod) -> Money {
        switch period {
        case .monthly: return monthly(tier, crews: crews)
        case .annual: return annualPerMonth(tier, crews: crews)
        }
    }
}
