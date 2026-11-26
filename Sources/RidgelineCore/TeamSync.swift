import Foundation

// The team sync engine: turns AppData into cloud rows and back, remembers what was last synced, and decides what to
// push and what a pulled row may overwrite. Pure and testable; the network part is `TeamSyncRemote` (TeamCloud.swift).
//
// Rules:
// - Each synced item has a fingerprint (SHA-256 of its JSON) saved in `AppData.teamSync` after it was pushed or pulled.
//   An item whose fingerprint differs has a local change to push; an item that vanished locally is a delete
//   (kept in `tombstones` until pushed as a row with deleted = true).
// - A round pushes first, then pulls. A pulled row replaces the local item (last write wins on the server), except while
//   the local item has a change not pushed yet that this login is allowed to push: that change is kept and wins next push.
// - Visits are append-only proof. A pulled visit is added once and never edited or removed (see VisitLog.appendSynced).

// Rows carry their `data` as JSONValue (AssistantTypes.swift), so it can be stored without knowing its type.

/// One row of the `records` table. Pulled rows carry `seq`; pushed rows send only the eight columns the app owns.
public struct SyncRow: Equatable, Sendable, Codable {
    public var businessID: UUID
    public var kind: String
    public var id: UUID
    public var data: JSONValue
    public var deleted: Bool
    public var assignees: [UUID]
    public var siteID: UUID?
    public var customerID: UUID?
    public var seq: Int64?
    public var updatedBy: String?

    public init(businessID: UUID, kind: String, id: UUID, data: JSONValue, deleted: Bool = false, assignees: [UUID] = [],
                siteID: UUID? = nil, customerID: UUID? = nil, seq: Int64? = nil, updatedBy: String? = nil) {
        self.businessID = businessID
        self.kind = kind
        self.id = id
        self.data = data
        self.deleted = deleted
        self.assignees = assignees
        self.siteID = siteID
        self.customerID = customerID
        self.seq = seq
        self.updatedBy = updatedBy
    }

    public var key: String { TeamSync.key(kind, id) }

    enum CodingKeys: String, CodingKey {
        case businessID = "business_id", kind, id, data, deleted, assignees, siteID = "site_id", customerID = "customer_id", seq
        case updatedBy = "updated_by"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessID = try c.decode(UUID.self, forKey: .businessID)
        kind = try c.decode(String.self, forKey: .kind)
        id = try c.decode(UUID.self, forKey: .id)
        data = try c.decodeIfPresent(JSONValue.self, forKey: .data) ?? .null
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        assignees = try c.decodeIfPresent([UUID].self, forKey: .assignees) ?? []
        siteID = try c.decodeIfPresent(UUID.self, forKey: .siteID)
        customerID = try c.decodeIfPresent(UUID.self, forKey: .customerID)
        seq = try c.decodeIfPresent(Int64.self, forKey: .seq)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)
    }

    /// Exactly the columns of the contract's push body. The server sets updated_by, updated_at and seq.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(businessID.uuidString.lowercased(), forKey: .businessID)
        try c.encode(kind, forKey: .kind)
        try c.encode(id.uuidString.lowercased(), forKey: .id)
        try c.encode(data, forKey: .data)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(assignees.map { $0.uuidString.lowercased() }, forKey: .assignees)
        if let siteID { try c.encode(siteID.uuidString.lowercased(), forKey: .siteID) } else { try c.encodeNil(forKey: .siteID) }
        if let customerID { try c.encode(customerID.uuidString.lowercased(), forKey: .customerID) } else { try c.encodeNil(forKey: .customerID) }
    }
}

/// Round 1 kinds, in the order pulled rows are applied (people before pay, clients and sites before jobs and visits).
public enum SyncKind: String, CaseIterable, Codable, Sendable {
    case customer, site, member, memberPay, job, visit, timeEntry
}

/// What a `memberPay` row holds: pay is kept out of the `member` row, which every employee can read.
public struct MemberPay: Equatable, Codable, Sendable {
    public var memberID: UUID
    public var hourlyRate: Money?
    public init(memberID: UUID, hourlyRate: Money?) {
        self.memberID = memberID
        self.hourlyRate = hourlyRate
    }
}

