import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Team sync: the owner and each employee sign in on their own phones and share jobs, clients, visits and time
// through the cloud backend described in supabase/CONTRACT.md. Plain REST through `HTTPClient`, no SDK.
// Nothing here ever logs or prints a token or a password.

/// Where team sync lives. Built from the Info.plist values; empty or unfilled build settings mean team sync is off.
public struct TeamCloudConfig: Equatable, Sendable {
    public let url: URL
    public let anonKey: String

    /// Nil when either value is missing, empty, or still an unfilled build setting such as "$(RIDGELINE_SUPABASE_URL)".
    public init?(url text: String?, anonKey key: String?) {
        guard let text, let key else { return nil }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !k.contains("$("), !text.contains("$("), let url = RoutingServerSettings.validatedURL(text) else { return nil }
        self.url = url
        self.anonKey = k
    }
}

/// A signed-in cloud login. Kept in the Keychain by the app, never in the data file.
public struct TeamCloudSession: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
    public var email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }

    // Printing a session (logs, crash reports, debugger) never shows the secrets.
    public var description: String { "TeamCloudSession(user: \(userID), expires: \(expiresAt))" }
    public var debugDescription: String { description }
}

/// What went wrong, in words the person can act on.
public enum TeamCloudError: Error, Equatable, Sendable {
    /// Wrong email, username or password.
    case wrongLogin
    /// Sign up with an email that already has an account.
    case accountExists
    /// No session, or the saved one can no longer be renewed: sign in again.
    case signedOut
    case offline
    /// Row security or the function refused it.
    case notAllowed(String?)
    /// 409, for example a username that is taken.
    case conflict(String)
    /// 404 from the `team` function: no such username.
    case notFound(String)
    /// Any other refusal, with a plain sentence.
    case rejected(String)
    case unreadable

    public var message: String {
        switch self {
        case .wrongLogin: return "That username or password is not right."
        case .accountExists: return "That email already has a team sync account, and the password is not right."
        case .signedOut: return "Team sync needs you to sign in again."
        case .offline: return "No connection right now. Changes stay on this phone and sync when you are back online."
        case .notAllowed(let why): return why ?? "Your login is not allowed to do that."
        case .conflict(let why), .rejected(let why), .notFound(let why): return why
        case .unreadable: return "Team sync sent an answer the app could not read. Try again later."
        }
    }
}

/// One row of `my_membership`.
public struct TeamMembership: Equatable, Sendable, Decodable {
    public var businessID: UUID
    public var businessName: String
    /// "owner" or a TeamRole raw value.
    public var role: String
    public var memberID: UUID?
    public var permissions: [String]
    public var disabled: Bool

    public init(businessID: UUID, businessName: String, role: String, memberID: UUID?, permissions: [String], disabled: Bool) {
        self.businessID = businessID
        self.businessName = businessName
        self.role = role
        self.memberID = memberID
        self.permissions = permissions
        self.disabled = disabled
    }

    enum CodingKeys: String, CodingKey {
        case businessID = "business_id", businessName = "business_name", role, memberID = "member_id", permissions, disabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessID = try c.decode(UUID.self, forKey: .businessID)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        memberID = try c.decodeIfPresent(UUID.self, forKey: .memberID)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }

    public var isOwner: Bool { role == "owner" }
    public var permissionSet: Set<Permission> { Set(permissions.compactMap(Permission.init(rawValue:))) }
}

/// The `team` Edge Function actions.
public enum TeamAction: Equatable, Sendable {
    case create(memberID: UUID, username: String, password: String, role: TeamRole, permissions: Set<Permission>)
    case resetPassword(username: String, password: String)
    case setAccess(username: String, role: TeamRole, permissions: Set<Permission>, disabled: Bool)
    case remove(username: String)

