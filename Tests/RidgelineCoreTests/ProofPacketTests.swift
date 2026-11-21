import XCTest
@testable import RidgelineCore

final class MaterialFormatTests: XCTestCase {
    func testUnitsAndSalt() {
        XCTAssertEqual(MaterialType.allCases.count, 5)
        XCTAssertEqual(MaterialType.liquidBrine.unit, .gallons)
        for m in [MaterialType.rockSalt, .treatedSalt, .sand, .none] { XCTAssertEqual(m.unit, .pounds) }
        XCTAssertTrue(MaterialType.rockSalt.isSalt)
        XCTAssertTrue(MaterialType.treatedSalt.isSalt)
        XCTAssertFalse(MaterialType.sand.isSalt)
        XCTAssertFalse(MaterialType.liquidBrine.isSalt)
        XCTAssertEqual(MaterialType.treatedSalt.title, "Treated salt")
    }

    func testAmounts() {
        XCTAssertEqual(MaterialFormat.amount(200, unit: .pounds), "200 lb")
        XCTAssertEqual(MaterialFormat.amount(12.5, unit: .gallons), "12.5 gal")
        XCTAssertEqual(MaterialFormat.amount(12.34, unit: .gallons), "12.3 gal")
        XCTAssertEqual(MaterialFormat.amount(0, unit: .pounds), "0 lb")
    }

    func testDescribe() {
        XCTAssertEqual(MaterialFormat.describe(material: nil, amount: nil), "Not recorded")
        XCTAssertEqual(MaterialFormat.describe(material: nil, amount: nil, legacySaltPounds: 50), "Salt, 50 lb")
        XCTAssertEqual(MaterialFormat.describe(material: MaterialType.none, amount: 30), "None")
        XCTAssertEqual(MaterialFormat.describe(material: .rockSalt, amount: 200), "Rock salt, 200 lb")
        XCTAssertEqual(MaterialFormat.describe(material: .liquidBrine, amount: 40), "Liquid brine, 40 gal")
        XCTAssertEqual(MaterialFormat.describe(material: .sand, amount: nil), "Sand, amount not entered")
        XCTAssertEqual(MaterialFormat.describe(material: .sand, amount: 0), "Sand, amount not entered")
    }

    func testRecordSummaryFallsBackToSaltPounds() {
        let old = VisitRecord(siteID: UUID(), crewMemberName: "Sam", stormID: "S1", arrival: Date(), saltPounds: 80)
        XCTAssertEqual(old.materialSummary, "Salt, 80 lb")
        let new = VisitRecord(siteID: UUID(), crewMemberName: "Sam", stormID: "S1", arrival: Date(),
                              material: .liquidBrine, materialAmount: 25)
        XCTAssertEqual(new.materialSummary, "Liquid brine, 25 gal")
    }

    func testOldRecordsWithoutMaterialStillLoadAndHashTheSame() throws {
        let record = VisitRecord(siteID: UUID(), crewMemberName: "Sam", stormID: "S1",
                                 arrival: Date(timeIntervalSince1970: 1_700_000_000))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let json = String(decoding: try enc.encode(record), as: UTF8.self)
        XCTAssertFalse(json.contains("material"), "nil material must not change the stored JSON or the hash")
        let back = try dec.decode(VisitRecord.self, from: Data(json.utf8))
        XCTAssertNil(back.material)
        XCTAssertNil(back.materialAmount)

        var withMaterial = record
        withMaterial.material = .treatedSalt
        withMaterial.materialAmount = 150
        let round = try dec.decode(VisitRecord.self, from: enc.encode(withMaterial))
        XCTAssertEqual(round.material, .treatedSalt)
        XCTAssertEqual(round.materialAmount, 150)
    }
}

