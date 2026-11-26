import Foundation

// Automatic arrival and departure: the phone's GPS fixes go in, "arrived at" and "left" come out, and the route moves
// on to the next stop by itself. Pure logic with no CoreLocation, so it is tested here and fed by the app.

/// One position from the phone's GPS.
public struct LocationFix: Equatable, Sendable {
    public var coordinate: Coordinate
    /// How far off the position may be, in meters. Negative means the phone could not tell.
    public var accuracyMeters: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, accuracyMeters: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.accuracyMeters = accuracyMeters
        self.timestamp = timestamp
    }
}

/// One stop on today's route that the crew can be checked in to.
public struct CheckInStop: Identifiable, Equatable, Sendable {
    /// The job id (the same id the route uses).
    public let id: UUID
    public var siteID: UUID?
    public var name: String
    public var coordinate: Coordinate
    /// The stop before it in the planned route, and the planned drive time from there. Nil without a plan.
    public var previousStopID: UUID?
    public var driveSecondsFromPrevious: Double?

    public init(id: UUID, siteID: UUID? = nil, name: String, coordinate: Coordinate, previousStopID: UUID? = nil,
                driveSecondsFromPrevious: Double? = nil) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.coordinate = coordinate
        self.previousStopID = previousStopID
        self.driveSecondsFromPrevious = driveSecondsFromPrevious
    }
}

/// When a fix counts as arrived or left.
public struct CheckInRules: Equatable, Sendable {
    /// Arrived: within this distance of the site...
    public var arriveRadiusMeters: Double
    /// ...for at least this long.
    public var arriveAfterSeconds: Double
    /// Fixes this inaccurate or worse are ignored.
    public var maxAccuracyMeters: Double
    /// Left: farther than this from the site after arriving.
    public var departRadiusMeters: Double
    /// Good fixes in a row that must be outside before "left" counts, so one bad jump is not a departure.
    public var departConfirmFixes: Int
    /// A longer silence between fixes near a site restarts the arrival clock (the phone was asleep or the app was closed).
    public var maxGapSeconds: Double

    public init(arriveRadiusMeters: Double = 60, arriveAfterSeconds: Double = 45, maxAccuracyMeters: Double = 50,
                departRadiusMeters: Double = 120, departConfirmFixes: Int = 2, maxGapSeconds: Double = 120) {
        self.arriveRadiusMeters = arriveRadiusMeters
        self.arriveAfterSeconds = arriveAfterSeconds
        self.maxAccuracyMeters = maxAccuracyMeters
        self.departRadiusMeters = departRadiusMeters
        self.departConfirmFixes = max(departConfirmFixes, 1)
        self.maxGapSeconds = maxGapSeconds
    }
}

public enum CheckInEvent: Equatable, Sendable {
    /// `at` is when the crew first came within range, not when the wait ended.
    case arrived(stopID: UUID, at: Date)
    /// `at` is the first fix outside the departure distance.
    case departed(stopID: UUID, at: Date)
}

/// Decides arrivals and departures from a stream of fixes. Each stop is arrived at once at most.
public struct ArrivalTracker: Equatable, Sendable {
    public let rules: CheckInRules
    /// Route order.
    public private(set) var stops: [CheckInStop]
    /// Stops arrived at (including the one the crew is at now and the ones already left).
    public private(set) var arrivedIDs: Set<UUID>
    /// Stops the crew arrived at and then left.
    public private(set) var finishedIDs: Set<UUID>
    /// The stop the crew is at right now.
    public private(set) var currentStopID: UUID?
    public private(set) var lastDepartedID: UUID?
    /// The last fix that was used (accurate and newer than the one before).
    public private(set) var lastFix: LocationFix?

    private var candidateID: UUID?
    private var candidateSince: Date?
    private var candidateLastSeen: Date?
    private var departCount = 0
    private var departFirstSeen: Date?

