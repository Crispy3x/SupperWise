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

public struct PortalSiteSnapshot: Codable, Equatable, Sendable {
    public let token: String
    public let label: String
    public let status: PortalStatus
    public let detail: String
    public let canRequest: Bool
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
                             visitStormName: String, timeZone: TimeZone = .current) -> PortalSnapshot {
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
            sites.append(PortalSiteSnapshot(token: link.token, label: site.address, status: status, detail: detail, canRequest: status != .done))
        }
        return PortalSnapshot(company: company.isEmpty ? "Your snow crew" : company,
                              storm: PortalStormInfo(id: storm.id.uuidString, name: storm.name, expected: SnowEstimateText.describe(forecastInches: forecastInches)),
                              sites: sites)
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
