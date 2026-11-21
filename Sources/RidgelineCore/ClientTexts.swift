import Foundation

/// The two quick texts a crew sends a client from their own phone. Nothing goes through a server.
public enum ClientTextKind: String, Codable, CaseIterable, Sendable {
    case onMyWay, done

    public var title: String {
        switch self {
        case .onMyWay: return "On my way"
        case .done: return "Job done"
        }
    }
}

/// One text sent about a job, kept on the job so the owner can see what went out and when.
public struct ClientTextLogEntry: Equatable, Codable, Sendable {
    public var kind: ClientTextKind
    public var sentAt: Date

    public init(kind: ClientTextKind, sentAt: Date) {
        self.kind = kind
        self.sentAt = sentAt
    }
}

/// Why the app will not text this client.
public enum ClientTextBlocker: Error, Equatable, Sendable {
    case notFound, noClient, optedOut, noPhone

    public var message: String {
        switch self {
        case .notFound: return "That job no longer exists."
        case .noClient: return "This job has no client to text."
        case .optedOut: return "This client asked to stop messages, so the app will not text them."
        case .noPhone: return "Add a mobile number for this client to text them."
        }
    }
}

/// A ready-to-send text. The crew sends it from Messages on their own phone.
public struct ClientTextDraft: Equatable, Sendable {
    public let jobID: UUID
    public let customerID: UUID
    public let kind: ClientTextKind
    /// The phone number as digits (and a leading + if there was one), ready for Messages.
    public let recipient: String
    public let body: String
    /// Opens Messages with the text filled in, for phones where the in-app composer is not available.
    public let smsURL: URL?
}

public enum ClientTexts {
    /// Every text stays under this many characters so it goes out as one or two message parts.
    public static let maxLength = 300
    /// How many texts are kept on one job. Older ones drop off.
    public static let maxLogEntries = 50

    /// Drive time rounded to the nearest 5 minutes, never under 5 and never over 10 hours. Nil for a bad value.
    public static func roundedETAMinutes(_ seconds: Double) -> Int? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let fives = Int((seconds / 300).rounded())
        return min(max(fives * 5, 5), 600)
    }

    /// "about 15 minutes", "about 1 hour", "about 1 hour 25 minutes".
    public static func etaPhrase(minutes: Int) -> String {
        let m = max(minutes, 0)
        if m < 60 { return "about \(m) minutes" }
        let h = m / 60, r = m % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        return r == 0 ? "about \(hours)" : "about \(hours) \(r) minutes"
    }

    static func oneLine(_ s: String, limit: Int) -> String {
        let flat = s.components(separatedBy: .newlines).joined(separator: " ")
        let clean = String(flat.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
        return String(clean.trimmingCharacters(in: .whitespaces).prefix(limit))
    }

    /// Tries the full text, then without the link, then cuts it, so it is always within `maxLength`.
    static func fit(_ build: (String?) -> String, link: String?) -> String {
        let full = build(link)
        if full.count <= maxLength { return full }
        let noLink = build(nil)
        if noLink.count <= maxLength { return noLink }
        return String(noLink.prefix(maxLength - 3)) + "..."
    }

    /// "Hi Sam, it's Ridge Plow. We're on our way to 12 Oak St and should be there in about 15 minutes. Follow along here: ..."
    public static func onMyWayMessage(clientName: String, company: String, address: String,
                                      etaMinutes: Int?, pageLink: String?) -> String {
        let name = ReviewRequests.firstName(oneLine(clientName, limit: 80))
        let biz = oneLine(company, limit: 60)
        let place = oneLine(address, limit: 80)
        let hello = biz.isEmpty ? "Hi \(name)! " : "Hi \(name), it's \(biz). "
        let whereTo = place.isEmpty ? "We're on our way" : "We're on our way to \(place)"
        let when = etaMinutes.map { " and should be there in \(etaPhrase(minutes: $0))." } ?? "."
        return fit({ link in
            hello + whereTo + when + (link.map { " Follow along here: \($0)" } ?? "")
        }, link: pageLink)
    }

    /// "Hi Sam, we just finished at 12 Oak St. A photo of the finished work is attached. Details: ... Thanks, Ridge Plow"
    public static func doneMessage(clientName: String, company: String, address: String,
                                   withPhoto: Bool, pageLink: String?) -> String {
        let name = ReviewRequests.firstName(oneLine(clientName, limit: 80))
        let biz = oneLine(company, limit: 60)
        let place = oneLine(address, limit: 80)
        let finished = place.isEmpty ? "Hi \(name), we just finished your job." : "Hi \(name), we just finished at \(place)."
        let photo = withPhoto ? " A photo of the finished work is attached." : ""
        let thanks = biz.isEmpty ? " Thank you!" : " Thanks, \(biz)"
        return fit({ link in
            finished + photo + (link.map { " Details: \($0)" } ?? "") + thanks
        }, link: pageLink)
    }

    /// "On my way sent 7:42 AM", or with the date when it was not sent today.
    public static func sentLine(_ entry: ClientTextLogEntry, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.isDate(entry.sentAt, inSameDayAs: now) ? "h:mm a" : "MMM d, h:mm a"
        return "\(entry.kind.title) sent \(f.string(from: entry.sentAt))"
    }
}