    /// `arrivedIDs` and `finishedIDs` come from check-ins already saved today, so turning the switch off and on again
    /// never logs the same arrival twice. A stop arrived at but not left is treated as where the crew is now.
    public init(stops: [CheckInStop], arrivedIDs: Set<UUID> = [], finishedIDs: Set<UUID> = [], rules: CheckInRules = CheckInRules()) {
        self.rules = rules
        self.stops = stops
        self.finishedIDs = finishedIDs
        self.arrivedIDs = arrivedIDs.union(finishedIDs)
        self.currentStopID = stops.first { arrivedIDs.contains($0.id) && !finishedIDs.contains($0.id) }?.id
    }

    /// The first stop in route order not yet arrived at.
    public var nextStop: CheckInStop? { stops.first { !arrivedIDs.contains($0.id) } }
    public var currentStop: CheckInStop? { currentStopID.flatMap { stop($0) } }
    /// Every stop arrived at and left.
    public var isRouteDone: Bool { !stops.isEmpty && currentStopID == nil && nextStop == nil }

    public func stop(_ id: UUID) -> CheckInStop? { stops.first { $0.id == id } }

    /// Takes one fix and returns what happened: nothing, an arrival, a departure, or a departure then nothing more.
    /// Inaccurate fixes, repeated fixes and fixes older than the last one are ignored.
    public mutating func ingest(_ fix: LocationFix) -> [CheckInEvent] {
        guard fix.accuracyMeters >= 0, fix.accuracyMeters < rules.maxAccuracyMeters else { return [] }
        if let last = lastFix, fix.timestamp <= last.timestamp { return [] }
        lastFix = fix
        var events: [CheckInEvent] = []

        if let id = currentStopID, let here = stop(id) {
            guard Geo.distanceMeters(fix.coordinate, here.coordinate) > rules.departRadiusMeters else {
                departCount = 0
                departFirstSeen = nil
                return []
            }
            if departCount == 0 { departFirstSeen = fix.timestamp }
            departCount += 1
            guard departCount >= rules.departConfirmFixes else { return [] }
            events.append(.departed(stopID: id, at: departFirstSeen ?? fix.timestamp))
            finishedIDs.insert(id)
            lastDepartedID = id
            currentStopID = nil
            departCount = 0
            departFirstSeen = nil
        } else if currentStopID != nil {
            currentStopID = nil   // the stop was taken off the route
        }

        let inRange = stops
            .filter { !arrivedIDs.contains($0.id) }
            .map { ($0, Geo.distanceMeters(fix.coordinate, $0.coordinate)) }
            .filter { $0.1 <= rules.arriveRadiusMeters }
            .min { $0.1 < $1.1 }?.0
        guard let site = inRange else {
            // A fix just outside the circle while parked (GPS jitter) keeps the clock running; driving off clears it.
            if let id = candidateID, let c = stop(id), Geo.distanceMeters(fix.coordinate, c.coordinate) <= rules.departRadiusMeters {
                return events
            }
            clearCandidate()
            return events
        }
        if candidateID == site.id, let since = candidateSince, let seen = candidateLastSeen,
           fix.timestamp.timeIntervalSince(seen) <= rules.maxGapSeconds {
            candidateLastSeen = fix.timestamp
            if fix.timestamp.timeIntervalSince(since) >= rules.arriveAfterSeconds {
                events.append(.arrived(stopID: site.id, at: since))
                arrivedIDs.insert(site.id)
                currentStopID = site.id
                clearCandidate()
            }
        } else {
            candidateID = site.id
            candidateSince = fix.timestamp
            candidateLastSeen = fix.timestamp
        }
        return events
    }

    /// Drive time to the next stop: the planned time when the crew just left the stop before it in the plan,
    /// otherwise an estimate from the last fix.
    public func secondsToNextStop(provider: DriveTimeProvider = HaversineDriveTime()) -> Double? {
        guard let next = nextStop else { return nil }
        if let left = lastDepartedID, next.previousStopID == left, let planned = next.driveSecondsFromPrevious {
            return planned
        }
        guard let here = lastFix?.coordinate else { return nil }
        return provider.seconds(from: here, to: next.coordinate)
    }

