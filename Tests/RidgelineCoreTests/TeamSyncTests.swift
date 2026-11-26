import XCTest
@testable import RidgelineCore

/// An in-memory `records` table: upserts by key, stamps a rising seq, and sends rows through JSON like the real server.
private final class FakeTeamServer: TeamSyncRemote, @unchecked Sendable {
    let businessID: UUID
    var rows: [String: SyncRow] = [:]
    var seq: Int64 = 0
    var pushes: [[SyncRow]] = []
    var pullCursors: [Int64] = []
    var refuse: (SyncRow) -> Bool = { _ in false }

    init(_ businessID: UUID) { self.businessID = businessID }

    func push(_ rows: [SyncRow]) async throws -> [String] {
        pushes.append(rows)
        var refused: [String] = []
        for row in rows {
            if refuse(row) { refused.append(row.key); continue }
            var wire = try JSONDecoder().decode(SyncRow.self, from: JSONEncoder().encode(row))
            seq += 1
            wire.seq = seq
            self.rows[wire.key] = wire
        }
        return refused
    }

    func pull(businessID: UUID, after cursor: Int64) async throws -> [SyncRow] {
        pullCursors.append(cursor)
        return rows.values.filter { $0.businessID == businessID && ($0.seq ?? 0) > cursor }.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
    }

    func row(_ kind: SyncKind, _ id: UUID) -> SyncRow? { rows[TeamSync.key(kind, id)] }
}

final class TeamSyncTests: XCTestCase {
    private let biz = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let customer = Customer(name: "Acme Plaza", phone: "555-0100")
    private lazy var site = Site(customerID: customer.id, address: "1 Main St", latitude: 45, longitude: -93)
    private lazy var dana = TeamMember(name: "Dana", role: .crewMember, createdAt: t0, hourlyRate: Money(dollars: 22))
    private lazy var job = Job(title: "Plow lot", kind: .snowPlowing, customerID: customer.id, siteID: site.id, start: t0,
                               assigneeIDs: [dana.id], createdAt: t0)

    private func linked(role: String = "owner", member: UUID? = nil, permissions: Set<Permission> = [], login: String = "") -> AppData {
        var d = AppData()
        var s = TeamSyncState(businessID: biz, role: role, memberID: member, login: login)
        s.permissions = permissions.map(\.rawValue).sorted()
        d.teamSync = s
        return d
    }

    private func ownerData() -> AppData {
        var d = linked()
        d.companyName = "Ridge"
        d.customers = [customer]
        d.sites = [site]
        d.team = [dana]
        d.jobs = [job]
        d.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Owner", stormID: "S1", arrival: t0, departure: t0 + 1800))
        d.timeEntries = [TimeEntry(memberName: "Dana", start: t0, end: t0 + 3600, siteID: site.id)]
        return d
    }

    /// Dana's own phone: a crew member who logs visits and clocks in.
    private func crewPhone() -> AppData {
        var d = linked(role: "crewMember", member: dana.id, permissions: [.logVisits, .useTimeClock], login: "dana")
        d.session = AppSession(role: .employee, memberID: dana.id, startedAt: t0)
        return d
    }

    // MARK: round trip

    func testEveryKindRoundTripsToAnotherPhone() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        let first = try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(first.pushed, 7)       // customer, site, member, memberPay, job, visit, timeEntry
        XCTAssertEqual(Set(server.rows.values.map(\.kind)), Set(SyncKind.allCases.map(\.rawValue)))

        // Links used by row security.
        let jobRow = try XCTUnwrap(server.row(.job, job.id))
        XCTAssertEqual(jobRow.assignees, [dana.id])
        XCTAssertEqual(jobRow.siteID, site.id)
        XCTAssertEqual(jobRow.customerID, customer.id)
        XCTAssertEqual(server.row(.site, site.id)?.siteID, site.id)
        XCTAssertEqual(server.row(.site, site.id)?.customerID, customer.id)
        // Pay never goes in the member row that every employee can read.
        XCTAssertNil(server.row(.member, dana.id)?.data["hourlyRate"])
        XCTAssertEqual(server.row(.memberPay, dana.id)?.data["hourlyRate"]?["cents"], .number(2200))

