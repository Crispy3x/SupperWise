import Foundation

/// A property outline drawn on the map: its corners, area and edge length.
public struct PropertyMeasurement: Equatable, Sendable {
    public let points: [Coordinate]
    public let squareFeet: Double
    public let perimeterFeet: Double
    public var acres: Double { squareFeet / PropertyMeasure.squareFeetPerAcre }
    /// True once there are enough corners to make a shape with some area.
    public var isUsable: Bool { points.count >= 3 && squareFeet >= 1 }

    public init(points: [Coordinate]) {
        self.points = points
        self.squareFeet = PropertyMeasure.areaSquareFeet(points)
        self.perimeterFeet = PropertyMeasure.perimeterFeet(points)
    }
}

/// Measures lawns, driveways and lots from corner points tapped on a satellite map.
public enum PropertyMeasure {
    public static let squareFeetPerAcre = 43_560.0
    public static let squareFeetPerSquareMeter = 10.763_910_416_709_722
    public static let feetPerMeter = 3.280_839_895_013_123
    /// Radius of a sphere with the same surface area as the Earth (authalic radius), in meters.
    static let earthRadiusMeters = 6_371_007.2

    /// Area inside the outline in square meters. Uses an equal-area (Lambert cylindrical) projection of the sphere,
    /// then the shoelace formula, so it is accurate for house lots and parking lots alike.
    /// Fewer than 3 usable corners, or corners all on one line, give 0. Corner order (clockwise or not) does not matter.
    public static func areaSquareMeters(_ points: [Coordinate]) -> Double {
        var ring = points.filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 }
        if ring.count > 1, ring.first == ring.last { ring.removeLast() }   // a closed ring repeats the first corner
        guard ring.count >= 3 else { return 0 }
        let origin = ring[0]
        let lat0 = origin.latitude * .pi / 180
        let sinLat0 = sin(lat0)
        let projected: [(x: Double, y: Double)] = ring.map { p in
            var dLon = (p.longitude - origin.longitude) * .pi / 180
            // Keep outlines that cross the 180th meridian in one piece.
            if dLon > .pi { dLon -= 2 * .pi } else if dLon < -.pi { dLon += 2 * .pi }
            let y = sin(p.latitude * .pi / 180) - sinLat0
            return (earthRadiusMeters * dLon, earthRadiusMeters * y)
        }
        var twiceArea = 0.0
        for i in 0..<projected.count {
            let a = projected[i], b = projected[(i + 1) % projected.count]
            twiceArea += a.x * b.y - b.x * a.y
        }
        return abs(twiceArea) / 2
    }

    public static func areaSquareFeet(_ points: [Coordinate]) -> Double {
        areaSquareMeters(points) * squareFeetPerSquareMeter
    }

    public static func areaAcres(_ points: [Coordinate]) -> Double {
        areaSquareFeet(points) / squareFeetPerAcre
    }

    /// Length around the closed outline in feet (handy for edging or fence work). 0 for fewer than 2 corners.
    public static func perimeterFeet(_ points: [Coordinate]) -> Double {
        guard points.count >= 2 else { return 0 }
        var meters = 0.0
        for i in 0..<points.count {
            let next = (i + 1) % points.count
            if next == 0 && points.count == 2 { break }   // a single line is not walked twice
            meters += Geo.distanceMeters(points[i], points[next])
        }
        return meters * feetPerMeter
    }

    /// Example: "12,400 sq ft". Rounded to the nearest 10 sq ft above 1,000.
    public static func squareFeetText(_ squareFeet: Double) -> String {
        guard squareFeet.isFinite, squareFeet > 0 else { return "0 sq ft" }
        let rounded = squareFeet >= 1_000 ? (squareFeet / 10).rounded() * 10 : squareFeet.rounded()
        return "\(grouped(Int(rounded))) sq ft"
    }

    /// Example: "0.28 acres".
    public static func acresText(_ squareFeet: Double) -> String {
        let acres = max(squareFeet.isFinite ? squareFeet : 0, 0) / squareFeetPerAcre
        let text = String(format: "%.2f", acres)
        return text == "1.00" ? "1 acre" : "\(text) acres"
    }

    /// Example: "12,400 sq ft (0.28 acres)".
    public static func describe(squareFeet: Double) -> String {
        "\(squareFeetText(squareFeet)) (\(acresText(squareFeet)))"
    }

    /// Reads an area someone typed, like "12,400" or "12400 sq ft". nil when there is no positive number.
    public static func parseSquareFeet(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Adds "Measured area: 12,400 sq ft (0.28 acres)" as the last line of a note. Leaves the note alone without an area.
    public static func notes(_ notes: String, addingArea squareFeet: Double?) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let squareFeet, squareFeet.isFinite, squareFeet > 0 else { return trimmed }
        let line = "Measured area: \(describe(squareFeet: squareFeet))"
        return trimmed.isEmpty ? line : trimmed + "\n" + line
    }

    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}

/// Turns a measured area into a price. Rates are the owner's to change; the defaults are only a starting point.
public enum AreaPricing {
    /// Starting rates: $6 per 1,000 sq ft to mow with a $40 minimum, 1.5 cents per sq ft to plow with a $45 minimum.
    public static let defaultMowingPerThousandSqFt = Money(dollars: 6)
    public static let defaultMowingMinimum = Money(dollars: 40)
    public static let defaultPlowingCentsPerSqFt = 1.5
    public static let defaultPlowingMinimum = Money(dollars: 45)

    /// Price for one mow: area / 1,000 times the rate, never below the minimum.
    public static func mowing(squareFeet: Double, perThousandSqFt: Money = defaultMowingPerThousandSqFt,
                              minimum: Money = defaultMowingMinimum) -> Money {
        price(squareFeet: squareFeet, centsPerSqFt: Double(perThousandSqFt.cents) / 1_000, minimum: minimum)
    }

    /// Price for one plow visit: area times cents per sq ft, never below the minimum.
    public static func plowing(squareFeet: Double, centsPerSqFt: Double = defaultPlowingCentsPerSqFt,
                               minimum: Money = defaultPlowingMinimum) -> Money {
        price(squareFeet: squareFeet, centsPerSqFt: centsPerSqFt, minimum: minimum)
    }

    /// Area times a rate in cents per sq ft, rounded to the cent, never below the minimum.
    /// A missing, zero or negative area or rate charges the minimum.
    public static func price(squareFeet: Double, centsPerSqFt: Double, minimum: Money) -> Money {
        let area = squareFeet.isFinite ? max(squareFeet, 0) : 0
        let rate = centsPerSqFt.isFinite ? max(centsPerSqFt, 0) : 0
        let raw = Money(cents: Int((area * rate).rounded()))
        return max(raw, minimum)
    }

    /// Whole dollars rounded to the nearest `step` (for price pickers that move in $5 steps). Never below one step.
    public static func roundedDollars(_ money: Money, step: Int = 5) -> Int {
        let step = max(step, 1)
        let dollars = Double(money.cents) / 100
        let rounded = Int((dollars / Double(step)).rounded()) * step
        return max(rounded, step)
    }
}
