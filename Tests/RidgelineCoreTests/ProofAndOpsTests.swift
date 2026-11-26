import XCTest
@testable import RidgelineCore

final class SHA256Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }
}

final class VisitLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func record(site: UUID = UUID(), storm: String = "S1", offset: TimeInterval = 0, photos: [PhotoRef] = []) -> VisitRecord {
        VisitRecord(siteID: site, crewMemberName: "Sam", stormID: storm, arrival: t0 + offset,
                    departure: t0 + offset + 1800, photos: photos)
    }
    private func photo(_ kind: PhotoKind) -> PhotoRef {
        PhotoRef(kind: kind, filename: "\(kind.rawValue).jpg", capturedAt: t0, sha256: SHA256.hex(kind.rawValue))
    }

    func testEmptyLogVerifies() { XCTAssertTrue(VisitLog().verify()) }

    func testChainVerifiesAfterAppends() {
        var log = VisitLog()
        for i in 0..<5 { log.append(record(offset: Double(i) * 3600)) }
        XCTAssertTrue(log.verify())
        XCTAssertEqual(log.entries.count, 5)
        XCTAssertEqual(log.entries[0].previousHash, VisitLog.genesisHash)
        XCTAssertEqual(log.entries[1].previousHash, log.entries[0].hash)
    }

    func testEditingAnEarlierRecordBreaksVerification() {
        var log = VisitLog()
        for i in 0..<3 { log.append(record(offset: Double(i) * 3600)) }
        log._tamper(at: 1) { $0.note = "we were never there" }
        XCTAssertFalse(log.verify())
    }

    func testLogSurvivesJSONRoundTrip() throws {
        var log = VisitLog()
        log.append(record(photos: [photo(.before), photo(.after)]))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(VisitLog.self, from: enc.encode(log))
        XCTAssertTrue(back.verify())
        XCTAssertEqual(back, log)
    }

    func testBillingVisitConversionUsesDuration() {
        let r = record()
        let v = r.asBillingVisit()
        XCTAssertEqual(v.hours, 0.5, accuracy: 0.0001)
        XCTAssertEqual(v.stormID, "S1")
    }

    func testDisputePacketMentionsIntegrityAndPhotos() {
        let site = Site(customerID: UUID(), address: "12 Oak Ln")
        var log = VisitLog()
        log.append(record(site: site.id, photos: [photo(.before), photo(.after)]))
        log.append(record(site: UUID()))   // another site: excluded
        let text = DisputePacket.render(site: site, log: log, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(text.contains("12 Oak Ln"))
        XCTAssertTrue(text.contains("Log integrity check: PASSED"))
        XCTAssertTrue(text.contains("Visits: 1"))
        XCTAssertTrue(text.contains("before: yes, after: yes"))
    }

    func testGeofenceNeverGuesses() {
        let atSite = Site(customerID: UUID(), address: "x", latitude: 45, longitude: -93)
        let noLocation = Site(customerID: UUID(), address: "y")
        XCTAssertEqual(ArrivalCheck.status(device: Coordinate(latitude: 45, longitude: -93), site: atSite), .inside)
        XCTAssertEqual(ArrivalCheck.status(device: Coordinate(latitude: 45.01, longitude: -93), site: atSite), .outside)
        XCTAssertEqual(ArrivalCheck.status(device: nil, site: atSite), .unknown)
        XCTAssertEqual(ArrivalCheck.status(device: Coordinate(latitude: 45, longitude: -93), site: noLocation), .unknown)
    }

    func testUnknownGeofenceIsReportedAsUnknownInThePacket() {
        let site = Site(customerID: UUID(), address: "3 Fir")
        var log = VisitLog()
        log.append(record(site: site.id))   // default geofence is unknown
        let text = DisputePacket.render(site: site, log: log)
        XCTAssertTrue(text.contains("location check): unknown"))
        XCTAssertFalse(text.contains("location check): inside"))
    }

    func testPhotoRefFromRealBytes() {
        let data = Data("abc".utf8)
        let ref = PhotoRef.make(imageData: data, kind: .before, capturedAt: t0)
        XCTAssertEqual(ref.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertTrue(ref.filename.hasSuffix(".jpg"))
        XCTAssertNotEqual(PhotoRef.make(imageData: data, kind: .before, capturedAt: t0).filename, ref.filename)
    }

    func testDisputePacketFlagsTamperedLog() {
        let site = Site(customerID: UUID(), address: "9 Elm")
        var log = VisitLog()
        log.append(record(site: site.id))
        log._tamper(at: 0) { $0.snowDepthInches = 99 }
        XCTAssertTrue(DisputePacket.render(site: site, log: log).contains("FAILED"))
    }
}

final class TimeClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testHoursOpenAndClosed() {
        let closed = TimeEntry(memberName: "Sam", start: t0, end: t0 + 7200)
        XCTAssertEqual(closed.hours(now: t0 + 99999), 2, accuracy: 0.0001)
        let open = TimeEntry(memberName: "Sam", start: t0)
        XCTAssertEqual(open.hours(now: t0 + 3600), 1, accuracy: 0.0001)
    }

    func testAdjustmentKeepsAuditTrail() {
        let e = TimeEntry(memberName: "Sam", start: t0, end: nil)
        let fixed = e.adjusted(newStart: t0, newEnd: t0 + 3600, by: "Owner", reason: "forgot to punch out", at: t0 + 9999)
        XCTAssertEqual(fixed.end, t0 + 3600)
        XCTAssertEqual(fixed.adjustments.count, 1)
        XCTAssertNil(fixed.adjustments[0].oldEnd)
        XCTAssertEqual(fixed.adjustments[0].reason, "forgot to punch out")
    }

    func testTotalsAndLaborCost() {
        let site = UUID()
        let entries = [
            TimeEntry(memberName: "Sam", start: t0, end: t0 + 3600, siteID: site),
            TimeEntry(memberName: "Sam", start: t0 + 7200, end: t0 + 7200 + 5400, siteID: site),
            TimeEntry(memberName: "Lee", start: t0, end: t0 + 3600),
        ]
        XCTAssertEqual(Timesheet.totalHours(entries, member: "Sam", from: t0, to: t0 + 86400, now: t0 + 90000), 2.5, accuracy: 0.0001)
        XCTAssertEqual(Timesheet.laborCost(entries, site: site, hourlyRate: Money(dollars: 20), now: t0 + 90000), Money(dollars: 50))
    }

    func testOpenLongerThanFlagsMissedPunchOuts() {
        let entries = [TimeEntry(memberName: "Sam", start: t0), TimeEntry(memberName: "Lee", start: t0 + 40000)]
        let flagged = Timesheet.openLongerThan(entries, hours: 12, now: t0 + 50000)
        XCTAssertEqual(flagged.map(\.memberName), ["Sam"])
    }

    func testGeofencePromptsOnlyInsideAndNotAlreadyClockedIn() {
        XCTAssertTrue(GeofencePrompt.shouldPrompt(distanceMeters: 40, alreadyClockedIn: false))
        XCTAssertFalse(GeofencePrompt.shouldPrompt(distanceMeters: 200, alreadyClockedIn: false))
        XCTAssertFalse(GeofencePrompt.shouldPrompt(distanceMeters: 40, alreadyClockedIn: true))
    }

    func testRegionMonitoringCappedAtTwenty() {
        let stops = (0..<30).map { Stop(id: UUID(), name: "\($0)", coordinate: Coordinate(latitude: 0, longitude: 0)) }
        XCTAssertEqual(GeofencePrompt.regionsToMonitor(nextStops: stops).count, 20)
        XCTAssertEqual(GeofencePrompt.regionsToMonitor(nextStops: stops, limit: 5).count, 5)
    }
}

