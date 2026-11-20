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

    func testProLimitsEmployeesToFiveAndMaxToTwentyFive() throws {
        var d = AppData()
        d.profile.chosenPlan = .pro
        var g = SeededGenerator(state: 1)
        for i in 1...5 { try d.addTeamMember(name: "Person \(i)", role: .crewMember, now: now, using: &g) }
        XCTAssertThrowsError(try d.addTeamMember(name: "Sixth", role: .crewMember, now: now, using: &g)) {
            XCTAssertEqual($0 as? TeamError, .limitReached(limit: 5))
        }
        d.profile.chosenPlan = .max
        XCTAssertNoThrow(try d.addTeamMember(name: "Sixth", role: .crewMember, now: now, using: &g))
        XCTAssertEqual(d.employeeLimit, 25)
        d.subscription = Subscription(trialStart: nil, plan: .pro)       // a paid plan wins over the chosen one
        XCTAssertEqual(d.employeeLimit, 5)
    }

    func testInviteCodesAreSixSafeCharactersAndUnique() throws {
        var d = AppData(); d.profile.chosenPlan = .max
        var g = SeededGenerator(state: 7)
        var codes = Set<String>()
        for i in 1...25 {
            let m = try d.addTeamMember(name: "P\(i)", role: .crewMember, now: now, using: &g)
            XCTAssertEqual(m.inviteCode.count, 6)
            XCTAssertTrue(m.inviteCode.allSatisfy { TeamRules.codeAlphabet.contains($0) })
            codes.insert(m.inviteCode)
        }
        XCTAssertEqual(codes.count, 25)
        XCTAssertFalse(codes.contains { $0.contains("0") || $0.contains("O") || $0.contains("1") || $0.contains("I") || $0.contains("L") })
    }

    func testEmptyNameRejectedAndNameTrimmed() throws {
        var d = AppData()
        XCTAssertThrowsError(try d.addTeamMember(name: "   ", role: .office, now: now)) { XCTAssertEqual($0 as? TeamError, .emptyName) }
        let m = try d.addTeamMember(name: "  Sam Lee ", role: .office, now: now)
        XCTAssertEqual(m.name, "Sam Lee")
    }

    func testRolesStartWithSensiblePermissionsAndOwnerChangesThem() throws {
        var d = AppData()
        let crew = try d.addTeamMember(name: "Crew", role: .crewMember, now: now)
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

    func testJoiningWithACodeStartsAnEmployeeSessionWithThatPersonsPermissions() throws {
        var d = AppData()
        let m = try d.addTeamMember(name: "Dana", role: .crewMember, now: now)
        XCTAssertThrowsError(try d.join(code: "NOPE", now: now)) { XCTAssertEqual($0 as? TeamError, .invalidCode) }
        XCTAssertNil(d.session)
        let spaced = m.inviteCode.prefix(3) + " - " + m.inviteCode.suffix(3)
        let joined = try d.join(code: String(spaced).lowercased(), now: now)       // case, spaces and dashes do not matter
        XCTAssertEqual(joined.id, m.id)
        XCTAssertEqual(d.session?.role, .employee)
        XCTAssertEqual(d.currentMember?.status, .active)
        XCTAssertTrue(d.can(.logVisits))
        XCTAssertFalse(d.can(.viewRevenue))
        XCTAssertFalse(d.can(.manageTeam))
        XCTAssertFalse(d.isOwnerSession)
    }

    func testOwnerCanDoEverythingAndNoSessionCountsAsOwner() {
        var d = AppData()
        XCTAssertTrue(d.can(.manageTeam))
        d.session = AppSession(role: .owner, startedAt: now)
        XCTAssertTrue(d.can(.viewRevenue))
    }

    func testSwitchingAPersonOffSignsThemOutAndFreesTheirSeat() throws {
        var d = AppData(); d.profile.chosenPlan = .pro
        var ids: [UUID] = []
        for i in 1...5 { ids.append(try d.addTeamMember(name: "P\(i)", role: .crewMember, now: now).id) }
        _ = try d.join(code: d.team[0].inviteCode, now: now)
        try d.setMemberEnabled(false, forMember: ids[0])
        XCTAssertNil(d.session)
        XCTAssertEqual(d.employeeCount, 4)
        XCTAssertThrowsError(try d.join(code: d.team[0].inviteCode, now: now)) { XCTAssertEqual($0 as? TeamError, .disabled) }
        _ = try d.addTeamMember(name: "New", role: .crewMember, now: now)                 // took the freed seat
        XCTAssertThrowsError(try d.setMemberEnabled(true, forMember: ids[0])) { XCTAssertEqual($0 as? TeamError, .limitReached(limit: 5)) }
    }

    func testRemovingAPersonUnassignsTheirJobs() throws {
        var d = AppData()
        let m = try d.addTeamMember(name: "Dana", role: .crewMember, now: now)
        let j = try d.addJob(title: "Plow", start: now, assigneeIDs: [m.id], now: now)
        try d.removeTeamMember(m.id)
        XCTAssertTrue(d.jobs.first { $0.id == j.id }!.assigneeIDs.isEmpty)
        XCTAssertTrue(d.team.isEmpty)
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
        let dana = try d.addTeamMember(name: "Dana", role: .crewMember, now: now)
        let lead = try d.addTeamMember(name: "Lee", role: .crewLead, now: now)
        _ = try d.addJob(title: "Dana's", start: now, assigneeIDs: [dana.id], now: now)
        _ = try d.addJob(title: "Someone else's", start: now, now: now)
        XCTAssertEqual(d.visibleJobs.count, 2)                                           // owner sees all
        _ = try d.join(code: dana.inviteCode, now: now)
        XCTAssertEqual(d.visibleJobs.map(\.title), ["Dana's"])
        XCTAssertEqual(d.jobs(on: now, calendar: utc).map(\.title), ["Dana's"])
        _ = try d.join(code: lead.inviteCode, now: now)
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
        var d = AppData()
        let m = try d.addTeamMember(name: "Dana", role: .dispatcher, now: now)
        _ = try d.addJob(title: "Plow", start: now, assigneeIDs: [m.id], now: now)
        d.session = AppSession(role: .owner, startedAt: now)
        d.tutorialsSeen = ["owner"]
        let back = try JSONDecoder.iso.decode(AppData.self, from: JSONEncoder.iso.encode(d))
        XCTAssertEqual(back, d)
        // A file saved before these features existed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(AppData())) as? [String: Any])
        for key in ["team", "jobs", "session", "tutorialsSeen", "dismissedHints"] { json.removeValue(forKey: key) }
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
        var d = AppData()
        let dana = try d.addTeamMember(name: "Dana", role: .crewMember, now: now)
        _ = try d.addJob(title: "Plow", start: now, assigneeIDs: [dana.id], now: now)
        d.subscription = Subscription(trialStart: now.addingTimeInterval(-12 * 86_400), plan: nil)          // 2 days left
        let ownerSees = Notifications.items(for: d, now: now, calendar: utc).map(\.id)
        XCTAssertTrue(ownerSees.contains("jobs-today")); XCTAssertTrue(ownerSees.contains("trial")); XCTAssertTrue(ownerSees.contains("invited"))
        _ = try d.join(code: dana.inviteCode, now: now)
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
