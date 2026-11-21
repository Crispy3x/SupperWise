import Foundation

// MARK: - Material spread on a visit

public enum MaterialUnit: String, Codable, Sendable {
    case pounds, gallons

    public var short: String { self == .pounds ? "lb" : "gal" }
}

/// What the crew spread at a site.
public enum MaterialType: String, Codable, Sendable, CaseIterable {
    case rockSalt, treatedSalt, sand, liquidBrine, none

    public var title: String {
        switch self {
        case .rockSalt: return "Rock salt"
        case .treatedSalt: return "Treated salt"
        case .sand: return "Sand"
        case .liquidBrine: return "Liquid brine"
        case .none: return "None"
        }
    }

    /// Liquid brine is measured in gallons, everything else in pounds.
    public var unit: MaterialUnit { self == .liquidBrine ? .gallons : .pounds }

    /// Salt counts toward the salt pounds used for job costing.
    public var isSalt: Bool { self == .rockSalt || self == .treatedSalt }
}

public enum MaterialFormat {
    /// "200 lb", "12.5 gal". Whole numbers drop the decimal.
    public static func amount(_ value: Double, unit: MaterialUnit) -> String {
        "\(number(value)) \(unit.short)"
    }

    /// One line for the proof packet. Older visits without a material fall back to their salt pounds.
    public static func describe(material: MaterialType?, amount: Double?, legacySaltPounds: Double = 0) -> String {
        guard let material else {
            return legacySaltPounds > 0 ? "Salt, \(Self.amount(legacySaltPounds, unit: .pounds))" : "Not recorded"
        }
        if material == MaterialType.none { return "None" }
        guard let amount, amount > 0 else { return "\(material.title), amount not entered" }
        return "\(material.title), \(Self.amount(amount, unit: material.unit))"
    }

    static func number(_ value: Double) -> String {
        let tenth = (value * 10).rounded() / 10
        return tenth == tenth.rounded() ? String(format: "%.0f", tenth) : String(format: "%.1f", tenth)
    }
}

extension VisitRecord {
    /// "Rock salt, 200 lb", "None", or "Not recorded".
    public var materialSummary: String {
        MaterialFormat.describe(material: material, amount: materialAmount, legacySaltPounds: saltPounds)
    }
}

// MARK: - Stamp burned into each photo

public enum PhotoStamp {
    /// Longest line drawn on a photo; longer text is cut with "...".
    public static let maxLineLength = 70

    /// The lines burned into the dark band at the bottom of a photo: date and time, address, GPS when known,
    /// and the weather note when there is one.
    public static func lines(capturedAt: Date, address: String, coordinate: Coordinate?, weatherNote: String,
                             timeZone: TimeZone = .current) -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "MMM d, yyyy h:mm a"
        var when = f.string(from: capturedAt)
        if let zone = timeZone.abbreviation(for: capturedAt) { when += " \(zone)" }

        var out = [when]
        let place = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { out.append(place) }
        if let coordinate { out.append("GPS \(format(coordinate))") }
        let weather = weatherNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !weather.isEmpty { out.append("Weather: \(weather)") }
        return out.map(truncate)
    }

    /// "44.97760 N, 93.26500 W"
    public static func format(_ c: Coordinate) -> String {
        let lat = String(format: "%.5f", abs(c.latitude))
        let lon = String(format: "%.5f", abs(c.longitude))
        return "\(lat) \(c.latitude >= 0 ? "N" : "S"), \(lon) \(c.longitude >= 0 ? "E" : "W")"
    }

    static func truncate(_ line: String) -> String {
        let oneLine = line.replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > maxLineLength else { return oneLine }
        return String(oneLine.prefix(maxLineLength - 3)) + "..."
    }
}

// MARK: - Proof packet per visit

/// Result of checking one stored photo against the fingerprint saved when it was taken.
public enum PhotoCheck: String, Equatable, Sendable {
    case intact, missing, changed, notChecked
}

extension PhotoStorage {
    public func check(_ ref: PhotoRef) -> PhotoCheck {
        do {
            _ = try data(for: ref)
            return .intact
        } catch PhotoStorageError.hashMismatch {
            return .changed
        } catch {
            return .missing
        }
    }
}

/// Chain of custody for one visit: is the record unchanged, is the log intact, do the photos match.
public enum CustodyStatus: Equatable, Sendable {
    case verified
    case photosNotChecked
    case photoProblem(missing: Int, changed: Int)
    case logAltered
    case recordAltered

    public var isGood: Bool { self == .verified || self == .photosNotChecked }

    public var text: String {
        switch self {
        case .verified: return "Verified: record and photos unchanged since saved"
        case .photosNotChecked: return "Record unchanged. Photos not checked on this device"
        case .photoProblem(let missing, let changed):
            var parts: [String] = []
            if missing > 0 { parts.append("\(missing) missing") }
            if changed > 0 { parts.append("\(changed) changed since taken") }
            return "Photo problem: " + parts.joined(separator: ", ")
        case .logAltered: return "Log altered: an earlier entry was changed"
        case .recordAltered: return "This record was changed after it was saved"
        }
    }
}

public struct ProofFact: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case normal, good, warning, bad }
    public let label: String
    public let value: String
    public let tone: Tone

    public init(_ label: String, _ value: String, tone: Tone = .normal) {
        self.label = label
        self.value = value
        self.tone = tone
    }
}

