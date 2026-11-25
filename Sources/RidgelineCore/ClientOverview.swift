import Foundation

/// What a line in a client's history is about. The screen picks the icon from this.
public enum ClientEventKind: String, Equatable, Sendable, CaseIterable {
    case jobDone, jobScheduled, invoiceCreated, invoicePaid, visitLogged, requestReceived, reviewAsked
}

/// One thing that happened with a client: a job, an invoice, a visit, a request.
public struct ClientEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ClientEventKind
    public let date: Date
    public let title: String
    public let detail: String
    /// Set on invoice lines, so the screen can open that invoice.
    public let invoiceNumber: String?
    /// Photos taken on a logged visit. Zero for everything else.
    public let photoCount: Int

    public init(id: String, kind: ClientEventKind, date: Date, title: String, detail: String = "",
                invoiceNumber: String? = nil, photoCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
        self.invoiceNumber = invoiceNumber
        self.photoCount = photoCount
    }
}

/// A proof photo taken at one of the client's properties.
public struct ClientPhoto: Identifiable, Equatable, Sendable {
    public var id: String { ref.filename }
    public let ref: PhotoRef
    public let siteID: UUID
    public let address: String
}

/// Everything about one client, worked out once: money, service dates, counts, photos and history.
public struct ClientOverview: Equatable, Sendable {
    public let customerID: UUID
    /// Unpaid invoices that were sent (not drafts, not void), including the overdue ones.
    public let balanceOwed: Money
    /// The part of `balanceOwed` that is past its due date.
    public let overdueAmount: Money
    /// Payments received this calendar year.
    public let paidThisYear: Money
    /// Invoices created but not sent yet. They are not counted as owed.
    public let draftTotal: Money
    public let unpaidInvoiceCount: Int
    public let overdueInvoiceCount: Int
    public let draftInvoiceCount: Int
    /// This client's invoices, newest first. Empty for someone who may not see revenue.
    public let invoices: [Invoice]
    /// The latest finished job visit or completed logged visit, never in the future.
    public let lastServiceDate: Date?
    /// The next open job from today on. For a repeating job this is its next visit.
    public let nextJob: Job?
    /// Open jobs, soonest first. A repeating job shows up once, as its next open visit.
    public let upcomingJobs: [Job]
    public let siteCount: Int
    public let visitCount: Int
    /// Proof photos from logged visits, newest first.
    public let photos: [ClientPhoto]
    /// Everything that happened, newest first.
    public let timeline: [ClientEvent]

    public var isOverdue: Bool { overdueAmount.cents > 0 }
    public var openJobCount: Int { upcomingJobs.count }
    public var invoiceCount: Int { invoices.count }
    public var photoCount: Int { photos.count }
}

public enum ClientProfileError: Error, Equatable, Sendable {
    case emptyAddress
    case duplicateAddress

    public var message: String {
        switch self {
        case .emptyAddress: return "Type the address first."
        case .duplicateAddress: return "This client already has that address."
        }
    }
}

extension Job {
    /// Turns a visit key like "2027-01-15" back into that day. Nil when the text is not a day.
    static func day(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The first visit on or after `day` that is still open (not done, not skipped). Nil when there is none soon.
    func nextOpenVisit(onOrAfter day: Date, calendar: Calendar) -> Job? {
        guard repeats else {
            let upcoming = status.isOpen && calendar.startOfDay(for: start) >= calendar.startOfDay(for: day)
            return upcoming ? self : nil
        }
        guard status != .cancelled else { return nil }
        var cursor = day
        for _ in 0..<60 {
            guard let at = nextOccurrence(onOrAfter: cursor, calendar: calendar) else { return nil }
            if let visit = occurrence(on: at, calendar: calendar), visit.status.isOpen { return visit }
            guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: at)) else { return nil }
            cursor = dayAfter
        }
        return nil
    }
}

