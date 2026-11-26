import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

/// Answers each request with the handler's reply and remembers what was sent.
private final class ScriptedHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    var handler: (URLRequest) -> (Int, String)
    var offline = false

    init(_ handler: @escaping (URLRequest) -> (Int, String)) { self.handler = handler }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return sent }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        lock.lock(); sent.append(request); lock.unlock()
        if offline { throw URLError(.notConnectedToInternet) }
        let (status, body) = handler(request)
        return (Data(body.utf8), status)
    }
}

private final class SessionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TeamCloudSession?] = []
    func add(_ s: TeamCloudSession?) { lock.lock(); values.append(s); lock.unlock() }
    var all: [TeamCloudSession?] { lock.lock(); defer { lock.unlock() }; return values }
}

final class TeamCloudTests: XCTestCase {
    private let config = TeamCloudConfig(url: "https://abc.supabase.co/", anonKey: "anon-key")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let business = UUID()

    private func session(expiresIn: TimeInterval = 3600, token: String = "access-1") -> TeamCloudSession {
        TeamCloudSession(accessToken: token, refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(expiresIn), userID: "user-1", email: "me@ridge.com")
    }

    private func authReply(_ token: String, refresh: String = "refresh-2") -> String {
        #"{"access_token":"\#(token)","token_type":"bearer","expires_in":3600,"refresh_token":"\#(refresh)","user":{"id":"user-1","email":"me@ridge.com"}}"#
    }

    private func cloud(_ http: ScriptedHTTP, session: TeamCloudSession? = nil, log: SessionLog? = nil) -> TeamCloud {
        let fixed = now
        return TeamCloud(config: config, client: http, session: session, now: { fixed }, onSessionChange: { log?.add($0) })
    }

