import Foundation

public enum RequestKind: String, Codable, CaseIterable, Sendable {
    /// "Please come" even though the forecast is under the trigger.
    case service
    /// "I need to get out soon." The owner decides whether to move this site up.
    case urgent
    /// "Skip me this storm" (away, or will do it themselves).
    case skip
    /// A kind message for the driver. It changes nothing on the route; the owner reads it and marks it read.
    case thanks
}

public enum UrgentReason: String, Codable, CaseIterable, Sendable {
    case leavingSoon, medical, visitorOrDelivery, other
}

public enum RequestStatus: String, Codable, Sendable {
    case pending, accepted, declined
}

public enum RequestError: Error, Equatable {
    case notFound
    case alreadyDecided
}

/// A request a client made on their page. Nothing changes the route until the owner accepts it.
public struct ServiceRequest: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    /// The id the portal server gave it, so the same request is never imported twice.
    public var remoteID: String?
    public var siteID: UUID
    public var stormID: UUID?
    public var kind: RequestKind
    public var urgentReason: UrgentReason?
    public var note: String
    public var createdAt: Date
    public private(set) var status: RequestStatus
    public private(set) var decidedAt: Date?
    /// What the client sees, for example why a request was declined.
    public private(set) var responseMessage: String
    /// Whether the client's page has been told the answer. nil in older saved files, which counts as not yet.
    public var syncedToPortal: Bool?

    public init(id: UUID = UUID(), remoteID: String? = nil, siteID: UUID, stormID: UUID? = nil, kind: RequestKind,
                urgentReason: UrgentReason? = nil, note: String = "", createdAt: Date) {
        self.id = id
        self.remoteID = remoteID
        self.siteID = siteID
        self.stormID = stormID
        self.kind = kind
        self.urgentReason = urgentReason
        self.note = note
        self.createdAt = createdAt
        self.status = .pending
        self.decidedAt = nil
        self.responseMessage = ""
    }

    public mutating func decide(accept: Bool, message: String, at date: Date) throws {
        guard status == .pending else { throw RequestError.alreadyDecided }
        status = accept ? .accepted : .declined
        decidedAt = date
        responseMessage = message
    }
}

/// A request as it arrives from the portal server.
public struct IncomingRequest: Equatable, Codable, Sendable {
    public let id: String
    public let token: String
    public let kind: String
    public let reason: String?
    public let note: String?
    public let createdAt: String
    public let stormId: String?
}

extension AppData {
    public static let maxPendingRequestsPerSite = 5
    public static let maxRequestNoteLength = 500

    /// Gives every site a private page address. Existing ones are kept.
    public mutating func ensurePortalLinks(now: Date) {
        for site in sites where !portalLinks.contains(where: { $0.siteID == site.id }) {
            portalLinks.append(PortalLink(siteID: site.id, token: PortalToken.generate(), createdAt: now))
        }
    }

    public func siteID(forToken token: String) -> UUID? {
        portalLinks.first { $0.token == token }?.siteID
    }

    /// Adds new client requests. Unknown pages, repeats and floods are ignored. Returns how many were added.
    @discardableResult
    public mutating func importRequests(_ incoming: [IncomingRequest]) -> Int {
        var added = 0
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        for r in incoming {
            guard let siteID = siteID(forToken: r.token) else { continue }
            guard !serviceRequests.contains(where: { $0.remoteID == r.id }) else { continue }
            guard let kind = RequestKind(rawValue: r.kind) else { continue }
            let pending = serviceRequests.filter { $0.siteID == siteID && $0.status == .pending && $0.kind != .thanks }.count
            guard kind == .thanks || pending < Self.maxPendingRequestsPerSite else { continue }
            let created = parser.date(from: r.createdAt) ?? plain.date(from: r.createdAt) ?? Date()
            let note = String(r.note?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRequestNoteLength) ?? "")
            serviceRequests.append(ServiceRequest(remoteID: r.id, siteID: siteID, stormID: r.stormId.flatMap(UUID.init(uuidString:)), kind: kind,
                                                  urgentReason: r.reason.flatMap(UrgentReason.init(rawValue:)), note: note, createdAt: created))
            added += 1
        }
        return added
    }

    /// Decisions made here that the client's page has not been told about yet.
    public var unsyncedDecisions: [ServiceRequest] {
        serviceRequests.filter { $0.status != .pending && $0.remoteID != nil && $0.syncedToPortal != true }
    }

    public mutating func markDecisionSynced(id: UUID) {
        if let i = serviceRequests.firstIndex(where: { $0.id == id }) { serviceRequests[i].syncedToPortal = true }
    }

    public mutating func decideRequest(id: UUID, accept: Bool, message: String, now: Date) throws {
        guard let i = serviceRequests.firstIndex(where: { $0.id == id }) else { throw RequestError.notFound }
        try serviceRequests[i].decide(accept: accept, message: message, at: now)
    }

    /// Records only the messages that were really sent, so a failure can be retried without double-sending.
    public mutating func recordSent(_ messages: [PlannedMessage], stormID: UUID, at date: Date) {
        for m in messages where !broadcastLog.contains(where: { $0.stormID == stormID && $0.siteID == m.siteID && $0.channel == m.channel }) {
            broadcastLog.append(BroadcastRecord(stormID: stormID, siteID: m.siteID, channel: m.channel, sentAt: date))
        }
    }

    /// A client asked to stop. Overrides any consent.
    public mutating func optOut(customerID: UUID, now: Date) throws {
        guard let i = customers.firstIndex(where: { $0.id == customerID }) else { throw OperationError.notFound }
        customers[i].optedOutAt = now
    }

    public mutating func recordConsent(customerID: UUID, email: Bool, sms: Bool, source: String, now: Date) throws {
        guard let i = customers.firstIndex(where: { $0.id == customerID }) else { throw OperationError.notFound }
        customers[i].emailConsent = email
        customers[i].smsConsent = sms
        customers[i].consentRecordedAt = now
        customers[i].consentSource = source
        if email || sms { customers[i].optedOutAt = nil }      // a fresh, recorded yes replaces an old stop
    }
}

public enum DispatchRules {
    /// Sites to serve this storm: those at their trigger depth, plus sites with an accepted service or urgent request,
    /// minus sites with an accepted skip. An accepted urgent request moves the site to the top priority tier.
    public static func effectiveSites(sites: [Site], inches: Double, stormID: UUID?, requests: [ServiceRequest]) -> [Site] {
        let accepted = requests.filter { $0.status == .accepted && ($0.stormID == nil || $0.stormID == stormID) }
        return sites.compactMap { site -> Site? in
            let mine = accepted.filter { $0.siteID == site.id }
            if mine.contains(where: { $0.kind == .skip }) { return nil }
            let requested = mine.contains { $0.kind == .service || $0.kind == .urgent }
            guard site.triggerInches <= inches || requested else { return nil }
            var copy = site
            if mine.contains(where: { $0.kind == .urgent }) { copy.priority = 1 }
            return copy
        }
        .sorted { ($0.priority, $0.triggerInches, $0.address) < ($1.priority, $1.triggerInches, $1.address) }
    }
}
