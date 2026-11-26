import Foundation

public enum GeofenceStatus: String, Codable, Sendable {
    case inside, outside, unknown
}

public enum ArrivalCheck {
    /// Compares the device location with the site. Without a site location or a device location the answer is
    /// `.unknown`, never a guess.
    public static func status(device: Coordinate?, site: Site, radiusMeters: Double = 75) -> GeofenceStatus {
        guard let device, let lat = site.latitude, let lon = site.longitude else { return .unknown }
        return Geo.distanceMeters(device, Coordinate(latitude: lat, longitude: lon)) <= radiusMeters ? .inside : .outside
    }
}

public enum PhotoKind: String, Codable, Sendable {
    case before, after, damage, gate, other
}

public struct PhotoRef: Equatable, Codable, Sendable {
    public var kind: PhotoKind
    public var filename: String
    public var capturedAt: Date
    /// SHA-256 of the image bytes, so a swapped photo is detectable.
    public var sha256: String

    /// Builds the reference for real image bytes: a unique file name and the SHA-256 of the bytes.
    public static func make(imageData: Data, kind: PhotoKind, capturedAt: Date, fileExtension: String = "jpg") -> PhotoRef {
        PhotoRef(kind: kind, filename: "\(UUID().uuidString).\(fileExtension)", capturedAt: capturedAt,
                 sha256: SHA256.hash(Array(imageData)).map { String(format: "%02x", $0) }.joined())
    }

    public init(kind: PhotoKind, filename: String, capturedAt: Date, sha256: String) {
        self.kind = kind
        self.filename = filename
        self.capturedAt = capturedAt
        self.sha256 = sha256
    }
}

/// What the crew recorded at a site during a storm.
public struct VisitRecord: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var siteID: UUID
    public var crewMemberName: String
    public var stormID: String
    public var arrival: Date
    public var departure: Date?
    /// Whether the device was at the site when the visit was logged. `.unknown` when no location check was made.
    public var geofence: GeofenceStatus
    public var status: VisitStatus
    public var snowDepthInches: Double
    public var weatherNote: String
    public var saltPounds: Double
    public var photos: [PhotoRef]
    public var note: String
    /// What was spread (see ProofPacket.swift). Optional so visits saved before this field still load and hash the same.
    public var material: MaterialType?
    /// Amount of `material`, in its unit (pounds, or gallons for liquid brine).
    public var materialAmount: Double?

    public init(id: UUID = UUID(), siteID: UUID, crewMemberName: String, stormID: String, arrival: Date,
                departure: Date? = nil, geofence: GeofenceStatus = .unknown, status: VisitStatus = .completed,
                snowDepthInches: Double = 0, weatherNote: String = "", saltPounds: Double = 0,
                photos: [PhotoRef] = [], note: String = "", material: MaterialType? = nil, materialAmount: Double? = nil) {
        self.id = id
        self.siteID = siteID
        self.crewMemberName = crewMemberName
        self.stormID = stormID
        self.arrival = arrival
        self.departure = departure
        self.geofence = geofence
        self.status = status
        self.snowDepthInches = snowDepthInches
        self.weatherNote = weatherNote
        self.saltPounds = saltPounds
        self.photos = photos
        self.note = note
        self.material = material
        self.materialAmount = materialAmount
    }

    public var hasBeforePhoto: Bool { photos.contains { $0.kind == .before } }
    public var hasAfterPhoto: Bool { photos.contains { $0.kind == .after } }

    public var durationHours: Double {
        guard let departure else { return 0 }
        return max(departure.timeIntervalSince(arrival), 0) / 3600
    }

    /// Billing view of this record.
    public func asBillingVisit(materials: Money = .zero) -> Visit {
        Visit(id: id, stormID: stormID, date: arrival, status: status,
              snowDepthInches: snowDepthInches, hours: durationHours, materials: materials)
    }
}

public struct VisitLogEntry: Equatable, Codable, Sendable {
    public var record: VisitRecord
    public var previousHash: String
    public var hash: String
    /// True for a visit recorded on another phone and received through team sync. It is not part of this phone's chain:
    /// its hash covers the record alone, so it is checked on its own. Nil for visits logged here (and in older files).
    public var synced: Bool? = nil
}

