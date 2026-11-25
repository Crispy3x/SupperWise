import Foundation

/// One line of a job's price: a service from the price list (or a typed amount), how many, and the price for one.
public struct JobPriceLine: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: Int
    /// The price for one, in cents.
    public var unitPriceCents: Int

    public init(id: UUID = UUID(), name: String, quantity: Int = 1, unitPrice: Money) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPriceCents = unitPrice.cents
    }

    public var unitPrice: Money { Money(cents: max(unitPriceCents, 0)) }

    /// Quantity times the price for one. Never below zero.
    public var total: Money { unitPrice * min(max(quantity, 0), QuickInvoice.maxQuantity) }

    /// "Lawn mow" for one, "Lawn mow x 2" for more.
    public var label: String { quantity > 1 ? "\(name) x \(quantity)" : name }
}

extension Job {
    /// What one visit of this job costs. Zero when the job has no price.
    public var priceTotal: Money { (priceLines ?? []).reduce(Money.zero) { $0 + $1.total } }

    public var hasPrice: Bool { priceTotal.cents > 0 }

    /// The invoices a visit was put on. A job that happens once has one visit, so any invoice counts.
    func invoiceIDs(forVisitKey key: String) -> [UUID] {
        guard let map = invoicedVisits else { return [] }
        if repeats { return map[key].map { [$0] } ?? [] }
        return Array(map.values)
    }
}

/// A finished visit with a price that is not on an invoice yet.
public struct UninvoicedVisit: Identifiable, Equatable, Sendable {
    public let jobID: UUID
    /// The day of the visit, like "2027-01-15".
    public let dayKey: String
    public let start: Date
    public let title: String
    /// The job's address, when it belongs to the client being billed.
    public let siteID: UUID?
    public let lines: [JobPriceLine]
    public let total: Money

    public var id: String { jobID.uuidString + "|" + dayKey }
}

/// One client's finished work that is waiting for an invoice, oldest visit first.
public struct ClientUninvoicedWork: Identifiable, Equatable, Sendable {
    public let customerID: UUID
    public let customerName: String
    public let visits: [UninvoicedVisit]

    public var id: UUID { customerID }
    public var total: Money { visits.reduce(Money.zero) { $0 + $1.total } }
}

/// What batch billing did: the draft invoices it made, and a plain sentence for each client it could not bill.
public struct JobBillingResult: Equatable, Sendable {
    public var invoices: [Invoice] = []
    public var problems: [String] = []

    public init() {}

    public var total: Money { invoices.reduce(Money.zero) { $0 + $1.total } }

    /// "3 draft invoices created for $420.00." or "Nothing to bill."
    public var summary: String {
        var parts: [String] = []
        if invoices.isEmpty {
            if problems.isEmpty { parts.append("Nothing to bill.") }
        } else {
            parts.append("\(invoices.count) draft invoice\(invoices.count == 1 ? "" : "s") created for \(total.formatted).")
        }
        return (parts + problems).joined(separator: " ")
    }
}

public enum JobBillingError: Error, Equatable {
    case jobNotFound
    case noPrice
    case noClient
    case notDone
    /// Carries the number of the invoice the visit is already on.
    case alreadyInvoiced(String)
    /// Carries the client's name.
    case noAddress(String)

    /// A plain sentence for the owner.
    public var message: String {
        switch self {
        case .jobNotFound: return "This job no longer exists."
        case .noPrice: return "This job has no price yet. Add a price first."
        case .noClient: return "This job has no client, so there is nobody to invoice."
        case .notDone: return "Mark this visit done first."
        case .alreadyInvoiced(let number): return "This visit is already on invoice \(number)."
        case .noAddress(let name): return "\(name) has no address yet. Add one in Clients, then invoice."
        }
    }
}

public enum JobBilling {
    /// Most price lines one job may hold.
    public static let maxLines = 20

    /// Tidies price lines before they are saved: names are trimmed, quantities stay between 1 and 999, and lines
    /// with no quantity or no price are dropped.
    public static func clean(_ lines: [JobPriceLine]) -> [JobPriceLine] {
        let kept = lines.compactMap { (line: JobPriceLine) -> JobPriceLine? in
            let quantity = min(line.quantity, QuickInvoice.maxQuantity)
            let cents = min(line.unitPriceCents, 100_000_000)
            guard quantity > 0, cents > 0 else { return nil }
            let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return JobPriceLine(id: line.id, name: name.isEmpty ? "Service" : String(name.prefix(80)), quantity: quantity, unitPrice: Money(cents: cents))
        }
        return Array(kept.prefix(maxLines))
    }

