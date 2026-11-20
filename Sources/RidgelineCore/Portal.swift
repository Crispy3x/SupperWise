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
    /// The owner's own payment link, only on bills that still need paying.
    public let payURL: String?
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
    /// The property's place on the map, rounded to about 100 metres. Nil when the site has no map location.
    public let siteLocation: Coordinate?
    /// How many stops come before this one on the route. Nil when there is no route.
    public let stopsAhead: Int?

    public init(token: String, label: String, status: PortalStatus, detail: String, canRequest: Bool,
                eta: String = "", summary: String = "", bills: [PortalBill] = [],
                siteLocation: Coordinate? = nil, stopsAhead: Int? = nil) {
        self.siteLocation = siteLocation
        self.stopsAhead = stopsAhead
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
    /// Conditions shown on every client page.
    public let weather: PortalWeather?
    /// The owner's own tip and coffee links. Money goes straight to them, never through this app or the server.
    public let tips: PortalTips?

    public init(company: String, storm: PortalStormInfo, sites: [PortalSiteSnapshot], weather: PortalWeather? = nil, tips: PortalTips? = nil) {
        self.company = company
        self.storm = storm
        self.sites = sites
        self.weather = weather
        self.tips = tips
    }
}

public struct PortalWeather: Codable, Equatable, Sendable {
    public let summary: String
    public let alerts: [String]

    public init(summary: String, alerts: [String]) {
        self.summary = summary
        self.alerts = alerts
    }

    /// One plain sentence from the forecast, for example "Snow expected: about 4.0 in over the next 24 hours. Low 24 F, wind up to 18 mph."
    public static func make(from forecast: WeatherWindowSummary?, alerts: [WinterAlert], hours: Int = 24) -> PortalWeather? {
        var parts: [String] = []
        if let f = forecast {
            if f.snowfallInches >= 0.1 { parts.append("Snow expected: about \(String(format: "%.1f", f.snowfallInches)) in over the next \(hours) hours.") }
            else { parts.append("No significant snow expected in the next \(hours) hours.") }
            var more: [String] = []
            if let low = f.minTemperatureF { more.append("Low \(Int(low.rounded())) F") }
            if let wind = f.maxWindMph, wind >= 10 { more.append("wind up to \(Int(wind.rounded())) mph") }
            if !more.isEmpty { parts.append(more.joined(separator: ", ") + ".") }
        }
        let headlines = alerts.map(\.headline).filter { !$0.isEmpty }.prefix(3)
        if parts.isEmpty && headlines.isEmpty { return nil }
        return PortalWeather(summary: parts.joined(separator: " "), alerts: Array(headlines))
    }
}

public struct PortalTips: Codable, Equatable, Sendable {
    public let tipURL: String?
    public let coffeeURL: String?

    public init(tipURL: String?, coffeeURL: String?) {
        self.tipURL = tipURL
        self.coffeeURL = coffeeURL
    }

    /// Only links that pass the payment-site check are ever sent.
    public static func make(from profile: BusinessProfile) -> PortalTips? {
        let tip = profile.tipLink.flatMap(PayLink.clean), coffee = profile.coffeeLink.flatMap(PayLink.clean)
        return tip == nil && coffee == nil ? nil : PortalTips(tipURL: tip, coffeeURL: coffee)
    }
}

/// One truck's position, for the map on client pages.
public struct PortalTruck: Codable, Equatable, Sendable {
    public let label: String
    public let latitude: Double
    public let longitude: Double

    public init(label: String, latitude: Double, longitude: Double) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum PortalSnapshotBuilder {
    /// - Parameters:
    ///   - servedSiteIDs: the sites the dispatch list will serve this storm (see `DispatchRules`).
    ///   - visitStormName: the storm name the crew logged visits under.
    public static func build(data: AppData, storm: StormEvent, forecastInches: Double, servedSiteIDs: Set<UUID>,
                             visitStormName: String, routeStart: Date? = nil, arrivalOffsets: [UUID: Double] = [:],
                             weather: PortalWeather? = nil, now: Date = Date(), timeZone: TimeZone = .current) -> PortalSnapshot {
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
            // Where this property is, to about 100 metres, and how many stops come first.
            var place: Coordinate?
            if let lat = site.latitude, let lon = site.longitude {
                place = Coordinate(latitude: (lat * 1000).rounded() / 1000, longitude: (lon * 1000).rounded() / 1000)
            }
            var ahead: Int?
            if status == .planned, let mine = arrivalOffsets[site.id] { ahead = arrivalOffsets.values.filter { $0 < mine }.count }
            sites.append(PortalSiteSnapshot(token: link.token, label: site.address, status: status, detail: detail, canRequest: status != .done,
                                            eta: eta, summary: winterSummary(site: site, data: data, now: now),
                                            bills: bills(for: site, data: data, now: now, timeZone: timeZone),
                                            siteLocation: place, stopsAhead: ahead))
        }
        return PortalSnapshot(company: company.isEmpty ? "Your snow crew" : company,
                              storm: PortalStormInfo(id: storm.id.uuidString, name: storm.name, expected: SnowEstimateText.describe(forecastInches: forecastInches)),
                              sites: sites, weather: weather, tips: PortalTips.make(from: data.profile))
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
                                  status: status, due: state == .paid ? "" : "Due \(f.string(from: inv.dueDate))",
                                  payURL: state == .paid ? nil : data.profile.payLink.flatMap(PayLink.clean))
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

    /// Sends where a truck is right now. Trucks are added or updated by their label, so several can share at once.
    /// `remove` takes trucks off every client page, for example when a crew stops sharing.
    public func publishTrucks(_ trucks: [PortalTruck], remove: [String] = []) async throws {
        struct Body: Encodable { let trucks: [PortalTruck]; let remove: [String]? }
        _ = try await send(request("PUT", "v1/portal/trucks", body: try JSONEncoder().encode(Body(trucks: trucks, remove: remove.isEmpty ? nil : remove))))
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
