import Foundation

/// One storm started with Storm mode: which sites the crew covers, the jobs made for them, and when it was finished.
/// Visits are tied to the storm by `stormName` (the same text the crew logs under, see `VisitRecord.stormID`).
public struct StormRun: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var stormID: UUID
    public var stormName: String
    public var startedAt: Date
    public var expectedInches: Double
    public var siteIDs: [UUID]
    public var jobIDs: [UUID]
    public var finishedAt: Date?
    /// Draft invoices made when the storm was finished.
    public var invoiceNumbers: [String]

    public init(id: UUID = UUID(), stormID: UUID, stormName: String, startedAt: Date, expectedInches: Double,
                siteIDs: [UUID], jobIDs: [UUID], finishedAt: Date? = nil, invoiceNumbers: [String] = []) {
        self.id = id
        self.stormID = stormID
        self.stormName = stormName
        self.startedAt = startedAt
        self.expectedInches = expectedInches
        self.siteIDs = siteIDs
        self.jobIDs = jobIDs
        self.finishedAt = finishedAt
        self.invoiceNumbers = invoiceNumbers
    }

    public var isActive: Bool { finishedAt == nil }
}

public enum StormModeError: Error, Equatable {
    case stormAlreadyActive
    case noSitesChosen
    case noActiveStorm
}

/// How far the crew is through the storm's sites.
public struct StormProgress: Equatable, Sendable {
    public let total: Int
    /// Sites with a completed visit this storm, or whose storm job was marked done.
    public let done: Int
    /// Sites the crew could not service (skipped visit or cancelled job) and that are not done.
    public let skipped: Int

    public var remaining: Int { max(total - done - skipped, 0) }
    public var isComplete: Bool { total > 0 && remaining == 0 }
    /// "7 of 18 done"
    public var text: String { "\(done) of \(total) done" }
}

/// What was spread during the storm, added up per material.
public struct MaterialTotal: Equatable, Sendable {
    public let material: MaterialType
    public let amount: Double
    public var text: String { "\(material.title): \(MaterialFormat.amount(amount, unit: material.unit))" }
}

/// What the crew logged during one storm.
public struct StormSummary: Equatable, Sendable {
    public let stormName: String
    public let sitesPlanned: Int
    /// Different sites with at least one completed visit (planned or not).
    public let sitesServiced: Int
    /// Completed visits. Each one is a push for the crew; contracts decide how many are billed.
    public let pushes: Int
    public let skippedVisits: Int
    /// Planned sites with no visit logged at all.
    public let sitesNotVisited: [UUID]
    public let deepestInches: Double?
    public let averageDepthInches: Double?
    /// Salt in pounds, including older visits that only recorded salt pounds.
    public let saltPounds: Double
    public let materials: [MaterialTotal]
}

/// The draft invoices a finished storm makes, one per site at most.
public struct StormInvoiceOutcome: Equatable, Sendable {
    public let created: [String]
    public let total: Money
    /// Sites that already have this storm on an invoice (for example made automatically after the visit). Not billed again.
    public let alreadyInvoiced: [UUID]
    /// Sites whose contract has nothing to bill for this storm (seasonal, pushes still inside a hybrid cap, under the lowest depth tier).
    public let nothingToBill: [UUID]
    public let noContract: [UUID]
}

public struct StormFinishResult: Equatable, Sendable {
    public let summary: StormSummary
    public let invoices: StormInvoiceOutcome
}

public enum StormMode {
    /// Sites to tick when a storm starts: every site whose trigger is at or below the expected snow, plus sites with
    /// an accepted service request, minus sites with an accepted skip. Most important first.
    public static func suggestedSites(data: AppData, inches: Double, stormName: String) -> [Site] {
        let stormID = data.storms.first { $0.name == stormName }?.id
        return DispatchRules.effectiveSites(sites: data.sites, inches: inches, stormID: stormID, requests: data.serviceRequests)
    }

    /// Expected snow to start from: the forecast rounded to the nearest half inch, or the fallback when there is no forecast.
    public static func prefillInches(forecast: Double?, fallback: Double) -> Double {
        guard let forecast, forecast.isFinite, forecast >= 0 else { return fallback }
        return min((forecast * 2).rounded() / 2, 36)
    }

    /// True when the forecast reaches the lowest trigger of any site (at least half an inch), or a winter alert is out.
    public static func forecastSaysSnow(forecastInches: Double?, hasWinterAlert: Bool, sites: [Site]) -> Bool {
        if hasWinterAlert { return true }
        guard let inches = forecastInches, !sites.isEmpty else { return false }
        let lowest = sites.map(\.triggerInches).min() ?? 0
        return inches >= max(lowest, 0.5)
    }

