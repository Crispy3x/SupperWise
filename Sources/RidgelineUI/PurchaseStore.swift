#if canImport(SwiftUI) && canImport(StoreKit)
import SwiftUI
import StoreKit
import RidgelineCore

/// Buying a plan with the Apple ID. Apple sets and shows the prices; the app only reads them.
/// A plan counts while Apple says the subscription is active, on every device signed in to the same Apple ID.
@Observable @MainActor
final class PurchaseStore {
    private(set) var products: [Product] = []
    private(set) var loading = false
    private(set) var purchasing = false
    private(set) var loadFailed = false
    var message: String?
    /// Called with the best plan Apple says is active, or nil when there is none.
    var onEntitlement: ((PlanTier?) -> Void)?
    private var listener: Task<Void, Never>?

    var isAvailable: Bool { !products.isEmpty }

    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates { await self?.handle(result) }
        }
        Task { await load(); await refreshEntitlements() }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            products = try await Product.products(for: StoreProducts.allIDs)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    func product(_ tier: PlanTier, annual: Bool) -> Product? {
        products.first { $0.id == StoreProducts.id(tier, annual: annual) }
    }

    func purchase(_ product: Product) async {
        purchasing = true
        message = nil
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                // Only a purchase Apple has signed counts. Anything else is not treated as a plan.
                message = await handle(result) ? "Thank you. Your plan is active."
                                               : "Apple could not confirm this purchase. If you were charged, tap Restore purchases."
            case .pending: message = "Waiting for approval from the Apple ID owner."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = "The purchase did not go through. You were not charged."
        }
    }

    func restore() async {
        message = nil
        do {
            try await AppStore.sync()
            let plan = await refreshEntitlements()
            message = plan == nil ? "No active plan was found for this Apple ID." : "Your \(plan == .max ? "Max" : "Pro") plan is restored."
        } catch {
            message = "Could not reach the App Store. Try again."
        }
    }

    @discardableResult
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        guard case .verified(let transaction) = result else { return false }
        await transaction.finish()
        await refreshEntitlements()
        return true
    }

    /// Tells the app the best plan Apple says is active, and returns it.
    @discardableResult
    func refreshEntitlements() async -> PlanTier? {
        var best: PlanTier?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, let plan = StoreProducts.plan(for: t.productID) else { continue }
            if plan.tier == .max || best == nil { best = plan.tier }
        }
        onEntitlement?(best)
        return best
    }
}
#endif
