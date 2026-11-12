import Foundation
import Observation
import RevenueCat

/// RevenueCat setup. The SDK key is public by design (it ships inside the app).
enum RC {
    /// Public SDK keys (they ship inside the app by design). Never put a secret key (`sk_`) in the app.
    /// Debug builds use RevenueCat's **Test Store** (simulated purchases, nothing charged);
    /// Release builds (TestFlight, App Store) use the App Store app "Supperwise (App Store)".
    static let testStoreKey = "test_IGrjzVZboqhOTMZWABawWgABIhz"
    static let appStoreKey = "appl_KefqzTvaHcaupcqpeCkkZFIjoCe"
    #if DEBUG
    static let apiKey = testStoreKey
    #else
    static let apiKey = appStoreKey
    #endif
    /// Entitlements, lowest to highest. Each plan's products also grant the levels below it, so a check for
    /// `plus` passes for Family and Pro subscribers too. `supper_wise_pro` is the top level (kept from the first setup).
    static let plusEntitlement = "plus"
    static let familyEntitlement = "family"
    static let proEntitlement = "supper_wise_pro"
    /// Product identifiers (RevenueCat Test Store now; the same ids in App Store Connect later).
    static let products: [Tier: (monthly: String, yearly: String)] = [
        .plus: ("plus_monthly", "plus_yearly"),
        .family: ("family_monthly", "family_yearly"),
        .pro: ("monthly", "yearly"),   // the project's original products are the Pro plan
    ]

    static func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: apiKey)
    }
}

/// The plans, lowest to highest: Plus, Family, Pro. Each is a RevenueCat entitlement.
enum Tier: Int, Comparable, CaseIterable, Identifiable {
    case free = 0, plus, family, pro
    var id: Int { rawValue }
    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["Free", "Supperwise Plus", "Supperwise Family", "Supperwise Pro"][rawValue] }
    var features: [String] {
        switch self {
        case .free: ["Your first week's plan and list, kept"]
        case .plus: ["A new week every Sunday", "Swap any night; the list reprices", "Cook mode with timers", "Holiday menus", "Save 10 recipes a month"]
        case .family: ["Everything in Plus", "First foods for babies", "Lunchbox planner, on the same list", "Product scanner and health scores", "Eating-out scores", "Leftovers, receipt check, weekly recap"]
        case .pro: ["Everything in Family", "Fridge scan: what can I cook tonight?"]
        }
    }
}

/// Which plan each feature needs (all of them are in Supperwise Pro).
enum Feature {
    case nextWeek, cookMode, importRecipe, holidayMenus, firstFoods, lunchbox, scanner, eatOut, leftovers, receipt, recap, fridge
    var tier: Tier {
        switch self {
        case .nextWeek, .cookMode, .importRecipe, .holidayMenus: .plus
        case .firstFoods, .lunchbox, .scanner, .eatOut, .leftovers, .receipt, .recap: .family
        case .fridge: .pro
        }
    }
}

/// Subscription state for the whole app, kept current by RevenueCat's customer-info stream.
@Observable
@MainActor
final class Subscriptions {
    private(set) var customerInfo: CustomerInfo? = nil
    private(set) var offering: Offering? = nil
    private(set) var tier: Tier = .free
    private(set) var lastError: String? = nil
    @ObservationIgnored private var listener: Task<Void, Never>? = nil

    init() {
        RC.configure()
        // Every purchase, renewal, expiry, refund or restore arrives here, from any device.
        listener = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    var isSubscribed: Bool { tier > .free }
    func has(_ f: Feature) -> Bool { tier >= f.tier }

    /// The highest active entitlement, with its renewal date, store and trial state.
    var activeEntitlement: EntitlementInfo? {
        [RC.proEntitlement, RC.familyEntitlement, RC.plusEntitlement].lazy.compactMap { self.customerInfo?.entitlements.active[$0] }.first
    }

    /// Loads customer info and the current offering. Safe to call often: the SDK caches both.
    func load() async {
        do {
            apply(try await Purchases.shared.customerInfo())
            offering = try await Purchases.shared.offerings().current
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func apply(_ info: CustomerInfo) {
        customerInfo = info
        tier = Self.tier(for: Set(info.entitlements.active.keys))
        if Demo.isOn { tier = .family }   // debug screenshots only
    }

    func restore() async {
        do {
            apply(try await Purchases.shared.restorePurchases())
            lastError = isSubscribed ? nil : "No active subscription was found for this Apple ID."
        } catch {
            lastError = Self.message(for: error)
        }
    }

    nonisolated static func tier(for active: Set<String>) -> Tier {
        if active.contains(RC.proEntitlement) || active.contains("pro") { return .pro }
        if active.contains(RC.familyEntitlement) { return .family }
        if active.contains(RC.plusEntitlement) { return .plus }
        return .free
    }

    /// Plain-language errors for the few cases people can act on.
    nonisolated static func message(for error: Error) -> String {
        if let e = error as? RevenueCat.ErrorCode {
            switch e {
            case .networkError, .offlineConnectionError: return "You're offline. Check your connection and try again."
            case .purchaseCancelledError: return "Purchase cancelled. You haven't been charged."
            case .storeProblemError: return "The App Store had a problem. Try again in a moment."
            case .paymentPendingError: return "Your purchase is waiting for approval. It unlocks as soon as it's approved."
            default: break
            }
        }
        return "Something went wrong with the subscription. Try again, or restore purchases in Settings."
    }
}
