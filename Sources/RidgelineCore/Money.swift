import Foundation

/// Money stored as whole cents so totals never drift with floating point.
public struct Money: Equatable, Hashable, Comparable, Codable, Sendable {
    public var cents: Int

    public init(cents: Int) { self.cents = cents }
    public init(dollars: Int) { self.cents = dollars * 100 }

    public static let zero = Money(cents: 0)

    public static func + (l: Money, r: Money) -> Money { Money(cents: l.cents + r.cents) }
    public static func - (l: Money, r: Money) -> Money { Money(cents: l.cents - r.cents) }
    public static func * (l: Money, r: Int) -> Money { Money(cents: l.cents * r) }
    public static func < (l: Money, r: Money) -> Bool { l.cents < r.cents }

    /// Multiplies by a percentage (e.g. 80 for 80%) rounding to the nearest cent.
    public func percent(_ pct: Int) -> Money {
        let scaled = Double(cents) * Double(pct) / 100.0
        return Money(cents: Int(scaled.rounded()))
    }

    /// Example: "$1,234.50"
    public var formatted: String {
        let sign = cents < 0 ? "-" : ""
        let absCents = abs(cents)
        let dollars = absCents / 100
        let rest = absCents % 100
        let grouped = Self.group(dollars)
        return "\(sign)$\(grouped).\(rest < 10 ? "0" : "")\(rest)"
    }

    private static func group(_ n: Int) -> String {
        let s = String(n)
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}
