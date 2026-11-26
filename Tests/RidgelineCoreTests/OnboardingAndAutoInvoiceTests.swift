import XCTest
@testable import RidgelineCore

final class OnboardingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testTenStepsInOrderAndOnlyTheBusinessNameIsRequired() {
        XCTAssertEqual(Onboarding.steps.count, 11)
        XCTAssertEqual(Onboarding.steps.map(\.id), OnboardingStepID.allCases)
        XCTAssertEqual(Onboarding.steps.filter(\.required).map(\.id), [.business])
        XCTAssertTrue(Onboarding.steps.allSatisfy { !$0.question.isEmpty && !$0.why.isEmpty && !$0.title.isEmpty })
        XCTAssertEqual(Set(Onboarding.steps.map(\.id)).count, 11)
    }

    func testCannotFinishWithoutABusinessName() {
        var d = AppData()
        var a = OnboardingAnswers()
        XCTAssertFalse(a.problems.isEmpty)
        XCTAssertThrowsError(try d.finishOnboarding(a, now: t0))
        a.businessName = "   "
        XCTAssertThrowsError(try d.finishOnboarding(a, now: t0))
        XCTAssertNil(d.profile.onboardingCompletedAt)                   // a failed finish changes nothing
        a.businessName = "  Ridge Plow  "
        XCTAssertNoThrow(try d.finishOnboarding(a, now: t0))
        XCTAssertEqual(d.companyName, "Ridge Plow")
    }

    func testEverythingElseHasADefaultSoOnlyTheNameIsNeeded() throws {
        var d = AppData()
        var a = OnboardingAnswers(); a.businessName = "Ridge Plow"
        try d.finishOnboarding(a, now: t0)
        XCTAssertEqual(d.profile.defaultSnowBilling, .perPush)
        XCTAssertEqual(d.profile.defaultTriggerInches, 2)
        XCTAssertEqual(d.profile.netDays, 14)
        XCTAssertEqual(d.profile.invoiceAutomation, .draft)            // safe default: nothing goes out without a look
        XCTAssertTrue(d.profile.stormMessagesOn)
        XCTAssertEqual(d.crews.map(\.name), ["Crew 1"])
        XCTAssertNil(d.depot)
        XCTAssertEqual(d.profile.onboardingCompletedAt, t0)
    }

    func testAnswersAreAppliedAndClamped() throws {
        var d = AppData()
        var a = OnboardingAnswers()
        a.businessName = "Ridge"; a.services = [.snowPlowing, .mowing]; a.clientTypes = [.commercial, .hoaOrPropertyManager]
        a.snowBilling = .hybrid; a.triggerInches = 99; a.homeBase = Coordinate(latitude: 45, longitude: -93); a.crewCount = 3
        a.netDays = 9999; a.paymentInstructions = String(repeating: "x", count: 1000); a.invoiceAutomation = .send; a.accentColor = "hotpink"
        a.skippedSteps = [.importClients, .branding]
        try d.finishOnboarding(a, now: t0)
        XCTAssertEqual(d.profile.services, [.snowPlowing, .mowing])
        XCTAssertEqual(d.profile.defaultSnowBilling, .hybrid)
        XCTAssertEqual(d.profile.defaultTriggerInches, 24)             // clamped
        XCTAssertEqual(d.profile.netDays, 120)
        XCTAssertEqual(d.profile.paymentInstructions.count, 300)
        XCTAssertEqual(d.profile.accentColor, "blue")                  // an unknown color falls back
        XCTAssertEqual(d.profile.skippedSteps, ["importClients", "branding"])
        XCTAssertEqual(d.depot, Coordinate(latitude: 45, longitude: -93))
        XCTAssertEqual(d.crews.map(\.name), ["Crew 1", "Crew 2", "Crew 3"])
        a.crewCount = -4; a.services = []; a.clientTypes = []
        var e = AppData(); try e.finishOnboarding(a, now: t0)
        XCTAssertEqual(e.profile.crewCount, 1)
        XCTAssertEqual(e.profile.services, [.snowPlowing])             // never an empty list
        a.crewCount = 500
        var f = AppData(); try f.finishOnboarding(a, now: t0)
        XCTAssertEqual(f.crews.count, 50)
    }

    func testRunningItAgainUpdatesWithoutDuplicatingCrews() throws {
        var d = AppData()
        var a = OnboardingAnswers(); a.businessName = "Ridge"; a.crewCount = 2
        try d.finishOnboarding(a, now: t0)
        let ids = d.crews.map(\.id)
        a.crewCount = 3; a.businessName = "Ridge Plow Co"
        try d.finishOnboarding(a, now: t0 + 60)
        XCTAssertEqual(d.crews.count, 3)
        XCTAssertEqual(Array(d.crews.map(\.id).prefix(2)), ids)
        XCTAssertEqual(d.companyName, "Ridge Plow Co")
        a.crewCount = 1
        try d.finishOnboarding(a, now: t0 + 120)
        XCTAssertEqual(d.crews.count, 3)                               // never deletes crews you already have
    }

    func testProfileSurvivesSaveAndOldFilesGetADefaultProfile() throws {
        var d = AppData()
        var a = OnboardingAnswers(); a.businessName = "Ridge"; a.invoiceAutomation = .send
        try d.finishOnboarding(a, now: t0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-ob-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(url: dir.appendingPathComponent("data.json"))
        try store.save(d)
        XCTAssertEqual(try store.load(), d)
        let old = try FileStore.decoder.decode(AppData.self, from: Data(#"{"companyName":"Old"}"#.utf8))
        XCTAssertNil(old.profile.onboardingCompletedAt)                // so the welcome flow shows for an old install
    }
}

final class AutoInvoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func world(mode: InvoiceAutomation, consent: Bool = true, terms: ContractTerms = .perPush(rate: Money(dollars: 60))) -> (AppData, Site) {
        var d = AppData()
        d.companyName = "Ridge Plow"
        d.profile.invoiceAutomation = mode
        d.profile.paymentInstructions = "Check or e-transfer to Ridge Plow"
        d.broadcastSettings.portalBaseURL = "https://portal.example.com"
        let c = Customer(name: "Pat Miller", email: "pat@example.com", emailConsent: consent)
        let s = Site(customerID: c.id, address: "14 Elm Ave")
        d.customers = [c]; d.sites = [s]
        d.contracts = [SnowContract(siteID: s.id, season: "2026-27", terms: terms)]
        d.ensurePortalLinks(now: t0)
        return (d, s)
    }

    private func visit(_ d: inout AppData, _ s: Site, storm: String, day: Double, skipped: Bool = false) -> VisitRecord {
        let r = VisitRecord(siteID: s.id, crewMemberName: "Sam", stormID: storm, arrival: t0 + day * 86_400, departure: t0 + day * 86_400 + 1800,
                            status: skipped ? .skipped(reason: "gate") : .completed, snowDepthInches: 4)
        d.visitLog.append(r)
        return r
    }

    func testOffDoesNothing() {
        var (d, s) = world(mode: .off)
        let r = visit(&d, s, storm: "S1", day: 0)
        let out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertNil(out.invoice); XCTAssertNil(out.message); XCTAssertTrue(d.invoices.isEmpty)
    }

    func testDraftModeMakesADraftAndNeverAMessage() {
        var (d, s) = world(mode: .draft)
        let r = visit(&d, s, storm: "S1", day: 0)
        let out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertEqual(out.invoice?.total, Money(dollars: 60))
        XCTAssertNil(out.message)
        XCTAssertEqual(d.invoices.count, 1)
        XCTAssertEqual(d.invoices[0].status(now: t0), .draft)
        XCTAssertEqual(d.invoices[0].dueDate, t0 + 14 * 86_400)        // uses the profile's payment days
    }

    func testSendModeReturnsAnEmailAndTheInvoiceStaysDraftUntilItReallyWentOut() throws {
        var (d, s) = world(mode: .send)
        let r = visit(&d, s, storm: "S1", day: 0)
        let out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        let m = try XCTUnwrap(out.message)
        XCTAssertEqual(m.to, "pat@example.com")
        XCTAssertTrue(m.subject.contains("INV-0001")); XCTAssertTrue(m.subject.contains("$60.00"))
        XCTAssertTrue(m.body.contains("Total due: $60.00 by Jan 29, 2027."))
        XCTAssertTrue(m.body.contains("How to pay: Check or e-transfer to Ridge Plow"))
        XCTAssertTrue(m.body.contains("https://portal.example.com/c/\(d.portalLinks[0].token)"))
        XCTAssertTrue(m.body.contains("agreed to messages from Ridge Plow"))
        XCTAssertEqual(d.invoices[0].status(now: t0), .draft)          // a failed send must not mark it sent
        try d.markInvoiceSent(number: "INV-0001", at: t0)
        XCTAssertEqual(d.invoices[0].status(now: t0), .sent)
        XCTAssertThrowsError(try d.markInvoiceSent(number: "nope", at: t0))
    }

    func testNoConsentOptOutOrBadEmailLeavesADraftWithAnExplanation() throws {
        var (d, s) = world(mode: .send, consent: false)
        var r = visit(&d, s, storm: "S1", day: 0)
        var out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertNil(out.message); XCTAssertNotNil(out.invoice)
        XCTAssertTrue(out.note.contains("not emailed"))

        (d, s) = world(mode: .send)
        try d.optOut(customerID: d.customers[0].id, now: t0)
        r = visit(&d, s, storm: "S1", day: 0)
        out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertNil(out.message)

        (d, s) = world(mode: .send)
        d.customers[0].email = "not-an-email"
        r = visit(&d, s, storm: "S1", day: 0)
        XCTAssertNil(d.autoInvoice(afterVisit: r, now: t0, calendar: utc).message)
    }

    func testSkippedVisitsAreNeverInvoicedOrEmailed() {
        var (d, s) = world(mode: .send)
        let r = visit(&d, s, storm: "S1", day: 0, skipped: true)
        let out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertNil(out.invoice); XCTAssertNil(out.message); XCTAssertTrue(d.invoices.isEmpty)
        XCTAssertTrue(out.note.contains("skipped"))
    }

    func testEachStormIsInvoicedOnceAndCompletingTwiceDoesNotRebill() {
        var (d, s) = world(mode: .draft)
        let r1 = visit(&d, s, storm: "S1", day: 0)
        _ = d.autoInvoice(afterVisit: r1, now: t0, calendar: utc)
        XCTAssertNil(d.autoInvoice(afterVisit: r1, now: t0 + 10, calendar: utc).invoice)       // same completion again: nothing new
        let r2 = visit(&d, s, storm: "S2", day: 5)
        let second = d.autoInvoice(afterVisit: r2, now: t0 + 5 * 86_400, calendar: utc)
        XCTAssertEqual(second.invoice?.lines.map { $0.stormID }, ["S2"])
        XCTAssertEqual(d.invoices.count, 2)
        XCTAssertEqual(d.invoices[1].number, "INV-0002")
    }

    func testAReturnTripUpdatesTheUnsentDraftInsteadOfBeingLost() throws {
        var (d, s) = world(mode: .draft, terms: .perPush(rate: Money(dollars: 50), counting: .perVisit))
        let r1 = visit(&d, s, storm: "S1", day: 0)
        XCTAssertEqual(d.autoInvoice(afterVisit: r1, now: t0, calendar: utc).invoice?.total, Money(dollars: 50))
        let r2 = visit(&d, s, storm: "S1", day: 0.1)                                           // every visit is a push
        let again = d.autoInvoice(afterVisit: r2, now: t0 + 8_640, calendar: utc)
        XCTAssertEqual(again.invoice?.number, "INV-0001")                                      // the same draft, not a second invoice
        XCTAssertTrue(again.note.contains("updated"))
        XCTAssertEqual(d.invoices.count, 1)
        XCTAssertEqual(d.invoices[0].total, Money(dollars: 100))
        XCTAssertEqual(d.invoices[0].lines.count, 1)
        // Once the invoice has gone to the client it is never changed.
        try d.markInvoiceSent(number: "INV-0001", at: t0 + 9_000)
        let r3 = visit(&d, s, storm: "S1", day: 0.2)
        XCTAssertNil(d.autoInvoice(afterVisit: r3, now: t0 + 17_280, calendar: utc).invoice)
        XCTAssertEqual(d.invoices[0].total, Money(dollars: 100))
    }

    func testTheEmailAsksForTheBalanceOnceSomethingIsPaid() throws {
        var (d, s) = world(mode: .draft)
        let r = visit(&d, s, storm: "S1", day: 0)
        _ = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        try d.invoices[0].record(ManualPayment(amount: Money(dollars: 20), date: t0, method: .cash))
        guard case .ready(let m) = d.invoiceEmail(number: "INV-0001", calendar: utc) else { return XCTFail("expected an email") }
        XCTAssertTrue(m.body.contains("Balance due: $40.00 by Jan 29, 2027 (total $60.00, paid so far $20.00)."))
        XCTAssertFalse(m.body.contains("Total due"))
        XCTAssertTrue(m.subject.contains("$40.00")); XCTAssertFalse(m.subject.contains("$60.00"))
    }

    func testSeasonalContractsAreNotBilledAtStopCompletion() {
        var (d, s) = world(mode: .send, terms: .seasonal(total: Money(dollars: 900)))
        let r = visit(&d, s, storm: "S1", day: 0)
        let out = d.autoInvoice(afterVisit: r, now: t0, calendar: utc)
        XCTAssertNil(out.invoice)                                      // the season base is not billed at the first push
        XCTAssertTrue(d.invoices.isEmpty)
    }

    func testHybridBillsOnlyPushesOverTheCap() {
        var (d, s) = world(mode: .draft, terms: .hybrid(seasonalBase: Money(dollars: 500), includedPushes: 2, overagePerPush: Money(dollars: 40)))
        let r1 = visit(&d, s, storm: "S1", day: 0)
        XCTAssertNil(d.autoInvoice(afterVisit: r1, now: t0, calendar: utc).invoice)            // inside the cap
        let r2 = visit(&d, s, storm: "S2", day: 3)
        XCTAssertNil(d.autoInvoice(afterVisit: r2, now: t0, calendar: utc).invoice)
        let r3 = visit(&d, s, storm: "S3", day: 6)
        let over = d.autoInvoice(afterVisit: r3, now: t0, calendar: utc)
        XCTAssertEqual(over.invoice?.total, Money(dollars: 40))                                // only the third push, and no base fee
    }

    func testNoContractMeansNoInvoice() {
        var (d, s) = world(mode: .draft)
        d.contracts = []
        let r = visit(&d, s, storm: "S1", day: 0)
        XCTAssertNil(d.autoInvoice(afterVisit: r, now: t0, calendar: utc).invoice)
    }

    func testMessageWithoutPortalOrPaymentTextStillReads() {
        var (d, s) = world(mode: .send)
        d.broadcastSettings.portalBaseURL = ""
        d.profile.paymentInstructions = ""
        let r = visit(&d, s, storm: "S1", day: 0)
        let m = d.autoInvoice(afterVisit: r, now: t0, calendar: utc).message
        XCTAssertNotNil(m)
        XCTAssertFalse(m!.body.contains("How to pay"))
        XCTAssertFalse(m!.body.contains("https://"))
    }

    func testHostileAddressCannotBreakTheSubject() {
        var (d, s) = world(mode: .send)
        d.companyName = "Ridge\r\nBcc: x@y.com"
        let r = visit(&d, s, storm: "S1", day: 0)
        let m = d.autoInvoice(afterVisit: r, now: t0, calendar: utc).message
        XCTAssertFalse(m!.subject.contains("\n")); XCTAssertFalse(m!.subject.contains("\r"))
    }
}