    /// Swaps in a changed route (a job added or re-planned) and keeps what already happened. Stops already arrived at
    /// stay on the list (in front) even when the new route leaves them out because they are done.
    public mutating func updateStops(_ newStops: [CheckInStop]) {
        let newIDs = Set(newStops.map(\.id))
        stops = stops.filter { arrivedIDs.contains($0.id) && !newIDs.contains($0.id) } + newStops
        if let id = currentStopID, stop(id) == nil { currentStopID = nil }
        if let id = candidateID, stop(id) == nil { clearCandidate() }
    }

    private mutating func clearCandidate() {
        candidateID = nil
        candidateSince = nil
        candidateLastSeen = nil
    }
}

/// The short lines shown in the banner.
public enum CheckInText {
    public static func arrived(_ name: String) -> String { "Arrived at \(name)" }
    public static func left(_ name: String) -> String { "Left \(name)" }

    public static func next(_ name: String, seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "Next: \(name)" }
        return "Next: \(name), \(minutes(seconds)) min"
    }

    /// Whole minutes, never "0 min".
    public static func minutes(_ seconds: Double) -> Int { max(1, Int((seconds / 60).rounded())) }

    public static let routeDone = "That was the last stop on today's route."
}

// MARK: - Saved on the job

/// When the crew got to a job and left it, saved by automatic check-in.
public struct JobCheckIn: Equatable, Codable, Sendable {
    public var arrivedAt: Date
    public var departedAt: Date?

    public init(arrivedAt: Date, departedAt: Date? = nil) {
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
    }
}

public enum AutoCheckInError: Error, Equatable, LocalizedError {
    case notAllowed

    public var errorDescription: String? {
        switch self {
        case .notAllowed: return "You can only check in to your own jobs."
        }
    }
}

extension Job {
    /// The automatic check-in for the visit on `day`, if there is one.
    public func checkIn(on day: Date, calendar: Calendar = .current) -> JobCheckIn? {
        checkIns?[Job.dayKey(day, calendar: calendar)]
    }
}

extension AppData {
    /// The owner can check in to any job. An employee needs "Log visits" and only gets the jobs assigned to them,
    /// even if they may see every job.
    public func canAutoCheckIn(_ job: Job) -> Bool {
        guard !job.isTask, can(.logVisits) else { return false }
        if isOwnerSession { return true }
        guard let me = currentMember?.id else { return false }
        return job.assigneeIDs.contains(me)
    }