    public static func total(_ lines: [JobPriceLine]) -> Money {
        clean(lines).reduce(Money.zero) { $0 + $1.total }
    }

    /// "$45", "45.50", "1,200" or "45,50" as cents. Nil when it is not an amount above zero.
    public static func cents(fromDollars text: String) -> Int? {
        var t = text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Some keyboards type a comma for the decimal point: one or two digits after the last comma means cents.
        if !t.contains("."), let comma = t.lastIndex(of: ",") {
            let digitsAfter = t.distance(from: comma, to: t.endIndex) - 1
            if digitsAfter == 1 || digitsAfter == 2 { t.replaceSubrange(comma...comma, with: ".") }
        }
        t = t.replacingOccurrences(of: ",", with: "")
        guard let value = Double(t), value.isFinite, value > 0, value < 1_000_000 else { return nil }
        let whole = Int((value * 100).rounded())
        return whole > 0 ? whole : nil
    }

    /// The price lines to save from the job screens: the picked services, plus a typed amount as one more line
    /// named after the job.
    public static func lines(picked: [JobPriceLine], customAmount: String, customName: String) -> [JobPriceLine] {
        var all = picked
        if let amount = cents(fromDollars: customAmount) {
            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            all.append(JobPriceLine(name: name.isEmpty ? "Custom price" : name, quantity: 1, unitPrice: Money(cents: amount)))
        }
        return clean(all)
    }

    /// A job's price lines in the shape the invoice builder takes (see QuickInvoice.lines).
    static func picks(_ lines: [JobPriceLine]) -> [QuickInvoicePick] {
        clean(lines).map { QuickInvoicePick(service: ServicePrice(name: $0.name, price: $0.unitPrice), quantity: $0.quantity) }
    }

    /// "Nov 12".
    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// The text of one visit on a statement, like "Nov 12  Mow and trim". The amount goes in its own column.
    public static func visitLine(title: String, start: Date, address: String? = nil, calendar: Calendar = .current) -> String {
        var text = "\(dayText(start, calendar: calendar))  \(title.trimmingCharacters(in: .whitespacesAndNewlines))"
        if let address, !address.isEmpty { text += " (\(address))" }
        return text
    }

    /// Noon on the day a visit key like "2027-01-15" stands for.
    static func noon(ofKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The finished visits of a job, oldest first. A job that happens once has one visit at most.
    static func doneVisits(of job: Job, calendar: Calendar) -> [(key: String, start: Date)] {
        guard job.repeats else {
            return job.status == .done ? [(key: Job.dayKey(job.start, calendar: calendar), start: job.start)] : []
        }
        guard job.status != .cancelled else { return [] }
        var out: [(key: String, start: Date)] = []
        for (key, status) in job.occurrenceStatuses ?? [:] where status == .done {
            guard let midday = noon(ofKey: key, calendar: calendar) else { continue }
            out.append((key: key, start: job.occurrenceStart(on: midday, calendar: calendar) ?? midday))
        }
        return out.sorted { $0.start < $1.start }
    }
}

extension AppData {
    /// Sets or clears what one visit of a job costs. For a repeating job every visit bills these same lines.
    public mutating func setJobPrice(_ lines: [JobPriceLine]?, id: UUID) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        let clean = JobBilling.clean(lines ?? [])
        jobs[i].priceLines = clean.isEmpty ? nil : clean
    }

    /// The client a job is billed to: the job's own client, or the client of its address.
    public func billingCustomerID(forJob job: Job) -> UUID? {
        if let id = job.customerID, customers.contains(where: { $0.id == id }) { return id }
        if let id = job.siteID, let site = sites.first(where: { $0.id == id }),
           customers.contains(where: { $0.id == site.customerID }) { return site.customerID }
        return nil
    }

