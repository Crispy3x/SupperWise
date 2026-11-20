import Foundation

public enum Feature: String, CaseIterable, Codable, Sendable {
    // Pro
    case crm, scheduling, quotesAndInvoices, offlineCrewApp, timeClock, proofOfService
    case snowBilling, basicRouteOrdering, customerNotices
    // Max
    case routeOptimizer, stormAutomation, subManagement, quickBooksSync, marketing, rolesAndReports
}

public enum Entitlements {
    public static func requiredTier(for feature: Feature) -> PlanTier {
        switch feature {
        case .crm, .scheduling, .quotesAndInvoices, .offlineCrewApp, .timeClock, .proofOfService,
             .snowBilling, .basicRouteOrdering, .customerNotices:
            return .pro
        case .routeOptimizer, .stormAutomation, .subManagement, .quickBooksSync, .marketing, .rolesAndReports:
            return .max
        }
    }
}

public enum SubscriptionState: Equatable, Sendable {
    case trial(daysLeft: Int)
    case active(PlanTier)
    case expired
}

/// A subscription is either a 14-day trial (all features unlocked, so owners see the storm and routing tools)
/// or an active paid plan. After the trial ends with no plan, access is read-only (`expired`).
public struct Subscription: Equatable, Codable, Sendable {
    public var trialStart: Date?
    public var plan: PlanTier?

    public init(trialStart: Date? = nil, plan: PlanTier? = nil) {
        self.trialStart = trialStart
        self.plan = plan
    }

    public static func startTrial(at date: Date) -> Subscription { Subscription(trialStart: date, plan: nil) }

    /// The day the free trial ends. Nil if there never was a trial.
    public var trialEnd: Date? { trialStart.map { $0.addingTimeInterval(Double(Pricing.trialDays) * 86_400) } }

    public func state(now: Date) -> SubscriptionState {
        if let plan { return .active(plan) }
        guard let start = trialStart else { return .expired }
        let elapsedDays = now.timeIntervalSince(start) / 86_400
        let left = Int((Double(Pricing.trialDays) - elapsedDays).rounded(.up))
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    public func canUse(_ feature: Feature, now: Date) -> Bool {
        switch state(now: now) {
        case .trial: return true
        case .active(let tier): return tier == .max || Entitlements.requiredTier(for: feature) == .pro
        case .expired: return false
        }
    }
}