    public static func progress(run: StormRun, data: AppData) -> StormProgress {
        let records = data.visitLog.entries.map(\.record).filter { $0.stormID == run.stormName }
        let runJobs = data.jobs.filter { run.jobIDs.contains($0.id) }
        var done = 0, skipped = 0
        for siteID in Set(run.siteIDs) {
            let visits = records.filter { $0.siteID == siteID }
            let jobs = runJobs.filter { $0.siteID == siteID }
            if visits.contains(where: { $0.status == .completed }) || jobs.contains(where: { $0.status == .done }) {
                done += 1
            } else if visits.contains(where: { if case .skipped = $0.status { return true } else { return false } })
                        || jobs.contains(where: { $0.status == .cancelled }) {
                skipped += 1
            }
        }
        return StormProgress(total: Set(run.siteIDs).count, done: done, skipped: skipped)
    }

    public static func summary(run: StormRun, data: AppData) -> StormSummary {
        let records = data.visitLog.entries.map(\.record).filter { $0.stormID == run.stormName }
        let completed = records.filter { $0.status == .completed }
        let depths = completed.map(\.snowDepthInches).filter { $0 > 0 }
        var totals: [MaterialType: Double] = [:]
        var salt = 0.0
        for r in completed {
            if let m = r.material, m != MaterialType.none, let amount = r.materialAmount, amount > 0 {
                totals[m, default: 0] += amount
                if m.isSalt { salt += amount }
            } else if r.material == nil, r.saltPounds > 0 {
                salt += r.saltPounds
            }
        }
        let visited = Set(records.map(\.siteID))
        var seen = Set<UUID>()
        let notVisited = run.siteIDs.filter { !visited.contains($0) && seen.insert($0).inserted }
        return StormSummary(
            stormName: run.stormName,
            sitesPlanned: Set(run.siteIDs).count,
            sitesServiced: Set(completed.map(\.siteID)).count,
            pushes: completed.count,
            skippedVisits: records.count - completed.count,
            sitesNotVisited: notVisited,
            deepestInches: depths.max(),
            averageDepthInches: depths.isEmpty ? nil : depths.reduce(0, +) / Double(depths.count),
            saltPounds: salt,
            materials: MaterialType.allCases.compactMap { m in totals[m].map { MaterialTotal(material: m, amount: $0) } })
    }
}

extension AppData {
    /// The storm the crew is working now, if one was started and not finished.
    public var activeStormRun: StormRun? { stormRuns.last { $0.isActive } }

    /// Starts a storm: saves the storm, makes a job for today at each chosen site (so they show on the map, route and
    /// calendar) and remembers which sites belong to it. Nothing is sent to anyone.
    @discardableResult
    public mutating func startStorm(baseName: String, expectedInches: Double, siteIDs: [UUID], now: Date) throws -> StormRun {
        guard activeStormRun == nil else { throw StormModeError.stormAlreadyActive }
        let wanted = Set(siteIDs)
        let chosen = sites.filter { wanted.contains($0.id) }
            .sorted { ($0.priority, $0.triggerInches, $0.address) < ($1.priority, $1.triggerInches, $1.address) }
        guard !chosen.isEmpty else { throw StormModeError.noSitesChosen }

        var next = self
        let inches = max(0, expectedInches)
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let usedByRuns = Set(next.stormRuns.map(\.stormName))
        let storm: StormEvent
        if !base.isEmpty, !usedByRuns.contains(base), let i = next.storms.firstIndex(where: { $0.name == base }) {
            // The storm was already set up (for example clients were messaged about it), so keep it and its message log.
            next.storms[i].forecastInches = inches
            storm = next.storms[i]
        } else {
            storm = StormEvent(name: StormNaming.uniqueName(base: base, existing: next.storms.map(\.name)), start: now, forecastInches: inches)
            next.storms.append(storm)
        }

        var jobIDs: [UUID] = []
        for site in chosen {
            let hasCustomer = next.customers.contains(where: { $0.id == site.customerID })
            let customer: UUID? = hasCustomer ? site.customerID : nil
            let job = try next.addJob(title: "Plow, storm \(storm.name)", kind: .snowPlowing, customerID: customer, siteID: site.id,
                                      start: now, durationMinutes: 30, notes: site.instructions, now: now)
            jobIDs.append(job.id)
        }
        let run = StormRun(stormID: storm.id, stormName: storm.name, startedAt: now, expectedInches: inches,
                           siteIDs: chosen.map(\.id), jobIDs: jobIDs)
        next.stormRuns.append(run)
        self = next
        return run
    }

