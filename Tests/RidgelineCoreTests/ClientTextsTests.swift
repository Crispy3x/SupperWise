import XCTest
@testable import RidgelineCore

final class ClientTextsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func setup(phone: String = "555-201-3344", optedOut: Bool = false, company: String = "Ridge Plow",
                       portalBase: String = "") -> (AppData, Job, Site) {
        var d = AppData()
        d.companyName = company
        let c = Customer(name: "Sam Lee", phone: phone, optedOutAt: optedOut ? now : nil)
        let s = Site(customerID: c.id, address: "12 Oak St", latitude: 44, longitude: -73)
        d.customers = [c]
        d.sites = [s]
        d.portalLinks = [PortalLink(siteID: s.id, token: "ABCDEFGHIJKLMNOPQRSTUVWX", createdAt: now)]
        d.broadcastSettings.portalBaseURL = portalBase
        let job = try! d.addJob(title: "Plow", kind: .snowPlowing, siteID: s.id, start: now, now: now)
        return (d, job, s)
    }

    // MARK: ETA

    func testETARoundsToFiveMinutes() {
        XCTAssertEqual(ClientTexts.roundedETAMinutes(0), 5)
        XCTAssertEqual(ClientTexts.roundedETAMinutes(7 * 60), 5)
        XCTAssertEqual(ClientTexts.roundedETAMinutes(8 * 60), 10)
        XCTAssertEqual(ClientTexts.roundedETAMinutes(13 * 60), 15)
        XCTAssertEqual(ClientTexts.roundedETAMinutes(62 * 60), 60)
        XCTAssertEqual(ClientTexts.roundedETAMinutes(99 * 3600), 600)
        XCTAssertNil(ClientTexts.roundedETAMinutes(-5))
        XCTAssertNil(ClientTexts.roundedETAMinutes(.infinity))
        XCTAssertNil(ClientTexts.roundedETAMinutes(.nan))
    }

    func testETAPhrase() {
        XCTAssertEqual(ClientTexts.etaPhrase(minutes: 15), "about 15 minutes")
        XCTAssertEqual(ClientTexts.etaPhrase(minutes: 60), "about 1 hour")
        XCTAssertEqual(ClientTexts.etaPhrase(minutes: 85), "about 1 hour 25 minutes")
        XCTAssertEqual(ClientTexts.etaPhrase(minutes: 120), "about 2 hours")
    }

    // MARK: messages

    func testOnMyWayWithETAAndNoPageLink() {
        let (d, job, _) = setup()
        guard case .success(let draft) = d.clientTextDraft(.onMyWay, jobID: job.id, etaSeconds: 13 * 60) else { return XCTFail() }
        XCTAssertEqual(draft.body, "Hi Sam, it's Ridge Plow. We're on our way to 12 Oak St and should be there in about 15 minutes.")
        XCTAssertEqual(draft.recipient, "5552013344")
        XCTAssertEqual(draft.kind, .onMyWay)
        XCTAssertNotNil(draft.smsURL)
        XCTAssertTrue(draft.smsURL!.absoluteString.hasPrefix("sms:5552013344&body=Hi%20Sam"))
    }

    func testOnMyWayIncludesPageLinkWhenBaseSet() {
        let (d, job, _) = setup(portalBase: "https://portal.ridgeplow.com/")
        guard case .success(let draft) = d.clientTextDraft(.onMyWay, jobID: job.id, etaSeconds: 600) else { return XCTFail() }
        XCTAssertTrue(draft.body.hasSuffix("Follow along here: https://portal.ridgeplow.com/c/ABCDEFGHIJKLMNOPQRSTUVWX"), draft.body)
        XCTAssertTrue(draft.body.contains("about 10 minutes"))
    }

    func testBadPortalBaseIsLeftOut() {
        let (d, job, s) = setup(portalBase: "http://portal.ridgeplow.com")
        XCTAssertNil(d.clientPageLink(siteID: s.id))
        guard case .success(let draft) = d.clientTextDraft(.onMyWay, jobID: job.id) else { return XCTFail() }
        XCTAssertFalse(draft.body.contains("http"))
        XCTAssertTrue(draft.body.hasSuffix("We're on our way to 12 Oak St."))
    }

    func testDoneMessageHasCompanyAndPhotoLine() {
        let (d, job, _) = setup(portalBase: "https://portal.ridgeplow.com")
        guard case .success(let draft) = d.clientTextDraft(.done, jobID: job.id, withPhoto: true) else { return XCTFail() }
        XCTAssertTrue(draft.body.hasPrefix("Hi Sam, we just finished at 12 Oak St. A photo of the finished work is attached."))
        XCTAssertTrue(draft.body.contains("Details: https://portal.ridgeplow.com/c/"))
        XCTAssertTrue(draft.body.hasSuffix("Thanks, Ridge Plow"))
        guard case .success(let plain) = d.clientTextDraft(.done, jobID: job.id) else { return XCTFail() }
        XCTAssertFalse(plain.body.contains("photo"))
    }

    func testNoCompanyNameStillReadsWell() {
        XCTAssertEqual(ClientTexts.onMyWayMessage(clientName: "Oak Plaza LLC", company: " ", address: "", etaMinutes: nil, pageLink: nil),
                       "Hi there! We're on our way.")
        XCTAssertEqual(ClientTexts.doneMessage(clientName: "Sam", company: "", address: "", withPhoto: false, pageLink: nil),
                       "Hi Sam, we just finished your job. Thank you!")
    }

    func testMessagesStayUnder300Characters() {
        let longName = String(repeating: "B", count: 500)
        let longPlace = String(repeating: "Main Street ", count: 40)
        let longLink = "https://portal.example.com/c/" + String(repeating: "x", count: 250)
        let a = ClientTexts.onMyWayMessage(clientName: longName, company: longName, address: longPlace, etaMinutes: 85, pageLink: longLink)
        let b = ClientTexts.doneMessage(clientName: longName, company: longName, address: longPlace, withPhoto: true, pageLink: longLink)
        XCTAssertLessThanOrEqual(a.count, ClientTexts.maxLength)
        XCTAssertLessThanOrEqual(b.count, ClientTexts.maxLength)
        // A link that does not fit is dropped rather than cut in half.
        XCTAssertFalse(a.contains("https://"))
        XCTAssertFalse(b.contains("https://"))
    }

    func testNewlinesInNamesAreFlattened() {
        let text = ClientTexts.onMyWayMessage(clientName: "Sam\nLee", company: "Ridge\nPlow", address: "12 Oak\r\nSt", etaMinutes: 5, pageLink: nil)
        XCTAssertFalse(text.contains("\n"))
        XCTAssertFalse(text.contains("\r"))
    }

    // MARK: opt-out and phone

    func testOptedOutClientIsNotTexted() {
        let (d, job, _) = setup(optedOut: true)
        XCTAssertEqual(d.clientTextBlocker(jobID: job.id), .optedOut)
        guard case .failure(let why) = d.clientTextDraft(.onMyWay, jobID: job.id) else { return XCTFail() }
        XCTAssertEqual(why, .optedOut)
        guard case .failure = d.clientTextDraft(.done, jobID: job.id) else { return XCTFail() }
    }

    func testMissingPhoneAndClient() {
        let (d, job, _) = setup(phone: "12")
        XCTAssertEqual(d.clientTextBlocker(jobID: job.id), .noPhone)
        var e = d
        let task = try! e.addJob(title: "Call county", start: now, isTask: true, now: now)
        XCTAssertEqual(e.clientTextBlocker(jobID: task.id), .noClient)
        XCTAssertEqual(e.clientTextBlocker(jobID: UUID()), .notFound)
    }

    // MARK: logging

    func testRecordingAddsToJobLog() throws {
        var (d, job, _) = setup()
        XCTAssertNil(d.jobs[0].clientTexts)
        try d.recordClientText(.onMyWay, jobID: job.id, now: now)
        try d.recordClientText(.done, jobID: job.id, now: now.addingTimeInterval(3600))
        let log = d.jobs.first { $0.id == job.id }!.sentTexts(forVisitOn: now, calendar: utc)
        XCTAssertEqual(log.map(\.kind), [.onMyWay, .done])
        XCTAssertEqual(d.jobs[0].lastSentText(.onMyWay, forVisitOn: now, calendar: utc)?.sentAt, now)
    }

    func testRecordingRefusesOptedOutClient() {
        var (d, job, _) = setup(optedOut: true)
        XCTAssertThrowsError(try d.recordClientText(.onMyWay, jobID: job.id, now: now)) { error in
            XCTAssertEqual(error as? ClientTextBlocker, .optedOut)
        }
        XCTAssertNil(d.jobs[0].clientTexts)
    }

    func testLogKeepsLatestEntries() throws {
        var (d, job, _) = setup()
        for i in 0..<(ClientTexts.maxLogEntries + 5) {
            try d.recordClientText(.onMyWay, jobID: job.id, now: now.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(d.jobs[0].clientTexts?.count, ClientTexts.maxLogEntries)
        XCTAssertEqual(d.jobs[0].clientTexts?.last?.sentAt, now.addingTimeInterval(Double(ClientTexts.maxLogEntries + 4)))
    }

    func testRepeatingJobShowsOnlyThatVisitsTexts() throws {
        var (d, job, _) = setup()
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: job.id)
        try d.recordClientText(.onMyWay, jobID: job.id, now: now)
        let nextWeek = now.addingTimeInterval(7 * 86_400)
        try d.recordClientText(.done, jobID: job.id, now: nextWeek)
        let series = d.jobs[0]
        XCTAssertEqual(series.sentTexts(forVisitOn: now, calendar: utc).map(\.kind), [.onMyWay])
        XCTAssertEqual(series.sentTexts(forVisitOn: nextWeek, calendar: utc).map(\.kind), [.done])
    }

    func testSentLine() {
        let entry = ClientTextLogEntry(kind: .onMyWay, sentAt: now)   // 2027-01-15 08:00 UTC
        XCTAssertEqual(ClientTexts.sentLine(entry, now: now, calendar: utc), "On my way sent 8:00 AM")
        XCTAssertEqual(ClientTexts.sentLine(ClientTextLogEntry(kind: .done, sentAt: now), now: now.addingTimeInterval(2 * 86_400), calendar: utc),
                       "Job done sent Jan 15, 8:00 AM")
    }

    func testLogSurvivesSaveAndLoad() throws {
        var (d, job, _) = setup()
        try d.recordClientText(.done, jobID: job.id, now: now)
        let encoder = JSONEncoder()
        let back = try JSONDecoder().decode(AppData.self, from: encoder.encode(d))
        XCTAssertEqual(back.jobs[0].clientTexts, [ClientTextLogEntry(kind: .done, sentAt: now)])
    }

    func testOldJobsWithoutLogStillLoad() throws {
        let (d, _, _) = setup()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d.jobs[0])) as! [String: Any]
        json.removeValue(forKey: "clientTexts")
        let job = try JSONDecoder().decode(Job.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(job.clientTexts)
    }

    // MARK: photo and next stop

    func testLatestAfterPhotoFromTodaysVisit() {
        var (d, _, s) = setup()
        let old = PhotoRef(kind: .after, filename: "old.jpg", capturedAt: now.addingTimeInterval(-86_400), sha256: "a")
        let before = PhotoRef(kind: .before, filename: "b.jpg", capturedAt: now.addingTimeInterval(60), sha256: "b")
        let early = PhotoRef(kind: .after, filename: "early.jpg", capturedAt: now.addingTimeInterval(120), sha256: "c")
        let late = PhotoRef(kind: .after, filename: "late.jpg", capturedAt: now.addingTimeInterval(900), sha256: "d")
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "A", stormID: "x", arrival: now.addingTimeInterval(-86_400), photos: [old]))
        d.visitLog.append(VisitRecord(siteID: s.id, crewMemberName: "A", stormID: "y", arrival: now, photos: [before, late, early]))
        d.visitLog.append(VisitRecord(siteID: UUID(), crewMemberName: "A", stormID: "y", arrival: now,
                                      photos: [PhotoRef(kind: .after, filename: "other.jpg", capturedAt: now.addingTimeInterval(1000), sha256: "e")]))
        XCTAssertEqual(d.latestAfterPhoto(siteID: s.id, on: now, calendar: utc)?.filename, "late.jpg")
        XCTAssertNil(d.latestAfterPhoto(siteID: s.id, on: now.addingTimeInterval(2 * 86_400), calendar: utc))
        XCTAssertNil(d.latestAfterPhoto(siteID: nil, on: now, calendar: utc))
    }

    func testNextStopSkipsFinishedJobs() throws {
        var (d, first, s) = setup()
        let second = try d.addJob(title: "Salt", kind: .salting, siteID: s.id, start: now.addingTimeInterval(1800), now: now)
        let order = [first.id, second.id]
        XCTAssertEqual(d.nextStopToText(order: order, on: now, calendar: utc), first.id)
        try d.setJobStatus(.done, id: first.id)
        XCTAssertEqual(d.nextStopToText(order: order, on: now, calendar: utc), second.id)
        try d.setJobStatus(.inProgress, id: second.id)
        XCTAssertNil(d.nextStopToText(order: order, on: now, calendar: utc))
    }
}
