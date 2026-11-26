import XCTest
@testable import RidgelineCore

final class StormModeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let stormName = "Nov 21"

    /// A business with one site per contract, all on the map.
    private func business(_ list: [(trigger: Double, priority: Int, terms: ContractTerms?)]) -> AppData {
        var d = AppData()
        for (i, item) in list.enumerated() {
            let c = Customer(name: "Client \(i)")
            let s = Site(customerID: c.id, address: "\(i + 1) Main St", latitude: 45 + Double(i) * 0.01, longitude: -93,
                         priority: item.priority, triggerInches: item.trigger)
            d.customers.append(c)
            d.sites.append(s)
            if let terms = item.terms { d.contracts.append(SnowContract(siteID: s.id, season: "2026-27", terms: terms)) }
        }
        return d
    }

    private func visit(_ site: Site, storm: String? = nil, status: VisitStatus = .completed, depth: Double = 4,
                       material: MaterialType? = nil, amount: Double? = nil, salt: Double = 0, at: Date? = nil) -> VisitRecord {
        let start = at ?? t0.addingTimeInterval(1800)
        return VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: storm ?? stormName, arrival: start,
                           departure: start.addingTimeInterval(3600), status: status, snowDepthInches: depth,
                           saltPounds: salt, material: material, materialAmount: amount)
    }

    private let perPush = ContractTerms.perPush(rate: Money(dollars: 55))

    // MARK: picking sites

    func testSuggestsEverySiteWhoseTriggerIsAtOrBelowTheExpectedSnow() {
        let d = business([(3, 3, nil), (1, 2, nil), (2, 1, nil), (4, 1, nil)])
        let picked = StormMode.suggestedSites(data: d, inches: 2, stormName: stormName)
        XCTAssertEqual(picked.map(\.triggerInches), [2, 1])             // most important first
        XCTAssertEqual(StormMode.suggestedSites(data: d, inches: 0.5, stormName: stormName).count, 0)
        XCTAssertEqual(StormMode.suggestedSites(data: d, inches: 4, stormName: stormName).count, 4)
    }

    func testAcceptedSkipRequestIsNotSuggested() throws {
        var d = business([(1, 3, nil), (1, 3, nil)])
        var skip = ServiceRequest(siteID: d.sites[0].id, kind: .skip, createdAt: t0)
        try skip.decide(accept: true, message: "", at: t0)
        d.serviceRequests = [skip]
        XCTAssertEqual(StormMode.suggestedSites(data: d, inches: 3, stormName: stormName).map(\.id), [d.sites[1].id])
    }

    func testPrefillUsesTheForecastRoundedToHalfInches() {
        XCTAssertEqual(StormMode.prefillInches(forecast: 3.3, fallback: 2), 3.5)
        XCTAssertEqual(StormMode.prefillInches(forecast: 3.2, fallback: 2), 3.0)
        XCTAssertEqual(StormMode.prefillInches(forecast: nil, fallback: 2), 2)
        XCTAssertEqual(StormMode.prefillInches(forecast: -1, fallback: 2), 2)
        XCTAssertEqual(StormMode.prefillInches(forecast: 80, fallback: 2), 36)
    }

    func testForecastSaysSnowOnceTheLowestTriggerIsReachedOrAnAlertIsOut() {
        let sites = business([(2, 3, nil), (3, 3, nil)]).sites
        XCTAssertFalse(StormMode.forecastSaysSnow(forecastInches: 1.5, hasWinterAlert: false, sites: sites))
        XCTAssertTrue(StormMode.forecastSaysSnow(forecastInches: 2, hasWinterAlert: false, sites: sites))
        XCTAssertTrue(StormMode.forecastSaysSnow(forecastInches: nil, hasWinterAlert: true, sites: sites))
        XCTAssertFalse(StormMode.forecastSaysSnow(forecastInches: 5, hasWinterAlert: false, sites: []))
        let low = business([(0.1, 3, nil)]).sites
        XCTAssertFalse(StormMode.forecastSaysSnow(forecastInches: 0.3, hasWinterAlert: false, sites: low))   // a dusting is not a storm
    }

    // MARK: starting

    func testStartMakesTheStormAndOneJobForTodayPerChosenSite() throws {
        var d = business([(1, 3, nil), (2, 2, nil), (6, 3, nil)])
        let chosen = [d.sites[0].id, d.sites[1].id]
        let run = try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: chosen, now: t0)

        XCTAssertEqual(run.stormName, stormName)
        XCTAssertEqual(d.storms.map(\.name), [stormName])
        XCTAssertEqual(d.storms[0].forecastInches, 3)
        XCTAssertEqual(run.siteIDs, [d.sites[1].id, d.sites[0].id])     // priority order
        XCTAssertEqual(d.jobs.count, 2)
        XCTAssertTrue(d.jobs.allSatisfy { $0.kind == .snowPlowing && $0.status == .scheduled && !$0.isTask })
        XCTAssertEqual(Set(d.jobs.compactMap(\.siteID)), Set(chosen))
        XCTAssertEqual(Set(run.jobIDs), Set(d.jobs.map(\.id)))
        XCTAssertEqual(d.jobs(on: t0).count, 2)                         // calendar
        XCTAssertEqual(d.routeStops(on: t0).count, 2)                   // map and route
        XCTAssertEqual(d.activeStormRun, run)
        XCTAssertTrue(d.customerName(forJob: d.jobs[0]).hasPrefix("Client"))
    }

    func testCannotStartWithNoSitesOrWhileAStormIsRunning() throws {
        var d = business([(1, 3, nil)])
        XCTAssertThrowsError(try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: [], now: t0)) {
            XCTAssertEqual($0 as? StormModeError, .noSitesChosen)
        }
        XCTAssertThrowsError(try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: [UUID()], now: t0))
        XCTAssertTrue(d.storms.isEmpty && d.jobs.isEmpty && d.stormRuns.isEmpty)   // a failed start changes nothing
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: [d.sites[0].id], now: t0)
        XCTAssertThrowsError(try d.startStorm(baseName: "Other", expectedInches: 3, siteIDs: [d.sites[0].id], now: t0)) {
            XCTAssertEqual($0 as? StormModeError, .stormAlreadyActive)
        }
        XCTAssertEqual(d.jobs.count, 1)
    }

    func testStartKeepsAStormAlreadySetUpButNeverReusesAFinishedOne() throws {
        var d = business([(1, 3, nil)])
        let messaged = StormEvent(name: stormName, start: t0, forecastInches: 1)
        d.storms = [messaged]
        let first = try d.startStorm(baseName: stormName, expectedInches: 4, siteIDs: [d.sites[0].id], now: t0)
        XCTAssertEqual(first.stormID, messaged.id)                       // keeps its message log
        XCTAssertEqual(d.storms.count, 1)
        try d.finishStorm(now: t0.addingTimeInterval(7200))
        let second = try d.startStorm(baseName: stormName, expectedInches: 4, siteIDs: [d.sites[0].id], now: t0.addingTimeInterval(9000))
        XCTAssertEqual(second.stormName, "\(stormName) (2)")
        XCTAssertNotEqual(second.stormID, messaged.id)
    }

    // MARK: progress

    func testProgressCountsDoneAndSkippedSites() throws {
        var d = business([(1, 3, nil), (1, 3, nil), (1, 3, nil), (1, 3, nil)])
        let run = try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        XCTAssertEqual(StormMode.progress(run: run, data: d).text, "0 of 4 done")

        d.visitLog.append(visit(d.sites[0]))
        d.visitLog.append(visit(d.sites[1], status: .skipped(reason: "Gate locked")))
        d.visitLog.append(visit(d.sites[3], storm: "Earlier storm"))     // another storm does not count
        let jobC = d.jobs.first { $0.siteID == d.sites[2].id }!
        try d.setJobStatus(.done, id: jobC.id)                           // marked done on the job instead

        let p = StormMode.progress(run: run, data: d)
        XCTAssertEqual(p.total, 4)
        XCTAssertEqual(p.done, 2)
        XCTAssertEqual(p.skipped, 1)
        XCTAssertEqual(p.remaining, 1)
        XCTAssertFalse(p.isComplete)
        XCTAssertEqual(p.text, "2 of 4 done")

        d.visitLog.append(visit(d.sites[1]))                             // came back and got it done
        XCTAssertEqual(StormMode.progress(run: run, data: d).done, 3)
    }

    func testACompletedVisitMarksTheStormJobDoneSoItLeavesTheRoute() throws {
        var d = business([(1, 3, nil), (1, 3, nil)])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        d.markStormJobDone(after: visit(d.sites[0], status: .skipped(reason: "Car in the way")))
        d.markStormJobDone(after: visit(d.sites[1], storm: "Some other storm"))
        XCTAssertEqual(d.routeStops(on: t0).count, 2)
        d.markStormJobDone(after: visit(d.sites[0]))
        XCTAssertEqual(d.jobs.first { $0.siteID == d.sites[0].id }?.status, .done)
        XCTAssertEqual(d.routeStops(on: t0).count, 1)
    }

    // MARK: finishing

    func testSummaryAddsUpPushesDepthAndMaterial() throws {
        var d = business([(1, 3, nil), (1, 3, nil), (1, 3, nil)])
        let run = try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        d.visitLog.append(visit(d.sites[0], depth: 3, material: .rockSalt, amount: 200))
        d.visitLog.append(visit(d.sites[0], depth: 5, material: .rockSalt, amount: 100))
        d.visitLog.append(visit(d.sites[1], depth: 4, material: .liquidBrine, amount: 20))
        d.visitLog.append(visit(d.sites[1], depth: 0, salt: 50))         // older visit with salt pounds only, depth not entered
        d.visitLog.append(visit(d.sites[1], status: .skipped(reason: "Blocked"), depth: 0))

        let s = StormMode.summary(run: run, data: d)
        XCTAssertEqual(s.pushes, 4)
        XCTAssertEqual(s.skippedVisits, 1)
        XCTAssertEqual(s.sitesServiced, 2)
        XCTAssertEqual(s.sitesPlanned, 3)
        XCTAssertEqual(s.sitesNotVisited, [d.sites[2].id])
        XCTAssertEqual(s.deepestInches, 5)
        XCTAssertEqual(s.averageDepthInches ?? 0, 4, accuracy: 0.001)    // 3, 5, 4: zero depth is "not entered"
        XCTAssertEqual(s.saltPounds, 350)
        XCTAssertEqual(s.materials.map { $0.material }, [MaterialType.rockSalt, MaterialType.liquidBrine])
        XCTAssertEqual(s.materials.map { $0.amount }, [300.0, 20.0])
        XCTAssertEqual(s.materials.last?.text, "Liquid brine: 20 gal")
    }

    func testFinishMakesDraftInvoicesByContractType() throws {
        var d = business([
            (1, 3, perPush),                                                                   // 0: per push, one per storm
            (1, 3, .perPush(rate: Money(dollars: 50), counting: .perVisit)),                   // 1: every visit a push
            (1, 3, .perInch(tiers: [DepthTier(minInches: 3, rate: Money(dollars: 120)),
                                    DepthTier(minInches: 8, rate: Money(dollars: 200))])),     // 2: by depth
            (1, 3, .seasonal(total: Money(dollars: 1400))),                                    // 3: seasonal
            (1, 3, .hybrid(seasonalBase: Money(dollars: 900), includedPushes: 8, overagePerPush: Money(dollars: 85))), // 4: inside cap
            (1, 3, .timeAndMaterials(hourly: Money(dollars: 110), materialsMarkupPercent: 15)), // 5: one hour
            (1, 3, nil),                                                                        // 6: no contract
        ])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        for site in d.sites { d.visitLog.append(visit(site, depth: 5)) }
        d.visitLog.append(visit(d.sites[0], depth: 6))
        d.visitLog.append(visit(d.sites[1], depth: 6))

        let result = try d.finishStorm(now: t0.addingTimeInterval(10_000))
        let o = result.invoices
        XCTAssertEqual(o.created.count, 4)
        XCTAssertEqual(o.nothingToBill, [d.sites[3].id, d.sites[4].id])
        XCTAssertEqual(o.noContract, [d.sites[6].id])
        XCTAssertTrue(o.alreadyInvoiced.isEmpty)
        func billed(_ i: Int) -> Money? { d.invoices.first { $0.siteID == d.sites[i].id }?.total }
        XCTAssertEqual(billed(0), Money(dollars: 55))
        XCTAssertEqual(billed(1), Money(dollars: 100))
        XCTAssertEqual(billed(2), Money(dollars: 120))
        XCTAssertEqual(billed(5), Money(dollars: 110))
        XCTAssertNil(billed(3))
        XCTAssertEqual(o.total, Money(dollars: 385))
        XCTAssertTrue(d.invoices.allSatisfy { $0.status(now: t0) == .draft })
        XCTAssertTrue(d.invoices.allSatisfy { inv in inv.lines.allSatisfy { $0.stormID == self.stormName } })
        XCTAssertEqual(Set(d.invoices.map(\.number)).count, 4)
        XCTAssertEqual(d.stormRuns.last?.invoiceNumbers, o.created)
    }

    func testFinishNeverBillsASiteAlreadyInvoicedForThisStorm() throws {
        var d = business([(1, 3, perPush), (1, 3, perPush)])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        let first = visit(d.sites[0])
        d.visitLog.append(first)
        XCTAssertNotNil(d.autoInvoice(afterVisit: first, now: t0).invoice)   // drafted automatically after the visit
        d.visitLog.append(visit(d.sites[0]))                                  // a return trip, same storm
        d.visitLog.append(visit(d.sites[1]))

        let o = try d.finishStorm(now: t0.addingTimeInterval(10_000)).invoices
        XCTAssertEqual(o.alreadyInvoiced, [d.sites[0].id])
        XCTAssertEqual(o.created.count, 1)
        XCTAssertEqual(d.invoices.filter { $0.siteID == d.sites[0].id }.count, 1)
        XCTAssertEqual(d.invoices.count, 2)
    }

    func testBillingTheSameStormTwiceMakesNothingNew() {
        var d = business([(1, 3, perPush)])
        d.visitLog.append(visit(d.sites[0]))
        XCTAssertEqual(d.billStorm(named: stormName, now: t0).created.count, 1)
        let again = d.billStorm(named: stormName, now: t0)
        XCTAssertTrue(again.created.isEmpty)
        XCTAssertEqual(again.alreadyInvoiced, [d.sites[0].id])
        XCTAssertEqual(d.invoices.count, 1)
    }

    func testAVoidedInvoiceDoesNotBlockBillingTheStorm() {
        var d = business([(1, 3, perPush)])
        d.visitLog.append(visit(d.sites[0]))
        d.billStorm(named: stormName, now: t0)
        d.invoices[0].void()
        XCTAssertEqual(d.billStorm(named: stormName, now: t0).created.count, 1)
    }

    func testHybridCountsPushesFromEarlierStormsTowardTheCap() {
        var d = business([(1, 3, .hybrid(seasonalBase: Money(dollars: 900), includedPushes: 1, overagePerPush: Money(dollars: 85)))])
        d.visitLog.append(visit(d.sites[0], storm: "Nov 2", at: t0.addingTimeInterval(-86_400 * 19)))
        d.visitLog.append(visit(d.sites[0]))
        let o = d.billStorm(named: stormName, now: t0)
        XCTAssertEqual(o.total, Money(dollars: 85))
        XCTAssertFalse(d.invoices[0].lines.contains { $0.stormID == nil })   // the seasonal base is never billed here
        XCTAssertFalse(d.invoices[0].lines.contains { $0.stormID == "Nov 2" })   // only this storm
    }

    func testFinishEndsTheStormAndClosesJobsAtSitesNobodyServiced() throws {
        var d = business([(1, 3, perPush), (1, 3, perPush), (1, 3, perPush)])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        d.visitLog.append(visit(d.sites[0], depth: 7))
        d.visitLog.append(visit(d.sites[2], status: .skipped(reason: "Gate locked")))
        let end = t0.addingTimeInterval(10_000)
        try d.finishStorm(now: end)

        XCTAssertNil(d.activeStormRun)
        XCTAssertEqual(d.stormRuns.last?.finishedAt, end)
        XCTAssertEqual(d.jobs.first { $0.siteID == d.sites[0].id }?.status, .done)
        // No visit, or only a skipped one: the storm is over, so the job no longer waits on the schedule or the route.
        XCTAssertEqual(d.jobs.first { $0.siteID == d.sites[1].id }?.status, .cancelled)
        XCTAssertEqual(d.jobs.first { $0.siteID == d.sites[2].id }?.status, .cancelled)
        XCTAssertTrue(d.routeStops(on: t0).isEmpty)
        XCTAssertEqual(d.storms.first?.actualInches, 7)
        XCTAssertThrowsError(try d.finishStorm(now: end)) { XCTAssertEqual($0 as? StormModeError, .noActiveStorm) }
    }

    func testPreviewShowsTheFinishWithoutChangingAnything() throws {
        var d = business([(1, 3, perPush)])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        d.visitLog.append(visit(d.sites[0]))
        let before = d
        let preview = d.previewFinishStorm(now: t0)
        XCTAssertEqual(preview?.invoices.created.count, 1)
        XCTAssertEqual(preview?.summary.pushes, 1)
        XCTAssertEqual(d, before)
        XCTAssertNil(AppData().previewFinishStorm(now: t0))
    }

    // MARK: saving

    func testStormsInProgressAreSavedAndOldFilesStillLoad() throws {
        var d = business([(1, 3, perPush)])
        try d.startStorm(baseName: stormName, expectedInches: 3, siteIDs: d.sites.map(\.id), now: t0)
        let loaded = try FileStore.decoder.decode(AppData.self, from: FileStore.encoder.encode(d))
        XCTAssertEqual(loaded.stormRuns, d.stormRuns)
        XCTAssertEqual(loaded.activeStormRun?.stormName, stormName)
        let old = try FileStore.decoder.decode(AppData.self, from: Data(#"{"companyName":"Old"}"#.utf8))
        XCTAssertTrue(old.stormRuns.isEmpty)
    }
}