final class PhotoStampTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testAllLines() {
        let lines = PhotoStamp.lines(capturedAt: t0, address: "12 Oak Ln", coordinate: Coordinate(latitude: 44.9776, longitude: -93.265),
                                     weatherNote: " Light snow, 25F ", timeZone: utc)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("Nov 14, 2023 10:13 PM"), lines[0])
        XCTAssertEqual(lines[1], "12 Oak Ln")
        XCTAssertEqual(lines[2], "GPS 44.97760 N, 93.26500 W")
        XCTAssertEqual(lines[3], "Weather: Light snow, 25F")
    }

    func testSkipsUnknownGPSAndEmptyWeather() {
        let lines = PhotoStamp.lines(capturedAt: t0, address: "12 Oak Ln", coordinate: nil, weatherNote: "  ", timeZone: utc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertFalse(lines.joined().contains("GPS"))
        XCTAssertFalse(lines.joined().contains("Weather"))
        XCTAssertEqual(PhotoStamp.lines(capturedAt: t0, address: "", coordinate: nil, weatherNote: "", timeZone: utc).count, 1)
    }

    func testSouthernAndEasternCoordinates() {
        XCTAssertEqual(PhotoStamp.format(Coordinate(latitude: -33.8688, longitude: 151.2093)), "33.86880 S, 151.20930 E")
    }

    func testLongLinesAreCut() {
        let long = String(repeating: "a", count: 200)
        let lines = PhotoStamp.lines(capturedAt: t0, address: long, coordinate: nil, weatherNote: "line one\nline two", timeZone: utc)
        XCTAssertEqual(lines[1].count, PhotoStamp.maxLineLength)
        XCTAssertTrue(lines[1].hasSuffix("..."))
        XCTAssertEqual(lines[2], "Weather: line one line two")
    }
}