final class NoticesAndPayTests: XCTestCase {
    func testSkippedNoticeSaysNotCharged() {
        let m = NoticeTemplates.message(.skipped, company: "Ridge Plow", address: "5 Pine", reason: "a car in the driveway")
        XCTAssertTrue(m.contains("won't be charged"))
        XCTAssertTrue(m.contains("a car in the driveway"))
    }

    func testEnRouteAndDelayedIncludeEta() {
        XCTAssertTrue(NoticeTemplates.message(.enRoute, company: "R", address: "A", etaMinutes: 12).contains("12 min"))
        XCTAssertTrue(NoticeTemplates.message(.delayed, company: "R", address: "A", etaMinutes: 40, reason: "heavy snow").contains("heavy snow"))
    }

    func testCompleteNeedsAfterPhoto() {
        let t = Date(timeIntervalSince1970: 0)
        var r = VisitRecord(siteID: UUID(), crewMemberName: "S", stormID: "S1", arrival: t)
        XCTAssertFalse(NoticeTemplates.canSendComplete(record: r))
        r.photos = [PhotoRef(kind: .after, filename: "a.jpg", capturedAt: t, sha256: "x")]
        XCTAssertTrue(NoticeTemplates.canSendComplete(record: r))
        r.status = .skipped(reason: "gate")
        XCTAssertFalse(NoticeTemplates.canSendComplete(record: r))
    }

