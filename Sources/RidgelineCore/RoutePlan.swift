import Foundation

// The route planner screen: where the day starts and ends, a lunch break, one-off stops that are not client jobs,
// the order the crew drives (optimized or dragged by hand) and the clock time at every stop.

/// A break the crew takes once they have worked a while (driving plus time on site).
public struct RouteBreak: Equatable, Codable, Sendable {
    public var minutes: Int
    /// The break starts after the first stop that brings the work time to this many hours.
    public var afterHours: Double

    public init(minutes: Int = 30, afterHours: Double = 4) {
        self.minutes = minutes
        self.afterHours = afterHours
    }
}

/// How every route starts and ends. Saved once, used every day.
public struct RouteSettings: Equatable, Codable, Sendable {
    public enum StartKind: String, Codable, CaseIterable, Sendable { case yard, custom }
    public enum FinishKind: String, Codable, CaseIterable, Sendable { case returnToStart, endAtLastStop, custom }

    public var startKind: StartKind = .yard
    /// Used when `startKind` is custom.
    public var startAddress: String = ""
    public var startCoordinate: Coordinate?
    /// When the truck leaves, in minutes after midnight.
    public var startMinutes: Int = 7 * 60
    public var finishKind: FinishKind = .returnToStart
    /// Used when `finishKind` is custom.
    public var finishAddress: String = ""
    public var finishCoordinate: Coordinate?
    /// Nil means no break.
    public var defaultBreak: RouteBreak?
    /// Time on site for stops added from the planner.
    public var defaultServiceMinutes: Int = 20

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case startKind, startAddress, startCoordinate, startMinutes, finishKind, finishAddress, finishCoordinate, defaultBreak, defaultServiceMinutes
    }

    // Every field falls back to its default, so files from older or newer versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startKind = (try? c.decodeIfPresent(StartKind.self, forKey: .startKind)) ?? .yard
        startAddress = try c.decodeIfPresent(String.self, forKey: .startAddress) ?? ""
        startCoordinate = try c.decodeIfPresent(Coordinate.self, forKey: .startCoordinate)
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 7 * 60
        finishKind = (try? c.decodeIfPresent(FinishKind.self, forKey: .finishKind)) ?? .returnToStart
        finishAddress = try c.decodeIfPresent(String.self, forKey: .finishAddress) ?? ""
        finishCoordinate = try c.decodeIfPresent(Coordinate.self, forKey: .finishCoordinate)
        defaultBreak = try c.decodeIfPresent(RouteBreak.self, forKey: .defaultBreak)
        defaultServiceMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultServiceMinutes) ?? 20
    }

    /// Keeps values in sensible ranges.
    public func cleaned() -> RouteSettings {
        var s = self
        s.startMinutes = min(max(startMinutes, 0), 24 * 60 - 1)
        s.startAddress = String(startAddress.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        s.finishAddress = String(finishAddress.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        s.defaultServiceMinutes = min(max(defaultServiceMinutes, 1), 240)
        if var b = s.defaultBreak {
            b.minutes = min(max(b.minutes, 5), 120)
            b.afterHours = min(max(b.afterHours, 0), 12)
            s.defaultBreak = b
        }
        return s
    }
}

/// A one-off stop for one day that is not a client job: the dump, the salt yard, a quick favour.
public struct AdHocStop: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    /// The day it belongs to, like "2027-01-15" (see `Job.dayKey`).
    public var day: String
    public var address: String
    public var coordinate: Coordinate
    public var serviceMinutes: Int
    public var note: String
    /// The team member who added it. Nil for the owner.
    public var createdBy: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), day: String, address: String, coordinate: Coordinate, serviceMinutes: Int = 20,
                note: String = "", createdBy: UUID? = nil, createdAt: Date) {
        self.id = id
        self.day = day
        self.address = address
        self.coordinate = coordinate
        self.serviceMinutes = serviceMinutes
        self.note = note
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    public var stop: Stop {
        Stop(id: id, name: address, coordinate: coordinate, priority: 3, serviceMinutes: Double(min(max(serviceMinutes, 1), 240)))
    }
}

/// The order the crew drives on one day. `optimized` turns false once someone drags a stop, and the order is kept
/// until they tap Optimize again.
public struct SavedRouteOrder: Equatable, Codable, Sendable {
    public var day: String
    public var stopIDs: [UUID]
    public var optimized: Bool

    public init(day: String, stopIDs: [UUID], optimized: Bool) {
        self.day = day
        self.stopIDs = stopIDs
        self.optimized = optimized
    }
}

/// One stop with its clock times.
public struct TimedStop: Equatable, Sendable {
    public let stop: Stop
    /// Drive from the previous stop (or the start).
    public let driveSeconds: Double
    public let arrivalOffsetSeconds: Double
    public let departureOffsetSeconds: Double
    public let arrival: Date
    public let departure: Date
    /// True when the break is taken just before driving to this stop.
    public let breakBefore: Bool
}

