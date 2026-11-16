import Foundation

/// Weather at dispatch time. Fill from Apple WeatherKit or the NWS, or type it in by hand.
public struct WeatherConditions: Equatable, Codable, Sendable {
    public var snowfallRateInPerHour: Double
    public var accumulationInches: Double
    public var temperatureF: Double
    public var windMph: Double
    public var visibilityMiles: Double

    public init(snowfallRateInPerHour: Double = 0, accumulationInches: Double = 0, temperatureF: Double = 30,
                windMph: Double = 0, visibilityMiles: Double = 10) {
        self.snowfallRateInPerHour = snowfallRateInPerHour
        self.accumulationInches = accumulationInches
        self.temperatureF = temperatureF
        self.windMph = windMph
        self.visibilityMiles = visibilityMiles
    }

    public static let clear = WeatherConditions()
}

/// Turns weather into a driving-speed factor and a service-time factor.
///
/// IMPORTANT: every number here is a starting guess, not a validated model. Owners can edit the values, and
/// `SpeedCalibrator` replaces the guess with what your own trucks actually did (from the visit log).
/// Google and Apple drive times reflect live traffic but have no snow-specific logic, so this layer sits on top.
public struct ConditionsModel: Equatable, Sendable {
    public var slowdownPerInch = 0.035
    public var heavySnowRateInPerHour = 1.0
    public var heavySnowSlowdown = 0.15
    /// Wet snow and ice risk band.
    public var icyTemperatureRangeF: ClosedRange<Double> = 25...34
    public var icySlowdown = 0.08
    public var windThresholdMph = 20.0
    public var slowdownPerMphOverThreshold = 0.005
    public var lowVisibilityMiles = 1.0
    public var lowVisibilitySlowdown = 0.15
    public var minSpeedFactor = 0.35
    public var serviceTimePerInch = 0.10
    public var heavySnowServiceBonus = 0.20
    public var maxServiceTimeFactor = 3.0

    public init() {}

    /// 1.0 = normal speed, 0.5 = twice as slow.
    public func speedFactor(_ c: WeatherConditions) -> Double {
        var slow = slowdownPerInch * max(c.accumulationInches, 0)
        let precipitating = c.snowfallRateInPerHour > 0 || c.accumulationInches > 0
        if c.snowfallRateInPerHour >= heavySnowRateInPerHour { slow += heavySnowSlowdown }
        if precipitating && icyTemperatureRangeF.contains(c.temperatureF) { slow += icySlowdown }
        if c.windMph > windThresholdMph { slow += (c.windMph - windThresholdMph) * slowdownPerMphOverThreshold }
        if c.visibilityMiles < lowVisibilityMiles { slow += lowVisibilitySlowdown }
        return max(minSpeedFactor, 1 - slow)
    }

    /// 1.0 = normal time per site. Deep snow and heavy fall take longer to clear.
    public func serviceTimeFactor(_ c: WeatherConditions) -> Double {
        var f = 1 + serviceTimePerInch * max(c.accumulationInches, 0)
        if c.snowfallRateInPerHour >= heavySnowRateInPerHour { f += heavySnowServiceBonus }
        return min(f, maxServiceTimeFactor)
    }
}

/// Learns a real speed factor from past drives: expected seconds vs what the crew actually took.
public enum SpeedCalibrator {
    public struct Observation: Equatable, Sendable {
        public var expectedSeconds: Double
        public var actualSeconds: Double
        public init(expectedSeconds: Double, actualSeconds: Double) {
            self.expectedSeconds = expectedSeconds
            self.actualSeconds = actualSeconds
        }
    }

    /// Median of expected/actual (below 1 means slower than expected). Needs at least `minimum` drives.
    public static func observedFactor(_ observations: [Observation], minimum: Int = 5) -> Double? {
        let ratios = observations
            .filter { $0.expectedSeconds > 0 && $0.actualSeconds > 0 }
            .map { $0.expectedSeconds / $0.actualSeconds }
            .sorted()
        guard ratios.count >= minimum else { return nil }
        let mid = ratios.count / 2
        let median = ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2
        return min(max(median, 0.3), 1.5)
    }

    /// Mix the model's guess with the observed value. `weight` is how much to trust the observation (0...1).
    public static func blend(model: Double, observed: Double?, weight: Double = 0.6) -> Double {
        guard let observed else { return model }
        let w = min(max(weight, 0), 1)
        return model * (1 - w) + observed * w
    }
}