        var other = linked()
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        XCTAssertEqual(other.customers, owner.customers)
        XCTAssertEqual(other.sites, owner.sites)
        XCTAssertEqual(other.jobs, owner.jobs)
        XCTAssertEqual(other.timeEntries, owner.timeEntries)
        XCTAssertEqual(other.team, owner.team)                     // pay arrived through memberPay
        XCTAssertEqual(other.visitLog.entries.map(\.record), owner.visitLog.entries.map(\.record))
        XCTAssertTrue(other.visitLog.verify())

        // Nothing changed: nobody pushes anything again.
        let pushesBefore = server.pushes.count
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(server.pushes.count, pushesBefore)
    }

    func testOnlyChangedItemsArePushed() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        owner.customers[0].phone = "555-0199"
        let report = try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(report.pushed, 1)
        XCTAssertEqual(server.pushes.last?.map(\.kind), ["customer"])
        // A pay change goes only in memberPay.
        owner.team[0].hourlyRate = Money(dollars: 25)
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(server.pushes.last?.map(\.kind), ["memberPay"])
    }

    func testDeletesPropagate() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        var other = linked()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        XCTAssertEqual(other.jobs.count, 1)

        owner.jobs.removeAll()
        let out = TeamSync.outgoing(owner)
        XCTAssertEqual(out.newTombstones, [TeamSync.key(.job, job.id)])
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        let pushed = try XCTUnwrap(server.pushes.last?.first)
        XCTAssertTrue(pushed.deleted)
        XCTAssertEqual(pushed.kind, "job")
        XCTAssertTrue(owner.teamSync?.tombstones.isEmpty ?? false)
        XCTAssertEqual(server.row(.job, job.id)?.deleted, true)       // never hard-deleted

        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        XCTAssertTrue(other.jobs.isEmpty)
    }

    func testFailedPushKeepsTheDeleteAsATombstone() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        owner.customers.removeAll()
        var state = try XCTUnwrap(owner.teamSync)
        TeamSync.recordTombstones(TeamSync.outgoing(owner), in: &state, now: t0)     // the push then failed
        owner.teamSync = state
        XCTAssertNotNil(owner.teamSync?.tombstones[TeamSync.key(.customer, customer.id)])
        let retry = TeamSync.outgoing(owner)
        XCTAssertEqual(retry.rows.filter(\.deleted).map(\.id), [customer.id])
    }

    func testRemoteEditIsApplied() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        var other = linked()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        other.sites[0].instructions = "Gate code 4411"
        try await TeamSync.syncOnce(&other, remote: server, now: t0)

        let report = try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(owner.sites[0].instructions, "Gate code 4411")
        XCTAssertEqual(report.apply.keptLocal, 0)
        XCTAssertTrue(TeamSync.outgoing(owner).rows.isEmpty)     // not echoed back
    }

    func testLocalChangeNotPushedYetIsNotOverwritten() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        var other = linked()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        other.customers[0].name = "Changed elsewhere"
        try await TeamSync.syncOnce(&other, remote: server, now: t0)

        owner.customers[0].name = "Changed here"                     // not pushed yet
        let rows = try await server.pull(businessID: biz, after: owner.teamSync?.cursor ?? 0)
        let result = TeamSync.apply(rows, to: &owner)
        XCTAssertEqual(result.keptLocal, 1)
        XCTAssertEqual(owner.customers[0].name, "Changed here")

        // The next round pushes it, and it wins everywhere (last write wins).
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        try await TeamSync.syncOnce(&other, remote: server, now: t0)
        XCTAssertEqual(other.customers[0].name, "Changed here")
    }

    func testCursorMovesForwardSoOnlyNewRowsArePulled() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(owner.teamSync?.cursor, server.seq)
        let before = server.seq
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(server.pullCursors.last, before)
        // A device from an older set of kinds starts over.
        owner.teamSync?.kindsVersion = 0
        XCTAssertEqual(TeamSync.cursor(for: try XCTUnwrap(owner.teamSync)), 0)
    }

    // MARK: employees

    func testCrewPushesOnlyWhatRowSecurityAllows() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        var crew = crewPhone()
        try await TeamSync.syncOnce(&crew, remote: server, now: t0)
        XCTAssertEqual(crew.jobs.count, 1)

        crew.customers[0].notes = "crew wrote this"                     // needs editClients: stays on this phone
        crew.jobs[0].status = .done                                    // assigned to Dana: a status change is allowed
        crew.jobs.append(Job(title: "New", start: t0, assigneeIDs: [dana.id], createdAt: t0))   // crew never creates jobs
        crew.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Dana", stormID: "S1", arrival: t0 + 7200))
        crew.timeEntries.append(TimeEntry(memberName: "Dana", start: t0 + 7200))
        let out = TeamSync.outgoing(crew)
        XCTAssertEqual(out.rows.map(\.kind).sorted(), ["job", "timeEntry", "visit"])
        XCTAssertEqual(out.notAllowed, 2)
        try await TeamSync.syncOnce(&crew, remote: server, now: t0)
        XCTAssertNotNil(crew.teamSync?.lastError)
        XCTAssertEqual(crew.customers[0].notes, "crew wrote this")    // not lost here
        XCTAssertEqual(server.row(.job, job.id)?.assignees, [dana.id])   // links unchanged with the status change

        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(owner.jobs.first { $0.id == job.id }?.status, .done)
        XCTAssertEqual(owner.timeEntries.count, 2)
        XCTAssertEqual(owner.visitLog.entries.count, 2)
    }

    func testRefusedRowsAreKeptButNotRetried() async throws {
        let server = FakeTeamServer(biz)
        server.refuse = { $0.kind == "timeEntry" }
        var owner = ownerData()
        let report = try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(report.refused, 1)
        XCTAssertEqual(owner.timeEntries.count, 1)
        XCTAssertNotNil(owner.teamSync?.lastError)
        let pushes = server.pushes.count
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        XCTAssertEqual(server.pushes.count, pushes)
        XCTAssertNil(owner.teamSync?.lastError)
    }

    func testMembershipMakesTheEmployeeExistWithItsPermissions() async throws {
        var phone = linked(role: "crewMember", login: "dana")
        let m = TeamMembership(businessID: biz, businessName: "Ridge", role: "crewLead", memberID: dana.id,
                               permissions: ["viewAllJobs", "logVisits", "manageTeam"], disabled: false)
        TeamSync.applyMembership(m, to: &phone, now: t0)
        phone.session = AppSession(role: .employee, memberID: dana.id, startedAt: t0)
        XCTAssertEqual(phone.currentMember?.name, "dana")
        XCTAssertEqual(phone.currentMember?.permissions, [.viewAllJobs, .logVisits, .manageTeam])
        XCTAssertTrue(phone.can(.viewAllJobs))
        XCTAssertFalse(phone.can(.viewRevenue))
        XCTAssertTrue(TeamSync.outgoing(phone).rows.isEmpty)        // the stand-in is never pushed, even with manageTeam

        // The real member row replaces the stand-in.
        let server = FakeTeamServer(biz)
        var owner = ownerData()
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        try await TeamSync.syncOnce(&phone, remote: server, now: t0)
        XCTAssertEqual(phone.currentMember?.name, "Dana")

        // Switched off: signed out at once.
        var off = m
        off.disabled = true
        TeamSync.applyMembership(off, to: &phone, now: t0)
        XCTAssertNil(phone.session)
    }

    func testPartialDataDoesNotCrash() {
        var crew = crewPhone()
        TeamSync.applyMembership(TeamMembership(businessID: biz, businessName: "Ridge", role: "crewMember", memberID: dana.id,
                                                permissions: ["logVisits"], disabled: false), to: &crew, now: t0)
        let enc = TeamSync.makeEncoder()
        let jobData = try! JSONDecoder().decode(JSONValue.self, from: enc.encode(job))       // its site and client are not here
        let visit = VisitRecord(siteID: UUID(), crewMemberName: "Sam", stormID: "S1", arrival: t0)
        let visitData = try! JSONDecoder().decode(JSONValue.self, from: enc.encode(visit))
        let ghost = UUID()                                                                    // pay for someone not visible here
        let rows = [SyncRow(businessID: biz, kind: "job", id: job.id, data: jobData, assignees: [dana.id], seq: 3),
                    SyncRow(businessID: biz, kind: "visit", id: visit.id, data: visitData, seq: 4),
                    SyncRow(businessID: biz, kind: "memberPay", id: ghost, data: .object(["memberID": .string(ghost.uuidString)]), seq: 5),
                    SyncRow(businessID: biz, kind: "invoice", id: UUID(), data: .object([:]), seq: 6),          // a newer kind
                    SyncRow(businessID: biz, kind: "customer", id: UUID(), data: .string("garbage"), seq: 7),
                    SyncRow(businessID: UUID(), kind: "customer", id: UUID(), data: .object([:]), seq: 99)]     // another business
        let result = TeamSync.apply(rows, to: &crew)
        XCTAssertEqual(crew.jobs.map(\.id), [job.id])
        XCTAssertEqual(crew.visibleJobs.map(\.id), [job.id])
        XCTAssertTrue(crew.sites.isEmpty)
        XCTAssertEqual(crew.visitLog.entries.count, 1)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(crew.teamSync?.cursor, 7)
    }

    func testRemovedMemberIsSignedOutOnTheirPhone() {
        var crew = crewPhone()
        crew.team = [dana]
        TeamSync.applyMembership(TeamMembership(businessID: biz, businessName: "", role: "crewMember", memberID: dana.id,
                                                permissions: ["logVisits"], disabled: false), to: &crew, now: t0)
        TeamSync.apply([SyncRow(businessID: biz, kind: "member", id: dana.id, data: .object([:]), deleted: true, seq: 9)], to: &crew)
        XCTAssertTrue(crew.team.isEmpty)
        XCTAssertNil(crew.session)
    }

    func testLinkingRefusesAPhoneWithOtherRecords() {
        XCTAssertNil(TeamSync.linkProblem(AppData(), businessID: biz))
        XCTAssertNil(TeamSync.linkProblem(linked(), businessID: biz))
        XCTAssertNotNil(TeamSync.linkProblem(linked(), businessID: UUID()))
        var owners = AppData()
        owners.customers = [customer]
        XCTAssertNotNil(TeamSync.linkProblem(owners, businessID: biz))
    }

    // MARK: proof of service

    func testMergedVisitLogVerifiesAndStillCatchesEdits() async throws {
        let server = FakeTeamServer(biz)
        var owner = ownerData()                 // one visit logged on the owner's phone
        owner.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Owner", stormID: "S2", arrival: t0 + 86_400))
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)
        var crew = crewPhone()
        try await TeamSync.syncOnce(&crew, remote: server, now: t0)
        crew.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Dana", stormID: "S2", arrival: t0 + 90_000))
        crew.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Dana", stormID: "S3", arrival: t0 + 200_000))
        XCTAssertTrue(crew.visitLog.verify())
        try await TeamSync.syncOnce(&crew, remote: server, now: t0)
        try await TeamSync.syncOnce(&owner, remote: server, now: t0)

        XCTAssertEqual(owner.visitLog.entries.count, 4)
        XCTAssertEqual(crew.visitLog.entries.count, 4)
        XCTAssertTrue(owner.visitLog.verify())
        XCTAssertTrue(crew.visitLog.verify())
        XCTAssertEqual(owner.visitLog.entries.filter { $0.synced == true }.count, 2)

        // Logging here after merged visits keeps this phone's own chain intact.
        owner.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Owner", stormID: "S4", arrival: t0 + 300_000))
        XCTAssertTrue(owner.visitLog.verify())
        let proofs = ProofPacket.visits(site: site, log: owner.visitLog)
        XCTAssertEqual(proofs.count, 5)

        // An edited visit from another phone is caught, and so is an edited local one.
        var edited = owner.visitLog
        let syncedIndex = try XCTUnwrap(edited.entries.firstIndex { $0.synced == true })
        edited._tamper(at: syncedIndex) { $0.note = "never there" }
        XCTAssertFalse(edited.verify())
        var editedLocal = owner.visitLog
        editedLocal._tamper(at: 0) { $0.snowDepthInches = 40 }
        XCTAssertFalse(editedLocal.verify())

        // A visit already in the log is never replaced by a pulled copy.
        var log = owner.visitLog
        var copy = log.entries[0].record
        copy.note = "rewritten"
        XCTAssertFalse(log.appendSynced(copy))
        XCTAssertEqual(log, owner.visitLog)
    }

    // MARK: saved files

    func testOldSavedFilesStillLoad() throws {
        var old = AppData()
        old.visitLog.append(VisitRecord(siteID: site.id, crewMemberName: "Sam", stormID: "S1", arrival: t0))
        let json = try FileStore.encoder.encode(old)
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertFalse(text.contains("teamSync"))
        XCTAssertFalse(text.contains("\"synced\""))                       // old-style entries are written as before
        let back = try FileStore.decoder.decode(AppData.self, from: json)
        XCTAssertNil(back.teamSync)
        XCTAssertTrue(back.visitLog.verify())

        let minimal = try FileStore.decoder.decode(AppData.self, from: Data(#"{"companyName":"Old","teamSync":{"businessID":"\#(biz.uuidString)"}}"#.utf8))
        XCTAssertEqual(minimal.teamSync?.businessID, biz)
        XCTAssertEqual(minimal.teamSync?.cursor, 0)
        XCTAssertEqual(minimal.teamSync?.role, "owner")

        var linkedData = ownerData()
        linkedData.teamSync?.fingerprints = ["customer/x": "abc"]
        linkedData.teamSync?.lastSyncAt = t0
        let again = try FileStore.decoder.decode(AppData.self, from: FileStore.encoder.encode(linkedData))
        XCTAssertEqual(again.teamSync, linkedData.teamSync)
    }

    func testRestoringABackupKeepsThisPhonesLinkAndResyncs() {
        var device = ownerData()
        device.teamSync?.cursor = 40
        device.teamSync?.fingerprints = ["customer/x": "abc"]
        var backup = AppData()
        backup.teamSync = TeamSyncState(businessID: UUID())
        let out = DataExport.preparedForDevice(backup, current: device)
        XCTAssertEqual(out.teamSync?.businessID, biz)
        XCTAssertEqual(out.teamSync?.cursor, 0)
        XCTAssertEqual(out.teamSync?.fingerprints, [:])
    }

    func testSyncedText() {
        XCTAssertEqual(TeamSync.syncedText(nil, now: t0), "Not synced yet")
        XCTAssertEqual(TeamSync.syncedText(t0 - 20, now: t0), "Synced just now")
        XCTAssertEqual(TeamSync.syncedText(t0 - 125, now: t0), "Synced 2 min ago")
        XCTAssertEqual(TeamSync.syncedText(t0 - 3 * 3600, now: t0), "Synced 3 hr ago")
    }

    func testAccessChangesAreSentOnce() {
        var owner = ownerData()
        owner.teamSync?.cloudLogins[dana.id.uuidString] = "dana"
        XCTAssertEqual(TeamSync.accessChanges(owner).map(\.username), ["dana"])
        owner.teamSync?.accessSent[dana.id.uuidString] = TeamSync.accessFingerprint(dana)
        XCTAssertTrue(TeamSync.accessChanges(owner).isEmpty)
        owner.team[0].status = .disabled
        XCTAssertEqual(TeamSync.accessChanges(owner).count, 1)
        XCTAssertTrue(TeamSync.membersWithoutCloudLogin(owner).isEmpty)
    }
}
