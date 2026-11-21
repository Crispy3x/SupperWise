import XCTest
@testable import RidgelineCore

final class SavedCopiesTests: XCTestCase {
    private var dir: URL!
    private var store: FileStore!
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ridgeline-copies-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = FileStore(url: dir.appendingPathComponent("data.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func business(_ name: String, clients: Int = 1) -> AppData {
        var d = AppData()
        d.companyName = name
        d.customers = (0..<clients).map { Customer(name: "Client \($0)") }
        return d
    }

    private func write(_ data: AppData, _ name: String) throws {
        try FileStore.encoder.encode(data).write(to: dir.appendingPathComponent(name))
    }

    private func writeGarbage(_ name: String) throws {
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent(name))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: recovery order

    func testDailyCopyName() {
        XCTAssertEqual(store.dailyCopyName(for: noon(2026, 11, 21), timeZone: utc), "data-20261121.json")
        XCTAssertEqual(store.backupURL.lastPathComponent, "data.json.bak")
    }

    func testRecoveryTriesBakFirst() throws {
        try writeGarbage("data.json")
        try write(business("Bak"), "data.json.bak")
        try write(business("Day 20"), "data-20261120.json")
        try write(business("Day 19"), "data-20261119.json")
        XCTAssertEqual(store.recoveryCandidates().map(\.lastPathComponent), ["data.json.bak", "data-20261120.json", "data-20261119.json"])

        let r = store.loadOrRecover(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(r.data.companyName, "Bak")
        XCTAssertEqual(r.restoredCopy, "data.json.bak")
        XCTAssertTrue(r.safeToSave)
        XCTAssertNotNil(r.notice)
        XCTAssertTrue(exists("data.unreadable-1800000000.json"))     // the bad file is kept
        XCTAssertEqual(try store.load().companyName, "Bak")           // and the copy is now the main file
    }

    func testRecoveryFallsBackToNewestDailyCopy() throws {
        try writeGarbage("data.json")
        try writeGarbage("data.json.bak")
        try write(business("Day 19"), "data-20261119.json")
        try write(business("Day 20"), "data-20261120.json")
        let r = store.loadOrRecover(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(r.data.companyName, "Day 20")
        XCTAssertEqual(r.restoredCopy, "data-20261120.json")
        XCTAssertTrue(r.notice?.contains("daily copy") ?? false)
    }

    func testRecoveryStartsEmptyWhenNoCopyReads() throws {
        try writeGarbage("data.json")
        try writeGarbage("data.json.bak")
        let r = store.loadOrRecover(now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(r.data, AppData())
        XCTAssertNil(r.restoredCopy)
        XCTAssertTrue(r.safeToSave)
        XCTAssertTrue(r.notice?.contains("started empty") ?? false)
    }

    func testMissingMainFileOpensACopy() throws {
        try write(business("Bak", clients: 2), "data.json.bak")
        let r = store.loadOrRecover()
        XCTAssertEqual(r.data.companyName, "Bak")
        XCTAssertEqual(r.restoredCopy, "data.json.bak")
        XCTAssertTrue(exists("data.json"))
    }

    // MARK: rolling and daily copies

    func testGoodLoadKeepsCopiesAndPrunesOldDailyOnes() throws {
        let now = noon(2026, 11, 21)
        try store.save(business("Ridge"))
        for day in ["20261101", "20261102", "20261103", "20261104"] { try write(business("Old \(day)"), "data-\(day).json") }
        try write(business("Safety"), "before-restore-1.json")
        try writeGarbage("data.unreadable-1.json")
        try write(business("Not a day"), "data-notaday.json")

        let r = store.loadOrRecover(now: now)
        XCTAssertNil(r.notice)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), try Data(contentsOf: store.url))
        let today = store.dailyCopyName(for: now)
        XCTAssertEqual(store.dailyCopyURLs().map(\.lastPathComponent), [today, "data-20261104.json", "data-20261103.json"])
        XCTAssertFalse(exists("data-20261101.json"))
        XCTAssertFalse(exists("data-20261102.json"))
        // Files that are not daily copies are left alone.
        XCTAssertTrue(exists("before-restore-1.json"))
        XCTAssertTrue(exists("data.unreadable-1.json"))
        XCTAssertTrue(exists("data-notaday.json"))
        XCTAssertTrue(exists("data.json"))

        // A second load the same day refreshes the .bak but keeps the day's first copy.
        try store.save(business("Ridge later"))
        _ = store.loadOrRecover(now: now.addingTimeInterval(3600))
        XCTAssertEqual(try store.readCopy(at: store.backupURL).companyName, "Ridge later")
        XCTAssertEqual(try store.readCopy(at: dir.appendingPathComponent(today)).companyName, "Ridge")
    }

    func testPruneKeepsNewestThree() throws {
        for day in ["20261118", "20261121", "20261119", "20261120", "20261117"] { try write(business(day), "data-\(day).json") }
        store.pruneDailyCopies()
        XCTAssertEqual(store.dailyCopyURLs().map(\.lastPathComponent), ["data-20261121.json", "data-20261120.json", "data-20261119.json"])
        store.pruneDailyCopies(keep: 1)
        XCTAssertEqual(store.dailyCopyURLs().map(\.lastPathComponent), ["data-20261121.json"])
    }

    func testEmptyBusinessIsNeverCopied() throws {
        try write(business("Bak", clients: 3), "data.json.bak")
        var empty = AppData(); empty.companyName = "Just started"
        try store.save(empty)
        XCTAssertFalse(store.keepCopies(of: empty))
        _ = store.loadOrRecover()
        XCTAssertEqual(try store.readCopy(at: store.backupURL).customers.count, 3)   // the good copy is not pushed out
        XCTAssertTrue(store.dailyCopyURLs().isEmpty)
    }

    func testSavedCopiesListsReadableCopiesWithClientCounts() throws {
        try write(business("Bak", clients: 2), "data.json.bak")
        try FileManager.default.setAttributes([.modificationDate: noon(2026, 11, 21)], ofItemAtPath: store.backupURL.path)
        try write(business("Day", clients: 5), "data-20261119.json")
        try FileManager.default.setAttributes([.modificationDate: noon(2026, 11, 19)],
                                              ofItemAtPath: dir.appendingPathComponent("data-20261119.json").path)
        try writeGarbage("data-20261118.json")                             // unreadable: left out
        try write(AppData(), "data-20261117.json")                         // nothing in it: left out
        try FileManager.default.copyItem(at: store.backupURL, to: dir.appendingPathComponent("data-20261120.json"))   // same as .bak: left out
        let copies = store.savedCopies()
        XCTAssertEqual(copies.map(\.id), ["data.json.bak", "data-20261119.json"])
        XCTAssertEqual(copies.map(\.clientCount), [2, 5])
        XCTAssertEqual(copies.map(\.kind), [.lastOpened, .daily])
    }

    // MARK: restoring a backup

    func testRestoreClearsTheSignedInSession() throws {
        var d = business("Ridge", clients: 2)
        d.session = AppSession(role: .owner, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let r = try DataExport.restore(from: try DataExport.backupJSON(d))
        XCTAssertNil(r.data.session)
        XCTAssertEqual(r.customerCount, 2)
    }

    private func login(_ username: String, role: SessionRole, member: UUID? = nil, hash: String) -> LoginCredential {
        LoginCredential(id: UUID(), username: username, role: role, memberID: member, salt: "00", hash: hash, iterations: 1,
                        createdAt: Date(timeIntervalSince1970: 0), failedAttempts: 0, lockedUntil: nil)
    }

    func testBackupFromAnotherOwnerBringsNoPasswordHashes() {
        var device = AppData()
        device.logins = [login("me@ridge.com", role: .owner, hash: "mine")]
        device.session = AppSession(role: .owner, startedAt: Date())
        let theirMember = UUID()
        var backup = business("Theirs")
        backup.team = [TeamMember(id: theirMember, name: "Sam", role: .crewMember, createdAt: Date(timeIntervalSince1970: 0))]
        backup.logins = [login("them@other.com", role: .owner, hash: "theirs"), login("sam", role: .employee, member: theirMember, hash: "sam")]
        backup.session = AppSession(role: .owner, startedAt: Date())
        backup.assistantConsentAt = Date(timeIntervalSince1970: 5)

        XCTAssertEqual(DataExport.sameOwner(backup: backup, device: device), false)
        let out = DataExport.preparedForDevice(backup, current: device)
        XCTAssertNil(out.session)
        XCTAssertEqual(out.logins, device.logins)
        XCTAssertNil(out.assistantConsentAt)
        XCTAssertEqual(out.companyName, "Theirs")                       // the records still come across
    }

    func testBackupFromSameOwnerKeepsThisDevicesOwnerPassword() {
        var device = AppData()
        device.logins = [login("me@ridge.com", role: .owner, hash: "new")]
        let member = UUID()
        var backup = business("Mine")
        backup.logins = [login("me@ridge.com", role: .owner, hash: "old"), login("sam", role: .employee, member: member, hash: "sam")]

        XCTAssertEqual(DataExport.sameOwner(backup: backup, device: device), true)
        let out = DataExport.preparedForDevice(backup, current: device)
        XCTAssertEqual(out.logins.map(\.hash), ["new", "sam"])
    }

    func testDifferentAppleAccountIsAnotherOwner() {
        var device = AppData()
        device.account = AccountProfile(appleUserID: "apple-a", displayName: "", email: "", createdAt: Date(timeIntervalSince1970: 0))
        var backup = AppData()
        backup.account = AccountProfile(appleUserID: "apple-b", displayName: "", email: "", createdAt: Date(timeIntervalSince1970: 0))
        backup.logins = [login("them@other.com", role: .owner, hash: "theirs")]
        XCTAssertEqual(DataExport.sameOwner(backup: backup, device: device), false)
        let out = DataExport.preparedForDevice(backup, current: device)
        XCTAssertEqual(out.account?.appleUserID, "apple-a")
        XCTAssertTrue(out.logins.isEmpty)
    }

    func testNewDeviceTakesTheBackupsLogins() {
        var backup = business("Mine")
        backup.logins = [login("me@ridge.com", role: .owner, hash: "h")]
        backup.session = AppSession(role: .owner, startedAt: Date())
        XCTAssertNil(DataExport.sameOwner(backup: backup, device: AppData()))
        let out = DataExport.preparedForDevice(backup, current: AppData())
        XCTAssertEqual(out.logins, backup.logins)
        XCTAssertNil(out.session)
    }

    // MARK: schema migrations

    private func logStep(_ from: Int) -> SchemaMigrationStep {
        SchemaMigrationStep(from: from) { object in
            var log = object["log"] as? [Int] ?? []
            log.append(from)
            object["log"] = log
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMigrationsRunInOrder() throws {
        let old = Data(#"{"schemaVersion":1,"companyName":"Ridge"}"#.utf8)
        let out = try SchemaMigrations.migrate(old, steps: [logStep(3), logStep(1), logStep(2)], to: 4)
        let obj = try object(out)
        XCTAssertEqual(obj["log"] as? [Int], [1, 2, 3])
        XCTAssertEqual(obj["schemaVersion"] as? Int, 4)
        XCTAssertEqual(obj["companyName"] as? String, "Ridge")
        XCTAssertEqual(SchemaMigrations.version(of: out), 4)
    }

    func testMigrationStartsFromTheFilesVersion() throws {
        let file = Data(#"{"schemaVersion":2}"#.utf8)
        let obj = try object(try SchemaMigrations.migrate(file, steps: [logStep(1), logStep(2), logStep(3)], to: 4))
        XCTAssertEqual(obj["log"] as? [Int], [2, 3])
        // A file with no version counts as version 1.
        let none = try object(try SchemaMigrations.migrate(Data("{}".utf8), steps: [logStep(1)], to: 2))
        XCTAssertEqual(none["log"] as? [Int], [1])
    }

    func testMissingStepThrowsAndCurrentFilesAreUntouched() throws {
        let old = Data(#"{"schemaVersion":1}"#.utf8)
        XCTAssertThrowsError(try SchemaMigrations.migrate(old, steps: [logStep(1), logStep(3)], to: 4)) {
            XCTAssertEqual($0 as? SchemaMigrationError, .missingStep(from: 2))
        }
        let current = Data(#"{"schemaVersion":4,"companyName":"Ridge"}"#.utf8)
        XCTAssertEqual(try SchemaMigrations.migrate(current, steps: [logStep(1)], to: 4), current)
        XCTAssertEqual(try SchemaMigrations.migrate(Data("[1]".utf8), steps: [], to: 4), Data("[1]".utf8))
    }

    func testTheAppStartsWithNoStepsAtTheCurrentVersion() throws {
        XCTAssertTrue(SchemaMigrations.steps.isEmpty)
        XCTAssertEqual(AppData().schemaVersion, SchemaMigrations.currentVersion)
        XCTAssertEqual(DataExport.supportedSchemaVersion, SchemaMigrations.currentVersion)
        let file = try FileStore.encoder.encode(business("Ridge"))
        XCTAssertEqual(try SchemaMigrations.migrate(file), file)
    }
}
