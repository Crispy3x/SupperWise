import XCTest
@testable import RidgelineCore

final class StormBroadcastTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ hour: Int, day: Int = 18) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: 30))!
    }

    private struct World {
        var data = AppData()
        let customer: Customer
        let site: Site
    }

    private func world(consent: Bool = true, email: String = "pat@example.com", trigger: Double = 2,
                       terms: ContractTerms = .perPush(rate: Money(dollars: 60))) -> World {
        var data = AppData()
        data.companyName = "Ridge Plow"
        data.broadcastSettings.portalBaseURL = "https://portal.example.com/"
        let c = Customer(name: "Pat Miller", email: email, emailConsent: consent)
        let s = Site(customerID: c.id, address: "14 Elm Ave", priority: 3, triggerInches: trigger)
        data.customers = [c]; data.sites = [s]
        data.contracts = [SnowContract(siteID: s.id, season: "2026-27", terms: terms)]
        data.ensurePortalLinks(now: at(12))
        return World(data: data, customer: c, site: s)
    }

    private let storm = StormEvent(name: "Nov 18", start: Date(timeIntervalSince1970: 0), forecastInches: 4)

    // MARK: words

    func testSnowEstimateIsAlwaysARange() {
        XCTAssertEqual(SnowEstimateText.describe(forecastInches: 0), "little or no snow")
        XCTAssertEqual(SnowEstimateText.describe(forecastInches: 0.7), "an inch or less")
        XCTAssertEqual(SnowEstimateText.describe(forecastInches: 3), "around 2 to 4 inches")
        XCTAssertEqual(SnowEstimateText.describe(forecastInches: 8), "around 6 to 10 inches")
        XCTAssertEqual(SnowEstimateText.describe(forecastInches: 1), "around 1 to 2 inches")
    }

    func testPortalTokensAreLongRandomAndWellFormed() {
        let tokens = (0..<1000).map { _ in PortalToken.generate() }
        XCTAssertEqual(Set(tokens).count, 1000)
        XCTAssertTrue(tokens.allSatisfy { $0.count == 24 && PortalToken.isWellFormed($0) })
        XCTAssertFalse(PortalToken.isWellFormed("short"))
        XCTAssertFalse(PortalToken.isWellFormed(String(repeating: "a", count: 21) + "!"))
        XCTAssertGreaterThanOrEqual(PortalToken.generate(length: 5).count, 22)       // never shorter than 22
    }

    func testEmailAndPhoneValidation() {
        XCTAssertTrue(ContactValidation.isValidEmail("pat@example.com"))
        for bad in ["", "pat", "pat@", "@example.com", "pat@example", "pat @example.com", "pat@example.com\nBcc: x@y.com", "a@b.com, c@d.com",
                    "pat@example..com", " pat@example.com", "Pat <pat@example.com>", "pat@@example.com"] {
            XCTAssertFalse(ContactValidation.isValidEmail(bad), bad)
        }
        XCTAssertTrue(ContactValidation.isValidPhone("(612) 555-0100"))
        XCTAssertFalse(ContactValidation.isValidPhone("555-0100"))
    }

    // MARK: quiet hours

    func testQuietHoursWrapMidnightAndDeferToMorning() {
        let q = QuietHours(startHour: 21, endHour: 6)
        XCTAssertFalse(q.isQuiet(at(12), calendar: utc))
        XCTAssertTrue(q.isQuiet(at(22), calendar: utc))
        XCTAssertTrue(q.isQuiet(at(3), calendar: utc))
        XCTAssertFalse(q.isQuiet(at(6), calendar: utc))
        XCTAssertEqual(utc.component(.hour, from: q.nextAllowed(after: at(22), calendar: utc)), 6)
        XCTAssertEqual(utc.component(.day, from: q.nextAllowed(after: at(22), calendar: utc)), 19)      // next morning
        XCTAssertEqual(utc.component(.day, from: q.nextAllowed(after: at(3), calendar: utc)), 18)       // same morning
        XCTAssertEqual(q.nextAllowed(after: at(12), calendar: utc), at(12))
        XCTAssertFalse(QuietHours(startHour: 5, endHour: 5).isQuiet(at(5), calendar: utc))              // no quiet window
    }

    // MARK: the plan

    func testPlanWritesAPersonalMessageWithLinkAndCoverage() {
        let w = world()
        let plan = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        XCTAssertEqual(plan.messages.count, 1)
        XCTAssertTrue(plan.skipped.isEmpty)
        let m = plan.messages[0]
        XCTAssertEqual(m.to, "pat@example.com")
        XCTAssertEqual(m.channel, .email)
        XCTAssertEqual(m.subject, "Snow expected: Ridge Plow will service 14 Elm Ave")
        let token = w.data.portalLinks[0].token
        XCTAssertTrue(m.body.contains("https://portal.example.com/c/\(token)"))    // trailing slash on the base is handled
        XCTAssertTrue(m.body.contains("around 3 to 5 inches"))
        XCTAssertTrue(m.body.contains("We expect to service your property."))
        XCTAssertTrue(m.body.contains("Your price is $60.00 per push (one push per storm)."))
        XCTAssertTrue(m.body.contains("Forecasts can change."))
        XCTAssertTrue(m.body.contains("agreed to storm updates from Ridge Plow"))
        XCTAssertEqual(m.sendAfter, at(12))
    }

    func testUnderTriggerForecastDoesNotPromiseService() {
        let w = world(trigger: 6)
        let m = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 3, now: at(12), calendar: utc).messages[0]
        XCTAssertEqual(m.subject, "Snow update from Ridge Plow")
        XCTAssertFalse(m.body.contains("We expect to service"))
        XCTAssertTrue(m.body.contains("under your 6 inch trigger"))
        XCTAssertTrue(m.body.contains("ask for service on your page"))
    }

    func testCoverageLinePerContractType() {
        func line(_ t: ContractTerms) -> String { world(terms: t).data.contracts[0].terms.stormCoverageLine }
        XCTAssertTrue(line(.seasonal(total: Money(dollars: 900))).contains("included in your seasonal contract"))
        XCTAssertTrue(line(.hybrid(seasonalBase: Money(dollars: 900), includedPushes: 8, overagePerPush: Money(dollars: 45))).contains("includes 8 pushes"))
        XCTAssertTrue(line(.perPush(rate: Money(dollars: 50), counting: .perVisit)).contains("each visit counts as a push"))
        XCTAssertTrue(line(.perInch(tiers: [])).contains("by snow depth"))
        XCTAssertTrue(line(.timeAndMaterials(hourly: Money(dollars: 95), materialsMarkupPercent: 10)).contains("time and materials"))
    }

    func testNoConsentOptOutAndBadContactAreSkippedWithReasons() {
        var w = world(consent: false)
        var plan = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        XCTAssertTrue(plan.messages.isEmpty)
        XCTAssertEqual(plan.skipped.map(\.reason), [.noConsent])

        w = world(email: "not-an-email")
        plan = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        XCTAssertEqual(plan.skipped.map(\.reason), [.noValidContact])

        w = world()
        try! w.data.optOut(customerID: w.customer.id, now: at(11))
        plan = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        XCTAssertEqual(plan.skipped.map(\.reason), [.optedOut])         // opt-out beats the earlier consent
    }

    func testRecordingFreshConsentClearsAnOldStop() throws {
        var w = world()
        try w.data.optOut(customerID: w.customer.id, now: at(11))
        try w.data.recordConsent(customerID: w.customer.id, email: true, sms: false, source: "ticked on the client page", now: at(13))
        let c = w.data.customers[0]
        XCTAssertNil(c.optedOutAt)
        XCTAssertEqual(c.consentSource, "ticked on the client page")
        XCTAssertNotNil(c.consentRecordedAt)
        XCTAssertEqual(StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(14), calendar: utc).messages.count, 1)
        XCTAssertThrowsError(try w.data.optOut(customerID: UUID(), now: at(1)))
    }

    func testNoPortalAddressOrContractSkips() {
        var w = world()
        w.data.broadcastSettings.portalBaseURL = "http://portal.example.com"            // not https
        XCTAssertEqual(StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc).skipped.map(\.reason), [.noPortalLink])
        w = world()
        w.data.contracts = []
        XCTAssertEqual(StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc).skipped.map(\.reason), [.noContract])
        w = world()
        w.data.portalLinks = []
        XCTAssertEqual(StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc).skipped.map(\.reason), [.noPortalLink])
    }

    func testNeverSendsTwiceForTheSameStormAndRetriesOnlyFailures() {
        var w = world()
        let first = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        w.data.recordSent(first.messages, stormID: storm.id, at: at(12))
        w.data.recordSent(first.messages, stormID: storm.id, at: at(13))             // recording twice adds nothing
        XCTAssertEqual(w.data.broadcastLog.count, 1)
        let again = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(14), calendar: utc)
        XCTAssertTrue(again.messages.isEmpty)
        XCTAssertEqual(again.skipped.map(\.reason), [.alreadySent])
        let other = StormEvent(name: "Nov 25", start: Date(timeIntervalSince1970: 0), forecastInches: 4)
        XCTAssertEqual(StormBroadcast.plan(data: w.data, storm: other, forecastInches: 4, now: at(14), calendar: utc).messages.count, 1)   // a new storm is fine
    }

    func testQuietHoursDelayButUrgentGoesNow() {
        let w = world()
        let late = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(23), calendar: utc).messages[0]
        XCTAssertEqual(utc.component(.hour, from: late.sendAfter), 6)
        XCTAssertEqual(utc.component(.day, from: late.sendAfter), 19)
        let urgent = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(23), urgent: true, calendar: utc).messages[0]
        XCTAssertEqual(urgent.sendAfter, at(23))
    }

    func testSmsOnlyWhenChosenAndConsented() {
        var w = world()
        XCTAssertTrue(StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc).messages.allSatisfy { $0.channel == .email })
        var c = w.data.customers[0]; c.phone = "(612) 555-0100"
        w.data.customers = [c]
        let plan = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), channels: [.email, .sms], calendar: utc)
        XCTAssertEqual(plan.messages.map(\.channel), [.email])
        XCTAssertEqual(plan.skipped.map(\.reason), [.noConsent])        // sms needs its own consent
    }

    func testHostileNameCannotBreakTheSubjectLine() {
        var w = world()
        w.data.sites[0].address = "14 Elm\r\nBcc: attacker@example.com"
        let m = StormBroadcast.plan(data: w.data, storm: storm, forecastInches: 4, now: at(12), calendar: utc).messages[0]
        XCTAssertFalse(m.subject.contains("\n"))
        XCTAssertFalse(m.subject.contains("\r"))
    }

    func testPlanIsOrderedAndDeterministic() {
        var data = AppData()
        data.broadcastSettings.portalBaseURL = "https://p.example.com"
        for name in ["Zed", "Amy", "Bob"] {
            let c = Customer(name: name, email: "\(name.lowercased())@example.com", emailConsent: true)
            let s = Site(customerID: c.id, address: "\(name) Street")
            data.customers.append(c); data.sites.append(s)
            data.contracts.append(SnowContract(siteID: s.id, season: "x", terms: .seasonal(total: Money(dollars: 1))))
        }
        data.ensurePortalLinks(now: at(1))
        let plan = StormBroadcast.plan(data: data, storm: storm, forecastInches: 4, now: at(12), calendar: utc)
        XCTAssertEqual(plan.messages.map(\.to), ["amy@example.com", "bob@example.com", "zed@example.com"])
    }

    func testOldSavedCustomersLoadWithNoConsent() throws {
        let id = UUID().uuidString
        let json = #"{"customers":[{"id":"\#(id)","name":"Old Pat","phone":"1","email":"a@b.com","notes":""}]}"#
        let d = try FileStore.decoder.decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(d.customers[0].name, "Old Pat")
        XCTAssertFalse(d.customers[0].emailConsent)          // never assumed
        XCTAssertNil(d.customers[0].optedOutAt)
    }

    func testEnsurePortalLinksKeepsExistingOnes() {
        var w = world()
        let before = w.data.portalLinks
        let s2 = Site(customerID: w.customer.id, address: "New Place")
        w.data.sites.append(s2)
        w.data.ensurePortalLinks(now: at(13))
        XCTAssertEqual(w.data.portalLinks.count, 2)
        XCTAssertEqual(w.data.portalLinks[0], before[0])
        XCTAssertEqual(w.data.siteID(forToken: w.data.portalLinks[1].token), s2.id)
        XCTAssertNil(w.data.siteID(forToken: "nope"))
    }
}

