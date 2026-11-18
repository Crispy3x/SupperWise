import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PortalStatus: String, Codable, Sendable {
    case planned, done, skipped, notExpected
}

public struct PortalStormInfo: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let expected: String
}

public struct PortalBill: Codable, Equatable, Sendable {
    public let number: String
    public let label: String
    /// Empty when the owner chose not to show amounts.
    public let total: String
    /// "Paid", "Due" or "Overdue". Drafts are never shown to clients.
    public let status: String
    public let due: String
}

public struct PortalSiteSnapshot: Codable, Equatable, Sendable {
    public let token: String
    public let label: String
    public let status: PortalStatus
    public let detail: String
    public let canRequest: Bool
    /// For example "Expected between 7:15 AM and 8:45 AM." Empty when there is no estimate.
    public let eta: String
    public let summary: String
    public let bills: [PortalBill]

    public init(token: String, label: String, status: PortalStatus, detail: String, canRequest: Bool,
                eta: String = "", summary: String = "", bills: [PortalBill] = []) {
        self.token = token
        self.label = label
        self.status = status
        self.detail = detail
        self.canRequest = canRequest
        self.eta = eta
        self.summary = summary
        self.bills = bills
    }
}

public enum ArrivalWindow {
    /// An honest window, not a promise: the expected arrival plus or minus `spreadMinutes`, widened to 15 minutes.
    public static func describe(routeStart: Date, offsetSeconds: Double, spreadMinutes: Int = 45, calendar: Calendar = .current) -> String {
        let arrival = routeStart.addingTimeInterval(max(offsetSeconds, 0))
        let spread = Double(max(spreadMinutes, 0)) * 60
        let q = 900.0
        let lo = Date(timeIntervalSinceReferenceDate: ((arrival.timeIntervalSinceReferenceDate - spread) / q).rounded(.down) * q)
        let hi = Date(timeIntervalSinceReferenceDate: ((arrival.timeIntervalSinceReferenceDate + spread) / q).rounded(.up) * q)
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return "Expected between \(f.string(from: lo)) and \(f.string(from: hi))."
    }
}

/// What the phone tells the portal server to show clients. It holds an address label, a status and a sentence per
/// page: no phone numbers, no email addresses and no customer names.
public struct PortalSnapshot: Codable, Equatable, Sendable {
    public let company: String
    public let storm: PortalStormInfo
    public let sites: [PortalSiteSnapshot]
}

public enum PortalSnapshotBuilder {
    /// - Parameters:
    ///   - servedSiteIDs: the sites the dispatch list will serve this storm (see `DispatchRules`).
    ///   - visitStormName: the storm name the crew logged visits under.
    public static func build(data: AppData, storm: StormEvent, forecastInches: Double, servedSiteIDs: Set<UUID>,
                             visitStormName: String, routeStart: Date? = nil, arrivalOffsets: [UUID: Double] = [:],
                             now: Date = Date(), timeZone: TimeZone = .current) -> PortalSnapshot {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)

        var sites: [PortalSiteSnapshot] = []
        for site in data.sites.sorted(by: { ($0.address, $0.id.uuidString) < ($1.address, $1.id.uuidString) }) {
            guard let link = data.portalLinks.first(where: { $0.siteID == site.id }),
                  let customer = data.customers.first(where: { $0.id == site.customerID }),
                  customer.optedOutAt == nil else { continue }       // people who said stop get no page
            let visit = data.visitLog.records(forSite: site.id).filter { $0.stormID == visitStormName }.last
            let status: PortalStatus
            let detail: String
            if let visit, case .skipped(let reason) = visit.status {
                status = .skipped
                detail = "We could not service your property this visit: \(reason)."
            } else if let visit {
                status = .done
                detail = "Done at \(f.string(from: visit.departure ?? visit.arrival))."
            } else if servedSiteIDs.contains(site.id) {
                status = .planned
                detail = "We expect to service your property."
            } else {
                status = .notExpected
                detail = "The forecast is under your \(String(format: "%g", site.triggerInches)) inch trigger. You can ask for service below."
            }
            var eta = ""
            if status == .planned, let start = routeStart, let offset = arrivalOffsets[site.id] {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = timeZone
                eta = ArrivalWindow.describe(routeStart: start, offsetSeconds: offset, calendar: cal)
            }
            sites.append(PortalSiteSnapshot(token: link.token, label: site.address, status: status, detail: detail, canRequest: status != .done,
                                            eta: eta, summary: winterSummary(site: site, data: data, now: now),
                                            bills: bills(for: site, data: data, now: now, timeZone: timeZone)))
        }
        return PortalSnapshot(company: company.isEmpty ? "Your snow crew" : company,
                              storm: PortalStormInfo(id: storm.id.uuidString, name: storm.name, expected: SnowEstimateText.describe(forecastInches: forecastInches)),
                              sites: sites)
    }
}

