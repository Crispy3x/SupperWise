import XCTest
@testable import RidgelineCore

/// A fixed random source so invite codes are the same every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class TeamJobsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    // MARK: team

    /// Adds a person the quick way: a username from their name and a password that passes the rules, with few iterations so tests stay fast.
    @discardableResult
    func add(_ d: inout AppData, _ name: String, role: TeamRole = .crewMember, password: String = "Plow-2027-ok", using g: inout SeededGenerator) throws -> TeamMember {
        try d.addTeamMember(name: name, role: role, username: name.lowercased().replacingOccurrences(of: " ", with: "."),
                            password: password, now: now, iterations: 2, using: &g)
    }

    func testProLimitsEmployeesToFiveAndMaxToTwentyFive() throws {
        var d = AppData()
        d.profile.chosenPlan = .pro
        var g = SeededGenerator(state: 1)
        for i in 1...5 { try add(&d, "Person \(i)", using: &g) }
        XCTAssertThrowsError(try add(&d, "Sixth", using: &g)) { XCTAssertEqual($0 as? TeamError, .limitReached(limit: 5)) }
        XCTAssertEqual(d.logins.count, 5)                                                // nothing half-added
        d.profile.chosenPlan = .max
        XCTAssertNoThrow(try add(&d, "Sixth", using: &g))
        XCTAssertEqual(d.employeeLimit, 25)
        d.subscription = Subscription(trialStart: nil, plan: .pro)       // a paid plan wins over the chosen one
        XCTAssertEqual(d.employeeLimit, 5)
    }

    func testEmptyNameRejectedAndNameTrimmed() throws {
        var d = AppData(); var g = SeededGenerator(state: 3)
        XCTAssertThrowsError(try d.addTeamMember(name: "   ", role: .office, username: "sam", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? TeamError, .emptyName)
        }
        let m = try d.addTeamMember(name: "  Sam Lee ", role: .office, username: "sam.lee", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        XCTAssertEqual(m.name, "Sam Lee")
        XCTAssertEqual(d.username(forMember: m.id), "sam.lee")
    }

    func testRolesStartWithSensiblePermissionsAndOwnerChangesThem() throws {
        var d = AppData(); var g = SeededGenerator(state: 4)
        let crew = try add(&d, "Crew", using: &g)
        XCTAssertEqual(crew.permissions, [.logVisits, .useTimeClock])
        XCTAssertFalse(TeamRole.manager.defaultPermissions.contains(.manageSettings))
        XCTAssertTrue(TeamRole.office.defaultPermissions.contains(.viewRevenue))
        XCTAssertFalse(TeamRole.dispatcher.defaultPermissions.contains(.viewRevenue))
        try d.setPermission(.viewClients, allowed: true, forMember: crew.id)
        XCTAssertTrue(d.team[0].permissions.contains(.viewClients))
        try d.setRole(.dispatcher, forMember: crew.id)
        XCTAssertEqual(d.team[0].permissions, TeamRole.dispatcher.defaultPermissions)     // a new role resets the permissions
        XCTAssertThrowsError(try d.setRole(.office, forMember: UUID())) { XCTAssertEqual($0 as? TeamError, .notFound) }
    }

    func testEmployeeSignsInWithTheUsernameAndPasswordTheOwnerMade() throws {
        var d = AppData(); var g = SeededGenerator(state: 5)
        let m = try add(&d, "Dana", password: "Plow-2027-ok", using: &g)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "wrong-password", now: now), .wrongCredentials)
        XCTAssertNil(d.session)
        XCTAssertEqual(d.attemptSignIn(username: "nobody", password: "Plow-2027-ok", now: now), .wrongCredentials)     // same answer: no guessing usernames
        XCTAssertEqual(d.attemptSignIn(username: "  DANA ", password: "Plow-2027-ok", now: now), .signedIn(.employee))  // case and spaces in the username do not matter
        XCTAssertEqual(d.session?.memberID, m.id)
        XCTAssertEqual(d.currentMember?.status, .active)
        XCTAssertNotNil(d.currentMember?.joinedAt)
        XCTAssertTrue(d.can(.logVisits))
        XCTAssertFalse(d.can(.viewRevenue))
        XCTAssertFalse(d.can(.manageTeam))
        XCTAssertFalse(d.isOwnerSession)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "plow-2027-ok", now: now), .wrongCredentials)        // passwords are case sensitive
    }

    func testPasswordsAreStoredOnlyAsHashes() throws {
        var d = AppData(); var g = SeededGenerator(state: 6)
        try add(&d, "Dana", password: "Plow-2027-ok", using: &g)
        let json = String(data: try JSONEncoder.iso.encode(d), encoding: .utf8)!
        XCTAssertFalse(json.contains("Plow-2027-ok"))
        XCTAssertEqual(d.logins[0].hash.count, 64)
        XCTAssertEqual(d.logins[0].salt.count, 32)
    }

    func testPasswordAndUsernameRules() throws {
        var d = AppData(); var g = SeededGenerator(state: 7)
        for bad in ["short1", "password", "12345678", "aaaaaaaa", String(repeating: "x1", count: 70)] {
            XCTAssertThrowsError(try d.addTeamMember(name: "A", role: .crewMember, username: "alex", password: bad, now: now, iterations: 2, using: &g), bad) {
                guard case .weakPassword = ($0 as? LoginError) else { return XCTFail("\($0)") }
            }
        }
        XCTAssertThrowsError(try d.addTeamMember(name: "A", role: .crewMember, username: "alexalex", password: "alexalex", now: now, iterations: 2, using: &g))   // same as username
        for bad in ["", "ab", "has space", "UPPER!", "semi;colon", String(repeating: "a", count: 33)] {
            XCTAssertThrowsError(try d.addTeamMember(name: "A", role: .crewMember, username: bad, password: "Plow-2027-ok", now: now, iterations: 2, using: &g), bad) {
                XCTAssertEqual($0 as? LoginError, .invalidUsername)
            }
        }
        XCTAssertTrue(d.team.isEmpty); XCTAssertTrue(d.logins.isEmpty)                  // a failed add leaves nothing behind
        try add(&d, "Dana", using: &g)
        XCTAssertThrowsError(try d.addTeamMember(name: "Other Dana", role: .crewMember, username: "DANA", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .usernameTaken)
        }
    }

    func testFiveWrongPasswordsLockTheLoginForFiveMinutes() throws {
        var d = AppData(); var g = SeededGenerator(state: 8)
        try add(&d, "Dana", using: &g)
        for _ in 1...4 { XCTAssertEqual(d.attemptSignIn(username: "dana", password: "nope-nope", now: now), .wrongCredentials) }
        let fifth = d.attemptSignIn(username: "dana", password: "nope-nope", now: now)
        XCTAssertEqual(fifth, .lockedOut(until: now.addingTimeInterval(300)))
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now.addingTimeInterval(120)),
                       .lockedOut(until: now.addingTimeInterval(300)))             // even the right password waits
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now.addingTimeInterval(301)), .signedIn(.employee))
        XCTAssertEqual(d.logins[0].failedAttempts, 0)
    }

    func testOwnerResetsAnEmployeesPassword() throws {
        var d = AppData(); var g = SeededGenerator(state: 9)
        let m = try add(&d, "Dana", using: &g)
        for _ in 1...5 { _ = d.attemptSignIn(username: "dana", password: "nope-nope", now: now) }            // locked
        try d.setEmployeePassword("New-pass-2028", forMember: m.id, now: now, iterations: 2, using: &g)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now), .wrongCredentials)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "New-pass-2028", now: now), .signedIn(.employee))
        XCTAssertThrowsError(try d.setEmployeePassword("short", forMember: m.id, now: now, iterations: 2, using: &g))
        XCTAssertThrowsError(try d.setEmployeePassword("New-pass-2028", forMember: UUID(), now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .notFound)
        }
    }

    func testOwnerLoginAndProtection() throws {
        var d = AppData(); var g = SeededGenerator(state: 10)
        XCTAssertFalse(d.ownerIsProtected)
        XCTAssertNoThrow(try d.startOwnerSessionWithoutLogin(now: now))                 // allowed while nothing protects the owner
        XCTAssertThrowsError(try d.createOwnerLogin(email: "not an email", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .invalidEmail)
        }
        try d.createOwnerLogin(email: " Owner@Ridge.com ", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        XCTAssertEqual(d.ownerEmail, "owner@ridge.com")
        XCTAssertTrue(d.ownerIsProtected)
        XCTAssertThrowsError(try d.createOwnerLogin(email: "other@ridge.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .ownerLoginExists)
        }
        XCTAssertThrowsError(try d.startOwnerSessionWithoutLogin(now: now)) { XCTAssertEqual($0 as? LoginError, .ownerProtected) }   // no walking in
        d.session = nil
        XCTAssertEqual(d.attemptSignIn(username: "owner@ridge.com", password: "wrong-wrong", now: now), .wrongCredentials)
        XCTAssertNil(d.session)
        XCTAssertEqual(d.attemptSignIn(username: "OWNER@ridge.com", password: "Plow-2027-ok", now: now), .signedIn(.owner))
        XCTAssertTrue(d.isOwnerSession)
        XCTAssertTrue(d.can(.manageTeam))
    }

    func testChangingTheOwnerPasswordNeedsTheCurrentOne() throws {
        var d = AppData(); var g = SeededGenerator(state: 11)
        try d.createOwnerLogin(email: "owner@ridge.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        XCTAssertThrowsError(try d.changeOwnerPassword(current: "wrong-wrong", new: "Brand-new-2028", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .wrongPassword)
        }
        try d.changeOwnerPassword(current: "Plow-2027-ok", new: "Brand-new-2028", now: now, iterations: 2, using: &g)
        XCTAssertEqual(d.attemptSignIn(username: "owner@ridge.com", password: "Plow-2027-ok", now: now), .wrongCredentials)
        XCTAssertEqual(d.attemptSignIn(username: "owner@ridge.com", password: "Brand-new-2028", now: now), .signedIn(.owner))
    }

    func testAppleSignInForTheOwnerMustMatchAndCannotSkipAnEmailLogin() throws {
        var d = AppData(); var g = SeededGenerator(state: 12)
        try d.signInOwnerWithApple(appleUserID: "apple-1", displayName: "Ryan", email: "r@x.com", now: now)
        XCTAssertTrue(d.isOwnerSession); XCTAssertTrue(d.ownerIsProtected)
        d.session = nil
        XCTAssertThrowsError(try d.signInOwnerWithApple(appleUserID: "apple-2", displayName: "", email: "", now: now)) {
            XCTAssertEqual($0 as? AccountError, .differentAccount)
        }
        XCTAssertNil(d.session)
        XCTAssertNoThrow(try d.signInOwnerWithApple(appleUserID: "apple-1", displayName: "", email: "", now: now))
        // An owner who only has an email login: a random Apple account must not get in.
        var e = AppData()
        try e.createOwnerLogin(email: "owner@ridge.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        XCTAssertThrowsError(try e.signInOwnerWithApple(appleUserID: "stranger", displayName: "", email: "", now: now)) {
            XCTAssertEqual($0 as? LoginError, .ownerProtected)
        }
        XCTAssertNil(e.session); XCTAssertNil(e.account)
    }

    func testSwitchingAPersonOffSignsThemOutAndFreesTheirSeat() throws {
        var d = AppData(); d.profile.chosenPlan = .pro; var g = SeededGenerator(state: 13)
        var ids: [UUID] = []
        for i in 1...5 { ids.append(try add(&d, "Pat\(i)", using: &g).id) }
        XCTAssertEqual(d.attemptSignIn(username: "pat1", password: "Plow-2027-ok", now: now), .signedIn(.employee))
        try d.setMemberEnabled(false, forMember: ids[0])
        XCTAssertNil(d.session)
        XCTAssertEqual(d.employeeCount, 4)
        XCTAssertEqual(d.attemptSignIn(username: "pat1", password: "Plow-2027-ok", now: now), .accessOff)
        XCTAssertNil(d.session)
        try add(&d, "New", using: &g)                                                    // took the freed seat
        XCTAssertThrowsError(try d.setMemberEnabled(true, forMember: ids[0])) { XCTAssertEqual($0 as? TeamError, .limitReached(limit: 5)) }
    }

    func testRemovingAPersonUnassignsTheirJobsAndDeletesTheirLogin() throws {
        var d = AppData(); var g = SeededGenerator(state: 14)
        let m = try add(&d, "Dana", using: &g)
        let j = try d.addJob(title: "Plow", start: now, assigneeIDs: [m.id], now: now)
        try d.removeTeamMember(m.id)
        XCTAssertTrue(d.jobs.first { $0.id == j.id }!.assigneeIDs.isEmpty)
        XCTAssertTrue(d.team.isEmpty); XCTAssertTrue(d.logins.isEmpty)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now), .wrongCredentials)
    }

    func testOwnerCanDoEverythingAndNoSessionCountsAsOwner() {
        var d = AppData()
        XCTAssertTrue(d.can(.manageTeam))
        d.session = AppSession(role: .owner, startedAt: now)
        XCTAssertTrue(d.can(.viewRevenue))
    }

    func testPasswordHashMatchesPublishedTestVectors() {
        // RFC 4231 test case 2 (HMAC-SHA256) and the well-known PBKDF2-HMAC-SHA256 vectors for "password" / "salt".
        let mac = PasswordHasher.hmacSHA256(key: Array("Jefe".utf8), message: Array("what do ya want for nothing?".utf8))
        XCTAssertEqual(PasswordHasher.hex(mac), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        let salt = Array("salt".utf8)
        XCTAssertEqual(PasswordHasher.hex(PasswordHasher.pbkdf2(password: "password", salt: salt, iterations: 1)),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(PasswordHasher.hex(PasswordHasher.pbkdf2(password: "password", salt: salt, iterations: 2)),
                       "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        XCTAssertEqual(PasswordHasher.hex(PasswordHasher.pbkdf2(password: "password", salt: salt, iterations: 4096)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
        XCTAssertTrue(PasswordHasher.constantTimeEqual([1, 2, 3], [1, 2, 3]))
        XCTAssertFalse(PasswordHasher.constantTimeEqual([1, 2, 3], [1, 2, 4]))
        XCTAssertEqual(PasswordHasher.bytes(fromHex: "00ff10"), [0, 255, 16])
        XCTAssertNil(PasswordHasher.bytes(fromHex: "xyz"))
    }

    func testSuggestedPasswordsPassTheRules() {
        var g = SeededGenerator(state: 99)
        for _ in 1...50 {
            let p = LoginRules.suggestedPassword(using: &g)
            XCTAssertEqual(p.count, 10)
            XCTAssertNoThrow(try LoginRules.checkPassword(p, username: "dana"))
        }
    }

    // MARK: jobs

    func testAddJobChecksTheTitleAndReferences() throws {
        var d = AppData()
        XCTAssertThrowsError(try d.addJob(title: " ", start: now, now: now))
        XCTAssertThrowsError(try d.addJob(title: "Plow", siteID: UUID(), start: now, now: now)) { XCTAssertEqual($0 as? OperationError, .notFound) }
        let job = try d.addJob(title: "Plow", start: now, durationMinutes: 1, assigneeIDs: [UUID()], now: now)
        XCTAssertEqual(job.durationMinutes, 5)             // at least five minutes
        XCTAssertTrue(job.assigneeIDs.isEmpty)             // unknown people are dropped
    }

    func testEmployeesSeeOnlyTheirOwnJobsUnlessAllowedToSeeAll() throws {
        var d = AppData()
        var g = SeededGenerator(state: 21)
        let dana = try add(&d, "Dana", using: &g)
        try add(&d, "Lee", role: .crewLead, using: &g)
        _ = try d.addJob(title: "Dana's", start: now, assigneeIDs: [dana.id], now: now)
        _ = try d.addJob(title: "Someone else's", start: now, now: now)
        XCTAssertEqual(d.visibleJobs.count, 2)                                           // owner sees all
        _ = d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now)
        XCTAssertEqual(d.visibleJobs.map(\.title), ["Dana's"])
        XCTAssertEqual(d.jobs(on: now, calendar: utc).map(\.title), ["Dana's"])
        _ = d.attemptSignIn(username: "lee", password: "Plow-2027-ok", now: now)
        XCTAssertEqual(d.visibleJobs.count, 2)                                           // crew lead may see all
    }

    func testDaysWithJobsAndJobsOnADay() throws {
        var d = AppData()
        let day2 = now.addingTimeInterval(86_400)
        _ = try d.addJob(title: "A", start: now, now: now)
        _ = try d.addJob(title: "B", start: now.addingTimeInterval(3600), now: now)
        _ = try d.addJob(title: "C", start: day2, now: now)
        XCTAssertEqual(d.daysWithJobs(inMonthOf: now, calendar: utc), [15, 16])
        XCTAssertEqual(d.jobs(on: now, calendar: utc).map(\.title), ["A", "B"])
        XCTAssertEqual(d.jobs(on: day2, calendar: utc).map(\.title), ["C"])
    }

    func testRouteStopsOnlyForOpenJobsWithAMapPlace() throws {
        var d = AppData()
        let c = Customer(name: "Pat"); d.customers.append(c)
        let withPlace = Site(customerID: c.id, address: "1 Elm", latitude: 44.9, longitude: -93.2)
        let noPlace = Site(customerID: c.id, address: "2 Oak")
        d.sites = [withPlace, noPlace]
        let a = try d.addJob(title: "A", siteID: withPlace.id, start: now, now: now)
        _ = try d.addJob(title: "B no place", siteID: noPlace.id, start: now, now: now)
        let done = try d.addJob(title: "C done", siteID: withPlace.id, start: now, now: now)
        try d.setJobStatus(.done, id: done.id)
        _ = try d.addJob(title: "D task", start: now, isTask: true, now: now)
        let stops = d.routeStops(on: now, calendar: utc)
        XCTAssertEqual(stops.map(\.id), [a.id])
        XCTAssertEqual(stops[0].name, "1 Elm")
        XCTAssertEqual(stops[0].priority, 3)
    }

    func testCalendarFileIsValidEscapedAndFolded() throws {
        var d = AppData()
        let c = Customer(name: "Pat, the; client"); d.customers.append(c)
        let s = Site(customerID: c.id, address: "1 Elm St, Apt 2"); d.sites = [s]
        let job = try d.addJob(title: "Plow; salt, \\ done", siteID: s.id, start: now, durationMinutes: 90,
                               notes: "Gate code 1234\nBack door " + String(repeating: "x", count: 120), now: now)
        let ics = CalendarExport.ics(jobs: [job], data: d, company: "Ridge Plow", now: now)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("DTSTART:20270115T080000Z"))
        XCTAssertTrue(ics.contains("DTEND:20270115T093000Z"))
        XCTAssertTrue(ics.contains("SUMMARY:Plow\\; salt\\, \\\\ done"))
        XCTAssertTrue(ics.contains("LOCATION:1 Elm St\\, Apt 2"))
        for line in ics.components(separatedBy: "\r\n") { XCTAssertLessThanOrEqual(line.utf8.count, 75, line) }
        XCTAssertFalse(ics.contains("\n\n"))
    }

    // MARK: saving, tutorials, notifications, revenue

    func testTeamJobsAndSessionSurviveSavingAndOldFilesStillLoad() throws {
        var d = AppData(); var g = SeededGenerator(state: 22)
        let m = try add(&d, "Dana", role: .dispatcher, using: &g)
        _ = try d.addJob(title: "Plow", start: now, assigneeIDs: [m.id], now: now)
        d.session = AppSession(role: .owner, startedAt: now)
        d.tutorialsSeen = ["owner"]
        let back = try JSONDecoder.iso.decode(AppData.self, from: JSONEncoder.iso.encode(d))
        XCTAssertEqual(back, d)
        // A file saved before these features existed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(AppData())) as? [String: Any])
        for key in ["team", "jobs", "session", "logins", "tutorialsSeen", "dismissedHints"] { json.removeValue(forKey: key) }
        let old = try JSONDecoder.iso.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.team.isEmpty); XCTAssertTrue(old.jobs.isEmpty); XCTAssertNil(old.session)
    }

    func testOldCustomerWithoutLeadFlagLoadsAsAClient() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Pat"}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(Customer.self, from: json).isLead)
    }

    func testOwnerAndEmployeeTutorialsDiffer() {
        let owner = Tutorials.steps(for: .owner), employee = Tutorials.steps(for: .employee)
        XCTAssertTrue((3...5).contains(owner.count)); XCTAssertTrue((3...5).contains(employee.count))
        XCTAssertTrue(owner.contains { $0.body.contains("14 days") && $0.body.contains("You pay for the plan") })
        XCTAssertTrue(employee.contains { $0.body.contains("You never pay") })
        XCTAssertFalse(employee.contains { $0.body.contains("Pick Pro or Max") })
        XCTAssertEqual(Set(owner.map(\.id)).count, owner.count)
    }

    func testNotificationsShowOnlyWhatThePersonMaySee() throws {
        var d = AppData(); var g = SeededGenerator(state: 23)
        let dana = try add(&d, "Dana", using: &g)
        _ = try d.addJob(title: "Plow", start: now, assigneeIDs: [dana.id], now: now)
        d.subscription = Subscription(trialStart: now.addingTimeInterval(-12 * 86_400), plan: nil)          // 2 days left
        let ownerSees = Notifications.items(for: d, now: now, calendar: utc).map(\.id)
        XCTAssertTrue(ownerSees.contains("jobs-today")); XCTAssertTrue(ownerSees.contains("trial")); XCTAssertTrue(ownerSees.contains("invited"))
        _ = d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now)
        let danaSees = Notifications.items(for: d, now: now, calendar: utc).map(\.id)
        XCTAssertEqual(danaSees, ["jobs-today"])                  // no trial, invoices, requests or invites for an employee
    }

    func testRevenueSummary() throws {
        var d = AppData()
        let c = Customer(name: "Pat"); d.customers.append(c)
        let s = Site(customerID: c.id, address: "1 Elm"); d.sites.append(s)
        var inv = Invoice(number: "INV-1", customerID: c.id, siteID: s.id, issueDate: now, dueDate: now.addingTimeInterval(86_400),
                          lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 10_000))])
        try inv.markSent(at: now)
        try inv.record(ManualPayment(amount: Money(cents: 4_000), date: now, method: .cash))
        d.invoices = [inv]
        let r = RevenueSummary.compute(for: d, now: now, calendar: utc)
        XCTAssertEqual(r.paidThisMonth.cents, 4_000)
        XCTAssertEqual(r.invoicedThisMonth.cents, 10_000)
        XCTAssertEqual(r.outstanding.cents, 6_000)
        XCTAssertEqual(r.overdueCount, 0)
        let late = RevenueSummary.compute(for: d, now: now.addingTimeInterval(40 * 86_400), calendar: utc)
        XCTAssertEqual(late.overdueCount, 1)
        XCTAssertEqual(late.paidThisMonth.cents, 0)            // last month's payment is not this month's
    }

    func testOnboardingStoresThePlanChoice() throws {
        var d = AppData()
        var a = OnboardingAnswers(); a.businessName = "Ridge Plow"; a.plan = .max
        try d.finishOnboarding(a, now: now)
        XCTAssertEqual(d.profile.chosenPlan, .max)
        XCTAssertEqual(d.employeeLimit, 25)
    }
}

extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