extension AppData {
    /// The whole picture for one client. Nil when the client no longer exists.
    /// Money is left out for someone who may not see revenue, and requests for someone who may not see requests.
    public func clientOverview(customerID: UUID, now: Date, calendar: Calendar = .current) -> ClientOverview? {
        guard let customer = customers.first(where: { $0.id == customerID }) else { return nil }
        let mySites = sites.filter { $0.customerID == customerID }
        let siteIDs = Set(mySites.map(\.id))
        var addressBySite: [UUID: String] = [:]
        for s in mySites { addressBySite[s.id] = s.address }
        var events: [ClientEvent] = []

        // Money
        let myInvoices = can(.viewRevenue) ? invoices.filter { $0.customerID == customerID || siteIDs.contains($0.siteID) } : []
        let thisYear = calendar.component(.year, from: now)
        var balance = Money.zero, overdue = Money.zero, paidYear = Money.zero, drafts = Money.zero
        var unpaidCount = 0, overdueCount = 0, draftCount = 0
        for inv in myInvoices {
            let status = inv.status(now: now)
            switch status {
            case .sent, .partiallyPaid:
                balance = balance + inv.balance
                unpaidCount += 1
            case .overdue:
                balance = balance + inv.balance
                overdue = overdue + inv.balance
                unpaidCount += 1
                overdueCount += 1
            case .draft:
                drafts = drafts + inv.total
                draftCount += 1
            case .paid, .void:
                break
            }
            events.append(ClientEvent(id: "invoice-\(inv.id.uuidString)", kind: .invoiceCreated, date: inv.issueDate,
                                      title: "Invoice \(inv.number) created",
                                      detail: inv.total.formatted + (status == .void ? " · void" : (status == .draft ? " · not sent yet" : "")),
                                      invoiceNumber: inv.number))
            guard !inv.isVoid else { continue }
            var received = Money.zero
            for p in inv.payments.sorted(by: { $0.date < $1.date }) {
                received = received + p.amount
                if calendar.component(.year, from: p.date) == thisYear { paidYear = paidYear + p.amount }
                let cleared = received >= inv.total
                events.append(ClientEvent(id: "payment-\(p.id.uuidString)", kind: .invoicePaid, date: p.date,
                                          title: cleared ? "Invoice \(inv.number) paid in full" : "Payment on invoice \(inv.number)",
                                          detail: p.amount.formatted + Self.paymentMethodText(p.method),
                                          invoiceNumber: inv.number))
            }
        }

        // Jobs
        let myJobs = visibleJobs.filter { job in
            !job.isTask && (job.customerID == customerID || (job.siteID.map { siteIDs.contains($0) } ?? false))
        }
        let today = calendar.startOfDay(for: now)
        let whenText = DateFormatter()
        whenText.dateStyle = .medium
        whenText.timeStyle = .short
        whenText.timeZone = calendar.timeZone
        var lastService: Date?
        var upcoming: [Job] = []
        for job in myJobs {
            let place = job.siteID.flatMap { addressBySite[$0] } ?? ""
            var doneDates: [(key: String, date: Date)] = []
            if job.repeats {
                for (key, status) in job.occurrenceStatuses ?? [:] where status == .done {
                    guard let day = Job.day(fromKey: key, calendar: calendar) else { continue }
                    doneDates.append((key, job.occurrenceStart(on: day, calendar: calendar) ?? day))
                }
            } else if job.status == .done {
                doneDates.append(("once", job.start))
            }
            for done in doneDates {
                let when = min(done.date, now)          // a job finished ahead of time still counts as done by now
                if when > (lastService ?? .distantPast) { lastService = when }
                events.append(ClientEvent(id: "job-done-\(job.id.uuidString)-\(done.key)", kind: .jobDone, date: when,
                                          title: "Job done: \(job.title)", detail: place))
            }
            // A job that does not repeat stays on the list until someone finishes it, even when its day has passed.
            let openVisit: Job? = job.repeats ? job.nextOpenVisit(onOrAfter: today, calendar: calendar) : (job.status.isOpen ? job : nil)
            if let openVisit { upcoming.append(openVisit) }
            if job.status != .cancelled {
                var parts = ["For \(whenText.string(from: job.start))"]
                if let rule = job.repeatRule, rule.repeats { parts.append(rule.summary.lowercased()) }
                if !place.isEmpty { parts.append(place) }
                events.append(ClientEvent(id: "job-scheduled-\(job.id.uuidString)", kind: .jobScheduled, date: job.createdAt,
                                          title: "Job scheduled: \(job.title)", detail: parts.joined(separator: " · ")))
            }
        }
        upcoming.sort { $0.start != $1.start ? $0.start < $1.start : $0.id.uuidString < $1.id.uuidString }

        // Logged visits and their photos
        var visitCount = 0
        var photos: [ClientPhoto] = []
        if !siteIDs.isEmpty {
            for entry in visitLog.entries where siteIDs.contains(entry.record.siteID) {
                let r = entry.record
                let place = addressBySite[r.siteID] ?? ""
                visitCount += 1
                var parts: [String] = []
                var title = "Visit logged"
                if case .skipped(let reason) = r.status {
                    title = "Visit skipped"
                    if !reason.isEmpty { parts.append(reason) }
                } else {
                    let finished = min(r.departure ?? r.arrival, now)
                    if finished > (lastService ?? .distantPast) { lastService = finished }
                }
                if !place.isEmpty { parts.append(place) }
                if !r.crewMemberName.isEmpty { parts.append("by \(r.crewMemberName)") }
                if !r.photos.isEmpty { parts.append(r.photos.count == 1 ? "1 photo" : "\(r.photos.count) photos") }
                events.append(ClientEvent(id: "visit-\(r.id.uuidString)", kind: .visitLogged, date: r.arrival, title: title,
                                          detail: parts.joined(separator: " · "), photoCount: r.photos.count))
                for ref in r.photos { photos.append(ClientPhoto(ref: ref, siteID: r.siteID, address: place)) }
            }
        }
        photos.sort { $0.ref.capturedAt != $1.ref.capturedAt ? $0.ref.capturedAt > $1.ref.capturedAt : $0.ref.filename < $1.ref.filename }

        // Requests from the client's page
        if can(.viewRequests), !siteIDs.isEmpty {
            for r in serviceRequests where siteIDs.contains(r.siteID) {
                var parts: [String] = []
                if !r.note.isEmpty { parts.append(r.note) }
                if r.kind != .thanks {
                    switch r.status {
                    case .pending: parts.append("waiting for your answer")
                    case .accepted: parts.append("accepted")
                    case .declined: parts.append("declined")
                    }
                }
                if let place = addressBySite[r.siteID], !place.isEmpty, mySites.count > 1 { parts.append(place) }
                events.append(ClientEvent(id: "request-\(r.id.uuidString)", kind: .requestReceived, date: r.createdAt,
                                          title: Self.requestTitle(r.kind), detail: parts.joined(separator: " · ")))
            }
        }

        if let asked = customer.reviewAskedAt {
            events.append(ClientEvent(id: "review-\(customerID.uuidString)", kind: .reviewAsked, date: asked, title: "Asked for a review"))
        }

        events.sort { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        return ClientOverview(customerID: customerID, balanceOwed: balance, overdueAmount: overdue, paidThisYear: paidYear,
                              draftTotal: drafts, unpaidInvoiceCount: unpaidCount, overdueInvoiceCount: overdueCount,
                              draftInvoiceCount: draftCount,
                              invoices: myInvoices.sorted { $0.issueDate != $1.issueDate ? $0.issueDate > $1.issueDate : $0.number > $1.number },
                              lastServiceDate: lastService,
                              nextJob: upcoming.first { $0.start >= today },
                              upcomingJobs: upcoming, siteCount: mySites.count, visitCount: visitCount,
                              photos: photos, timeline: events)
    }

    static func paymentMethodText(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: return " by cash"
        case .check: return " by check"
        case .card: return " by card"
        case .bankTransfer: return " by bank transfer"
        case .other: return ""
        }
    }