final class ProofPacketTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let utc = TimeZone(identifier: "UTC")!
    private let site = Site(customerID: UUID(), address: "12 Oak Ln", latitude: 45, longitude: -93)

    private func photo(_ kind: PhotoKind, _ name: String) -> PhotoRef {
        PhotoRef(kind: kind, filename: name, capturedAt: t0, sha256: SHA256.hex(name))
    }

    private func fullVisit(offset: TimeInterval = 0) -> VisitRecord {
        VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "S1", arrival: t0 + offset, departure: t0 + offset + 1800,
                    geofence: .inside, snowDepthInches: 3.5, weatherNote: "Light snow",
                    photos: [photo(.before, "b.jpg"), photo(.after, "a.jpg")],
                    material: .rockSalt, materialAmount: 200)
    }

    private func value(_ proof: VisitProof, _ label: String) -> String? {
        proof.facts.first { $0.label == label }?.value
    }

    func testDurations() {
        XCTAssertEqual(ProofPacket.duration(0), "0 min")
        XCTAssertEqual(ProofPacket.duration(1500), "25 min")
        XCTAssertEqual(ProofPacket.duration(3600), "1 hr")
        XCTAssertEqual(ProofPacket.duration(7500), "2 hr 5 min")
        XCTAssertEqual(ProofPacket.duration(-50), "0 min")
    }

    func testPhotoText() {
        XCTAssertEqual(ProofPacket.photoText([]), "None")
        XCTAssertEqual(ProofPacket.photoText([photo(.after, "1"), photo(.before, "2"), photo(.after, "3")]), "3 (1 before, 2 after)")
    }

    func testCustodyPriority() {
        XCTAssertEqual(ProofPacket.custody(entryIntact: false, logVerified: false, checks: [.changed]), .recordAltered)
        XCTAssertEqual(ProofPacket.custody(entryIntact: true, logVerified: false, checks: [.intact]), .logAltered)
        XCTAssertEqual(ProofPacket.custody(entryIntact: true, logVerified: true, checks: [.missing, .changed, .intact]),
                       .photoProblem(missing: 1, changed: 1))
        XCTAssertEqual(ProofPacket.custody(entryIntact: true, logVerified: true, checks: [.intact, .notChecked]), .photosNotChecked)
        XCTAssertEqual(ProofPacket.custody(entryIntact: true, logVerified: true, checks: [.intact]), .verified)
        XCTAssertEqual(ProofPacket.custody(entryIntact: true, logVerified: true, checks: []), .verified)
        XCTAssertTrue(CustodyStatus.photosNotChecked.isGood)
        XCTAssertFalse(CustodyStatus.photoProblem(missing: 1, changed: 0).isGood)
        XCTAssertEqual(CustodyStatus.photoProblem(missing: 2, changed: 1).text, "Photo problem: 2 missing, 1 changed since taken")
    }

    func testVisitFacts() {
        var log = VisitLog()
        log.append(fullVisit())
        let proofs = ProofPacket.visits(site: site, log: log, timeZone: utc)
        XCTAssertEqual(proofs.count, 1)
        let p = proofs[0]
        XCTAssertEqual(p.heading, "Storm S1, Nov 14, 2023")
        XCTAssertEqual(value(p, "Arrived"), "Nov 14, 2023 10:13 PM")
        XCTAssertEqual(value(p, "Left"), "Nov 14, 2023 10:43 PM")
        XCTAssertEqual(value(p, "Time on site"), "30 min")
        XCTAssertEqual(value(p, "Status"), "Done")
        XCTAssertEqual(value(p, "Snow depth"), "3.5 in")
        XCTAssertEqual(value(p, "Material"), "Rock salt, 200 lb")
        XCTAssertEqual(value(p, "Weather"), "Light snow")
        XCTAssertEqual(value(p, "At the site"), "Yes, phone was at the site")
        XCTAssertEqual(value(p, "Photos"), "2 (1 before, 1 after)")
        XCTAssertEqual(p.custody, .photosNotChecked)
        XCTAssertEqual(p.fingerprint, log.entries[0].hash)
    }

    func testPhotoChecksDriveCustody() {
        var log = VisitLog()
        log.append(fullVisit())
        XCTAssertEqual(ProofPacket.visits(site: site, log: log, photoCheck: { _ in .intact })[0].custody, .verified)
        let swapped = ProofPacket.visits(site: site, log: log, photoCheck: { $0.filename == "a.jpg" ? .changed : .intact })
        XCTAssertEqual(swapped[0].custody, .photoProblem(missing: 0, changed: 1))
    }

    func testTamperedRecordAndBrokenLog() {
        var log = VisitLog()
        log.append(fullVisit())
        log.append(fullVisit(offset: 7200))
        log._tamper(at: 0) { $0.materialAmount = 900 }
        let proofs = ProofPacket.visits(site: site, log: log, photoCheck: { _ in .intact })
        XCTAssertEqual(proofs[0].custody, .recordAltered)
        XCTAssertEqual(proofs[1].custody, .logAltered)
    }

    func testSkippedVisitAndMissingDeparture() {
        var log = VisitLog()
        log.append(VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "", arrival: t0,
                               status: .skipped(reason: "Gate locked")))
        log.append(VisitRecord(siteID: UUID(), crewMemberName: "Other", stormID: "S1", arrival: t0))   // other site
        let proofs = ProofPacket.visits(site: site, log: log, timeZone: utc)
        XCTAssertEqual(proofs.count, 1)
        let p = proofs[0]
        XCTAssertEqual(p.heading, "Visit, Nov 14, 2023")
        XCTAssertEqual(value(p, "Status"), "Skipped: Gate locked")
        XCTAssertEqual(value(p, "Left"), "Not recorded")
        XCTAssertEqual(value(p, "Time on site"), "Not recorded")
        XCTAssertNil(value(p, "Material"))
        XCTAssertNil(value(p, "Snow depth"))
        XCTAssertEqual(value(p, "At the site"), "Not checked")
        XCTAssertEqual(value(p, "Photos"), "None")
        XCTAssertEqual(p.custody, .verified)
    }

    func testRenderedText() {
        var log = VisitLog()
        var visit = fullVisit()
        visit.material = .treatedSalt
        visit.materialAmount = 150
        log.append(visit)
        let text = ProofPacket.render(site: site, log: log, timeZone: utc, photoCheck: { _ in .intact })
        XCTAssertTrue(text.contains("PROOF PACKET: 12 Oak Ln"))
        XCTAssertTrue(text.contains("Log check: PASSED"))
        XCTAssertTrue(text.contains("Visits: 1"))
        XCTAssertTrue(text.contains("Material: Treated salt, 150 lb"))
        XCTAssertTrue(text.contains("Chain of custody: Verified"))
        XCTAssertTrue(text.contains("Record fingerprint: \(log.entries[0].hash)"))
    }

    func testDisputePacketShowsMaterial() {
        var log = VisitLog()
        log.append(fullVisit())
        XCTAssertTrue(DisputePacket.render(site: site, log: log).contains("material: Rock salt, 200 lb"))
    }

    func testPhotoStorageCheck() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = PhotoStorage(directory: dir)
        let ref = try storage.save(Data("stamped photo".utf8), kind: .after, capturedAt: t0)
        XCTAssertEqual(storage.check(ref), .intact)
        try Data("swapped".utf8).write(to: dir.appendingPathComponent(ref.filename))
        XCTAssertEqual(storage.check(ref), .changed)
        try FileManager.default.removeItem(at: dir.appendingPathComponent(ref.filename))
        XCTAssertEqual(storage.check(ref), .missing)
    }
}