/// Append-only, hash-chained log. Editing or removing any earlier entry breaks `verify()`.
/// With team sync, visits from other phones are added with `appendSynced`: each carries a hash of its own record
/// (previous hash = genesis) instead of joining this phone's chain, so honest merged logs verify and an edited record
/// is still caught. Visits logged on this phone keep forming one chain, skipping over the synced ones.
/// This makes the log tamper-evident for insurance and claim disputes; it is not a legal guarantee on its own.
public struct VisitLog: Equatable, Codable, Sendable {
    public private(set) var entries: [VisitLogEntry] = []
    public static let genesisHash = String(repeating: "0", count: 64)

    public init() {}

    public mutating func append(_ record: VisitRecord) {
        let previous = entries.last(where: { $0.synced != true })?.hash ?? Self.genesisHash
        entries.append(VisitLogEntry(record: record, previousHash: previous, hash: Self.hash(record, previous: previous)))
    }

    /// Adds a visit recorded on another phone (team sync). A visit already in the log is not added again or changed.
    @discardableResult
    public mutating func appendSynced(_ record: VisitRecord) -> Bool {
        guard !entries.contains(where: { $0.record.id == record.id }) else { return false }
        entries.append(VisitLogEntry(record: record, previousHash: Self.genesisHash,
                                     hash: Self.hash(record, previous: Self.genesisHash), synced: true))
        return true
    }

    public func verify() -> Bool {
        var previous = Self.genesisHash
        for e in entries {
            if e.synced == true {
                // From another phone: its own hash must still match its record.
                if e.previousHash != Self.genesisHash || e.hash != Self.hash(e.record, previous: Self.genesisHash) { return false }
                continue
            }
            if e.previousHash != previous { return false }
            if e.hash != Self.hash(e.record, previous: previous) { return false }
            previous = e.hash
        }
        return true
    }

    public func records(forSite siteID: UUID) -> [VisitRecord] {
        entries.map(\.record).filter { $0.siteID == siteID }
    }

    static func hash(_ record: VisitRecord, previous: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return SHA256.hex(previous + json)
    }

    // Test hook: lets tests simulate tampering without a public mutator.
    mutating func _tamper(at index: Int, _ change: (inout VisitRecord) -> Void) {
        change(&entries[index].record)
    }
}

/// Plain-text dispute packet an owner can send to an insurer or customer.
public enum DisputePacket {
    public static func render(site: Site, log: VisitLog, from: Date? = nil, to: Date? = nil,
                              timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")

        let records = log.records(forSite: site.id)
            .filter { (from == nil || $0.arrival >= from!) && (to == nil || $0.arrival <= to!) }
            .sorted { $0.arrival < $1.arrival }

        var lines: [String] = []
        lines.append("PROOF OF SERVICE: \(site.address)")
        lines.append("Log integrity check: \(log.verify() ? "PASSED" : "FAILED (log was altered)")")
        lines.append("Visits: \(records.count)")
        lines.append("")
        for r in records {
            let out = r.departure.map { f.string(from: $0) } ?? "n/a"
            var status = "completed"
            if case .skipped(let reason) = r.status { status = "skipped (\(reason))" }
            lines.append("\(f.string(from: r.arrival)) to \(out) | storm \(r.stormID) | \(status)")
            lines.append("  crew: \(r.crewMemberName) | at site (location check): \(r.geofence.rawValue) | depth: \(r.snowDepthInches) in | salt: \(r.saltPounds) lb")
            if r.material != nil { lines.append("  material: \(r.materialSummary)") }
            if !r.weatherNote.isEmpty { lines.append("  weather: \(r.weatherNote)") }
            lines.append("  photos: \(r.photos.count) (before: \(r.hasBeforePhoto ? "yes" : "no"), after: \(r.hasAfterPhoto ? "yes" : "no"))")
            if !r.note.isEmpty { lines.append("  note: \(r.note)") }
        }
        return lines.joined(separator: "\n")
    }
}