extension Job {
    /// Texts sent about this job. For a repeating job, only the ones sent on that visit's day.
    public func sentTexts(forVisitOn day: Date, calendar: Calendar = .current) -> [ClientTextLogEntry] {
        let all = (clientTexts ?? []).sorted { $0.sentAt < $1.sentAt }
        guard repeats else { return all }
        return all.filter { calendar.isDate($0.sentAt, inSameDayAs: day) }
    }

    /// The most recent text of one kind for this visit, if any.
    public func lastSentText(_ kind: ClientTextKind, forVisitOn day: Date, calendar: Calendar = .current) -> ClientTextLogEntry? {
        sentTexts(forVisitOn: day, calendar: calendar).last { $0.kind == kind }
    }
}

extension AppData {
    /// The client a job is for: the job's own client, or the owner of its site.
    public func clientTextCustomer(for job: Job) -> Customer? {
        if let id = job.customerID, let c = customers.first(where: { $0.id == id }) { return c }
        if let id = job.siteID, let s = sites.first(where: { $0.id == id }) { return customers.first { $0.id == s.customerID } }
        return nil
    }

    /// The client's private page for a site, when a page address is set up in Settings. Nil otherwise.
    public func clientPageLink(siteID: UUID?) -> String? {
        guard let siteID else { return nil }
        var base = broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard RoutingServerSettings.validatedURL(base) != nil,
              let token = portalLinks.first(where: { $0.siteID == siteID })?.token else { return nil }
        return "\(base)/c/\(token)"
    }

    /// Why this job's client cannot be texted, or nil when they can.
    public func clientTextBlocker(jobID: UUID) -> ClientTextBlocker? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return .notFound }
        guard let c = clientTextCustomer(for: job) else { return .noClient }
        if c.optedOutAt != nil { return .optedOut }
        if !ContactValidation.isValidPhone(c.phone) { return .noPhone }
        return nil
    }

    /// The text for one job, or why it cannot be sent. `etaSeconds` is the drive time for "On my way".
    public func clientTextDraft(_ kind: ClientTextKind, jobID: UUID, etaSeconds: Double? = nil,
                                withPhoto: Bool = false) -> Result<ClientTextDraft, ClientTextBlocker> {
        if let b = clientTextBlocker(jobID: jobID) { return .failure(b) }
        guard let job = jobs.first(where: { $0.id == jobID }), let c = clientTextCustomer(for: job) else { return .failure(.notFound) }
        let link = clientPageLink(siteID: job.siteID)
        let place = address(forJob: job)
        let body: String
        switch kind {
        case .onMyWay:
            body = ClientTexts.onMyWayMessage(clientName: c.name, company: companyName, address: place,
                                              etaMinutes: etaSeconds.flatMap(ClientTexts.roundedETAMinutes), pageLink: link)
        case .done:
            body = ClientTexts.doneMessage(clientName: c.name, company: companyName, address: place, withPhoto: withPhoto, pageLink: link)
        }
        let recipient = c.phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
        return .success(ClientTextDraft(jobID: job.id, customerID: c.id, kind: kind, recipient: recipient, body: body,
                                        smsURL: ReviewRequests.smsURL(phone: c.phone, body: body)))
    }

    /// Notes on the job that a text went out. Refuses a client who cannot be texted. Keeps the latest 50.
    public mutating func recordClientText(_ kind: ClientTextKind, jobID: UUID, now: Date) throws {
        if let b = clientTextBlocker(jobID: jobID) { throw b }
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { throw ClientTextBlocker.notFound }
        var log = jobs[i].clientTexts ?? []
        log.append(ClientTextLogEntry(kind: kind, sentAt: now))
        jobs[i].clientTexts = Array(log.suffix(ClientTexts.maxLogEntries))
    }

    /// The newest "after" photo from a visit logged at this site on `day`, for the "Job done" text.
    public func latestAfterPhoto(siteID: UUID?, on day: Date, calendar: Calendar = .current) -> PhotoRef? {
        guard let siteID else { return nil }
        return visitLog.records(forSite: siteID)
            .filter { calendar.isDate($0.arrival, inSameDayAs: day) }
            .flatMap(\.photos)
            .filter { $0.kind == .after }
            .max { $0.capturedAt < $1.capturedAt }
    }

    /// The next stop to text in a planned route: the first job in `order` that is still scheduled that day.
    public func nextStopToText(order: [UUID], on day: Date, calendar: Calendar = .current) -> UUID? {
        let todays = jobs(on: day, calendar: calendar)
        return order.first { id in todays.contains { $0.id == id && !$0.isTask && $0.status == .scheduled } }
    }
}