    private func body(_ r: URLRequest) -> Any? { r.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } }
    private func query(_ r: URLRequest, _ name: String) -> String? {
        URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func row(_ seq: Int64) -> String {
        #"{"business_id":"\#(business.uuidString.lowercased())","kind":"customer","id":"\#(UUID().uuidString.lowercased())","data":{"name":"A"},"deleted":false,"assignees":[],"site_id":null,"customer_id":null,"updated_by":"u","updated_at":"2027-01-15T08:00:00Z","seq":\#(seq)}"#
    }

    // MARK: config and names

    func testConfigIgnoresUnfilledBuildSettings() {
        XCTAssertNil(TeamCloudConfig(url: "$(RIDGELINE_SUPABASE_URL)", anonKey: "$(RIDGELINE_SUPABASE_ANON_KEY)"))
        XCTAssertNil(TeamCloudConfig(url: "", anonKey: ""))
        XCTAssertNil(TeamCloudConfig(url: "https://abc.supabase.co", anonKey: " "))
        XCTAssertNil(TeamCloudConfig(url: "http://abc.supabase.co", anonKey: "k"))     // tokens never travel without https
        XCTAssertNil(TeamCloudConfig(url: nil, anonKey: "k"))
        XCTAssertEqual(TeamCloudConfig(url: " https://abc.supabase.co ", anonKey: "k ")?.anonKey, "k")
    }

    func testUsernameBecomesCrewEmail() {
        XCTAssertEqual(TeamCloud.crewEmail(for: " Dana.Cole "), "dana.cole@crew.ridgelineops.app")
        XCTAssertTrue(TeamCloud.isValidUsername("dana_1-x.y"))
        XCTAssertFalse(TeamCloud.isValidUsername("da"))
        XCTAssertFalse(TeamCloud.isValidUsername("dana cole"))
        XCTAssertFalse(TeamCloud.isValidUsername("dana@x"))
    }

    func testSessionNeverPrintsTokens() {
        let s = session(token: "secret-access")
        XCTAssertFalse(String(describing: s).contains("secret-access"))
        XCTAssertFalse(String(reflecting: s).contains("refresh-1"))
    }

    // MARK: auth

    func testSignInWithUsernameSendsCrewEmailAndApikeyOnly() async throws {
        let http = ScriptedHTTP { _ in (200, self.authReply("access-9")) }
        let log = SessionLog()
        let c = cloud(http, log: log)
        let s = try await c.signIn(username: "Dana", password: "Plow-2027-ok")
        XCTAssertEqual(s.accessToken, "access-9")
        XCTAssertEqual(s.userID, "user-1")
        XCTAssertEqual(s.expiresAt, now.addingTimeInterval(3600))
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.url?.path, "/auth/v1/token")
        XCTAssertEqual(query(req, "grant_type"), "password")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))          // not signed in yet
        let sent = body(req) as? [String: String]
        XCTAssertEqual(sent?["email"], "dana@crew.ridgelineops.app")
        XCTAssertEqual(sent?["password"], "Plow-2027-ok")
        XCTAssertEqual(log.all.count, 1)
        let signedIn = await c.isSignedIn
        XCTAssertTrue(signedIn)
    }

    func testWrongPasswordIsPlain() async {
        let http = ScriptedHTTP { _ in (400, #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#) }
        do {
            try await cloud(http).signIn(email: "me@ridge.com", password: "nope-nope-1")
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error as? TeamCloudError, .wrongLogin)
            XCTAssertEqual((error as? TeamCloudError)?.message, "That username or password is not right.")
        }
        let old = ScriptedHTTP { _ in (400, #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#) }
        do { try await cloud(old).signIn(email: "me@ridge.com", password: "x"); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .wrongLogin)
        }
    }

    func testSignUpOfTakenEmailSaysSo() async {
        let http = ScriptedHTTP { _ in (422, #"{"code":422,"error_code":"user_already_exists","msg":"User already registered"}"#) }
        do { try await cloud(http).signUp(email: "me@ridge.com", password: "Plow-2027-ok"); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .accountExists)
        }
    }

    func testOfflineIsPlain() async {
        let http = ScriptedHTTP { _ in (200, "") }
        http.offline = true
        do { try await cloud(http).signIn(email: "me@ridge.com", password: "Plow-2027-ok"); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .offline)
        }
    }

    func testRefreshesOnceAfter401AndRetries() async throws {
        let http = ScriptedHTTP { req in
            if req.url?.path == "/auth/v1/token" { return (200, self.authReply("access-2")) }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" { return (401, #"{"code":"PGRST301","message":"JWT expired"}"#) }
            return (200, "[]")
        }
        let log = SessionLog()
        let c = cloud(http, session: session(), log: log)
        let rows = try await c.myMembership()
        XCTAssertEqual(rows, [])
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertEqual(query(http.requests[1], "grant_type"), "refresh_token")
        XCTAssertEqual((body(http.requests[1]) as? [String: String])?["refresh_token"], "refresh-1")
        XCTAssertEqual(http.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
        XCTAssertEqual(log.all.last??.refreshToken, "refresh-2")
    }

    func testStill401AfterRefreshMeansSignedOut() async {
        let http = ScriptedHTTP { req in
            req.url?.path == "/auth/v1/token" ? (200, self.authReply("access-2")) : (401, "{}")
        }
        do { _ = try await cloud(http, session: session()).myMembership(); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .signedOut)
        }
        XCTAssertEqual(http.requests.count, 3)        // request, one refresh, one retry: never a loop
    }

    func testExpiringSessionRenewsFirst() async throws {
        let http = ScriptedHTTP { req in req.url?.path == "/auth/v1/token" ? (200, self.authReply("access-2")) : (200, "[]") }
        _ = try await cloud(http, session: session(expiresIn: 10)).myMembership()
        XCTAssertEqual(http.requests.first?.url?.path, "/auth/v1/token")
        XCTAssertEqual(http.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testRefusedRefreshClearsSession() async {
        let http = ScriptedHTTP { _ in (400, #"{"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#) }
        let log = SessionLog()
        let c = cloud(http, session: session(expiresIn: 0), log: log)
        do { _ = try await c.myMembership(); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .signedOut)
        }
        let signedIn = await c.isSignedIn
        XCTAssertFalse(signedIn)
        XCTAssertEqual(log.all.count, 1)
        XCTAssertNil(log.all.first ?? nil)
    }

    // MARK: RPCs and the team function

    func testCreateBusinessAndMembership() async throws {
        let id = UUID()
        let member = UUID()
        let http = ScriptedHTTP { req in
            if req.url?.path == "/rest/v1/rpc/create_business" { return (200, "\"\(id.uuidString.lowercased())\"") }
            return (200, #"[{"business_id":"\#(id.uuidString.lowercased())","business_name":"Ridge","role":"crewMember","member_id":"\#(member.uuidString.lowercased())","permissions":["logVisits","useTimeClock","bogus"],"disabled":false}]"#)
        }
        let c = cloud(http, session: session())
        let made = try await c.createBusiness(name: "Ridge")
        XCTAssertEqual(made, id)
        XCTAssertEqual((body(http.requests[0]) as? [String: String])?["p_name"], "Ridge")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "apikey"), "anon-key")
        let m = try await c.myMembership()
        XCTAssertEqual(m.first?.businessID, id)
        XCTAssertEqual(m.first?.memberID, member)
        XCTAssertEqual(m.first?.permissionSet, [.logVisits, .useTimeClock])
        XCTAssertFalse(m.first?.isOwner ?? true)
    }

    func testCreateBusinessErrorReadsMessage() async {
        let http = ScriptedHTTP { _ in (400, #"{"code":"P0001","details":null,"hint":null,"message":"You already belong to a business."}"#) }
        do { _ = try await cloud(http, session: session()).createBusiness(name: "Ridge"); XCTFail("should fail") } catch {
            XCTAssertEqual((error as? TeamCloudError)?.message, "You already belong to a business.")
        }
    }

    func testTeamFunctionSendsActionAndShowsPlainErrors() async throws {
        let member = UUID()
        var reply = (200, #"{"ok":true}"#)
        let http = ScriptedHTTP { _ in reply }
        let c = cloud(http, session: session())
        try await c.team(.create(memberID: member, username: "dana", password: "Plow-2027-ok", role: .crewLead, permissions: [.useTimeClock, .logVisits]), businessID: business)
        let sent = try XCTUnwrap(body(http.requests[0]) as? [String: Any])
        XCTAssertEqual(http.requests[0].url?.path, "/functions/v1/team")
        XCTAssertEqual(sent["action"] as? String, "create")
        XCTAssertEqual(sent["business_id"] as? String, business.uuidString.lowercased())
        XCTAssertEqual(sent["member_id"] as? String, member.uuidString.lowercased())
        XCTAssertEqual(sent["role"] as? String, "crewLead")
        XCTAssertEqual(sent["permissions"] as? [String], ["logVisits", "useTimeClock"])

        reply = (409, #"{"error":"username taken"}"#)
        do { try await c.team(.create(memberID: member, username: "dana", password: "Plow-2027-ok", role: .crewLead, permissions: []), businessID: business); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .conflict("That username is taken. Pick another."))
        }
        reply = (400, #"{"error":"Passwords need 8 to 72 characters."}"#)
        do { try await c.team(.resetPassword(username: "dana", password: "short"), businessID: business); XCTFail("should fail") } catch {
            XCTAssertEqual((error as? TeamCloudError)?.message, "Passwords need 8 to 72 characters.")
        }
        reply = (404, #"{"error":"unknown username"}"#)
        do { try await c.team(.remove(username: "ghost"), businessID: business); XCTFail("should fail") } catch {
            XCTAssertEqual(error as? TeamCloudError, .notFound("Unknown username."))
        }
        let access = try XCTUnwrap(TeamAction.setAccess(username: "dana", role: .crewMember, permissions: [], disabled: true)
            .body(businessID: business)["disabled"])
        XCTAssertEqual(access, .bool(true))
    }

    // MARK: records

    func testPullPagesBySeq() async throws {
        let http = ScriptedHTTP { req in
            let after = Int64(self.query(req, "seq")?.replacingOccurrences(of: "gt.", with: "") ?? "0") ?? 0
            let count = after == 7 ? 500 : 2
            let rows = (1...count).map { self.row(after + Int64($0)) }
            return (200, "[" + rows.joined(separator: ",") + "]")
        }
        let rows = try await cloud(http, session: session()).pull(businessID: business, after: 7)
        XCTAssertEqual(rows.count, 502)
        XCTAssertEqual(http.requests.count, 2)
        let first = http.requests[0]
        XCTAssertEqual(first.httpMethod, "GET")
        XCTAssertEqual(first.url?.path, "/rest/v1/records")
        XCTAssertEqual(query(first, "business_id"), "eq.\(business.uuidString.lowercased())")
        XCTAssertEqual(query(first, "order"), "seq.asc")
        XCTAssertEqual(query(first, "limit"), "500")
        XCTAssertEqual(query(http.requests[1], "seq"), "gt.507")
        XCTAssertEqual(rows.last?.seq, 509)
    }

    func testPushInBatchesOf200WithMergeDuplicates() async throws {
        let http = ScriptedHTTP { _ in (201, "[]") }
        let rows = (0..<450).map { _ in SyncRow(businessID: business, kind: "customer", id: UUID(), data: .object(["name": .string("A")])) }
        let refused = try await cloud(http, session: session()).push(rows)
        XCTAssertEqual(refused, [])
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertEqual(http.requests.map { (body($0) as? [Any])?.count ?? 0 }, [200, 200, 50])
        let req = http.requests[0]
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=representation")
        let first = try XCTUnwrap((body(req) as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["business_id", "kind", "id", "data", "deleted", "assignees", "site_id", "customer_id"])
        XCTAssertTrue(first["site_id"] is NSNull)
    }

    func testRefusedBatchIsRetriedRowByRow() async throws {
        let bad = UUID()
        let http = ScriptedHTTP { req in
            let rows = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [[String: Any]] ?? []
            let hasBad = rows.contains { ($0["id"] as? String) == bad.uuidString.lowercased() }
            return hasBad ? (403, #"{"code":"42501","message":"new row violates row-level security policy for table \"records\""}"#) : (201, "[]")
        }
        let rows = [UUID(), bad, UUID()].map { SyncRow(businessID: business, kind: "job", id: $0, data: .object([:])) }
        let refused = try await cloud(http, session: session()).push(rows)
        XCTAssertEqual(refused, [TeamSync.key(.job, bad)])
        XCTAssertEqual(http.requests.count, 4)      // the batch, then each row once
    }
}