/// This device's link to a team sync business. Saved in AppData; holds no password and no token.
public struct TeamSyncState: Equatable, Codable, Sendable {
    public var businessID: UUID
    public var businessName: String = ""
    /// "owner", or the TeamRole raw value of the employee signed in on this device.
    public var role: String = "owner"
    /// For an employee: which TeamMember they are.
    public var memberID: UUID?
    /// For an employee: Permission raw values from their membership.
    public var permissions: [String] = []
    public var disabled = false
    /// The cloud login: the owner's email or the employee's username.
    public var login: String = ""
    /// Highest `seq` pulled so far.
    public var cursor: Int64 = 0
    /// Which set of kinds the cursor covers. When the app syncs more kinds, the cursor starts over.
    public var kindsVersion: Int = TeamSync.kindsVersion
    /// "kind/id" -> fingerprint of the item as last pushed or pulled.
    public var fingerprints: [String: String] = [:]
    /// "kind/id" -> when the item was found deleted here. Pushed as deleted rows, then dropped.
    public var tombstones: [String: Date] = [:]
    public var lastSyncAt: Date?
    public var lastError: String?
    /// Owner side: team member id (uuidString) -> username of their cloud login.
    public var cloudLogins: [String: String] = [:]
    /// Owner side: member id -> role, permissions and on/off as last sent to the `team` function.
    public var accessSent: [String: String] = [:]

    public init(businessID: UUID, businessName: String = "", role: String = "owner", memberID: UUID? = nil, login: String = "") {
        self.businessID = businessID
        self.businessName = businessName
        self.role = role
        self.memberID = memberID
        self.login = login
    }

    public var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case businessID, businessName, role, memberID, permissions, disabled, login, cursor, kindsVersion, fingerprints, tombstones
        case lastSyncAt, lastError, cloudLogins, accessSent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessID = try c.decode(UUID.self, forKey: .businessID)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "owner"
        memberID = try c.decodeIfPresent(UUID.self, forKey: .memberID)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        login = try c.decodeIfPresent(String.self, forKey: .login) ?? ""
        cursor = try c.decodeIfPresent(Int64.self, forKey: .cursor) ?? 0
        kindsVersion = try c.decodeIfPresent(Int.self, forKey: .kindsVersion) ?? 0
        fingerprints = try c.decodeIfPresent([String: String].self, forKey: .fingerprints) ?? [:]
        tombstones = try c.decodeIfPresent([String: Date].self, forKey: .tombstones) ?? [:]
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        cloudLogins = try c.decodeIfPresent([String: String].self, forKey: .cloudLogins) ?? [:]
        accessSent = try c.decodeIfPresent([String: String].self, forKey: .accessSent) ?? [:]
    }

    /// After restoring a backup: keep the link, forget what was synced, so the backup's items are pushed and the
    /// rest comes back from the cloud (nothing is deleted because it is missing from the backup).
    public func resetForRestore() -> TeamSyncState {
        var copy = self
        copy.cursor = 0
        copy.fingerprints = [:]
        copy.tombstones = [:]
        copy.lastError = nil
        return copy
    }
}

/// Who is pushing, and so which rows the row security will accept. Rows it would refuse are not sent.
public struct SyncWriter: Equatable, Sendable {
    public var isOwner: Bool
    public var memberID: UUID?
    public var permissions: Set<Permission>
    public var disabled: Bool

    public static let owner = SyncWriter(isOwner: true, memberID: nil, permissions: Set(Permission.allCases), disabled: false)

    public init(isOwner: Bool, memberID: UUID?, permissions: Set<Permission>, disabled: Bool) {
        self.isOwner = isOwner
        self.memberID = memberID
        self.permissions = permissions
        self.disabled = disabled
    }

    public init(state: TeamSyncState) {
        if state.isOwner {
            self = .owner
        } else {
            self = SyncWriter(isOwner: false, memberID: state.memberID,
                              permissions: Set(state.permissions.compactMap { Permission(rawValue: $0) }), disabled: state.disabled)
        }
    }

