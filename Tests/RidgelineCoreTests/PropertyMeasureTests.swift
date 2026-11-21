import Foundation
import XCTest
@testable import RidgelineCore

final class PropertyMeasureTests: XCTestCase {
    /// A 100 ft x 100 ft square with its south-west corner in downtown Minneapolis.
    private func minneapolisSquare(feet: Double = 100) -> [Coordinate] {
        let lat = 44.9778, lon = -93.2650
        let meters = feet / PropertyMeasure.feetPerMeter
        let metersPerDegreeLat = 111_195.0
        let dLat = meters / metersPerDegreeLat
        let dLon = meters / (metersPerDegreeLat * cos(lat * .pi / 180))
        return [
            Coordinate(latitude: lat, longitude: lon),
            Coordinate(latitude: lat + dLat, longitude: lon),
            Coordinate(latitude: lat + dLat, longitude: lon + dLon),
            Coordinate(latitude: lat, longitude: lon + dLon)
        ]
    }

    func testHundredFootSquareNearMinneapolisIsTenThousandSquareFeet() {
        let area = PropertyMeasure.areaSquareFeet(minneapolisSquare())
        XCTAssertEqual(area, 10_000, accuracy: 100)     // within 1%
        XCTAssertEqual(PropertyMeasure.areaAcres(minneapolisSquare()), 10_000 / 43_560, accuracy: 0.0023)
    }