    /// Call after a visit is saved: a completed visit during the storm marks that site's storm job done, so it leaves the route.
    public mutating func markStormJobDone(after visit: VisitRecord) {
        guard visit.status == .completed, let run = activeStormRun, run.stormName == visit.stormID else { return }
        for i in jobs.indices where run.jobIDs.contains(jobs[i].id) && jobs[i].siteID == visit.siteID && jobs[i].status.isOpen {
            jobs[i].status = .done
        }
    }

    /// Draft invoices for one storm, using each site's contract. A site that already has this storm on an invoice
    /// (not voided) is left alone, so finishing never bills a storm twice. Seasonal bases are never billed here.
    @discardableResult
    public mutating func billStorm(named stormName: String, now: Date) -> StormInvoiceOutcome {
        var siteOrder: [UUID] = []
        for r in visitLog.entries.map(\.record) where r.stormID == stormName && !siteOrder.contains(r.siteID) {
            siteOrder.append(r.siteID)
        }
        var created: [String] = [], already: [UUID] = [], nothing: [UUID] = [], noContract: [UUID] = []
        var total = Money.zero
        for siteID in siteOrder {
            guard let site = sites.first(where: { $0.id == siteID }) else { continue }
            guard let contract = contracts.last(where: { $0.siteID == siteID }) else { noContract.append(siteID); continue }
            let billedBefore = invoices.contains { inv in
                inv.siteID == siteID && !inv.isVoid && inv.lines.contains { $0.stormID == stormName && !$0.isLateFee }
            }
            if billedBefore { already.append(siteID); continue }
            let all = visitLog.records(forSite: siteID).map { $0.asBillingVisit() }
            let usedBefore = SnowBilling.bill(terms: contract.terms, visits: all.filter { $0.stormID != stormName }, includeSeasonalBase: false).pushesUsed
            let result = SnowBilling.bill(terms: contract.terms, visits: all.filter { $0.stormID == stormName },
                                          includeSeasonalBase: false, alreadyUsedPushes: usedBefore)
            let number = InvoiceNumbering.next(existing: invoices.map(\.number))
            let invoice = Invoice.fromBilling(result, number: number, customerID: site.customerID, siteID: siteID,
                                              issueDate: now, netDays: profile.netDays)
            guard !invoice.lines.isEmpty, invoice.total.cents > 0 else { nothing.append(siteID); continue }
            invoices.append(invoice)
            created.append(number)
            total = total + invoice.total
        }
        return StormInvoiceOutcome(created: created, total: total, alreadyInvoiced: already, nothingToBill: nothing, noContract: noContract)
    }

    /// What finishing the storm would do, without changing anything.
    public func previewFinishStorm(now: Date) -> StormFinishResult? {
        guard let run = activeStormRun else { return nil }
        var copy = self
        return StormFinishResult(summary: StormMode.summary(run: run, data: self), invoices: copy.billStorm(named: run.stormName, now: now))
    }

    /// Ends the active storm: adds up the visits, makes draft invoices, marks visited sites' jobs done and saves the deepest
    /// snow logged as the storm's actual snowfall. Storm jobs at sites nobody serviced are cancelled, so a finished storm
    /// leaves nothing open on the schedule or the route.
    @discardableResult
    public mutating func finishStorm(now: Date) throws -> StormFinishResult {
        guard let index = stormRuns.lastIndex(where: { $0.isActive }) else { throw StormModeError.noActiveStorm }
        let run = stormRuns[index]
        let summary = StormMode.summary(run: run, data: self)
        let outcome = billStorm(named: run.stormName, now: now)
        let serviced = Set(visitLog.entries.map(\.record).filter { $0.stormID == run.stormName && $0.status == .completed }.map(\.siteID))
        for i in jobs.indices where run.jobIDs.contains(jobs[i].id) && jobs[i].status.isOpen {
            if let site = jobs[i].siteID, serviced.contains(site) { jobs[i].status = .done } else { jobs[i].status = .cancelled }
        }
        if let deepest = summary.deepestInches, let s = storms.firstIndex(where: { $0.id == run.stormID }) {
            storms[s].actualInches = deepest
        }
        stormRuns[index].finishedAt = now
        stormRuns[index].invoiceNumbers = outcome.created
        return StormFinishResult(summary: summary, invoices: outcome)
    }
}