    /// Today's route for automatic check-in: open jobs with a map location that this person may check in to,
    /// in the planned order when there is a plan, otherwise in the route's own order.
    public func autoCheckInStops(on day: Date, plan: RoutePlanResult? = nil, calendar: Calendar = .current) -> [CheckInStop] {
        let dayJobs = Dictionary(jobs(on: day, calendar: calendar).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allowed = routeStops(on: day, calendar: calendar).filter { stop in dayJobs[stop.id].map { canAutoCheckIn($0) } ?? false }
        var ordered = allowed
        var drive: [UUID: Double] = [:]
        var planPrevious: [UUID: UUID] = [:]
        if let plan {
            let rank = Dictionary(plan.stops.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
            ordered = allowed.enumerated()
                .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
                .map(\.element)
            for (i, p) in plan.planned.enumerated() {
                drive[p.stop.id] = p.driveSeconds
                if i > 0 { planPrevious[p.stop.id] = plan.planned[i - 1].stop.id }
            }
        }
        // The plan's time for its first stop is from the yard, so only stop-to-stop times are kept.
        return ordered.map { s -> CheckInStop in
            let previous = planPrevious[s.id]
            return CheckInStop(id: s.id, siteID: dayJobs[s.id]?.siteID, name: s.name, coordinate: s.coordinate,
                               previousStopID: previous, driveSecondsFromPrevious: previous == nil ? nil : drive[s.id])
        }
    }

    /// Which of these stops already have an arrival, and which a departure, saved for `day`.
    public func savedCheckIns(for stops: [CheckInStop], on day: Date, calendar: Calendar = .current) -> (arrived: Set<UUID>, finished: Set<UUID>) {
        var arrived = Set<UUID>(), finished = Set<UUID>()
        for s in stops {
            guard let c = jobs.first(where: { $0.id == s.id })?.checkIn(on: day, calendar: calendar) else { continue }
            arrived.insert(s.id)
            if c.departedAt != nil { finished.insert(s.id) }
        }
        return (arrived, finished)
    }

    /// Saves the arrival time on the job and marks the visit in progress. Returns false when an arrival was already
    /// saved for that day (a duplicate), which changes nothing.
    @discardableResult
    public mutating func recordArrival(jobID: UUID, at time: Date, calendar: Calendar = .current) throws -> Bool {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { throw OperationError.notFound }
        guard canAutoCheckIn(jobs[i]) else { throw AutoCheckInError.notAllowed }
        let day = overnightVisitDay(of: jobs[i], at: time, calendar: calendar) ?? time
        let key = Job.dayKey(day, calendar: calendar)
        var map = jobs[i].checkIns ?? [:]
        guard map[key] == nil else { return false }
        map[key] = JobCheckIn(arrivedAt: time)
        jobs[i].checkIns = map
        if jobs[i].occurrenceStatus(on: day, calendar: calendar) == .scheduled {
            try setOccurrenceStatus(.inProgress, id: jobID, on: day, calendar: calendar)
        }
        return true
    }

    /// A route that runs past midnight: a repeating job with no visit on the day of `time` but one still open the day
    /// before is checked in to under that day before. Nil in every other case.
    func overnightVisitDay(of job: Job, at time: Date, calendar: Calendar) -> Date? {
        guard job.repeats, job.occurrenceStart(on: time, calendar: calendar) == nil,
              let eve = calendar.date(byAdding: .day, value: -1, to: time),
              job.occurrenceStart(on: eve, calendar: calendar) != nil,
              job.occurrenceStatus(on: eve, calendar: calendar).isOpen else { return nil }
        return eve
    }

    /// Saves the departure time and, when `markDone` is true, marks the visit done. A second departure keeps the first time.
    /// A crew that arrived before midnight and leaves after it is leaving that same visit: the departure goes on the
    /// arrival's day. Returns the day of the visit that was left, for marking it done later.
    @discardableResult
    public mutating func recordDeparture(jobID: UUID, at time: Date, markDone: Bool, calendar: Calendar = .current) throws -> Date {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { throw OperationError.notFound }
        guard canAutoCheckIn(jobs[i]) else { throw AutoCheckInError.notAllowed }
        var map = jobs[i].checkIns ?? [:]
        var day = time
        if map[Job.dayKey(time, calendar: calendar)] == nil {
            if let eve = calendar.date(byAdding: .day, value: -1, to: time),
               let open = map[Job.dayKey(eve, calendar: calendar)], open.departedAt == nil {
                day = eve
            } else if let eve = overnightVisitDay(of: jobs[i], at: time, calendar: calendar) {
                day = eve
            }
        }
        let key = Job.dayKey(day, calendar: calendar)
        var entry = map[key] ?? JobCheckIn(arrivedAt: time)
        if entry.departedAt == nil { entry.departedAt = max(time, entry.arrivedAt) }
        map[key] = entry
        jobs[i].checkIns = map
        if markDone && jobs[i].occurrenceStatus(on: day, calendar: calendar).isOpen {
            try setOccurrenceStatus(.done, id: jobID, on: day, calendar: calendar)
        }
        return day
    }

    /// The owner's choice: mark a job done as soon as the crew leaves it, or ask first.
    public mutating func setAutoCheckInMarksDone(_ on: Bool) throws {
        guard isOwnerSession else { throw AutoCheckInError.notAllowed }
        autoCheckInMarksDone = on
    }
}