    func body(businessID: UUID) -> JSONValue {
        var o: [String: JSONValue] = ["business_id": .string(businessID.uuidString.lowercased())]
        func perms(_ p: Set<Permission>) -> JSONValue { .array(p.map(\.rawValue).sorted().map(JSONValue.string)) }
        switch self {
        case .create(let memberID, let username, let password, let role, let permissions):
            o["action"] = .string("create")
            o["member_id"] = .string(memberID.uuidString.lowercased())
            o["username"] = .string(username)
            o["password"] = .string(password)
            o["role"] = .string(role.rawValue)
            o["permissions"] = perms(permissions)
        case .resetPassword(let username, let password):
            o["action"] = .string("reset_password")
            o["username"] = .string(username)
            o["password"] = .string(password)
        case .setAccess(let username, let role, let permissions, let disabled):
            o["action"] = .string("set_access")
            o["username"] = .string(username)
            o["role"] = .string(role.rawValue)
            o["permissions"] = perms(permissions)
            o["disabled"] = .bool(disabled)
        case .remove(let username):
            o["action"] = .string("remove")
            o["username"] = .string(username)
        }
        return .object(o)
    }
}

/// Where pulled rows come from and pushed rows go. `TeamCloud` in the app, an in-memory fake in tests.
public protocol TeamSyncRemote: Sendable {
    /// Upserts the rows. Returns the keys (`TeamSync.key`) of rows the server refused for this login; they are not retried.
    func push(_ rows: [SyncRow]) async throws -> [String]
    /// Every row of the business with `seq` above the cursor, oldest first.
    func pull(businessID: UUID, after cursor: Int64) async throws -> [SyncRow]
}

