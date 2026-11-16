import Foundation

public struct StormEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var start: Date
    public var forecastInches: Double
    public var actualInches: Double?

    public init(id: UUID = UUID(), name: String, start: Date, forecastInches: Double, actualInches: Double? = nil) {
        self.id = id
        self.name = name
        self.start = start
        self.forecastInches = forecastInches
        self.actualInches = actualInches
    }

    /// Best known snowfall: actual once recorded, forecast before that.
    public var effectiveInches: Double { actualInches ?? forecastInches }
}

public enum TriggerEvaluator {
    /// Sites whose trigger depth has been reached, most important first, then shallowest trigger.
    public static func sitesToServe(sites: [Site], inches: Double) -> [Site] {
        sites
            .filter { $0.triggerInches <= inches }
            .sorted { ($0.priority, $0.triggerInches, $0.address) < ($1.priority, $1.triggerInches, $1.address) }
    }

    /// Sites that will be triggered by the forecast but are not yet (for early-warning alerts).
    public static func sitesNearTrigger(sites: [Site], inches: Double, within margin: Double = 1) -> [Site] {
        sites.filter { $0.triggerInches > inches && $0.triggerInches <= inches + margin }
    }
}