final class ServiceRequestTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func data() -> (AppData, Site, String) {
        var d = AppData()
        let c = Customer(name: "Pat")
        let s = Site(customerID: c.id, address: "14 Elm", priority: 3, triggerInches: 4)
        d.customers = [c]; d.sites = [s]
        d.ensurePortalLinks(now: t0)
        return (d, s, d.portalLinks[0].token)
    }

    private func incoming(_ id: String, token: String, kind: String = "urgent", reason: String? = "leavingSoon", note: String? = "Need to leave by 7") -> IncomingRequest {
        IncomingRequest(id: id, token: token, kind: kind, reason: reason, note: note, createdAt: "2026-11-18T05:10:00Z", stormId: nil)
    }

    func testImportAddsOnceAndIgnoresUnknownPagesAndBadKinds() {
        var (d, site, token) = data()
        XCTAssertEqual(d.importRequests([incoming("r1", token: token), incoming("r1", token: token),
                                         incoming("r2", token: "unknown-token-unknown-token"), incoming("r3", token: token, kind: "hack")]), 1)
        XCTAssertEqual(d.serviceRequests.count, 1)
        XCTAssertEqual(d.serviceRequests[0].siteID, site.id)
        XCTAssertEqual(d.serviceRequests[0].urgentReason, .leavingSoon)
        XCTAssertEqual(d.serviceRequests[0].status, .pending)
        XCTAssertEqual(d.importRequests([incoming("r1", token: token)]), 0)          // the same request later is not added again
    }

    func testFloodingOnePageIsCapped() {
        var (d, _, token) = data()
        let flood = (0..<20).map { incoming("f\($0)", token: token) }
        XCTAssertEqual(d.importRequests(flood), AppData.maxPendingRequestsPerSite)
    }

    func testLongNotesAreTrimmed() {
        var (d, _, token) = data()
        d.importRequests([incoming("long", token: token, note: String(repeating: "x", count: 5000))])
        XCTAssertEqual(d.serviceRequests[0].note.count, AppData.maxRequestNoteLength)
    }

    func testDecisionIsOneWay() throws {
        var (d, _, token) = data()
        d.importRequests([incoming("r1", token: token)])
        let id = d.serviceRequests[0].id
        try d.decideRequest(id: id, accept: false, message: "We cannot reach you before 9", now: t0)
        XCTAssertEqual(d.serviceRequests[0].status, .declined)
        XCTAssertEqual(d.serviceRequests[0].responseMessage, "We cannot reach you before 9")
        XCTAssertThrowsError(try d.decideRequest(id: id, accept: true, message: "", now: t0)) { XCTAssertEqual($0 as? RequestError, .alreadyDecided) }
        XCTAssertThrowsError(try d.decideRequest(id: UUID(), accept: true, message: "", now: t0)) { XCTAssertEqual($0 as? RequestError, .notFound) }
    }

    func testRequestsChangeNothingUntilAccepted() {
        var (d, site, token) = data()
        d.importRequests([incoming("r1", token: token)])
        // Forecast 2 inches, trigger 4: not served, and a pending urgent request does not change that.
        XCTAssertTrue(DispatchRules.effectiveSites(sites: d.sites, inches: 2, stormID: nil, requests: d.serviceRequests).isEmpty)
        try! d.decideRequest(id: d.serviceRequests[0].id, accept: true, message: "On our way first", now: t0)
        let served = DispatchRules.effectiveSites(sites: d.sites, inches: 2, stormID: nil, requests: d.serviceRequests)
        XCTAssertEqual(served.map(\.id), [site.id])
        XCTAssertEqual(served[0].priority, 1)                                   // urgent moves to the top tier
        XCTAssertEqual(d.sites[0].priority, 3)                                  // the saved site is unchanged
    }

    func testAcceptedServiceKeepsPriorityAndAcceptedSkipRemovesTheSite() {
        var (d, site, token) = data()
        d.importRequests([incoming("r1", token: token, kind: "service", reason: nil)])
        try! d.decideRequest(id: d.serviceRequests[0].id, accept: true, message: "", now: t0)
        XCTAssertEqual(DispatchRules.effectiveSites(sites: d.sites, inches: 2, stormID: nil, requests: d.serviceRequests).first?.priority, 3)
        d.importRequests([incoming("r2", token: token, kind: "skip", reason: nil)])
        try! d.decideRequest(id: d.serviceRequests[1].id, accept: true, message: "", now: t0)
        XCTAssertTrue(DispatchRules.effectiveSites(sites: d.sites, inches: 9, stormID: nil, requests: d.serviceRequests).isEmpty)
        _ = site
    }

    func testRequestsOnlyApplyToTheirOwnStorm() {
        var (d, site, token) = data()
        let stormA = UUID(), stormB = UUID()
        d.serviceRequests = [ServiceRequest(siteID: site.id, stormID: stormA, kind: .urgent, createdAt: t0)]
        try! d.decideRequest(id: d.serviceRequests[0].id, accept: true, message: "", now: t0)
        XCTAssertEqual(DispatchRules.effectiveSites(sites: d.sites, inches: 1, stormID: stormA, requests: d.serviceRequests).count, 1)
        XCTAssertTrue(DispatchRules.effectiveSites(sites: d.sites, inches: 1, stormID: stormB, requests: d.serviceRequests).isEmpty)
        _ = token
    }

    func testRequestsSurviveSaveAndLoad() throws {
        var (d, _, token) = data()
        d.importRequests([incoming("r1", token: token)])
        try d.decideRequest(id: d.serviceRequests[0].id, accept: true, message: "ok", now: t0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-req-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(d)
        XCTAssertEqual(try store.load(), d)
    }
}
