import Foundation

public struct TimeAdjustment: Equatable, Codable, Sendable {
    public var by: String
    public var reason: String
    public var at: Date
    public var oldStart: Date
    public var oldEnd: Date?
}

/// A shift or a per-job timer. Missed punches can be corrected, but every correction is kept.
public struct TimeEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var memberName: String
    public var start: Date
    public var end: Date?
    /// Set for per-job timers.
    public var siteID: UUID?
    public var adjustments: [TimeAdjustment]

    public init(id: UUID = UUID(), memberName: String, start: Date, end: Date? = nil,
                siteID: UUID? = nil, adjustments: [TimeAdjustment] = []) {
        self.id = id
        self.memberName = memberName
        self.start = start
        self.end = end
        self.siteID = siteID
        self.adjustments = adjustments
    }

    public func hours(now: Date) -> Double {
        max((end ?? now).timeIntervalSince(start), 0) / 3600
    }

    public func adjusted(newStart: Date, newEnd: Date?, by: String, reason: String, at: Date) -> TimeEntry {
        var copy = self
        copy.adjustments.append(TimeAdjustment(by: by, reason: reason, at: at, oldStart: start, oldEnd: end))
        copy.start = newStart
        copy.end = newEnd
        return copy
    }
}

public enum Timesheet {
    public static func totalHours(_ entries: [TimeEntry], member: String, from: Date, to: Date, now: Date) -> Double {
        entries
            .filter { $0.memberName == member && $0.start >= from && $0.start < to }
            .reduce(0) { $0 + $1.hours(now: now) }
    }

    /// Labor cost for one site's job timers.
    public static func laborCost(_ entries: [TimeEntry], site: UUID, hourlyRate: Money, now: Date) -> Money {
        let hours = entries.filter { $0.siteID == site }.reduce(0) { $0 + $1.hours(now: now) }
        return Money(cents: Int((Double(hourlyRate.cents) * hours).rounded()))
    }

    /// People still clocked in after a long time, likely a missed punch-out.
    public static func openLongerThan(_ entries: [TimeEntry], hours limit: Double, now: Date) -> [TimeEntry] {
        entries.filter { $0.end == nil && $0.hours(now: now) > limit }
    }
}

public enum GeofencePrompt {
    /// Prompt, don't auto-punch: ask "You arrived, start the job?" once the crew is inside the radius.
    public static func shouldPrompt(distanceMeters: Double, radiusMeters: Double = 75, alreadyClockedIn: Bool) -> Bool {
        !alreadyClockedIn && distanceMeters <= radiusMeters
    }

    /// iOS limits region monitoring to 20 regions, so only monitor the next few stops.
    public static func regionsToMonitor(nextStops: [Stop], limit: Int = 20) -> [Stop] {
        Array(nextStops.prefix(min(limit, 20)))
    }
}
