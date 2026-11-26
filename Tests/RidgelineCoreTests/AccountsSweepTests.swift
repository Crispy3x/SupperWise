import XCTest
@testable import RidgelineCore

/// Bugs found in the pre-launch sweep of accounts, clients, team and saved data. Each test failed (or could not be
/// written) before its fix.
final class AccountsSweepTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC

    // MARK: the owner login

    /// An employee could open Profile and make the owner login with their own email and password.
    func testAnEmployeeCannotMakeTheOwnerLogin() throws {
        var d = AppData(); var g = SeededGenerator(state: 41)
        let dana = try d.addTeamMember(name: "Dana", role: .manager, username: "dana", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
        XCTAssertEqual(d.attemptSignIn(username: "dana", password: "Plow-2027-ok", now: now), .signedIn(.employee))
        XCTAssertThrowsError(try d.createOwnerLogin(email: "dana@home.com", password: "Mine-now-2027", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .ownerProtected)
        }
        XCTAssertFalse(d.hasOwnerLogin)
        XCTAssertEqual(d.session?.memberID, dana.id)
        // The owner, signed in, still can.
        d.session = AppSession(role: .owner, startedAt: now)
        XCTAssertNoThrow(try d.createOwnerLogin(email: "owner@ridge.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g))
        XCTAssertEqual(d.ownerEmail, "owner@ridge.com")
    }

    /// With only Sign in with Apple protecting the owner, the welcome screen offered "Create a login", which let anyone in.
    func testALinkedAppleAccountCannotBeSidesteppedByMakingALogin() throws {
        var d = AppData(); var g = SeededGenerator(state: 42)
        try d.signInOwnerWithApple(appleUserID: "apple-1", displayName: "Ryan", email: "", now: now)
        d.session = nil                                                     // signed out: back on the welcome screen
        XCTAssertTrue(d.ownerIsProtected)
        XCTAssertThrowsError(try d.createOwnerLogin(email: "stranger@x.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .ownerProtected)
        }
        XCTAssertFalse(d.hasOwnerLogin)
        // Signed in with Apple again, the owner can add an email login as well.
        try d.signInOwnerWithApple(appleUserID: "apple-1", displayName: "", email: "", now: now)
        XCTAssertNoThrow(try d.createOwnerLogin(email: "ryan@x.com", password: "Plow-2027-ok", now: now, iterations: 2, using: &g))
    }

    /// A person restored from a backup made under another owner login has no sign-in, and "Set a new password" only
    /// answered "That login no longer exists". They can now be given a username and password.
    func testATeamMemberWithoutASignInCanBeGivenOne() throws {
        var d = AppData(); var g = SeededGenerator(state: 43)
        let sam = TeamMember(name: "Sam", role: .crewMember, createdAt: now)
        d.team = [sam]
        XCTAssertThrowsError(try d.setEmployeePassword("Plow-2027-ok", forMember: sam.id, now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .notFound)
        }
        XCTAssertThrowsError(try d.createEmployeeLogin(username: "x", password: "Plow-2027-ok", forMember: sam.id, now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .invalidUsername)
        }
        XCTAssertThrowsError(try d.createEmployeeLogin(username: "sam", password: "short", forMember: sam.id, now: now, iterations: 2, using: &g))
        XCTAssertThrowsError(try d.createEmployeeLogin(username: "sam", password: "Plow-2027-ok", forMember: UUID(), now: now, iterations: 2, using: &g)) {
            XCTAssertEqual($0 as? LoginError, .notFound)
        }
        XCTAssertTrue(d.logins.isEmpty)                                     // a refused sign-in leaves nothing behind

        try d.createEmployeeLogin(username: " Sam ", password: "Plow-2027-ok", forMember: sam.id, now: now, iterations: 2, using: &g)
        XCTAssertEqual(d.username(forMember: sam.id), "sam")
        XCTAssertEqual(d.attemptSignIn(username: "sam", password: "Plow-2027-ok", now: now), .signedIn(.employee))
        XCTAssertThrowsError(try d.createEmployeeLogin(username: "sam2", password: "Plow-2027-ok", forMember: sam.id, now: now, iterations: 2, using: &g))
        XCTAssertEqual(d.logins.count, 1)                                   // never two sign-ins for one person
    }

    // MARK: restoring

    /// After "Forgot your password?" and an erase, restoring a backup brought the forgotten login straight back and signed
    /// everyone out. The restore screen now says so first, and says how to keep a new login.
    func testRestoreWarnsWhenTheBackupsOwnLoginWillBeNeeded() throws {
        var g = SeededGenerator(state: 44)
        var backup = AppData()
        backup.session = AppSession(role: .owner, startedAt: now)
        try backup.createOwnerLogin(email: "old@ridge.com", password: "Forgotten-2026", now: now, iterations: 2, using: &g)

        let erased = AppData()                                              // no login on this device yet
        let warning = try XCTUnwrap(DataExport.signInWarning(backup: backup, device: erased))
        XCTAssertTrue(warning.contains("old@ridge.com"))
        XCTAssertTrue(warning.contains("create a login in Profile first"))
        XCTAssertEqual(DataExport.preparedForDevice(backup, current: erased).ownerEmail, "old@ridge.com")   // which is why the warning matters

        var withNewLogin = AppData()
        withNewLogin.session = AppSession(role: .owner, startedAt: now)
        try withNewLogin.createOwnerLogin(email: "new@ridge.com", password: "Brand-new-2027", now: now, iterations: 2, using: &g)
        XCTAssertNil(DataExport.signInWarning(backup: backup, device: withNewLogin))
        XCTAssertEqual(DataExport.preparedForDevice(backup, current: withNewLogin).ownerEmail, "new@ridge.com")   // the new login is kept

        var appleBackup = AppData()
        appleBackup.account = AccountProfile(appleUserID: "apple-1", displayName: "", email: "", createdAt: now)
        XCTAssertTrue(DataExport.signInWarning(backup: appleBackup, device: erased)?.contains("Apple account") ?? false)
        XCTAssertNil(DataExport.signInWarning(backup: AppData(), device: erased))                              // nothing to warn about
    }

    /// Any JSON file at all (for example one from another app) read as an empty backup, and "Replace" then wiped the business.
    func testAJSONFileThatIsNotABackupIsRefused() throws {
        for other in ["{}", #"{"name":"something-else","version":"1.0.0"}"#, #"{"items":[1,2,3]}"#] {
            XCTAssertThrowsError(try DataExport.restore(from: Data(other.utf8)), other) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        }
        XCTAssertNoThrow(try DataExport.restore(from: try DataExport.backupJSON(AppData())))               // a real, empty backup still reads
        XCTAssertEqual(try DataExport.restore(from: Data(#"{"customers":[],"companyName":"Old"}"#.utf8)).data.companyName, "Old")   // and one from before versions
    }

    // MARK: typed values

    /// Typing "inf" or a huge number as hourly pay crashed the app when it was turned into whole cents.
    func testTypedHourlyPayIsReadSafely() {
        XCTAssertEqual(TeamRules.hourlyRate(typed: ""), .empty)
        XCTAssertEqual(TeamRules.hourlyRate(typed: "   "), .empty)
        XCTAssertEqual(TeamRules.hourlyRate(typed: "0"), .empty)
        XCTAssertEqual(TeamRules.hourlyRate(typed: "20"), .rate(Money(dollars: 20)))
        XCTAssertEqual(TeamRules.hourlyRate(typed: " 22,50 "), .rate(Money(cents: 2250)))
        XCTAssertEqual(TeamRules.hourlyRate(typed: "$18.75"), .rate(Money(cents: 1875)))
        XCTAssertEqual(TeamRules.hourlyRate(typed: "1000"), .rate(Money(dollars: 1000)))
        for bad in ["inf", "infinity", "nan", "1e400", "1e30", "-5", "abc", "20 an hour", "1.2.3", "1001", "99999999999999999999999"] {
            XCTAssertEqual(TeamRules.hourlyRate(typed: bad), .invalid, bad)
        }
    }

    /// A phone or email is optional, but one that cannot work was saved as typed and then quietly never used.
    func testOptionalEmailAndPhoneAreCheckedOnlyWhenTyped() {
        XCTAssertNil(ContactValidation.emailProblem(""))
        XCTAssertNil(ContactValidation.emailProblem("   "))
        XCTAssertNil(ContactValidation.emailProblem(" sam@example.com "))
        for bad in ["sam@", "sam", "sam@home", "a b@c.com", "sam@@x.com"] {
            XCTAssertNotNil(ContactValidation.emailProblem(bad), bad)
        }
        XCTAssertNil(ContactValidation.phoneProblem(""))
        for good in ["555-0100", "(555) 555-1234", "+1 555 555 1234", "555.555.1234 ext 12", "555-555-1234 x5"] {
            XCTAssertNil(ContactValidation.phoneProblem(good), good)
        }
        for bad in ["12345", "call me", "555-CALL-NOW", "1234567890123456"] {
            XCTAssertNotNil(ContactValidation.phoneProblem(bad), bad)
        }
    }

    /// Every refused payment link was blamed on "not on the list", even a Stripe link with a space in it.
    func testPayLinkProblemNamesWhatIsReallyWrong() {
        XCTAssertEqual(PayLink.problem(for: "https://paypal.me/ridge plow"), "Take the spaces out of the link.")
        XCTAssertTrue(PayLink.problem(for: "https://buy.stripe.com/x#frag")?.contains("plain link") ?? false)
        XCTAssertTrue(PayLink.problem(for: "https://stripe.com:8443/x")?.contains("plain link") ?? false)
        XCTAssertTrue(PayLink.problem(for: "https://stripe.com/" + String(repeating: "a", count: 600))?.contains("too long") ?? false)
        XCTAssertTrue(PayLink.problem(for: "https://evil.example.com/pay")?.contains("not on the list") ?? false)
        XCTAssertEqual(PayLink.problem(for: "paypal.me/x"), "The link must start with https://")
        XCTAssertNil(PayLink.problem(for: "  https://paypal.me/ridgeplow  "))
    }

    // MARK: sample clients

    /// The data "Load sample clients" adds: six made-up clients, and a yard and business name when there were none.
    private func withSampleClients() -> AppData {
        var d = AppData()
        for sample in AppData.sampleClients {
            let c = Customer(name: sample.name, phone: AppData.samplePhone)
            let site = Site(customerID: c.id, address: sample.address)
            d.customers.append(c)
            d.sites.append(site)
            d.contracts.append(SnowContract(siteID: site.id, season: "2026-27", terms: .perPush(rate: Money(dollars: 55))))
        }
        d.depot = AppData.sampleYard
        d.companyName = AppData.sampleCompanyName
        d.ensurePortalLinks(now: now)
        return d
    }

    /// There was no way to take the sample clients out again, short of deleting them one by one.
    func testSampleClientsComeOutAgainAndRealOnesStay() {
        var d = withSampleClients()
        let real = Customer(name: "Pat Miller", phone: "612-555-0188")     // a real client who shares a sample client's name and address
        let realSite = Site(customerID: real.id, address: "14 Elm Ave")
        d.customers.append(real)
        d.sites.append(realSite)
        XCTAssertEqual(d.sampleCustomerIDs.count, 6)

        let result = d.removeSampleClients()
        XCTAssertEqual(result.removed, 6)
        XCTAssertEqual(result.kept, 0)
        XCTAssertEqual(d.customers.map(\.id), [real.id])
        XCTAssertEqual(d.sites.map(\.id), [realSite.id])
        XCTAssertTrue(d.contracts.isEmpty)
        XCTAssertTrue(d.portalLinks.isEmpty)
        XCTAssertNil(d.depot)                                               // the sample yard would give a forecast for the wrong city
        XCTAssertEqual(d.companyName, "")
        XCTAssertTrue(d.sampleCustomerIDs.isEmpty)
        XCTAssertEqual(d.removeSampleClients().removed, 0)                  // nothing left to remove, nothing else touched
        XCTAssertEqual(d.customers.count, 1)
    }

    func testAnInvoicedSampleClientStaysAndAChangedYardIsKept() {
        var d = withSampleClients()
        let home = Coordinate(latitude: 43.0, longitude: -78.8)
        d.depot = home
        d.companyName = "Ridge Plow"
        let c = d.customers[0], site = d.sites[0]
        d.invoices = [Invoice(number: "INV-1", customerID: c.id, siteID: site.id, issueDate: now, dueDate: now.addingTimeInterval(86_400),
                              lines: [InvoiceLineItem(description: "Push", amount: Money(dollars: 60))])]
        let result = d.removeSampleClients()
        XCTAssertEqual(result.removed, 5)
        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(d.customers.map(\.id), [c.id])                       // invoices are records, so this one stays
        XCTAssertEqual(d.depot, home)
        XCTAssertEqual(d.companyName, "Ridge Plow")
        XCTAssertTrue(AppData().sampleCustomerIDs.isEmpty)
    }

    // MARK: properties

    /// A property added by mistake could have its address changed but could never be taken off the client.
    func testAPropertyAddedByMistakeCanBeRemovedButRecordsStay() throws {
        var d = AppData()
        let sam = Customer(name: "Sam Lee")
        let elm = Site(customerID: sam.id, address: "14 Elm Ave"), oak = Site(customerID: sam.id, address: "9 Oak St")
        d.customers = [sam]
        d.sites = [elm, oak]
        d.contracts = [SnowContract(siteID: oak.id, season: "2026-27", terms: .perPush(rate: Money(dollars: 50)))]
        d.ensurePortalLinks(now: now)
        _ = try d.addJob(title: "Plow", kind: .snowPlowing, customerID: sam.id, siteID: oak.id, start: now, now: now)
        _ = try d.addJob(title: "Salt", kind: .salting, customerID: sam.id, siteID: elm.id, start: now, now: now)
        d.invoices = [Invoice(number: "INV-1", customerID: sam.id, siteID: elm.id, issueDate: now, dueDate: now.addingTimeInterval(86_400),
                              lines: [InvoiceLineItem(description: "Push", amount: Money(dollars: 60))])]

        XCTAssertThrowsError(try d.deleteSite(elm.id)) { XCTAssertEqual($0 as? ClientProfileError, .propertyHasRecords) }
        XCTAssertEqual(d.sites.count, 2)

        try d.deleteSite(oak.id)
        XCTAssertEqual(d.sites.map(\.id), [elm.id])
        XCTAssertTrue(d.contracts.isEmpty)
        XCTAssertEqual(d.portalLinks.map(\.siteID), [elm.id])
        XCTAssertEqual(d.jobs.map(\.title), ["Salt"])                       // the other property's job is untouched
        XCTAssertEqual(d.customers.count, 1)
        XCTAssertThrowsError(try d.deleteSite(oak.id)) { XCTAssertEqual($0 as? OperationError, .notFound) }
    }
}