/// The proof summary for one visit, shown as a card and shared as text.
public struct VisitProof: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let heading: String
    public let facts: [ProofFact]
    public let custody: CustodyStatus
    /// The visit's hash in the log.
    public let fingerprint: String
}

public enum ProofPacket {
    /// Proof for every visit at the site, oldest first.
    public static func visits(site: Site, log: VisitLog, timeZone: TimeZone = .current,
                              photoCheck: (PhotoRef) -> PhotoCheck = { _ in .notChecked }) -> [VisitProof] {
        let verified = log.verify()
        return log.entries
            .filter { $0.record.siteID == site.id }
            .sorted { $0.record.arrival < $1.record.arrival }
            .map { proof(for: $0, logVerified: verified, timeZone: timeZone, photoCheck: photoCheck) }
    }

    public static func proof(for entry: VisitLogEntry, logVerified: Bool, timeZone: TimeZone = .current,
                             photoCheck: (PhotoRef) -> PhotoCheck = { _ in .notChecked }) -> VisitProof {
        let r = entry.record
        let full = dateFormatter("MMM d, yyyy h:mm a", timeZone)
        let day = dateFormatter("MMM d, yyyy", timeZone)

        var facts: [ProofFact] = []
        facts.append(ProofFact("Arrived", full.string(from: r.arrival)))
        facts.append(ProofFact("Left", r.departure.map { full.string(from: $0) } ?? "Not recorded",
                               tone: r.departure == nil ? .warning : .normal))
        facts.append(ProofFact("Time on site", r.departure == nil ? "Not recorded" : duration(r.durationHours * 3600)))
        switch r.status {
        case .completed: facts.append(ProofFact("Status", "Done", tone: .good))
        case .skipped(let reason): facts.append(ProofFact("Status", reason.isEmpty ? "Skipped" : "Skipped: \(reason)", tone: .warning))
        }
        facts.append(ProofFact("Crew", r.crewMemberName))
        if r.status == .completed {
            facts.append(ProofFact("Snow depth", "\(MaterialFormat.number(r.snowDepthInches)) in"))
            facts.append(ProofFact("Material", r.materialSummary))
        }
        if !r.weatherNote.isEmpty { facts.append(ProofFact("Weather", r.weatherNote)) }
        switch r.geofence {
        case .inside: facts.append(ProofFact("At the site", "Yes, phone was at the site", tone: .good))
        case .outside: facts.append(ProofFact("At the site", "No, phone was away from the site", tone: .bad))
        case .unknown: facts.append(ProofFact("At the site", "Not checked", tone: .warning))
        }
        facts.append(ProofFact("Photos", photoText(r.photos), tone: r.photos.isEmpty ? .warning : .normal))

        let intact = entry.hash == VisitLog.hash(r, previous: entry.previousHash)
        let status = custody(entryIntact: intact, logVerified: logVerified, checks: r.photos.map(photoCheck))
        let storm = r.stormID.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = (storm.isEmpty ? "Visit" : "Storm \(storm)") + ", " + day.string(from: r.arrival)
        return VisitProof(id: r.id, heading: heading, facts: facts, custody: status, fingerprint: entry.hash)
    }

    /// Worst problem wins: a changed record, then a broken log, then photo trouble.
    public static func custody(entryIntact: Bool, logVerified: Bool, checks: [PhotoCheck]) -> CustodyStatus {
        if !entryIntact { return .recordAltered }
        if !logVerified { return .logAltered }
        let missing = checks.filter { $0 == .missing }.count
        let changed = checks.filter { $0 == .changed }.count
        if missing + changed > 0 { return .photoProblem(missing: missing, changed: changed) }
        if checks.contains(.notChecked) { return .photosNotChecked }
        return .verified
    }

    /// "25 min", "1 hr", "2 hr 5 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// "None" or "3 (2 before, 1 after)".
    public static func photoText(_ photos: [PhotoRef]) -> String {
        guard !photos.isEmpty else { return "None" }
        let order: [PhotoKind] = [.before, .after, .damage, .gate, .other]
        let parts = order.compactMap { kind -> String? in
            let n = photos.filter { $0.kind == kind }.count
            return n > 0 ? "\(n) \(kind.rawValue)" : nil
        }
        return "\(photos.count) (\(parts.joined(separator: ", ")))"
    }

    /// Plain-text packet for sharing with an insurer or customer.
    public static func render(site: Site, log: VisitLog, timeZone: TimeZone = .current,
                              photoCheck: (PhotoRef) -> PhotoCheck = { _ in .notChecked }) -> String {
        let proofs = visits(site: site, log: log, timeZone: timeZone, photoCheck: photoCheck)
        var lines: [String] = []
        lines.append("PROOF PACKET: \(site.address)")
        lines.append("Log check: \(log.verify() ? "PASSED (no changes since recording)" : "FAILED (log was altered)")")
        lines.append("Visits: \(proofs.count)")
        for p in proofs {
            lines.append("")
            lines.append(p.heading)
            for fact in p.facts { lines.append("  \(fact.label): \(fact.value)") }
            lines.append("  Chain of custody: \(p.custody.text)")
            lines.append("  Record fingerprint: \(p.fingerprint)")
        }
        return lines.joined(separator: "\n")
    }

    private static func dateFormatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
}
