import Foundation

public struct Customer: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var phone: String
    public var email: String
    public var notes: String
    /// The client agreed to storm emails. Never assumed: it must be recorded.
    public var emailConsent: Bool
    public var smsConsent: Bool
    public var consentRecordedAt: Date?
    /// How the consent was given, for example "ticked when the quote was accepted".
    public var consentSource: String
    /// Set when the client asked to stop. Overrides any consent.
    public var optedOutAt: Date?
    /// Someone who has asked about your service but is not a client yet.
    public var isLead: Bool
    /// When the owner last asked this client for a review (see ReviewRequests.swift). Nil means never.
    public var reviewAskedAt: Date? = nil

    public init(id: UUID = UUID(), name: String, phone: String = "", email: String = "", notes: String = "",
                emailConsent: Bool = false, smsConsent: Bool = false, consentRecordedAt: Date? = nil,
                consentSource: String = "", optedOutAt: Date? = nil, isLead: Bool = false) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.notes = notes
        self.emailConsent = emailConsent
        self.smsConsent = smsConsent
        self.consentRecordedAt = consentRecordedAt
        self.consentSource = consentSource
        self.optedOutAt = optedOutAt
        self.isLead = isLead
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, phone, email, notes, emailConsent, smsConsent, consentRecordedAt, consentSource, optedOutAt, isLead, reviewAskedAt
    }

    // Older saved files have no consent fields, so they fall back to "no consent".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        emailConsent = try c.decodeIfPresent(Bool.self, forKey: .emailConsent) ?? false
        smsConsent = try c.decodeIfPresent(Bool.self, forKey: .smsConsent) ?? false
        consentRecordedAt = try c.decodeIfPresent(Date.self, forKey: .consentRecordedAt)
        consentSource = try c.decodeIfPresent(String.self, forKey: .consentSource) ?? ""
        optedOutAt = try c.decodeIfPresent(Date.self, forKey: .optedOutAt)
        isLead = try c.decodeIfPresent(Bool.self, forKey: .isLead) ?? false
        reviewAskedAt = try c.decodeIfPresent(Date.self, forKey: .reviewAskedAt)
    }
}

public enum ContactValidation {
    /// A basic check that stops obvious mistakes and header-injection tricks. It does not prove the address works.
    public static func isValidEmail(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t == text, t.count <= 254, !t.contains(" "), !t.contains(","), !t.contains(";"), !t.contains("\n"), !t.contains("\r"), !t.contains("<"), !t.contains(">") else { return false }
        let parts = t.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64 else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains("..") else { return false }
        return true
    }

    public static func isValidPhone(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        return digits.count >= 10 && digits.count <= 15
    }
}

/// A place a crew services (a driveway, a lot, a set of walks).
public struct Site: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var customerID: UUID
    public var address: String
    public var latitude: Double?
    public var longitude: Double?
    /// 1 = most important (hospital lot), larger = lower priority. Used for dispatch order.
    public var priority: Int
    /// Snow depth (inches) that triggers service for this site.
    public var triggerInches: Double
    /// Standing instructions shown to the crew (gate codes, "don't pile on the lawn").
    public var instructions: String
    /// Lawn or lot size measured on the satellite map, in square feet. nil until someone measures it.
    public var lawnAreaSqFt: Double? = nil

    public init(id: UUID = UUID(), customerID: UUID, address: String, latitude: Double? = nil,
                longitude: Double? = nil, priority: Int = 3, triggerInches: Double = 2,
                instructions: String = "") {
        self.id = id
        self.customerID = customerID
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.priority = priority
        self.triggerInches = triggerInches
        self.instructions = instructions
    }
}

public struct SnowContract: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var siteID: UUID
    /// Season label, e.g. "2026-27".
    public var season: String
    public var terms: ContractTerms

    public init(id: UUID = UUID(), siteID: UUID, season: String, terms: ContractTerms) {
        self.id = id
        self.siteID = siteID
        self.season = season
        self.terms = terms
    }
}
