import XCTest
@testable import RidgelineCore

final class ContactsImportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAddressOnOneLine() {
        XCTAssertEqual(ContactImport.oneLineAddress(street: "14 Elm Ave\nApt 2", city: "Minneapolis", state: "MN", postalCode: "55401"),
                       "14 Elm Ave, Apt 2, Minneapolis, MN 55401")
        XCTAssertEqual(ContactImport.oneLineAddress(street: "", city: " Duluth ", state: "MN", postalCode: ""), "Duluth, MN")
        XCTAssertEqual(ContactImport.oneLineAddress(street: "7 Birch Ct", city: "", state: "", postalCode: "55802"), "7 Birch Ct, 55802")
        XCTAssertEqual(ContactImport.oneLineAddress(street: " \n ", city: "", state: "", postalCode: ""), "")
    }

    func testACardBecomesNameFirstPhoneFirstWorkingEmailAndAddress() {
        let card = ContactCard(name: " Pat Miller ", phones: ["", "(555) 555-1234", "555-0000"], emails: ["not an email", "pat@example.com", "other@example.com"],
                               address: "14 Elm Ave\nMinneapolis, MN 55401")
        XCTAssertEqual(ContactImport.row(from: card), ImportedClient(name: "Pat Miller", address: "14 Elm Ave, Minneapolis, MN 55401", phone: "(555) 555-1234", email: "pat@example.com"))
        XCTAssertEqual(ContactImport.row(from: ContactCard(name: "Lakeside Clinic")), ImportedClient(name: "Lakeside Clinic", address: "", phone: "", email: ""))
        XCTAssertNil(ContactImport.row(from: ContactCard(name: "  ", phones: ["555-0100"])))           // no name, no client
        XCTAssertEqual(ContactImport.row(from: ContactCard(name: String(repeating: "n", count: 300)))?.name.count, 120)
    }

    func testDuplicatesAreSkippedByTheSpreadsheetRules() {
        var d = AppData()
        let pat = Customer(name: "Pat Miller")
        let dana = Customer(name: "Dana Reyes")                                                       // saved with no address
        d.customers = [pat, dana]
        d.sites = [Site(customerID: pat.id, address: "14 Elm Ave, Minneapolis")]
        let cards = [
            ContactCard(name: "pat  miller", address: "14  elm ave,  MINNEAPOLIS"),                    // same client, typed differently
            ContactCard(name: "Pat Miller", address: "99 Oak St"),                                    // a second property: new, as in a spreadsheet
            ContactCard(name: "Dana Reyes", address: "7 Birch Ct"),                                   // already here, just without an address
            ContactCard(name: "Sam Lee", phones: ["555-0101"]),                                       // no address: still a client
            ContactCard(name: "sam lee"),                                                             // picked twice
            ContactCard(name: "", phones: ["555-0102"]),                                              // no name
            ContactCard(name: "Lakeside Clinic", address: "100 Lake St"),
            ContactCard(name: "Lakeside Clinic", address: "100 Lake St"),                             // picked twice
            ContactCard(name: "Pat Miller"),                                                          // no address to compare: the name is enough
        ]
        let plan = ContactImport.plan(cards, existing: d)
        XCTAssertEqual(plan.clients.map(\.name), ["Pat Miller", "Sam Lee", "Lakeside Clinic"])
        XCTAssertEqual(plan.clients.map(\.address), ["99 Oak St", "", "100 Lake St"])
        XCTAssertEqual(plan.alreadyHere, 5)
        XCTAssertEqual(plan.withoutName, 1)
        XCTAssertEqual(plan.withoutAddress, 1)
        // The spreadsheet import agrees on the first two.
        let report = ClientImport.clients(from: "Name,Address\npat  miller,\"14  elm ave,  MINNEAPOLIS\"\nPat Miller,99 Oak St\n", existing: d)
        XCTAssertEqual(report.clients.map(\.address), ["99 Oak St"])
        XCTAssertEqual(ContactImport.plan([], existing: d), ContactImportPlan(clients: [], alreadyHere: 0, withoutName: 0))
    }

    func testResultLine() {
        XCTAssertEqual(ContactImport.resultLine(added: 12, alreadyHere: 2), "Added 12 clients, skipped 2 already here")
        XCTAssertEqual(ContactImport.resultLine(added: 1, alreadyHere: 0), "Added 1 client")
        XCTAssertEqual(ContactImport.resultLine(added: 0, alreadyHere: 3), "No clients added, skipped 3 already here")
        XCTAssertEqual(ContactImport.resultLine(added: 5, alreadyHere: 1, withoutName: 2), "Added 5 clients, skipped 1 already here and 2 with no name")
    }

    func testAddingAContactNeverRecordsConsentOrAPrice() {
        var d = AppData()
        d.profile.defaultTriggerInches = 3
        let withAddress = ImportedClient(name: "Pat Miller", address: "14 Elm Ave, Minneapolis", phone: "(555) 555-1234", email: "pat@example.com")
        let id = d.addContactClient(withAddress, coordinate: Coordinate(latitude: 44.98, longitude: -93.27), now: now)
        XCTAssertEqual(d.customers.count, 1)
        XCTAssertEqual(d.customers[0].id, id)
        XCTAssertEqual(d.customers[0].phone, "(555) 555-1234")
        XCTAssertFalse(d.customers[0].emailConsent)                                                   // nobody imported agreed to messages
        XCTAssertFalse(d.customers[0].smsConsent)
        XCTAssertNil(d.customers[0].consentRecordedAt)
        XCTAssertFalse(d.customers[0].isLead)
        XCTAssertEqual(d.sites.count, 1)
        XCTAssertEqual(d.sites[0].customerID, id)
        XCTAssertEqual(d.sites[0].latitude, 44.98)                                                    // lands on the map
        XCTAssertEqual(d.sites[0].longitude, -93.27)
        XCTAssertEqual(d.sites[0].triggerInches, 3)
        XCTAssertTrue(d.contracts.isEmpty)                                                            // no price yet, so no contract
        XCTAssertEqual(d.portalLinks.map(\.siteID), [d.sites[0].id])

        d.addContactClient(ImportedClient(name: "Sam Lee", address: "", phone: "", email: ""), now: now)
        XCTAssertEqual(d.customers.count, 2)
        XCTAssertEqual(d.sites.count, 1)                                                              // no address, no site
        // Picking the same people again adds nobody.
        let again = ContactImport.plan([ContactCard(name: "Pat Miller", address: "14 Elm Ave, Minneapolis"), ContactCard(name: "Sam Lee")], existing: d)
        XCTAssertTrue(again.clients.isEmpty)
        XCTAssertEqual(again.alreadyHere, 2)
    }
}
