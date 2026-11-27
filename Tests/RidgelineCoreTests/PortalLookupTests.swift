import XCTest
@testable import RidgelineCore

/// The website tracker sign-in hashes (PortalLookup.swift). The vector is the same one server/test/lookup.test.mjs uses,
/// so the phone and the server agree on every byte.
final class PortalLookupTests: XCTestCase {
    private let salt = "0123456789abcdef0123456789abcdef"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testNormalizationFoldsAccentsAndDropsApostrophesAndHyphens() {
        XCTAssertEqual(PortalLookup.normalize("O'Neil"), "oneil")
        XCTAssertEqual(PortalLookup.normalize("O\u{2019}NEIL"), "oneil")
        XCTAssertEqual(PortalLookup.normalize("García"), "garcia")
        XCTAssertEqual(PortalLookup.normalize("Smith-Jones"), "smithjones")
        XCTAssertEqual(PortalLookup.normalize("123"), "")
    }

    func testTheLastWordOfTheNameIsUsedUnlessTheOwnerSetANameForTheTracker() {
        XCTAssertEqual(PortalLookup.lastName(for: Customer(name: "Pat O'Neil")), "oneil")
        XCTAssertEqual(PortalLookup.lastName(for: Customer(name: "José García")), "garcia")
        XCTAssertEqual(PortalLookup.lastName(for: Customer(name: "Ann Smith-Jones")), "smithjones")
        XCTAssertEqual(PortalLookup.lastName(for: Customer(name: "Lakeside Clinic")), "clinic")
        XCTAssertEqual(PortalLookup.lastName(for: Customer(name: "Pat Miller  2")), "miller")
        var c = Customer(name: "Lakeside Clinic")
        c.portalLastName = "Lakeside"
        XCTAssertEqual(PortalLookup.lastName(for: c), "lakeside")
        c.portalLastName = "Van Dyke"
        XCTAssertEqual(PortalLookup.lastName(for: c), "vandyke")
        c.portalLastName = "  "
        XCTAssertEqual(PortalLookup.lastName(for: c), "clinic")
    }

    func testHouseNumberIsTheLeadingDigitsOfTheAddress() {
        XCTAssertEqual(PortalLookup.houseNumber("14B Elm Ave"), "14")
        XCTAssertEqual(PortalLookup.houseNumber("  221 Baker St"), "221")
        XCTAssertEqual(PortalLookup.houseNumber("Elm Ave 14"), "")
    }

    func testHashesMatchTheKnownVectorTheServerTestUses() {
        XCTAssertEqual(PortalLookup.lookup(salt: salt, lastName: "oneil", houseNumber: "14"),
                       "43443a09da5ad7258ff6eea3c740d9ce55bb9f79b573f98a966883a8fa9ef554")
        XCTAssertEqual(PortalLookup.lookupName(salt: salt, lastName: "oneil"),
                       "3e000e0bfeec41d7b5bb938ab2d4469bc826ee8fd62d1fb88aa4b7f3563f087b")
        XCTAssertNil(PortalLookup.lookup(salt: "short", lastName: "oneil", houseNumber: "14"))
        XCTAssertNil(PortalLookup.lookup(salt: salt, lastName: "oneil", houseNumber: ""))
        XCTAssertNil(PortalLookup.lookupName(salt: salt, lastName: ""))
    }

    func testSaltIsMadeOnceAndIsThirtyTwoHexCharacters() {
        var d = AppData()
        XCTAssertEqual(d.portalLookupSalt, "")
        d.ensurePortalLookupSalt()
        let first = d.portalLookupSalt
        XCTAssertTrue(PortalLookup.isSalt(first))
        d.ensurePortalLookupSalt()
        XCTAssertEqual(d.portalLookupSalt, first)
        XCTAssertNotEqual(PortalLookup.newSalt(), PortalLookup.newSalt())
    }

    func testSaltAndTrackerNameSurviveSavingAndOldFilesLoad() throws {
        var d = AppData()
        d.portalLookupSalt = salt
        var c = Customer(name: "Lakeside Clinic")
        c.portalLastName = "Lakeside"
        d.customers = [c]
        let back = try JSONDecoder().decode(AppData.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(back.portalLookupSalt, salt)
        XCTAssertEqual(back.customers[0].portalLastName, "Lakeside")
        let old = try JSONDecoder().decode(AppData.self, from: Data(#"{"customers":[{"id":"\#(UUID().uuidString)","name":"Pat"}]}"#.utf8))
        XCTAssertEqual(old.portalLookupSalt, "")
        XCTAssertEqual(old.customers[0].portalLastName, "")
    }

    func testSnapshotCarriesHashesSaltAndReviewLinkButNeverTheName() throws {
        var d = AppData()
        d.companyName = "Ridge Plow"
        d.portalLookupSalt = salt
        d.profile.reviewLink = "https://g.page/r/ridgeplow/review"
        let c = Customer(name: "Pat O'Neil", email: "pat@example.com")
        let s = Site(customerID: c.id, address: "14B Elm Ave", latitude: 44.97, longitude: -93.26, priority: 3, triggerInches: 2)
        d.customers = [c]; d.sites = [s]
        d.ensurePortalLinks(now: t0)
        let storm = StormEvent(name: "Nov 18", start: t0, forecastInches: 4)
        let snap = PortalSnapshotBuilder.build(data: d, storm: storm, forecastInches: 4, servedSiteIDs: [s.id], visitStormName: "Nov 18",
                                               now: t0, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(snap.lookupSalt, salt)
        XCTAssertEqual(snap.reviewURL, "https://g.page/r/ridgeplow/review")
        XCTAssertEqual(snap.sites[0].lookup, "43443a09da5ad7258ff6eea3c740d9ce55bb9f79b573f98a966883a8fa9ef554")
        XCTAssertEqual(snap.sites[0].lookupName, "3e000e0bfeec41d7b5bb938ab2d4469bc826ee8fd62d1fb88aa4b7f3563f087b")
        let json = String(data: try JSONEncoder().encode(snap), encoding: .utf8)!
        for key in ["lookupSalt", "reviewURL", "\"lookup\"", "lookupName"] { XCTAssertTrue(json.contains(key), key) }
        for secret in ["O'Neil", "Neil", "oneil", "pat@example.com"] { XCTAssertFalse(json.contains(secret), secret) }

        // A review link that fails the ReviewLink rules is not sent; without a salt no hashes are sent.
        d.profile.reviewLink = "https://evil.example.com/review"
        d.portalLookupSalt = ""
        let plain = PortalSnapshotBuilder.build(data: d, storm: storm, forecastInches: 4, servedSiteIDs: [s.id], visitStormName: "Nov 18",
                                                now: t0, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNil(plain.reviewURL)
        XCTAssertNil(plain.lookupSalt)
        XCTAssertNil(plain.sites[0].lookup)
        XCTAssertNil(plain.sites[0].lookupName)
    }
}