/// A day's route with clock times, a break and totals, for "5h 32m · 19 stops".
public struct RouteDayPlan: Equatable, Sendable {
    public let stops: [TimedStop]
    public let startTime: Date
    public let finishDriveSeconds: Double
    /// When the truck reaches the finish (or leaves the last stop when the route ends there).
    public let endTime: Date
    public let breakStart: Date?
    public let driveSeconds: Double
    public let serviceSeconds: Double
    public let breakSeconds: Double

    public var totalSeconds: Double { driveSeconds + serviceSeconds + breakSeconds }
    public var stopCount: Int { stops.count }
    /// Stops whose arrival is after their deadline.
    public var lateStopIDs: [UUID] {
        stops.filter { t in t.stop.deadlineSeconds.map { t.arrivalOffsetSeconds > $0 } ?? false }.map(\.stop.id)
    }

    /// The same route in the shape the rest of the app reads (Home map numbers, auto check-in, client texts).
    public var result: RoutePlanResult {
        RoutePlanResult(planned: stops.map { PlannedStop(stop: $0.stop, driveSeconds: $0.driveSeconds, arrivalOffsetSeconds: $0.arrivalOffsetSeconds) },
                        lateStopIDs: lateStopIDs)
    }
}

public enum RouteDayPlanner {
    /// Clock times for stops in the given order: start time, then drive and time on site for each stop, with the break
    /// taken once, after the first stop that brings the work time (drive plus service) to the break threshold. The break
    /// only falls between stops: never before the first stop or after the last one.
    public static func timeline(order: [Stop], start: Coordinate, end: Coordinate?, startTime: Date,
                                breakRule: RouteBreak?, provider: DriveTimeProvider) -> RouteDayPlan {
        var here = start
        var clock = 0.0
        var work = 0.0
        var drive = 0.0
        var service = 0.0
        var breakAt: Double?
        var breakSeconds = 0.0
        var out: [TimedStop] = []
        for (i, s) in order.enumerated() {
            var breakBefore = false
            if i > 0, breakAt == nil, let rule = breakRule, rule.minutes > 0, work >= rule.afterHours * 3600 {
                breakAt = clock
                breakSeconds = Double(rule.minutes) * 60
                clock += breakSeconds
                breakBefore = true
            }
            let d = provider.seconds(from: here, to: s.coordinate)
            clock += d
            work += d
            drive += d
            let arrival = clock
            let onSite = max(s.serviceMinutes, 0) * 60
            clock += onSite
            work += onSite
            service += onSite
            out.append(TimedStop(stop: s, driveSeconds: d, arrivalOffsetSeconds: arrival, departureOffsetSeconds: clock,
                                 arrival: startTime.addingTimeInterval(arrival), departure: startTime.addingTimeInterval(clock),
                                 breakBefore: breakBefore))
            here = s.coordinate
        }
        var finish = 0.0
        if let end, !order.isEmpty {
            finish = provider.seconds(from: here, to: end)
            clock += finish
            drive += finish
        }
        return RouteDayPlan(stops: out, startTime: startTime, finishDriveSeconds: finish, endTime: startTime.addingTimeInterval(clock),
                            breakStart: breakAt.map { startTime.addingTimeInterval($0) }, driveSeconds: drive, serviceSeconds: service,
                            breakSeconds: breakSeconds)
    }

    /// Orders the stops to drive the least (counting the drive to the finish), then works out the clock times.
    public static func optimize(stops: [Stop], start: Coordinate, end: Coordinate?, startTime: Date, breakRule: RouteBreak?,
                                provider: DriveTimeProvider) -> RouteDayPlan {
        let ordered = RouteOptimizer.optimize(stops: stops, start: start, provider: provider, end: end).stops
        return timeline(order: ordered, start: start, end: end, startTime: startTime, breakRule: breakRule, provider: provider)
    }

    /// Puts stops in a saved order. Stops added since go at the end; stops that are gone are dropped.
    public static func apply(order saved: [UUID], to stops: [Stop]) -> [Stop] {
        var byID: [UUID: Stop] = [:]
        for s in stops where byID[s.id] == nil { byID[s.id] = s }
        var seen = Set<UUID>()
        var out: [Stop] = []
        for id in saved {
            guard let s = byID[id], seen.insert(id).inserted else { continue }
            out.append(s)
        }
        for s in stops where seen.insert(s.id).inserted { out.append(s) }
        return out
    }
}

/// Short text for the planner screen.
public enum RouteText {
    /// "5h 32m", "45m", "0m".
    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "5h 32m · 19 stops".
    public static func summary(_ plan: RouteDayPlan) -> String {
        "\(duration(plan.totalSeconds)) · \(plan.stopCount) stop\(plan.stopCount == 1 ? "" : "s")"
    }

    /// "12 Main St, Burlington, VT 05401" becomes ("12 Main St", "Burlington, VT 05401").
    public static func addressLines(_ address: String) -> (street: String, rest: String) {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = text.firstIndex(of: ",") else { return (text, "") }
        let street = text[..<comma].trimmingCharacters(in: .whitespaces)
        let rest = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (street, rest)
    }

    /// "Maple Street Dental" becomes "MS". At most two letters.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

extension AppData {
    // MARK: settings