    /// The invoice a visit is on, if it was billed. A void invoice does not count, so its visits can be billed again.
    /// For a job that happens once the day is ignored.
    public func invoice(forJobVisit jobID: UUID, on day: Date, calendar: Calendar = .current) -> Invoice? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        let ids = job.invoiceIDs(forVisitKey: Job.dayKey(day, calendar: calendar))
        guard !ids.isEmpty else { return nil }
        return invoices.first { !$0.isVoid && ids.contains($0.id) }
    }

    /// Finished visits that have a price and are not on an invoice yet, grouped by client (clients by name, visits
    /// oldest first). Reminders, jobs with no price and jobs with no client are left out. `through` is the last day
    /// to include; nil takes everything.
    public func uninvoicedWork(through: Date? = nil, calendar: Calendar = .current) -> [ClientUninvoicedWork] {
        let standing = Set(invoices.filter { !$0.isVoid }.map(\.id))
        let lastDay = through.map { calendar.startOfDay(for: $0) }
        var byClient: [UUID: [UninvoicedVisit]] = [:]
        for job in jobs where !job.isTask && job.hasPrice {
            guard let customerID = billingCustomerID(forJob: job) else { continue }
            let lines = JobBilling.clean(job.priceLines ?? [])
            let siteID = job.siteID.flatMap { (id: UUID) -> UUID? in
                sites.contains(where: { $0.id == id && $0.customerID == customerID }) ? id : nil
            }
            for visit in JobBilling.doneVisits(of: job, calendar: calendar) {
                if job.invoiceIDs(forVisitKey: visit.key).contains(where: { standing.contains($0) }) { continue }
                if let lastDay, calendar.startOfDay(for: visit.start) > lastDay { continue }
                byClient[customerID, default: []].append(
                    UninvoicedVisit(jobID: job.id, dayKey: visit.key, start: visit.start, title: job.title, siteID: siteID,
                                    lines: lines, total: lines.reduce(Money.zero) { $0 + $1.total }))
            }
        }
        let groups = byClient.compactMap { (entry) -> ClientUninvoicedWork? in
            guard let customer = customers.first(where: { $0.id == entry.key }) else { return nil }
            let visits = entry.value.sorted { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
            return ClientUninvoicedWork(customerID: customer.id, customerName: customer.name, visits: visits)
        }
        return groups.sorted {
            let order = $0.customerName.localizedCaseInsensitiveCompare($1.customerName)
            return order == .orderedSame ? $0.customerID.uuidString < $1.customerID.uuidString : order == .orderedAscending
        }
    }

    /// Makes one draft invoice for one finished visit, with the job's price lines. It refuses a visit that is not
    /// done, has no price or client, or is already on an invoice.
    @discardableResult
    public mutating func createInvoice(forJobVisit jobID: UUID, on day: Date, now: Date, calendar: Calendar = .current) throws -> Invoice {
        guard let job = jobs.first(where: { $0.id == jobID }) else { throw JobBillingError.jobNotFound }
        guard !job.isTask, job.hasPrice else { throw JobBillingError.noPrice }
        guard let customerID = billingCustomerID(forJob: job) else { throw JobBillingError.noClient }
        let key = Job.dayKey(job.repeats ? day : job.start, calendar: calendar)
        guard let visit = JobBilling.doneVisits(of: job, calendar: calendar).first(where: { $0.key == key }) else { throw JobBillingError.notDone }
        if let existing = invoice(forJobVisit: jobID, on: visit.start, calendar: calendar) { throw JobBillingError.alreadyInvoiced(existing.number) }
        let siteID = job.siteID.flatMap { (id: UUID) -> UUID? in
            sites.contains(where: { $0.id == id && $0.customerID == customerID }) ? id : nil
        }
        let note = "\(job.title), \(JobBilling.dayText(visit.start, calendar: calendar))"
        let invoice = try jobInvoice(customerID: customerID, siteID: siteID, picks: JobBilling.picks(job.priceLines ?? []), note: note, now: now)
        markInvoiced(jobID: jobID, dayKey: key, invoiceID: invoice.id)
        return invoice
    }

    /// Batch billing, for weekly or monthly statements: one draft invoice per client covering all their finished
    /// visits that are not invoiced yet, one line per visit like "Nov 12  Mow and trim". Pass a client to bill only
    /// them, and `through` to stop at a day. A visit is never billed twice.
    @discardableResult
    public mutating func createInvoices(forClient customerID: UUID? = nil, through: Date? = nil, now: Date,
                                        calendar: Calendar = .current) -> JobBillingResult {
        var result = JobBillingResult()
        let addresses = Dictionary(sites.map { ($0.id, $0.address) }, uniquingKeysWith: { first, _ in first })
        for work in uninvoicedWork(through: through, calendar: calendar) where customerID == nil || work.customerID == customerID {
            // A client with work at more than one address gets the address on each line.
            let places = Set(work.visits.map(\.siteID))
            let manyPlaces = places.count > 1
            let picks = work.visits.map { (visit: UninvoicedVisit) -> QuickInvoicePick in
                var address: String?
                if manyPlaces, let id = visit.siteID { address = addresses[id] }
                let text = JobBilling.visitLine(title: visit.title, start: visit.start, address: address, calendar: calendar)
                return QuickInvoicePick(service: ServicePrice(name: text, price: visit.total), quantity: 1)
            }
            do {
                let siteID: UUID? = manyPlaces ? nil : work.visits.first?.siteID
                let invoice = try jobInvoice(customerID: work.customerID, siteID: siteID, picks: picks, note: "", now: now)
                for visit in work.visits { markInvoiced(jobID: visit.jobID, dayKey: visit.dayKey, invoiceID: invoice.id) }
                result.invoices.append(invoice)
            } catch let error as JobBillingError {
                result.problems.append(error.message)
            } catch {
                result.problems.append("\(work.customerName) could not be invoiced.")
            }
        }
        return result
    }

    /// Call when a visit is marked done. Follows the owner's choice for automatic invoices: off does nothing; draft
    /// and send both make a draft for this visit (sending always waits for the owner). Returns the new draft, if any.
    @discardableResult
    public mutating func autoInvoice(afterJobDone jobID: UUID, on day: Date, now: Date, calendar: Calendar = .current) -> Invoice? {
        guard profile.invoiceAutomation != .off else { return nil }
        return try? createInvoice(forJobVisit: jobID, on: day, now: now, calendar: calendar)
    }

    /// Builds the draft with the same code as Quick invoice: numbering, due date from the payment terms, the client's address.
    private mutating func jobInvoice(customerID: UUID, siteID: UUID?, picks: [QuickInvoicePick], note: String, now: Date) throws -> Invoice {
        do {
            return try createQuickInvoice(customerID: customerID, siteID: siteID, picks: picks, note: note, now: now)
        } catch QuickInvoiceError.noAddress {
            throw JobBillingError.noAddress(customers.first(where: { $0.id == customerID })?.name ?? "This client")
        } catch QuickInvoiceError.clientNotFound {
            throw JobBillingError.noClient
        } catch {
            throw JobBillingError.noPrice
        }
    }

    private mutating func markInvoiced(jobID: UUID, dayKey: String, invoiceID: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        var map = jobs[i].invoicedVisits ?? [:]
        map[dayKey] = invoiceID
        jobs[i].invoicedVisits = map
    }
}

