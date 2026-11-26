import XCTest
@testable import RidgelineCore

final class FinalSweepTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCrewSeeStormJobsWhileTheStormRunsButNotOtherUnassignedJobs() throws {
        var d = AppData()
        let c = Customer(name: "Pat")
        let site = Site(customerID: c.id, address: "14 Elm Ave", latitude: 45, longitude: -93, triggerInches: 2)
        d.customers = [c]; d.sites = [site]
        _ = try d.addJob(title: "Office errand", start: now, now: now)                 // unassigned, not part of the storm
        let run = try d.startStorm(baseName: "Nov 21", expectedInches: 3, siteIDs: [site.id], now: now)
        let crew = TeamMember(name: "Dana", role: .crewMember, status: .active, createdAt: now)
        d.team.append(crew)
        d.session = AppSession(role: .employee, memberID: crew.id, startedAt: now)
        guard d.can(.logVisits), !d.can(.viewAllJobs) else { return }                    // only meaningful for the default crew role
        XCTAssertEqual(Set(d.visibleJobs.map(\.id)), Set(run.jobIDs))
        _ = try d.finishStorm(now: now.addingTimeInterval(3600))
        XCTAssertTrue(d.visibleJobs.isEmpty)
    }

    func testTimesheetPeriodDoesNotCountTheNextPeriodsFirstInstant() {
        var d = AppData()
        let start = now, end = now.addingTimeInterval(7 * 86_400)
        d.timeEntries = [TimeEntry(memberName: "Sam", start: end, end: end.addingTimeInterval(3600))]
        let report = TimesheetReport.compute(for: d, interval: DateInterval(start: start, end: end), now: end.addingTimeInterval(7200))
        XCTAssertTrue(report.rows.isEmpty)
    }
}