    /// `existing`: the row was synced before. A crew member who only logs visits may change an existing job assigned to
    /// them (its status), never create or delete one.
    public func mayWrite(_ kind: SyncKind, assignees: [UUID] = [], existing: Bool = true, deleting: Bool = false) -> Bool {
        if disabled { return false }
        if isOwner { return true }
        let p = permissions
        switch kind {
        case .customer, .site: return p.contains(.editClients)
        case .job:
            if p.contains(.editJobs) { return true }
            guard p.contains(.logVisits), existing, !deleting, let me = memberID else { return false }
            return assignees.contains(me)
        case .visit: return p.contains(.logVisits)
        case .timeEntry: return p.contains(.useTimeClock) || p.contains(.manageTeam)
        case .member, .memberPay: return p.contains(.manageTeam)
        }
    }
}

public enum TeamSync {
    /// Bump when the app starts syncing more kinds, so devices pull everything again.
    public static let kindsVersion = 1

    public static func key(_ kind: String, _ id: UUID) -> String { "\(kind)/\(id.uuidString.lowercased())" }
    public static func key(_ kind: SyncKind, _ id: UUID) -> String { key(kind.rawValue, id) }

    static func parse(_ key: String) -> (kind: SyncKind, id: UUID)? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = SyncKind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        return (kind, id)
    }

    // MARK: encoding

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func hexDigest(_ data: Data) -> String {
        SHA256.hash([UInt8](data)).map { String(format: "%02x", $0) }.joined()
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
        guard let raw = try? JSONEncoder().encode(value) else { return nil }
        return try? makeDecoder().decode(type, from: raw)
    }

    /// The member as it goes in its row: no pay.
    static func publicMember(_ m: TeamMember) -> TeamMember {
        var copy = m
        copy.hourlyRate = nil
        return copy
    }

    /// Permissions are a Set, whose JSON order changes from run to run, so the fingerprint uses them sorted.
    private struct MemberPrint: Encodable {
        let member: TeamMember
        let permissions: [String]
    }

    public static func memberFingerprint(_ m: TeamMember) -> String {
        var bare = publicMember(m)
        let perms = bare.permissions.map(\.rawValue).sorted()
        bare.permissions = []
        guard let data = try? makeEncoder().encode(MemberPrint(member: bare, permissions: perms)) else { return "" }
        return hexDigest(data)
    }

    /// Role, permissions and on/off: what the `team` function's set_access carries.
    public static func accessFingerprint(_ m: TeamMember) -> String {
        "\(m.role.rawValue)|\(m.permissions.map(\.rawValue).sorted().joined(separator: ","))|\(m.status == .disabled)"
    }

    // MARK: local items

    /// One syncable item as it stands on this device.
    public struct LocalItem: Sendable {
        public let kind: SyncKind
        public let id: UUID
        public let fingerprint: String
        let json: Data
        public let assignees: [UUID]
        public let siteID: UUID?
        public let customerID: UUID?
        public var key: String { TeamSync.key(kind, id) }
    }

    private static func item<T: Encodable>(_ kind: SyncKind, _ id: UUID, _ value: T, assignees: [UUID] = [], siteID: UUID? = nil,
                                           customerID: UUID? = nil, fingerprint: String? = nil) -> LocalItem? {
        guard let json = try? makeEncoder().encode(value) else { return nil }
        return LocalItem(kind: kind, id: id, fingerprint: fingerprint ?? hexDigest(json), json: json, assignees: assignees,
                         siteID: siteID, customerID: customerID)
    }

    /// Every synced item on this device, built for one kind or all.
    public static func localItems(_ data: AppData, only kinds: Set<SyncKind> = Set(SyncKind.allCases), id onlyID: UUID? = nil) -> [LocalItem] {
        var out: [LocalItem] = []
        let siteOwner = Dictionary(data.sites.map { ($0.id, $0.customerID) }, uniquingKeysWith: { a, _ in a })
        func wanted(_ id: UUID) -> Bool { onlyID == nil || onlyID == id }
        if kinds.contains(.customer) {
            for c in data.customers where wanted(c.id) { if let i = item(.customer, c.id, c, customerID: c.id) { out.append(i) } }
        }
        if kinds.contains(.site) {
            for s in data.sites where wanted(s.id) { if let i = item(.site, s.id, s, siteID: s.id, customerID: s.customerID) { out.append(i) } }
        }
        if kinds.contains(.member) {
            for m in data.team where wanted(m.id) {
                if let i = item(.member, m.id, publicMember(m), fingerprint: memberFingerprint(m)) { out.append(i) }
            }
        }
        if kinds.contains(.memberPay) {
            for m in data.team where wanted(m.id) {
                if let i = item(.memberPay, m.id, MemberPay(memberID: m.id, hourlyRate: m.hourlyRate)) { out.append(i) }
            }
        }
        if kinds.contains(.job) {
            for j in data.jobs where wanted(j.id) {
                let customer = j.customerID ?? j.siteID.flatMap { siteOwner[$0] }
                if let i = item(.job, j.id, j, assignees: j.assigneeIDs, siteID: j.siteID, customerID: customer) { out.append(i) }
            }
        }
        if kinds.contains(.visit) {
            for e in data.visitLog.entries where wanted(e.record.id) {
                let r = e.record
                if let i = item(.visit, r.id, r, siteID: r.siteID, customerID: siteOwner[r.siteID]) { out.append(i) }
            }
        }
        if kinds.contains(.timeEntry) {
            for t in data.timeEntries where wanted(t.id) {
                if let i = item(.timeEntry, t.id, t, siteID: t.siteID, customerID: t.siteID.flatMap { siteOwner[$0] }) { out.append(i) }
            }
        }
        return out
    }

    static func localFingerprint(_ data: AppData, kind: SyncKind, id: UUID) -> String? {
        localItems(data, only: [kind], id: id).first?.fingerprint
    }

    // MARK: push

    /// What to push now.
    public struct Outgoing: Sendable {
        public var rows: [SyncRow] = []
        /// key -> fingerprint to save once pushed; nil for a delete.
        public var fingerprints: [String: String?] = [:]
        /// Keys newly found deleted here, to keep as tombstones until pushed.
        public var newTombstones: [String] = []
        /// Changes this login may not push (row security would refuse them). They stay on this device.
        public var notAllowed = 0
    }

    public static func writer(for data: AppData) -> SyncWriter {
        data.teamSync.map(SyncWriter.init(state:)) ?? .owner
    }

    /// Items changed or deleted since they were last synced, as rows. Does not change anything.
    public static func outgoing(_ data: AppData) -> Outgoing {
        guard let state = data.teamSync else { return Outgoing() }
        let writer = SyncWriter(state: state)
        var out = Outgoing()
        var present = Set<String>()
        for item in localItems(data) {
            let key = item.key
            present.insert(key)
            let synced = state.fingerprints[key]
            guard synced != item.fingerprint else { continue }
            // No pay set and never shared: nothing to tell anyone (crew phones never see pay at all).
            if item.kind == .memberPay, synced == nil, data.team.first(where: { $0.id == item.id })?.hourlyRate == nil { continue }
            guard writer.mayWrite(item.kind, assignees: item.assignees, existing: synced != nil) else { out.notAllowed += 1; continue }
            guard let value = try? makeDecoder().decode(JSONValue.self, from: item.json) else { continue }
            out.rows.append(SyncRow(businessID: state.businessID, kind: item.kind.rawValue, id: item.id, data: value,
                                    assignees: item.assignees, siteID: item.siteID, customerID: item.customerID))
            out.fingerprints[key] = .some(item.fingerprint)
        }
        let gone = Set(state.fingerprints.keys).union(state.tombstones.keys).subtracting(present)
        for key in gone.sorted() {
            guard let parsed = parse(key), parsed.kind != .visit else { continue }   // proof is never deleted
            if state.tombstones[key] == nil { out.newTombstones.append(key) }
            guard writer.mayWrite(parsed.kind, existing: true, deleting: true) else { out.notAllowed += 1; continue }
            out.rows.append(SyncRow(businessID: state.businessID, kind: parsed.kind.rawValue, id: parsed.id, data: .object([:]), deleted: true))
            out.fingerprints[key] = .some(nil)
        }
        return out
    }

    /// Saves the deletes found by `outgoing` as tombstones, so they are not forgotten if the push fails.
    public static func recordTombstones(_ out: Outgoing, in state: inout TeamSyncState, now: Date) {
        for key in out.newTombstones where state.tombstones[key] == nil {
            state.tombstones[key] = now
            state.fingerprints[key] = nil
        }
    }

    /// After a push: what was sent now counts as synced. Rows the server refused count too, so they are not sent again
    /// and again; they stay on this device as they are, and the next local change to them is tried again.
    public static func markPushed(_ out: Outgoing, refused: [String], in state: inout TeamSyncState) {
        for (key, value) in out.fingerprints {
            if let value { state.fingerprints[key] = value } else { state.fingerprints[key] = nil; state.tombstones[key] = nil }
        }
        let skipped = out.notAllowed + refused.count
        state.lastError = skipped == 0 ? nil
            : "\(skipped) change\(skipped == 1 ? " was" : "s were") not shared because your login is not allowed to make \(skipped == 1 ? "it" : "them"). \(skipped == 1 ? "It stays" : "They stay") on this phone."
    }

    // MARK: pull

    public static func cursor(for state: TeamSyncState) -> Int64 {
        state.kindsVersion < kindsVersion ? 0 : state.cursor
    }

    public struct ApplyResult: Equatable, Sendable {
        public var applied = 0
        /// Remote rows not applied because this device has a change to them that is not pushed yet.
        public var keptLocal = 0
        /// Unknown kinds (from a newer app) and rows that could not be read.
        public var skipped = 0
    }

    /// Applies pulled rows. Never crashes on partial data: a job whose site is missing here is kept as it is.
    @discardableResult
    public static func apply(_ rows: [SyncRow], to data: inout AppData) -> ApplyResult {
        guard var state = data.teamSync else { return ApplyResult() }
        let writer = SyncWriter(state: state)
        var result = ApplyResult()
        var latest: [String: SyncRow] = [:]
        var highest = cursor(for: state)
        for row in rows where row.businessID == state.businessID {
            highest = max(highest, row.seq ?? highest)
            if let seen = latest[row.key], (seen.seq ?? 0) > (row.seq ?? 0) { continue }
            latest[row.key] = row
        }
        let order = Dictionary(uniqueKeysWithValues: SyncKind.allCases.enumerated().map { pair in (pair.element.rawValue, pair.offset) })
        let sorted = latest.values.sorted {
            let a = order[$0.kind] ?? Int.max, b = order[$1.kind] ?? Int.max
            return a != b ? a < b : ($0.seq ?? 0) < ($1.seq ?? 0)
        }
        for row in sorted {
            guard let kind = SyncKind(rawValue: row.kind) else { result.skipped += 1; continue }
            let key = row.key
            let localItem = localItems(data, only: [kind], id: row.id).first
            let local = localItem?.fingerprint
            let synced = state.fingerprints[key]
            // A change made here and not pushed yet wins, if this login may push it. Otherwise the remote row wins.
            // A person who just arrived in this same batch has an empty pay item here; that is not an edit of ours.
            let emptyNewPay = kind == .memberPay && synced == nil && data.team.first(where: { $0.id == row.id })?.hourlyRate == nil
            let unpushedEdit = local != nil && local != synced && !emptyNewPay
            let unpushedDelete = local == nil && state.tombstones[key] != nil
            if (unpushedEdit || unpushedDelete) && kind != .visit
                && writer.mayWrite(kind, assignees: localItem?.assignees ?? [], existing: synced != nil, deleting: unpushedDelete) {
                result.keptLocal += 1
                continue
            }
            if row.deleted {
                if kind != .visit { remove(kind, row.id, from: &data) }
                state.fingerprints[key] = nil
                state.tombstones[key] = nil
                result.applied += 1
                continue
            }
            guard upsert(kind, row, into: &data) else { result.skipped += 1; continue }
            state.tombstones[key] = nil
            state.fingerprints[key] = localFingerprint(data, kind: kind, id: row.id)
            result.applied += 1
        }
        state.cursor = highest
        state.kindsVersion = kindsVersion
        data.teamSync = state
        return result
    }

    private static func upsert(_ kind: SyncKind, _ row: SyncRow, into data: inout AppData) -> Bool {
        func put<T: Identifiable>(_ value: T, _ list: inout [T]) where T.ID == UUID {
            if let i = list.firstIndex(where: { $0.id == value.id }) { list[i] = value } else { list.append(value) }
        }
        switch kind {
        case .customer:
            guard let v = decode(Customer.self, from: row.data), v.id == row.id else { return false }
            put(v, &data.customers)
        case .site:
            guard let v = decode(Site.self, from: row.data), v.id == row.id else { return false }
            put(v, &data.sites)
        case .job:
            guard let v = decode(Job.self, from: row.data), v.id == row.id else { return false }
            put(v, &data.jobs)
        case .timeEntry:
            guard let v = decode(TimeEntry.self, from: row.data), v.id == row.id else { return false }
            put(v, &data.timeEntries)
        case .visit:
            guard let v = decode(VisitRecord.self, from: row.data), v.id == row.id else { return false }
            data.visitLog.appendSynced(v)       // already there: left as recorded
        case .member:
            guard var v = decode(TeamMember.self, from: row.data), v.id == row.id else { return false }
            v.hourlyRate = data.team.first { $0.id == v.id }?.hourlyRate   // pay comes only from memberPay
            put(v, &data.team)
        case .memberPay:
            guard let v = decode(MemberPay.self, from: row.data), v.memberID == row.id else { return false }
            guard let i = data.team.firstIndex(where: { $0.id == v.memberID }) else { return true }   // person not visible here
            data.team[i].hourlyRate = v.hourlyRate.flatMap { $0.cents >= 0 && $0.cents <= 100_000 ? $0 : nil }
        }
        return true
    }

    private static func remove(_ kind: SyncKind, _ id: UUID, from data: inout AppData) {
        switch kind {
        case .customer: data.customers.removeAll { $0.id == id }
        case .site: data.sites.removeAll { $0.id == id }
        case .job: data.jobs.removeAll { $0.id == id }
        case .timeEntry: data.timeEntries.removeAll { $0.id == id }
        case .visit: break
        case .member:
            data.team.removeAll { $0.id == id }
            data.logins.removeAll { $0.memberID == id }
            if data.session?.memberID == id { data.session = nil }
        case .memberPay:
            if let i = data.team.firstIndex(where: { $0.id == id }) { data.team[i].hourlyRate = nil }
        }
    }

    // MARK: one round

    public struct RoundReport: Equatable, Sendable {
        public var pushed = 0
        public var refused = 0
        public var pulled = 0
        public var apply = ApplyResult()
    }

    /// Push what changed here, then pull and apply what changed elsewhere. The app runs the same steps (AppModel+TeamSync).
    @discardableResult
    public static func syncOnce(_ data: inout AppData, remote: TeamSyncRemote, now: Date) async throws -> RoundReport {
        guard let start = data.teamSync else { return RoundReport() }
        var report = RoundReport()
        let out = outgoing(data)
        if var s = data.teamSync { recordTombstones(out, in: &s, now: now); data.teamSync = s }
        var refused: [String] = []
        if !out.rows.isEmpty { refused = try await remote.push(out.rows) }
        if var s = data.teamSync { markPushed(out, refused: refused, in: &s); data.teamSync = s }
        report.pushed = out.rows.count - refused.count
        report.refused = refused.count
        let pullFrom = data.teamSync.map(cursor(for:)) ?? 0
        let rows = try await remote.pull(businessID: start.businessID, after: pullFrom)
        report.pulled = rows.count
        report.apply = apply(rows, to: &data)
        data.teamSync?.lastSyncAt = now
        return report
    }

    // MARK: employees

    /// Updates the link from `my_membership` and makes sure the employee's own TeamMember exists here with the
    /// permissions from the membership. Changes made this way are not local edits, so they are never pushed.
    public static func applyMembership(_ m: TeamMembership, to data: inout AppData, now: Date) {
        guard var state = data.teamSync, state.businessID == m.businessID else { return }
        if !m.businessName.isEmpty { state.businessName = m.businessName }
        state.role = m.role
        state.memberID = m.memberID
        state.permissions = m.permissions.sorted()
        state.disabled = m.disabled
        data.teamSync = state
        guard !m.isOwner, let id = m.memberID else { return }
        let memberKey = TeamSync.key(.member, id)
        let before = data.team.first { $0.id == id }
        let wasSynced = before.map { state.fingerprints[memberKey] == memberFingerprint($0) } ?? true
        var member = before ?? TeamMember(id: id, name: state.login.isEmpty ? "Me" : state.login,
                                          role: TeamRole(rawValue: m.role) ?? .crewMember, createdAt: now)
        if let role = TeamRole(rawValue: m.role) { member.role = role }
        member.permissions = m.permissionSet
        member.status = m.disabled ? .disabled : .active
        if member.joinedAt == nil && !m.disabled { member.joinedAt = now }
        if let i = data.team.firstIndex(where: { $0.id == id }) { data.team[i] = member } else { data.team.append(member) }
        if wasSynced { data.teamSync?.fingerprints[memberKey] = memberFingerprint(member) }
        if before == nil, let pay = localItems(data, only: [.memberPay], id: id).first {
            data.teamSync?.fingerprints[pay.key] = pay.fingerprint      // the stand-in's empty pay is never pushed
        }
        if m.disabled, data.session?.memberID == id { data.session = nil }
    }

    /// True when the device holds business records worth keeping.
    public static func holdsBusinessRecords(_ data: AppData) -> Bool {
        !(data.customers.isEmpty && data.sites.isEmpty && data.invoices.isEmpty && data.jobs.isEmpty && data.quotes.isEmpty
          && data.team.isEmpty && data.timeEntries.isEmpty && data.visitLog.entries.isEmpty)
    }

    /// Why an employee may not link this device to `businessID`, or nil when they may. A device already linked to that
    /// business, or holding no business records, may join; any other records are never mixed into a team.
    public static func linkProblem(_ data: AppData, businessID: UUID) -> String? {
        if let linked = data.teamSync {
            return linked.businessID == businessID ? nil : "This phone holds another team's records, so it cannot join this team."
        }
        return holdsBusinessRecords(data) ? "This phone already holds a business's records. Sign in on your own phone." : nil
    }

    // MARK: owner side

    /// Team members whose role, permissions or on/off changed since last sent to the `team` function.
    public static func accessChanges(_ data: AppData) -> [(member: TeamMember, username: String)] {
        guard let state = data.teamSync else { return [] }
        return data.team.compactMap { m in
            guard let user = state.cloudLogins[m.id.uuidString], state.accessSent[m.id.uuidString] != accessFingerprint(m) else { return nil }
            return (m, user)
        }
    }

    /// Team members who are on but have no login for their own phone yet.
    public static func membersWithoutCloudLogin(_ data: AppData) -> [TeamMember] {
        guard let state = data.teamSync else { return [] }
        return data.team.filter { $0.status != .disabled && state.cloudLogins[$0.id.uuidString] == nil }
    }

    /// "Synced just now", "Synced 2 min ago", "Synced 3 hr ago", "Synced Nov 24".
    public static func syncedText(_ at: Date?, now: Date) -> String {
        guard let at else { return "Not synced yet" }
        let seconds = max(0, now.timeIntervalSince(at))
        if seconds < 60 { return "Synced just now" }
        if seconds < 3600 { return "Synced \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "Synced \(Int(seconds / 3600)) hr ago" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return "Synced \(f.string(from: at))"
    }
}