extension PortalSnapshotBuilder {
    /// Invoices the client may see: sent ones, never drafts or voided ones.
    static func bills(for site: Site, data: AppData, now: Date, timeZone: TimeZone) -> [PortalBill] {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return data.invoices
            .filter { $0.siteID == site.id && !$0.isVoid && $0.sentAt != nil }
            .sorted { $0.issueDate > $1.issueDate }
            .prefix(30)
            .map { inv in
                let state = inv.status(now: now)
                let status = state == .paid ? "Paid" : (state == .overdue ? "Overdue" : "Due")
                let label = inv.lines.count == 1 ? inv.lines[0].description : "\(inv.lines.count) items"
                return PortalBill(number: inv.number, label: label, total: data.profile.portalShowsAmounts ? inv.total.formatted : "",
                                  status: status, due: state == .paid ? "" : "Due \(f.string(from: inv.dueDate))")
            }
    }

    /// One plain line about this winter, from the visit log: how many storms were serviced and, for a cap, how many of the included pushes are used.
    static func winterSummary(site: Site, data: AppData, now: Date) -> String {
        let since = now.addingTimeInterval(-200 * 86_400)
        let storms = Set(data.visitLog.records(forSite: site.id)
            .filter { $0.status == .completed && $0.arrival >= since }.map(\.stormID)).count
        guard storms > 0 else { return "" }
        if let c = data.contracts.last(where: { $0.siteID == site.id }), case .hybrid(_, let included, _, _) = c.terms {
            return "Seasonal contract: \(min(storms, included)) of \(included) included pushes used" + (storms > included ? ", \(storms - included) beyond that." : ".")
        }
        return "\(storms) storm\(storms == 1 ? "" : "s") serviced so far this winter."
    }
}

public enum PortalError: Error, Equatable {
    case server(Int)
    case unreadable
}

/// Talks to the Ridgeline server for the owner: publishes pages, collects client requests, answers them, sends email.
/// Keep the token in the Keychain, never in the saved data file.
public struct PortalClient: Sendable {
    public let baseURL: URL
    public let token: String
    public let client: HTTPClient

    public init(baseURL: URL, token: String, client: HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, status) = try await client.send(r)
        guard status == 200 else { throw PortalError.server(status) }
        return data
    }

    public func publish(_ snapshot: PortalSnapshot) async throws {
        _ = try await send(request("PUT", "v1/portal/snapshot", body: try JSONEncoder().encode(snapshot)))
    }

    /// New client requests since `date` (or all, if nil). Importing the same request twice is harmless.
    public func fetchRequests(since date: Date? = nil) async throws -> [IncomingRequest] {
        var query: [URLQueryItem] = []
        if let date {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            query.append(URLQueryItem(name: "since", value: f.string(from: date)))
        }
        struct Wire: Decodable { let requests: [IncomingRequest] }
        let data = try await send(request("GET", "v1/portal/requests", query: query))
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { throw PortalError.unreadable }
        return wire.requests
    }

    public func decide(remoteRequestID: String, accept: Bool, message: String) async throws {
        struct Body: Encodable { let id: String; let status: String; let message: String }
        let body = try JSONEncoder().encode(Body(id: remoteRequestID, status: accept ? "accepted" : "declined", message: message))
        _ = try await send(request("POST", "v1/portal/decisions", body: body))
    }

    /// Sends the email messages through the server. Returns one yes or no per message, in order, so only the ones
    /// that really went out are recorded as sent.
    public func sendEmails(_ messages: [PlannedMessage]) async throws -> [Bool] {
        guard !messages.isEmpty else { return [] }
        struct Out: Encodable { let to: String; let subject: String; let text: String }
        struct Body: Encodable { let messages: [Out] }
        struct Result: Decodable { let index: Int; let ok: Bool }
        struct Wire: Decodable { let results: [Result] }
        let body = try JSONEncoder().encode(Body(messages: messages.map { Out(to: $0.to, subject: $0.subject, text: $0.body) }))
        let data = try await send(request("POST", "v1/send/email", body: body))
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { throw PortalError.unreadable }
        var ok = [Bool](repeating: false, count: messages.count)
        for r in wire.results where r.index >= 0 && r.index < ok.count { ok[r.index] = r.ok }
        return ok
    }
}