    static func requestTitle(_ kind: RequestKind) -> String {
        switch kind {
        case .service: return "Asked for service"
        case .urgent: return "Asked to be done first"
        case .skip: return "Asked to skip a storm"
        case .thanks: return "Sent a thank-you"
        }
    }

    // MARK: changes made on the client profile

    /// Adds another property for a client, with its private page link. The same address twice is refused.
    @discardableResult
    public mutating func addSite(customerID: UUID, address: String, coordinate: Coordinate? = nil, now: Date) throws -> Site {
        guard customers.contains(where: { $0.id == customerID }) else { throw OperationError.notFound }
        let clean = String(address.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !clean.isEmpty else { throw ClientProfileError.emptyAddress }
        let wanted = Self.normalizedAddress(clean)
        guard !sites.contains(where: { $0.customerID == customerID && Self.normalizedAddress($0.address) == wanted }) else {
            throw ClientProfileError.duplicateAddress
        }
        let site = Site(customerID: customerID, address: clean, latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                        triggerInches: profile.defaultTriggerInches)
        sites.append(site)
        ensurePortalLinks(now: now)
        return site
    }

    /// Changes a property's address. A map location belongs to the address it was found for, so a new address
    /// without a new location clears the old one. The same address keeps its location.
    public mutating func updateSiteAddress(siteID: UUID, address: String, coordinate: Coordinate? = nil) throws {
        guard let i = sites.firstIndex(where: { $0.id == siteID }) else { throw OperationError.notFound }
        let clean = String(address.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !clean.isEmpty else { throw ClientProfileError.emptyAddress }
        let wanted = Self.normalizedAddress(clean)
        let owner = sites[i].customerID
        guard !sites.contains(where: { $0.id != siteID && $0.customerID == owner && Self.normalizedAddress($0.address) == wanted }) else {
            throw ClientProfileError.duplicateAddress
        }
        let sameAddress = Self.normalizedAddress(sites[i].address) == wanted
        sites[i].address = clean
        if let coordinate {
            sites[i].latitude = coordinate.latitude
            sites[i].longitude = coordinate.longitude
        } else if !sameAddress {
            sites[i].latitude = nil
            sites[i].longitude = nil
        }
    }

    /// Saves the standing instructions the crew sees at a property (gate code, where to pile snow).
    public mutating func setSiteInstructions(siteID: UUID, instructions: String) throws {
        guard let i = sites.firstIndex(where: { $0.id == siteID }) else { throw OperationError.notFound }
        sites[i].instructions = String(instructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
    }

    /// Saves the owner's private notes about a client.
    public mutating func setCustomerNotes(customerID: UUID, notes: String) throws {
        guard let i = customers.firstIndex(where: { $0.id == customerID }) else { throw OperationError.notFound }
        customers[i].notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }
}