    func testCornerOrderAndClosingPointDoNotChangeArea() {
        let square = minneapolisSquare()
        let forward = PropertyMeasure.areaSquareFeet(square)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet(Array(square.reversed())), forward, accuracy: 0.01)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet(square + [square[0]]), forward, accuracy: 0.01)
    }

    func testLargerLotScales() {
        // A 300 ft square is nine times the 100 ft one: about 2.07 acres.
        let big = PropertyMeasure.areaSquareFeet(minneapolisSquare(feet: 300))
        XCTAssertEqual(big, 90_000, accuracy: 900)
        XCTAssertEqual(PropertyMeasure.areaAcres(minneapolisSquare(feet: 300)), 2.066, accuracy: 0.03)
    }

    func testTriangleIsHalfTheSquare() {
        let s = minneapolisSquare()
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], s[1], s[2]]), 5_000, accuracy: 50)
    }

    func testDegeneratePolygonsHaveNoArea() {
        let s = minneapolisSquare()
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([]), 0)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0]]), 0)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], s[1]]), 0)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], s[1], s[0]]), 0)          // closed line, no inside
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], s[0], s[0], s[0]]), 0)     // same spot tapped
        let mid = Coordinate(latitude: (s[0].latitude + s[2].latitude) / 2, longitude: (s[0].longitude + s[2].longitude) / 2)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], mid, s[2]]), 0, accuracy: 0.5)   // all on one line
        let bad = Coordinate(latitude: .nan, longitude: 0)
        XCTAssertEqual(PropertyMeasure.areaSquareFeet([s[0], s[1], bad]), 0)
        XCTAssertFalse(PropertyMeasurement(points: [s[0], s[1]]).isUsable)
    }

    func testOutlineAcrossTheDateLine() {
        let a = [Coordinate(latitude: 0, longitude: 179.9999), Coordinate(latitude: 0.0001, longitude: 179.9999),
                 Coordinate(latitude: 0.0001, longitude: -179.9999), Coordinate(latitude: 0, longitude: -179.9999)]
        let b = [Coordinate(latitude: 0, longitude: 10.0), Coordinate(latitude: 0.0001, longitude: 10.0),
                 Coordinate(latitude: 0.0001, longitude: 10.0002), Coordinate(latitude: 0, longitude: 10.0002)]
        XCTAssertEqual(PropertyMeasure.areaSquareFeet(a), PropertyMeasure.areaSquareFeet(b), accuracy: 1)
    }

    func testMeasurementAndPerimeter() {
        let m = PropertyMeasurement(points: minneapolisSquare())
        XCTAssertTrue(m.isUsable)
        XCTAssertEqual(m.squareFeet, 10_000, accuracy: 100)
        XCTAssertEqual(m.perimeterFeet, 400, accuracy: 4)
        XCTAssertEqual(PropertyMeasure.perimeterFeet(Array(minneapolisSquare().prefix(2))), 100, accuracy: 1)
        XCTAssertEqual(PropertyMeasure.perimeterFeet([]), 0)
    }

    func testTextAndParsing() {
        XCTAssertEqual(PropertyMeasure.squareFeetText(12_403), "12,400 sq ft")
        XCTAssertEqual(PropertyMeasure.squareFeetText(850.4), "850 sq ft")
        XCTAssertEqual(PropertyMeasure.squareFeetText(0), "0 sq ft")
        XCTAssertEqual(PropertyMeasure.acresText(43_560), "1 acre")
        XCTAssertEqual(PropertyMeasure.acresText(12_400), "0.28 acres")
        XCTAssertEqual(PropertyMeasure.describe(squareFeet: 12_400), "12,400 sq ft (0.28 acres)")
        XCTAssertEqual(PropertyMeasure.parseSquareFeet("12,400 sq ft"), 12_400)
        XCTAssertNil(PropertyMeasure.parseSquareFeet(""))
        XCTAssertNil(PropertyMeasure.parseSquareFeet("0"))
    }

    func testAreaIsAddedToQuoteNotes() {
        XCTAssertEqual(PropertyMeasure.notes("", addingArea: 12_400), "Measured area: 12,400 sq ft (0.28 acres)")
        XCTAssertEqual(PropertyMeasure.notes("Gate code 1234 ", addingArea: 12_400), "Gate code 1234\nMeasured area: 12,400 sq ft (0.28 acres)")
        XCTAssertEqual(PropertyMeasure.notes("Gate code 1234", addingArea: nil), "Gate code 1234")
        XCTAssertEqual(PropertyMeasure.notes("Note", addingArea: 0), "Note")
    }

    func testMowingPrice() {
        // 12,000 sq ft at $6 per 1,000 is $72.
        XCTAssertEqual(AreaPricing.mowing(squareFeet: 12_000), Money(dollars: 72))
        XCTAssertEqual(AreaPricing.mowing(squareFeet: 12_000, perThousandSqFt: Money(dollars: 5), minimum: .zero), Money(dollars: 60))
        // A small yard hits the minimum.
        XCTAssertEqual(AreaPricing.mowing(squareFeet: 2_000), Money(dollars: 40))
        XCTAssertEqual(AreaPricing.mowing(squareFeet: 1_234, perThousandSqFt: Money(dollars: 10), minimum: .zero), Money(cents: 1_234))
    }

    func testPlowingPrice() {
        // A 20,000 sq ft lot at 1.5 cents is $300.
        XCTAssertEqual(AreaPricing.plowing(squareFeet: 20_000), Money(dollars: 300))
        XCTAssertEqual(AreaPricing.plowing(squareFeet: 20_000, centsPerSqFt: 2, minimum: .zero), Money(dollars: 400))
        // A driveway hits the minimum.
        XCTAssertEqual(AreaPricing.plowing(squareFeet: 800), Money(dollars: 45))
    }

    func testPriceEdgeCasesChargeTheMinimum() {
        XCTAssertEqual(AreaPricing.price(squareFeet: 0, centsPerSqFt: 2, minimum: Money(dollars: 30)), Money(dollars: 30))
        XCTAssertEqual(AreaPricing.price(squareFeet: -500, centsPerSqFt: 2, minimum: Money(dollars: 30)), Money(dollars: 30))
        XCTAssertEqual(AreaPricing.price(squareFeet: .infinity, centsPerSqFt: 2, minimum: Money(dollars: 30)), Money(dollars: 30))
        XCTAssertEqual(AreaPricing.price(squareFeet: 5_000, centsPerSqFt: -1, minimum: .zero), .zero)
    }

    func testRoundedDollars() {
        XCTAssertEqual(AreaPricing.roundedDollars(Money(cents: 7_240)), 70)
        XCTAssertEqual(AreaPricing.roundedDollars(Money(cents: 7_260)), 75)
        XCTAssertEqual(AreaPricing.roundedDollars(Money(dollars: 1)), 5)
        XCTAssertEqual(AreaPricing.roundedDollars(Money(dollars: 72), step: 1), 72)
    }
}