    /// Where the truck starts: the custom address when set and found on the map, otherwise the yard.
    public var routeStartCoordinate: Coordinate? {
        if routeSettings.startKind == .custom, let c = routeSettings.startCoordinate { return c }
        return depot
    }

    /// Where the truck finishes. Nil when the route ends at the last stop.
    public func routeFinishCoordinate(start: Coordinate?) -> Coordinate? {
        switch routeSettings.finishKind {
        case .returnToStart: return start
        case .endAtLastStop: return nil
        case .custom: return routeSettings.finishCoordinate
        }
    }

    /// When the truck leaves on `day`.
    public func routeStartTime(on day: Date, calendar: Calendar = .current) -> Date {
        let m = min(max(routeSettings.startMinutes, 0), 24 * 60 - 1)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) ?? calendar.startOfDay(for: day)
    }

    public mutating func setRouteSettings(_ settings: RouteSettings) {
        routeSettings = settings.cleaned()
    }

    // MARK: stops

    /// One-off stops for `day` that this person may see: everyone's for the owner and those who see all jobs, otherwise their own.
    public func adHocStops(on day: Date, calendar: Calendar = .current) -> [AdHocStop] {
        let key = Job.dayKey(day, calendar: calendar)
        let me = currentMember?.id
        return adHocStops.filter { $0.day == key && (can(.viewAllJobs) || ($0.createdBy != nil && $0.createdBy == me)) }
    }

    /// Everything the planner routes on `day`: the open client jobs with a place on the map, then the one-off stops.
    public func plannerStops(on day: Date, calendar: Calendar = .current) -> [Stop] {
        routeStops(on: day, calendar: calendar) + adHocStops(on: day, calendar: calendar).map(\.stop)
    }

    public func routeOrder(on day: Date, calendar: Calendar = .current) -> SavedRouteOrder? {
        let key = Job.dayKey(day, calendar: calendar)
        return routeOrders.first { $0.day == key }
    }

    /// The planner's stops in the saved order (optimized or dragged). New stops go at the end.
    public func orderedPlannerStops(on day: Date, calendar: Calendar = .current) -> [Stop] {
        let stops = plannerStops(on: day, calendar: calendar)
        guard let saved = routeOrder(on: day, calendar: calendar) else { return stops }
        return RouteDayPlanner.apply(order: saved.stopIDs, to: stops)
    }

    /// Saves the order for `day`. `optimized` is false when the user dragged stops by hand.
    public mutating func setRouteOrder(_ ids: [UUID], on day: Date, optimized: Bool, calendar: Calendar = .current) {
        let key = Job.dayKey(day, calendar: calendar)
        // The order is shared by everyone, but an employee who sees only their own stops orders only those. Their stops
        // take the places they already held, and every stop they cannot see keeps its place.
        var mine = Set<UUID>()
        let fresh = ids.filter { mine.insert($0).inserted }
        var next = fresh.makeIterator()
        var merged: [UUID] = []
        for old in routeOrders.first(where: { $0.day == key })?.stopIDs ?? [] {
            if !mine.contains(old) {
                merged.append(old)
            } else if let id = next.next() {
                merged.append(id)
            }
        }
        while let id = next.next() { merged.append(id) }
        routeOrders.removeAll { $0.day == key }
        routeOrders.append(SavedRouteOrder(day: key, stopIDs: merged, optimized: optimized))
    }

    @discardableResult
    public mutating func addAdHocStop(address: String, coordinate: Coordinate, on day: Date, serviceMinutes: Int? = nil, note: String = "",
                                      now: Date, calendar: Calendar = .current) throws -> AdHocStop {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OperationError.emptyName }
        pruneOldRouteDays(now: now, calendar: calendar)
        let stop = AdHocStop(day: Job.dayKey(day, calendar: calendar), address: String(clean.prefix(200)), coordinate: coordinate,
                             serviceMinutes: min(max(serviceMinutes ?? routeSettings.defaultServiceMinutes, 1), 240),
                             note: String(note.prefix(500)), createdBy: currentMember?.id, createdAt: now)
        adHocStops.append(stop)
        return stop
    }

    public mutating func updateAdHocStop(id: UUID, serviceMinutes: Int, note: String) throws {
        guard let i = adHocStops.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        adHocStops[i].serviceMinutes = min(max(serviceMinutes, 1), 240)
        adHocStops[i].note = String(note.prefix(500))
    }

    public mutating func removeAdHocStop(id: UUID) throws {
        guard adHocStops.contains(where: { $0.id == id }) else { throw OperationError.notFound }
        adHocStops.removeAll { $0.id == id }
        for i in routeOrders.indices { routeOrders[i].stopIDs.removeAll { $0 == id } }
    }

    /// Time on site for a job, which the route uses as its service time.
    public mutating func setJobServiceMinutes(_ minutes: Int, id: UUID) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        jobs[i].durationMinutes = min(max(minutes, 5), 240)
    }

    /// One-off stops and saved orders older than 30 days are not needed any more.
    mutating func pruneOldRouteDays(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return }
        let key = Job.dayKey(cutoff, calendar: calendar)
        adHocStops.removeAll { $0.day < key }
        routeOrders.removeAll { $0.day < key }
    }
}
