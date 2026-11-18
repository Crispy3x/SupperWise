import XCTest
@testable import RidgelineCore

final class DataExportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample() throws -> AppData {
        var d = AppData()
        d.companyName = "Ridge, \"Plow\" Co"
        let c = Customer(name: "=EVIL()", phone: "555-0100")
        let s = Site(customerID: c.id, address: "5 Pine, Unit 2", latitude: 45.0, longitude: -93.0, priority: 1, triggerInches: 2.5, instructions: "Gate code 1234")
        d.customers = [c]; d.sites = [s]
        d.contracts = [SnowContract(siteID: s.id, season: "2026-27", terms: .perPush(rate: Money(dollars: 60)))]
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "S1", arrival: t0, departure: t0 + 1800, geofence: .inside,
                                      snowDepthInches: 4, saltPounds: 30, photos: [PhotoRef(kind: .after, filename: "a.jpg", capturedAt: t0, sha256: "x")], note: "ok"))
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "S2", arrival: t0 + 86_400, status: .skipped(reason: "Car in the way")))
        var inv = Invoice(number: "INV-0001", customerID: c.id, siteID: s.id, issueDate: t0, dueDate: t0 + 14 * 86_400,
                          lines: [InvoiceLineItem(description: "Storm S1", amount: Money(dollars: 60))])
        try inv.markSent(at: t0)
        try inv.record(ManualPayment(amount: Money(dollars: 25), date: t0 + 86_400, method: .check, note: "#1042"))
        d.invoices = [inv]
        d.timeEntries = [TimeEntry(memberName: "Sam", start: t0, end: t0 + 5400, siteID: s.id)]
        d.quotes = [Quote(number: "Q-0001", customerID: c.id, address: "5 Pine, Unit 2", season: "2026-27", terms: .seasonal(total: Money(dollars: 800)), createdAt: t0)]
        d.laborCostPerHour = Money(dollars: 30)
        return d
    }

    func testBackupRoundTripsEverything() throws {
        let d = try sample()
        let result = try DataExport.restore(from: try DataExport.backupJSON(d))
        XCTAssertEqual(result.data, d)
        XCTAssertTrue(result.visitLogVerified)
        XCTAssertEqual(result.customerCount, 1)
        XCTAssertEqual(result.siteCount, 1)
        XCTAssertEqual(result.invoiceCount, 1)
        XCTAssertEqual(result.visitCount, 2)
    }

    func testRestoreRefusesNonBackupsAndNewerFiles() throws {
        XCTAssertThrowsError(try DataExport.restore(from: Data("not json".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        XCTAssertThrowsError(try DataExport.restore(from: Data("[1,2,3]".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        XCTAssertThrowsError(try DataExport.restore(from: Data(#"{"schemaVersion":99}"#.utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(found: 99, supported: 1))
        }
        // An old, sparse file still restores with defaults.
        XCTAssertEqual(try DataExport.restore(from: Data(#"{"schemaVersion":1,"companyName":"Old"}"#.utf8)).data.companyName, "Old")
    }

    func testRestoreFlagsATamperedVisitLog() throws {
        let json = String(data: try DataExport.backupJSON(try sample()), encoding: .utf8)!
        let edited = json.replacingOccurrences(of: "\"snowDepthInches\" : 4", with: "\"snowDepthInches\" : 40")
        XCTAssertNotEqual(json, edited)
        let r = try DataExport.restore(from: Data(edited.utf8))
        XCTAssertFalse(r.visitLogVerified)           // restored, but marked so the app can warn
    }

    func testCSVFilesAreComplete() throws {
        let files = DataExport.csvFiles(try sample(), now: t0 + 86_400 * 2)
        XCTAssertEqual(files.map(\.name), ["customers.csv", "sites.csv", "contracts.csv", "visits.csv", "invoices.csv", "payments.csv", "time_entries.csv", "quotes.csv"])
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.content) })
        for (name, content) in byName {
            XCTAssertTrue(content.hasSuffix("\r\n"), name)
            XCTAssertGreaterThanOrEqual(content.split(separator: "\r\n").count, 1, name)
        }
        XCTAssertEqual(byName["visits.csv"]!.split(separator: "\r\n").count, 3)         // header plus two visits
        XCTAssertTrue(byName["visits.csv"]!.contains("skipped,Car in the way"))
        XCTAssertTrue(byName["visits.csv"]!.contains(",inside,"))
        XCTAssertTrue(byName["payments.csv"]!.contains("INV-0001,2027-01-14 08:00,25.00,check,#1042") || byName["payments.csv"]!.contains(",25.00,check,"))
        XCTAssertTrue(byName["time_entries.csv"]!.contains(",1.50,"))
        XCTAssertTrue(byName["contracts.csv"]!.contains("Per push $60.00 (one push per storm)"))
    }

    func testCSVEscapingAndFormulaProtection() throws {
        let files = DataExport.csvFiles(try sample(), now: t0)
        let customers = files.first { $0.name == "customers.csv" }!.content
        XCTAssertTrue(customers.contains("'=EVIL()"))                   // formula neutralised
        XCTAssertFalse(customers.contains("\r\n=EVIL"))
        let sites = files.first { $0.name == "sites.csv" }!.content
        XCTAssertTrue(sites.contains("\"5 Pine, Unit 2\""))             // comma quoted
        XCTAssertTrue(sites.contains(",45.0,-93.0,1,2.5,"))             // negative longitude is a number, not guarded
    }

    func testEmptyDataStillExports() {
        let files = DataExport.csvFiles(AppData(), now: t0)
        XCTAssertEqual(files.count, 8)
        XCTAssertTrue(files.allSatisfy { $0.content.contains("\r\n") })
        XCTAssertNoThrow(try DataExport.restore(from: try DataExport.backupJSON(AppData())))
    }
}
