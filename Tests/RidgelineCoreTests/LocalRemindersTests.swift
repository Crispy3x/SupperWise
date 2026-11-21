import XCTest
@testable import RidgelineCore

final class LocalRemindersTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// An owner with reminders on, one client and one site (2 in trigger).
    func ownerData() -> (AppData, Customer, Site) {
        var d = AppData()
        d.profile.remindersEnabled = true
        d.session = AppSession(role: .owner, startedAt: now)
        d.subscription = Subscription(trialStart: nil, plan: .pro)
        let c = Customer(name: "Smith")
        let s = Site(customerID: c.id, address: "12 Oak St", triggerInches: 2)
        d.customers = [c]
        d.sites = [s]
        return (d, c, s)
    }

    func sentInvoice(_ number: String, _ c: Customer, _ s: Site, due: Date, dollars: Int = 50) -> Invoice {
        var inv = Invoice(number: number, customerID: c.id, siteID: s.id, issueDate: now, dueDate: due,
                          lines: [InvoiceLineItem(description: "Plow", amount: Money(dollars: dollars))])
        try? inv.markSent(at: now)
        return inv
    }

    func plan(_ d: AppData, now: Date? = nil, forecast: SnowOutlook? = nil) -> [LocalReminder] {
        LocalReminderPlanner.plan(data: d, now: now ?? self.now, forecast: forecast, calendar: utc)
    }

    func testNothingWhenOffOrSignedOut() {
        var (d, c, s) = ownerData()
        d.jobs = [Job(title: "Plow", siteID: s.id, start: at(2027, 1, 16, 6), createdAt: now)]
        d.invoices = [sentInvoice("1001", c, s, due: at(2027, 1, 18, 8))]
        XCTAssertFalse(plan(d).isEmpty)
        d.profile.remindersEnabled = nil
        XCTAssertTrue(plan(d).isEmpty, "off until turned on")
        d.profile.remindersEnabled = false
        XCTAssertTrue(plan(d).isEmpty)
        d.profile.remindersEnabled = true
        d.session = nil
        XCTAssertTrue(plan(d).isEmpty, "signed out")
    }

    func testTomorrowsFirstJobAtSevenTheEveningBefore() {
        var (d, _, s) = ownerData()
        d.jobs = [
            Job(title: "Late plow", siteID: s.id, start: at(2027, 1, 16, 9), createdAt: now),
            Job(title: "Early plow", customerID: d.customers[0].id, siteID: s.id, start: at(2027, 1, 16, 6), createdAt: now),
            Job(title: "Buy salt", start: at(2027, 1, 16, 5), isTask: true, createdAt: now),
            Job(title: "Old job", siteID: s.id, start: at(2027, 1, 16, 4), status: .done, createdAt: now),
            Job(title: "Today", siteID: s.id, start: at(2027, 1, 15, 14), createdAt: now),
        ]
        let jobs = plan(d).filter { $0.kind == .jobs }
        XCTAssertEqual(jobs.count, 1)
        let r = jobs[0]
        XCTAssertEqual(r.id, "ridgeline.reminder.jobs.2027-01-16")
        XCTAssertEqual(r.fireDate, at(2027, 1, 15, 19))
        XCTAssertEqual(r.title, "Tomorrow: 2 jobs, first at 6:00 AM")
        XCTAssertEqual(r.body, "First: Early plow at 12 Oak St for Smith.")
    }

    func testOneReminderPerDayAndNoneOnceTheEveningHasPassed() {
        var (d, _, s) = ownerData()
        d.jobs = [
            Job(title: "A", siteID: s.id, start: at(2027, 1, 16, 7), createdAt: now),
            Job(title: "B", siteID: s.id, start: at(2027, 1, 17, 8), createdAt: now),
            Job(title: "Too far", siteID: s.id, start: at(2027, 1, 30, 8), createdAt: now),
        ]
        XCTAssertEqual(plan(d).filter { $0.kind == .jobs }.map(\.fireDate), [at(2027, 1, 15, 19), at(2027, 1, 16, 19)])
        let late = plan(d, now: at(2027, 1, 15, 20)).filter { $0.kind == .jobs }
        XCTAssertEqual(late.map(\.id), ["ridgeline.reminder.jobs.2027-01-17"])
        XCTAssertEqual(late.first?.title, "Tomorrow: 1 job, first at 8:00 AM")
    }

    func testEmployeeGetsOnlyTheirOwnJobs() {
        var (d, c, s) = ownerData()
        d.subscription = .startTrial(at: now)
        let me = TeamMember(name: "Sam", role: .crewMember, permissions: [.viewAllJobs], status: .active, createdAt: now)
        let other = TeamMember(name: "Lee", role: .crewMember, status: .active, createdAt: now)
        d.team = [me, other]
        d.session = AppSession(role: .employee, memberID: me.id, startedAt: now)
        d.jobs = [
            Job(title: "Lee's job", siteID: s.id, start: at(2027, 1, 16, 6), assigneeIDs: [other.id], createdAt: now),
            Job(title: "Sam's job", siteID: s.id, start: at(2027, 1, 16, 7), assigneeIDs: [me.id], createdAt: now),
            Job(title: "Nobody's", siteID: s.id, start: at(2027, 1, 17, 7), createdAt: now),
        ]
        d.invoices = [sentInvoice("1001", c, s, due: at(2027, 1, 18, 8))]
        let r = plan(d, forecast: SnowOutlook(snowInches: 6, loadedAt: now))
        XCTAssertEqual(r.map(\.kind), [.jobs], "no invoice, snow or trial reminders for employees")
        XCTAssertEqual(r.first?.title, "Tomorrow: your job, first at 7:00 AM")
        XCTAssertEqual(r.first?.body, "First: Sam's job at 12 Oak St for Smith.")

        d.team[0].status = .disabled
        XCTAssertTrue(plan(d).isEmpty)
    }

    func testInvoiceReminderTheMorningAfterItIsDue() {
        var (d, c, s) = ownerData()
        var paid = sentInvoice("1003", c, s, due: at(2027, 1, 18, 8))
        try? paid.record(ManualPayment(amount: Money(dollars: 50), date: now, method: .cash))
        var void = sentInvoice("1004", c, s, due: at(2027, 1, 18, 8))
        void.void()
        let draft = Invoice(number: "1005", customerID: c.id, siteID: s.id, issueDate: now, dueDate: at(2027, 1, 18, 8),
                            lines: [InvoiceLineItem(description: "Plow", amount: Money(dollars: 50))])
        d.invoices = [
            sentInvoice("1001", c, s, due: at(2027, 1, 18, 8), dollars: 120),
            sentInvoice("1002", c, s, due: at(2027, 1, 14, 8)),     // already overdue: the in-app list covers it
            paid, void, draft,
        ]
        let r = plan(d).filter { $0.kind == .invoices }
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2027, 1, 19, 9))
        XCTAssertEqual(r[0].title, "Invoice 1001 is overdue")
        XCTAssertEqual(r[0].body, "Smith owes $120.00. It was due yesterday.")
    }

    func testInvoicesDueTheSameDayShareOneReminder() {
        var (d, c, s) = ownerData()
        let jones = Customer(name: "Jones")
        let lake = Customer(name: "Lake HOA")
        d.customers += [jones, lake]
        d.invoices = [
            sentInvoice("1001", c, s, due: at(2027, 1, 18, 8)),
            sentInvoice("1002", jones, s, due: at(2027, 1, 18, 17), dollars: 75),
            sentInvoice("1003", lake, s, due: at(2027, 1, 18, 23), dollars: 25),
        ]
        let r = plan(d).filter { $0.kind == .invoices }
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].id, "ridgeline.reminder.invoices.2027-01-19")
        XCTAssertEqual(r[0].title, "3 invoices are overdue")
        XCTAssertEqual(r[0].body, "Smith, Jones and 1 more. $150.00 in all.")
    }

    func testSnowHeadsUpWhenForecastReachesLowestTrigger() {
        var (d, _, _) = ownerData()
        let big = Customer(name: "Mall")
        d.customers.append(big)
        d.sites.append(Site(customerID: big.id, address: "1 Mall Rd", triggerInches: 4))
        let lead = Customer(name: "Maybe", isLead: true)
        d.customers.append(lead)
        d.sites.append(Site(customerID: lead.id, address: "9 Elm St", triggerInches: 1))

        let r = plan(d, forecast: SnowOutlook(snowInches: 2.5, loadedAt: now)).filter { $0.kind == .storm }
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2027, 1, 15, 19))
        XCTAssertEqual(r[0].title, "Snow coming: about 2.5 in")
        XCTAssertTrue(r[0].body.contains("2 in trigger"))

        XCTAssertTrue(plan(d, forecast: SnowOutlook(snowInches: 1.5, loadedAt: now)).filter { $0.kind == .storm }.isEmpty,
                      "under the lowest client trigger (leads do not count)")
        XCTAssertTrue(plan(d).filter { $0.kind == .storm }.isEmpty, "no forecast loaded")
        let evening = at(2027, 1, 15, 20)
        XCTAssertTrue(plan(d, now: evening, forecast: SnowOutlook(snowInches: 5, loadedAt: evening)).filter { $0.kind == .storm }.isEmpty,
                      "loaded after 7 PM: the owner just saw it")
        d.sites = []
        XCTAssertTrue(plan(d, forecast: SnowOutlook(snowInches: 5, loadedAt: now)).isEmpty, "no clients, no trigger")
    }

    func testTrialReminderTwoDaysBeforeItEnds() {
        var (d, _, _) = ownerData()
        d.subscription = .startTrial(at: now)                 // ends 2027-01-29 08:00
        let r = plan(d).filter { $0.kind == .trial }
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2027, 1, 27, 10))
        XCTAssertEqual(r[0].title, "Your free trial ends in 2 days")
        XCTAssertTrue(plan(d, now: at(2027, 1, 27, 11)).filter { $0.kind == .trial }.isEmpty, "time already passed")
        d.subscription.plan = .max
        XCTAssertTrue(plan(d).filter { $0.kind == .trial }.isEmpty, "a plan is picked")
    }

    func testSortedUniqueAndUnderThePhoneLimit() {
        var (d, c, s) = ownerData()
        d.subscription = .startTrial(at: now)
        for i in 1...59 {
            d.invoices.append(sentInvoice("\(2000 + i)", c, s, due: now.addingTimeInterval(Double(i) * 86_400)))
        }
        for i in 1...7 { d.jobs.append(Job(title: "Plow \(i)", siteID: s.id, start: now.addingTimeInterval(Double(i) * 86_400), createdAt: now)) }
        let r = plan(d, forecast: SnowOutlook(snowInches: 3, loadedAt: now))
        XCTAssertEqual(r.count, LocalReminderPlanner.maxReminders)
        XCTAssertEqual(r.map(\.fireDate), r.map(\.fireDate).sorted())
        XCTAssertEqual(Set(r.map(\.id)).count, r.count)
        XCTAssertTrue(r.allSatisfy { $0.id.hasPrefix(LocalReminderPlanner.idPrefix) && $0.fireDate > now })
        XCTAssertEqual(r.first?.kind, .jobs)                   // ties at 7 PM sort by id: jobs before storm
        XCTAssertTrue(r.contains { $0.kind == .storm })
        XCTAssertTrue(r.contains { $0.kind == .trial })
    }

    func testOldSavedProfileLoadsWithRemindersOff() throws {
        let json = #"{"companyName":"Ridge Plow"}"#.data(using: .utf8)!
        let d = try JSONDecoder().decode(AppData.self, from: json)
        XCTAssertNil(d.profile.remindersEnabled)
        XCTAssertFalse(d.profile.remindersOn)
        var p = BusinessProfile()
        p.remindersEnabled = true
        let back = try JSONDecoder().decode(BusinessProfile.self, from: JSONEncoder().encode(p))
        XCTAssertTrue(back.remindersOn)
    }
}
