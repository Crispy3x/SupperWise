import Foundation

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case scheduled, inProgress, done, cancelled

    public var title: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }
    public var isOpen: Bool { self == .scheduled || self == .inProgress }
}

public enum JobKind: String, Codable, CaseIterable, Sendable {
    case snowPlowing, salting, lawnCare, cleanup, other

    public var title: String {
        switch self {
        case .snowPlowing: return "Snow plowing"
        case .salting: return "Salting"
        case .lawnCare: return "Lawn care"
        case .cleanup: return "Cleanup"
        case .other: return "Other"
        }
    }
}

/// Something on the schedule: a job at a client's site, or a reminder or task with no site.
public struct Job: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: JobKind
    public var customerID: UUID?
    public var siteID: UUID?
    public var start: Date
    public var durationMinutes: Int
    public var status: JobStatus
    public var assigneeIDs: [UUID]
    public var notes: String
    /// True for a reminder or task. These show on the calendar but not in the Jobs list, on the map or in the route.
    public var isTask: Bool
    public var createdAt: Date
    /// How often the job comes back (see RecurringJobs.swift). Nil means it happens once.
    public var repeatRule: RepeatRule?
    /// For a repeating job: visits that are done, skipped or in progress, by day ("2027-01-15"). Other visits are scheduled.
    public var occurrenceStatuses: [String: JobStatus]?
    /// Texts sent to the client about this job, like "On my way" (see ClientTexts.swift). Nil when none were sent.
    public var clientTexts: [ClientTextLogEntry]? = nil
    /// Automatic arrival and departure times, by day ("2027-01-15"), see AutoCheckIn.swift. Nil when none were saved.
    public var checkIns: [String: JobCheckIn]? = nil

    public init(id: UUID = UUID(), title: String, kind: JobKind = .other, customerID: UUID? = nil, siteID: UUID? = nil,
                start: Date, durationMinutes: Int = 60, status: JobStatus = .scheduled, assigneeIDs: [UUID] = [],
                notes: String = "", isTask: Bool = false, createdAt: Date) {
        self.id = id
        self.title = title
        self.kind = kind
        self.customerID = customerID
        self.siteID = siteID
        self.start = start
        self.durationMinutes = durationMinutes
        self.status = status
        self.assigneeIDs = assigneeIDs
        self.notes = notes
        self.isTask = isTask
        self.createdAt = createdAt
    }
}

extension AppData {
    @discardableResult
    public mutating func addJob(title: String, kind: JobKind = .other, customerID: UUID? = nil, siteID: UUID? = nil, start: Date,
                                durationMinutes: Int = 60, assigneeIDs: [UUID] = [], notes: String = "", isTask: Bool = false,
                                now: Date) throws -> Job {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OperationError.emptyName }
        if let siteID, !sites.contains(where: { $0.id == siteID }) { throw OperationError.notFound }
        if let customerID, !customers.contains(where: { $0.id == customerID }) { throw OperationError.notFound }
        let job = Job(title: String(clean.prefix(120)), kind: kind, customerID: customerID, siteID: siteID, start: start,
                      durationMinutes: min(max(durationMinutes, 5), 24 * 60), assigneeIDs: assigneeIDs.filter { id in team.contains { $0.id == id } },
                      notes: String(notes.prefix(1000)), isTask: isTask, createdAt: now)
        jobs.append(job)
        return job
    }

    public mutating func setJobStatus(_ status: JobStatus, id: UUID) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { throw OperationError.notFound }
        jobs[i].status = status
    }

    public mutating func deleteJob(_ id: UUID) throws {
        guard jobs.contains(where: { $0.id == id }) else { throw OperationError.notFound }
        jobs.removeAll { $0.id == id }
    }

    /// Jobs this person may see: the owner and anyone allowed to see all jobs get everything; others only what is assigned to them.
    public var visibleJobs: [Job] {
        if can(.viewAllJobs) { return jobs }
        guard let id = currentMember?.id else { return [] }
        return jobs.filter { $0.assigneeIDs.contains(id) }
    }

    public func jobs(on day: Date, calendar: Calendar = .current) -> [Job] {
        // Repeating jobs come back as that day's visit: same id, that day's start and status.
        visibleJobs.compactMap { $0.occurrence(on: day, calendar: calendar) }.sorted { $0.start < $1.start }
    }

    /// Days of the month containing `date` that have something scheduled (for the dots on the calendar).
    public func daysWithJobs(inMonthOf date: Date, calendar: Calendar = .current) -> Set<Int> {
        visibleJobs.reduce(into: Set<Int>()) { $0.formUnion($1.occurrenceDays(inMonthOf: date, calendar: calendar)) }
    }

    public func customerName(forJob job: Job) -> String {
        if let id = job.customerID, let c = customers.first(where: { $0.id == id }) { return c.name }
        if let id = job.siteID, let s = sites.first(where: { $0.id == id }), let c = customers.first(where: { $0.id == s.customerID }) { return c.name }
        return ""
    }

    public func address(forJob job: Job) -> String {
        guard let id = job.siteID, let s = sites.first(where: { $0.id == id }) else { return "" }
        return s.address
    }

    /// The route for a day: open jobs that have a place on the map. Ordered by drive time only, so every stop has the same priority.
    public func routeStops(on day: Date, calendar: Calendar = .current) -> [Stop] {
        jobs(on: day, calendar: calendar).compactMap { job in
            guard !job.isTask, job.status.isOpen, let id = job.siteID, let site = sites.first(where: { $0.id == id }),
                  let lat = site.latitude, let lon = site.longitude else { return nil }
            let name = site.address.isEmpty ? job.title : site.address
            return Stop(id: job.id, name: name, coordinate: Coordinate(latitude: lat, longitude: lon), priority: 3,
                        serviceMinutes: Double(min(max(job.durationMinutes, 5), 240)))
        }
    }
}

/// Shares the schedule as a standard calendar file (.ics) that Apple Calendar, Google Calendar and Outlook all open.
public enum CalendarExport {
    public static func ics(jobs: [Job], data: AppData, company: String, now: Date) -> String {
        let stamp = utc(now)
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Ridgeline Ops//Schedule//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
        for job in jobs.sorted(by: { $0.start < $1.start }) {
            let end = job.start.addingTimeInterval(Double(job.durationMinutes) * 60)
            var description: [String] = []
            let who = data.customerName(forJob: job)
            if !who.isEmpty { description.append("Client: \(who)") }
            if !company.isEmpty { description.append(company) }
            if !job.notes.isEmpty { description.append(job.notes) }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(job.id.uuidString.lowercased())@ridgelineops")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART:\(utc(job.start))")
            lines.append("DTEND:\(utc(end))")
            if let rule = job.icsRepeatRule() { lines.append("RRULE:\(rule)") }
            lines.append("SUMMARY:\(escape(job.title))")
            let place = data.address(forJob: job)
            if !place.isEmpty { lines.append("LOCATION:\(escape(place))") }
            if !description.isEmpty { lines.append("DESCRIPTION:\(escape(description.joined(separator: "\n")))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space, as the calendar format requires.
    static func fold(_ line: String) -> String {
        var out = "", current = 0
        for ch in line {
            let size = String(ch).utf8.count
            if current + size > 75 { out += "\r\n "; current = 1 }
            out.append(ch); current += size
        }
        return out
    }
}