    func testSubPayRules() {
        let job = SubJob(jobAmount: Money(dollars: 200), hours: 2.5, pushes: 3, hasBeforePhoto: true, hasAfterPhoto: true)
        XCTAssertEqual(SubPay.pay(rule: .percentOfJob(60), job: job, requirePhotos: true).amount, Money(dollars: 120))
        XCTAssertEqual(SubPay.pay(rule: .hourly(Money(dollars: 40)), job: job, requirePhotos: true).amount, Money(dollars: 100))
        XCTAssertEqual(SubPay.pay(rule: .perPush(Money(dollars: 25)), job: job, requirePhotos: true).amount, Money(dollars: 75))
        XCTAssertEqual(SubPay.pay(rule: .perLot(Money(dollars: 55)), job: job, requirePhotos: true).amount, Money(dollars: 55))
    }

    func testNoPhotoNoPay() {
        let job = SubJob(jobAmount: Money(dollars: 200), hasBeforePhoto: true, hasAfterPhoto: false)
        let held = SubPay.pay(rule: .percentOfJob(60), job: job, requirePhotos: true)
        XCTAssertEqual(held.amount, .zero)
        XCTAssertNotNil(held.heldReason)
        XCTAssertEqual(SubPay.pay(rule: .percentOfJob(60), job: job, requirePhotos: false).amount, Money(dollars: 120))
    }
}

final class EntitlementAndStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    func testTrialCountsDownAndUnlocksEverything() {
        let sub = Subscription.startTrial(at: t0)
        XCTAssertEqual(sub.state(now: t0), .trial(daysLeft: 14))
        XCTAssertEqual(sub.state(now: t0 + 13.5 * day), .trial(daysLeft: 1))
        XCTAssertTrue(sub.canUse(.routeOptimizer, now: t0 + 5 * day))
    }

    func testTrialExpiresAfterFourteenDays() {
        let sub = Subscription.startTrial(at: t0)
        XCTAssertEqual(sub.state(now: t0 + 14 * day), .expired)
        XCTAssertFalse(sub.canUse(.crm, now: t0 + 20 * day))
    }

    func testProAndMaxGating() {
        let pro = Subscription(plan: .pro)
        XCTAssertTrue(pro.canUse(.snowBilling, now: t0))
        XCTAssertTrue(pro.canUse(.routeOptimizer, now: t0))            // route planning is in every plan, as the plan screen says
        XCTAssertFalse(pro.canUse(.rolesAndReports, now: t0))          // custom permissions are what Max adds
        XCTAssertFalse(pro.canUse(.stormAutomation, now: t0))
        let max = Subscription(plan: .max)
        for f in Feature.allCases { XCTAssertTrue(max.canUse(f, now: t0)) }
    }

    func testNoSubscriptionIsExpired() {
        XCTAssertEqual(Subscription().state(now: t0), .expired)
    }

    func testFileStoreRoundTripAndMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        XCTAssertEqual(try store.load(), AppData())    // missing file gives empty data

        var data = AppData()
        data.companyName = "Ridge Plow"
        let c = Customer(name: "Pat")
        let s = Site(customerID: c.id, address: "1 Main", latitude: 45, longitude: -93)
        data.customers = [c]
        data.sites = [s]
        data.contracts = [SnowContract(siteID: s.id, season: "2026-27", terms: .perPush(rate: Money(dollars: 60)))]
        data.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: "S1", arrival: t0))
        data.subscription = .startTrial(at: t0)
        try store.save(data)
        let back = try store.load()
        XCTAssertEqual(back, data)
        XCTAssertTrue(back.visitLog.verify())
    }
}
