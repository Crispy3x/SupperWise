import Foundation

/// The subscription products sold through the App Store. Prices are set in App Store Connect and shown exactly as Apple returns them.
public enum StoreProducts {
    public static let prefix = "com.supperwise.app"

    public static func id(_ tier: PlanTier, annual: Bool) -> String {
        "\(prefix).\(tier.rawValue).\(annual ? "annual" : "monthly")"
    }

    public static var allIDs: [String] {
        PlanTier.allCases.flatMap { [id($0, annual: false), id($0, annual: true)] }
    }

    /// Which plan a product id unlocks, and whether it bills yearly.
    public static func plan(for productID: String) -> (tier: PlanTier, annual: Bool)? {
        for tier in PlanTier.allCases {
            if productID == id(tier, annual: false) { return (tier, false) }
            if productID == id(tier, annual: true) { return (tier, true) }
        }
        return nil
    }

    public static let termsURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
}