// MARK: - the assistant

extension AssistantTools {
    /// Saves a price the assistant was given for a new job. Returns a sentence to add to its answer.
    static func applyPrice(_ dollars: Double?, to job: Job, in data: inout AppData) -> String {
        guard let dollars, dollars.isFinite, dollars > 0 else { return "" }
        guard !job.isTask else { return " A reminder or task has no price, so the price was left out." }
        guard data.can(.viewRevenue) else { return " The price was left out because this person may not see money." }
        let cents = Int((min(dollars, 999_999) * 100).rounded())
        guard cents > 0, (try? data.setJobPrice([JobPriceLine(name: job.title, quantity: 1, unitPrice: Money(cents: cents))], id: job.id)) != nil else { return "" }
        return " Price: \(Money(cents: cents).formatted)."
    }

    /// Draft invoices for finished, priced visits that are not invoiced yet: one per client. Nothing is sent.
    static func billFinishedJobs(_ input: JSONValue, _ data: inout AppData, _ now: Date, _ calendar: Calendar) -> ToolOutcome {
        var only: Customer?
        if let name = input["client_name"]?.string, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            let (found, problem) = client(named: name, in: data)
            guard let found else { return .error(problem ?? "No such client.") }
            only = found
        }
        let result = data.createInvoices(forClient: only?.id, now: now, calendar: calendar)
        guard !result.invoices.isEmpty else {
            if !result.problems.isEmpty { return .error(result.problems.joined(separator: " ")) }
            return .text(only.map { "\($0.name) has no finished jobs waiting for an invoice." } ?? "No finished jobs are waiting for an invoice.")
        }
        var lines = ["Created \(result.invoices.count) draft invoice\(result.invoices.count == 1 ? "" : "s") for \(result.total.formatted). They are drafts and have NOT been sent."]
        for invoice in result.invoices {
            let who = data.customers.first { $0.id == invoice.customerID }?.name ?? "?"
            lines.append("- \(invoice.number) | \(who) | \(invoice.total.formatted) | \(invoice.lines.count) visit\(invoice.lines.count == 1 ? "" : "s")")
        }
        lines.append(contentsOf: result.problems.map { "Not billed: \($0)" })
        return .text(lines.joined(separator: "\n"))
    }
}
