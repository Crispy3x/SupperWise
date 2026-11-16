import Foundation

public struct Customer: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var phone: String
    public var email: String
    public var notes: String

    public init(id: UUID = UUID(), name: String, phone: String = "", email: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.notes = notes
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