/// Talks to the team sync backend: sign up, sign in, renew, the two RPCs, the `team` function, pull and push.
public actor TeamCloud: TeamSyncRemote {
    public nonisolated let config: TeamCloudConfig
    private let client: HTTPClient
    private let now: @Sendable () -> Date
    private let onSessionChange: @Sendable (TeamCloudSession?) -> Void
    public private(set) var session: TeamCloudSession?
    private var refreshing: Task<TeamCloudSession, Error>?

    public static let crewDomain = "crew.ridgelineops.app"
    public static let pageSize = 500
    public static let pushBatchSize = 200
    /// The server accepts passwords of 8 to 72 characters.
    public static let maxPasswordLength = 72

    public init(config: TeamCloudConfig, client: HTTPClient = URLSessionHTTPClient(), session: TeamCloudSession? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                onSessionChange: @escaping @Sendable (TeamCloudSession?) -> Void = { _ in }) {
        self.config = config
        self.client = client
        self.session = session
        self.now = now
        self.onSessionChange = onSessionChange
    }

    public var isSignedIn: Bool { session != nil }
    public var userID: String? { session?.userID }

    /// The hidden email behind an employee username. Nobody sees it and no mail can arrive there.
    public static func crewEmail(for username: String) -> String {
        "\(LoginRules.normalizedUsername(username))@\(crewDomain)"
    }

    /// 3 to 32 of a-z, 0-9, dot, dash, underscore, after lowercasing.
    public static func isValidUsername(_ text: String) -> Bool {
        let u = LoginRules.normalizedUsername(text)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return (3...32).contains(u.count) && u.allSatisfy { allowed.contains($0) }
    }

    // MARK: auth

    @discardableResult
    public func signIn(email: String, password: String) async throws -> TeamCloudSession {
        let mail = LoginRules.normalizedUsername(email)
        let body = try JSONEncoder().encode(["email": mail, "password": password])
        let req = request("POST", "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], body: body, bearer: nil)
        let (data, status) = try await transport(req)
        guard status == 200 else { throw Self.authError(status: status, data: data) }
        let fresh = try parseSession(data, email: mail)
        setSession(fresh)
        return fresh
    }

    @discardableResult
    public func signIn(username: String, password: String) async throws -> TeamCloudSession {
        guard Self.isValidUsername(username) else { throw TeamCloudError.wrongLogin }
        return try await signIn(email: Self.crewEmail(for: username), password: password)
    }

    /// Makes the owner's cloud account. Email confirmation is off in the project, so a session comes back at once;
    /// if it does not, a normal sign-in is tried.
    @discardableResult
    public func signUp(email: String, password: String) async throws -> TeamCloudSession {
        let mail = LoginRules.normalizedUsername(email)
        let body = try JSONEncoder().encode(["email": mail, "password": password])
        let (data, status) = try await transport(request("POST", "/auth/v1/signup", body: body, bearer: nil))
        guard (200..<300).contains(status) else { throw Self.authError(status: status, data: data, signingUp: true) }
        if let fresh = try? parseSession(data, email: mail) {
            setSession(fresh)
            return fresh
        }
        return try await signIn(email: mail, password: password)
    }

    /// Forgets the session here and tells the server, best effort. With `onlyIfUserID`, a newer login made since is kept.
    public func signOut(onlyIfUserID: String? = nil) async {
        guard let current = session else { return }
        if let onlyIfUserID, current.userID != onlyIfUserID { return }
        setSession(nil)
        _ = try? await transport(request("POST", "/auth/v1/logout", bearer: current.accessToken))
    }

    /// Renews the access token with the refresh token. Two callers at once share one renewal.
    @discardableResult
    public func refresh() async throws -> TeamCloudSession {
        if let running = refreshing { return try await running.value }
        guard let current = session else { throw TeamCloudError.signedOut }
        let task = Task { try await self.exchange(refreshToken: current.refreshToken, email: current.email) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            setSession(fresh)
            return fresh
        } catch TeamCloudError.signedOut {
            setSession(nil)
            throw TeamCloudError.signedOut
        }
    }

    private func exchange(refreshToken: String, email: String) async throws -> TeamCloudSession {
        let body = try JSONEncoder().encode(["refresh_token": refreshToken])
        let req = request("POST", "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body, bearer: nil)
        let (data, status) = try await transport(req)
        if status == 400 || status == 401 || status == 403 { throw TeamCloudError.signedOut }
        guard status == 200 else { throw Self.dataError(status: status, data: data) }
        return try parseSession(data, email: email)
    }

    // MARK: RPCs

    /// Makes the business; the caller becomes its owner.
    public func createBusiness(name: String) async throws -> UUID {
        let body = try JSONEncoder().encode(["p_name": name])
        let (data, status) = try await authorized { self.request("POST", "/rest/v1/rpc/create_business", body: body, bearer: $0) }
        guard (200..<300).contains(status) else { throw Self.dataError(status: status, data: data) }
        if let id = try? JSONDecoder().decode(UUID.self, from: data) { return id }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"[]")))
        guard let id = UUID(uuidString: text) else { throw TeamCloudError.unreadable }
        return id
    }

    /// The businesses this login belongs to (empty when none).
    public func myMembership() async throws -> [TeamMembership] {
        let (data, status) = try await authorized { self.request("POST", "/rest/v1/rpc/my_membership", body: Data("{}".utf8), bearer: $0) }
        guard (200..<300).contains(status) else { throw Self.dataError(status: status, data: data) }
        guard let rows = try? JSONDecoder().decode([TeamMembership].self, from: data) else { throw TeamCloudError.unreadable }
        return rows
    }

    // MARK: team function

    public func team(_ action: TeamAction, businessID: UUID) async throws {
        let body = try JSONEncoder().encode(action.body(businessID: businessID))
        let (data, status) = try await authorized { self.request("POST", "/functions/v1/team", body: body, bearer: $0) }
        guard (200..<300).contains(status) else { throw Self.functionError(status: status, data: data) }
    }

    /// Deletes this person's cloud login (and, for an owner, the business with all its records and employee logins).
    public func deleteMe() async throws {
        let body = Data(#"{"action":"delete_me"}"#.utf8)
        let (data, status) = try await authorized { self.request("POST", "/functions/v1/team", body: body, bearer: $0) }
        guard (200..<300).contains(status) else { throw Self.functionError(status: status, data: data) }
    }

    // MARK: records

    public func pull(businessID: UUID, after cursor: Int64) async throws -> [SyncRow] {
        var all: [SyncRow] = []
        var position = cursor
        for _ in 0..<10_000 {
            let page = try await pullPage(businessID: businessID, after: position)
            all += page
            let highest = page.compactMap(\.seq).max() ?? position
            if page.count < Self.pageSize || highest <= position { break }
            position = highest
        }
        return all
    }

    private func pullPage(businessID: UUID, after cursor: Int64) async throws -> [SyncRow] {
        let query = [URLQueryItem(name: "business_id", value: "eq.\(businessID.uuidString.lowercased())"),
                     URLQueryItem(name: "seq", value: "gt.\(cursor)"),
                     URLQueryItem(name: "order", value: "seq.asc"),
                     URLQueryItem(name: "limit", value: "\(Self.pageSize)")]
        let (data, status) = try await authorized { self.request("GET", "/rest/v1/records", query: query, bearer: $0) }
        guard status == 200 else { throw Self.dataError(status: status, data: data) }
        guard let rows = try? JSONDecoder().decode([SyncRow].self, from: data) else { throw TeamCloudError.unreadable }
        return rows
    }

    /// Upserts in batches of 200. One refused row fails its whole batch, so a refused batch (403 row security, or a 400
    /// such as a crew member changing more than a job's status) is sent again one row at a time; the refused rows are
    /// returned and the rest go through.
    public func push(_ rows: [SyncRow]) async throws -> [String] {
        var refused: [String] = []
        var start = 0
        while start < rows.count {
            let batch = Array(rows[start..<min(start + Self.pushBatchSize, rows.count)])
            start += Self.pushBatchSize
            do {
                try await pushBatch(batch)
            } catch is RowsRefused {
                guard batch.count > 1 else { refused.append(batch[0].key); continue }
                for row in batch {
                    do { try await pushBatch([row]) } catch is RowsRefused { refused.append(row.key) }
                }
            }
        }
        return refused
    }

    /// The server turned down the rows themselves (400, 403, 409, 422), not the connection or the login.
    private struct RowsRefused: Error {}

    private func pushBatch(_ batch: [SyncRow]) async throws {
        let body = try JSONEncoder().encode(batch)
        let (data, status) = try await authorized { token -> URLRequest in
            var req = self.request("POST", "/rest/v1/records", body: body, bearer: token)
            req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
            return req
        }
        if [400, 403, 409, 422].contains(status) { throw RowsRefused() }
        guard (200..<300).contains(status) else { throw Self.dataError(status: status, data: data) }
    }

    // MARK: plumbing

    private func setSession(_ new: TeamCloudSession?) {
        session = new
        onSessionChange(new)
    }

    private func endpoint(_ path: String, _ query: [URLQueryItem]) -> URL {
        var base = config.url.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var parts = URLComponents(string: base + path) ?? URLComponents()
        if !query.isEmpty { parts.queryItems = query }
        return parts.url ?? config.url
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, bearer: String?) -> URLRequest {
        var req = URLRequest(url: endpoint(path, query))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func transport(_ req: URLRequest) async throws -> (data: Data, status: Int) {
        do {
            return try await client.send(req)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TeamCloudError.offline
        }
    }

    /// Sends with the access token, renewing it first when it is about to run out, and once more after a 401.
    private func authorized(_ make: (String) -> URLRequest) async throws -> (data: Data, status: Int) {
        guard var current = session else { throw TeamCloudError.signedOut }
        var renewed = false
        if current.expiresAt.timeIntervalSince(now()) < 60 {
            current = try await refresh()
            renewed = true
        }
        var result = try await transport(make(current.accessToken))
        if result.status == 401 && !renewed {
            current = try await refresh()
            result = try await transport(make(current.accessToken))
        }
        if result.status == 401 { throw TeamCloudError.signedOut }
        return result
    }

    private struct AuthReply: Decodable {
        struct User: Decodable { let id: String; let email: String? }
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let expiresAt: Double?
        let user: User?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", expiresAt = "expires_at", user
        }
    }

    private func parseSession(_ data: Data, email: String) throws -> TeamCloudSession {
        guard let reply = try? JSONDecoder().decode(AuthReply.self, from: data), let access = reply.accessToken, !access.isEmpty,
              let refreshToken = reply.refreshToken, let user = reply.user else { throw TeamCloudError.unreadable }
        let expiry = reply.expiresAt.map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(reply.expiresIn ?? 3600)
        return TeamCloudSession(accessToken: access, refreshToken: refreshToken, expiresAt: expiry, userID: user.id,
                                email: user.email ?? email)
    }

    /// The error shapes GoTrue, PostgREST and the Edge Function use.
    struct ErrorBody: Decodable {
        var error: String?
        var errorDescription: String?
        var errorCode: String?
        var msg: String?
        var message: String?
        var code: String?

        enum CodingKeys: String, CodingKey {
            case error, errorDescription = "error_description", errorCode = "error_code", msg, message, code
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            errorDescription = try? c.decodeIfPresent(String.self, forKey: .errorDescription)
            errorCode = try? c.decodeIfPresent(String.self, forKey: .errorCode)
            msg = try? c.decodeIfPresent(String.self, forKey: .msg)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
            if let text = try? c.decodeIfPresent(String.self, forKey: .code) { code = text }
            else if let number = try? c.decodeIfPresent(Int.self, forKey: .code) { code = String(number) }
        }

        static func read(_ data: Data) -> ErrorBody? { try? JSONDecoder().decode(ErrorBody.self, from: data) }
    }

    /// Makes a server phrase into a sentence: capital first letter, full stop at the end.
    static func sentence(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return t }
        t = first.uppercased() + t.dropFirst()
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }

    static func authError(status: Int, data: Data, signingUp: Bool = false) -> TeamCloudError {
        let body = ErrorBody.read(data)
        let code = (body?.errorCode ?? body?.error ?? "").lowercased()
        let text = (body?.msg ?? body?.errorDescription ?? body?.message ?? "").lowercased()
        if status == 429 || code.contains("rate_limit") { return .rejected("Too many tries. Wait a minute and try again.") }
        if code == "user_already_exists" || code == "email_exists" || text.contains("already registered") { return .accountExists }
        if code == "weak_password" || text.contains("password should") { return .rejected("Pick a stronger password with at least 8 characters.") }
        if code == "email_not_confirmed" || text.contains("not confirmed") {
            return .rejected("This email has to be confirmed before team sync can use it.")
        }
        if code == "signup_disabled" || text.contains("signups not allowed") { return .rejected("New team sync accounts are switched off right now.") }
        if code == "invalid_credentials" || code == "invalid_grant" || text.contains("invalid login") { return .wrongLogin }
        if status >= 500 { return .rejected("Team sync is having trouble right now. Try again in a few minutes.") }
        if signingUp, status == 422 || status == 400 { return .rejected("That email cannot be used for team sync. Check it and try again.") }
        return status == 400 || status == 401 ? .wrongLogin : .rejected("Signing in did not work (code \(status)). Try again later.")
    }

    /// PostgREST and RPC errors carry their sentence in `message` (for example "You already belong to a business.").
    static func dataError(status: Int, data: Data) -> TeamCloudError {
        let body = ErrorBody.read(data)
        if status == 401 { return .signedOut }
        if status == 403 || body?.code == "42501" { return .notAllowed(nil) }
        if status >= 500 { return .rejected("Team sync is having trouble right now. Try again in a few minutes.") }
        if let text = body?.message ?? body?.error, !text.isEmpty {
            return status == 409 ? .conflict(sentence(text)) : .rejected(sentence(text))
        }
        return .rejected("Team sync could not save that (code \(status)). Try again later.")
    }

    /// The `team` function answers `{error: "plain sentence"}`; that sentence is shown as is.
    static func functionError(status: Int, data: Data) -> TeamCloudError {
        let said = ErrorBody.read(data)?.error.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if said.lowercased() == "username taken" { return .conflict("That username is taken. Pick another.") }
        if status == 401 { return .signedOut }
        if !said.isEmpty {
            if status == 409 { return .conflict(sentence(said)) }
            if status == 403 { return .notAllowed(sentence(said)) }
            if status == 404 { return .notFound(sentence(said)) }
            return .rejected(sentence(said))
        }
        if status == 404 { return .notFound("That login was not found.") }
        if status == 403 { return .notAllowed(nil) }
        if status == 409 { return .conflict("That already exists.") }
        if status >= 500 { return .rejected("Team sync is having trouble right now. Try again in a few minutes.") }
        return .rejected("Team sync could not do that (code \(status)). Try again later.")
    }
}
