import Foundation

/// Passwords are never stored. Only a salted PBKDF2-HMAC-SHA256 hash is, so a copy of the data file does not reveal them.
public enum PasswordHasher {
    public static let defaultIterations = 50_000

    public static func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var k = key.count > 64 ? SHA256.hash(key) : key
        k += [UInt8](repeating: 0, count: 64 - k.count)
        let inner = SHA256.hash(k.map { $0 ^ 0x36 } + message)
        return SHA256.hash(k.map { $0 ^ 0x5c } + inner)
    }

    /// PBKDF2 with HMAC-SHA256, one 32-byte block.
    public static func pbkdf2(password: String, salt: [UInt8], iterations: Int) -> [UInt8] {
        let key = Array(password.utf8)
        var u = hmacSHA256(key: key, message: salt + [0, 0, 0, 1])
        var out = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = hmacSHA256(key: key, message: u)
                for i in 0..<out.count { out[i] ^= u[i] }
            }
        }
        return out
    }

    public static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    public static func bytes(fromHex text: String) -> [UInt8]? {
        guard text.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let b = UInt8(text[index..<next], radix: 16) else { return nil }
            out.append(b)
            index = next
        }
        return out
    }

    public static func makeSalt<G: RandomNumberGenerator>(using generator: inout G) -> [UInt8] {
        (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
    }

    /// Compares without stopping at the first difference, so timing does not reveal how much matched.
    public static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

public enum LoginError: Error, Equatable {
    case invalidEmail
    case invalidUsername
    case usernameTaken
    case weakPassword(String)
    case ownerLoginExists
    case ownerProtected
    case notFound
    case wrongPassword
}

public enum LoginRules {
    public static let minPasswordLength = 8
    static let commonPasswords: Set<String> = ["password", "password1", "12345678", "123456789", "1234567890", "qwerty123", "qwertyuiop",
                                               "iloveyou", "11111111", "00000000", "letmein1", "welcome1", "abc12345", "snowplow", "ridgeline"]

    public static func normalizedUsername(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 3 to 32 letters, digits, dots, dashes or underscores, and not already taken.
    public static func checkedUsername(_ text: String, existing: [LoginCredential]) throws -> String {
        let u = normalizedUsername(text)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard (3...32).contains(u.count), u.allSatisfy({ allowed.contains($0) }) else { throw LoginError.invalidUsername }
        guard !existing.contains(where: { $0.username == u }) else { throw LoginError.usernameTaken }
        return u
    }

    public static func checkPassword(_ password: String, username: String) throws {
        guard password.count >= minPasswordLength else { throw LoginError.weakPassword("Use at least \(minPasswordLength) characters.") }
        guard password.count <= 128 else { throw LoginError.weakPassword("Use at most 128 characters.") }
        guard password.lowercased() != username.lowercased(), !commonPasswords.contains(password.lowercased()) else {
            throw LoginError.weakPassword("That password is too easy to guess. Pick something less common.")
        }
        guard Set(password).count > 2 else { throw LoginError.weakPassword("Mix in more different characters.") }
    }

    /// A readable password the owner can hand to an employee: letters and digits that are not easy to mix up.
    public static func suggestedPassword<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<10).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

/// A saved login: who it is for, and the salted hash of the password. The owner's login uses their email as the username.
public struct LoginCredential: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var username: String
    public var role: SessionRole
    public var memberID: UUID?
    public var salt: String
    public var hash: String
    public var iterations: Int
    public var createdAt: Date
    public var failedAttempts: Int
    public var lockedUntil: Date?

    static func make<G: RandomNumberGenerator>(username: String, password: String, role: SessionRole, memberID: UUID?, now: Date,
                                               iterations: Int = PasswordHasher.defaultIterations, using generator: inout G) -> LoginCredential {
        let salt = PasswordHasher.makeSalt(using: &generator)
        let hash = PasswordHasher.pbkdf2(password: password, salt: salt, iterations: iterations)
        return LoginCredential(id: UUID(), username: username, role: role, memberID: memberID, salt: PasswordHasher.hex(salt),
                               hash: PasswordHasher.hex(hash), iterations: iterations, createdAt: now, failedAttempts: 0, lockedUntil: nil)
    }

    func matches(_ password: String) -> Bool {
        guard let salt = PasswordHasher.bytes(fromHex: salt), let want = PasswordHasher.bytes(fromHex: hash) else { return false }
        return PasswordHasher.constantTimeEqual(PasswordHasher.pbkdf2(password: password, salt: salt, iterations: iterations), want)
    }
}

public enum SignInOutcome: Equatable, Sendable {
    case signedIn(SessionRole)
    /// Same message for an unknown username and a wrong password, so nobody can find out which usernames exist.
    case wrongCredentials
    case lockedOut(until: Date)
    case accessOff
}

extension AppData {
    public static let maxFailedAttempts = 5
    public static let lockoutSeconds: TimeInterval = 300

    public var hasOwnerLogin: Bool { logins.contains { $0.role == .owner } }
    public var ownerEmail: String? { logins.first { $0.role == .owner }?.username }

    /// Once the owner has a login or a linked Apple account, getting in as owner needs it again after signing out.
    public var ownerIsProtected: Bool { hasOwnerLogin || account != nil }

    public func username(forMember id: UUID) -> String? { logins.first { $0.memberID == id }?.username }

    @discardableResult
    public mutating func createOwnerLogin<G: RandomNumberGenerator>(email: String, password: String, now: Date,
                                                                    iterations: Int = PasswordHasher.defaultIterations,
                                                                    using generator: inout G) throws -> LoginCredential {
        guard !hasOwnerLogin else { throw LoginError.ownerLoginExists }
        let mail = LoginRules.normalizedUsername(email)
        guard ContactValidation.isValidEmail(mail) else { throw LoginError.invalidEmail }
        guard !logins.contains(where: { $0.username == mail }) else { throw LoginError.usernameTaken }
        try LoginRules.checkPassword(password, username: mail)
        let login = LoginCredential.make(username: mail, password: password, role: .owner, memberID: nil, now: now, iterations: iterations, using: &generator)
        logins.append(login)
        return login
    }

    @discardableResult
    public mutating func createOwnerLogin(email: String, password: String, now: Date) throws -> LoginCredential {
        var g = SystemRandomNumberGenerator()
        return try createOwnerLogin(email: email, password: password, now: now, using: &g)
    }

    /// The owner chooses a new password for an employee. It also clears any lock from too many wrong tries.
    public mutating func setEmployeePassword<G: RandomNumberGenerator>(_ password: String, forMember id: UUID, now: Date,
                                                                       iterations: Int = PasswordHasher.defaultIterations,
                                                                       using generator: inout G) throws {
        guard let i = logins.firstIndex(where: { $0.memberID == id }) else { throw LoginError.notFound }
        try LoginRules.checkPassword(password, username: logins[i].username)
        let fresh = LoginCredential.make(username: logins[i].username, password: password, role: .employee, memberID: id, now: logins[i].createdAt, iterations: iterations, using: &generator)
        logins[i] = fresh
    }

    public mutating func setEmployeePassword(_ password: String, forMember id: UUID, now: Date) throws {
        var g = SystemRandomNumberGenerator()
        try setEmployeePassword(password, forMember: id, now: now, using: &g)
    }

    /// The owner changes their own password. The current one must be right.
    public mutating func changeOwnerPassword<G: RandomNumberGenerator>(current: String, new: String, now: Date,
                                                                       iterations: Int = PasswordHasher.defaultIterations,
                                                                       using generator: inout G) throws {
        guard let i = logins.firstIndex(where: { $0.role == .owner }) else { throw LoginError.notFound }
        guard logins[i].matches(current) else { throw LoginError.wrongPassword }
        try LoginRules.checkPassword(new, username: logins[i].username)
        logins[i] = LoginCredential.make(username: logins[i].username, password: new, role: .owner, memberID: nil, now: logins[i].createdAt, iterations: iterations, using: &generator)
    }

    public mutating func changeOwnerPassword(current: String, new: String, now: Date) throws {
        var g = SystemRandomNumberGenerator()
        try changeOwnerPassword(current: current, new: new, now: now, using: &g)
    }

    /// Tries a username and password. This never throws: a wrong password must still be counted and saved, so it returns the outcome.
    /// Five wrong tries in a row lock that login for five minutes.
    public mutating func attemptSignIn(username: String, password: String, now: Date) -> SignInOutcome {
        let name = LoginRules.normalizedUsername(username)
        guard let i = logins.firstIndex(where: { $0.username == name }) else { return .wrongCredentials }
        if let until = logins[i].lockedUntil, until > now { return .lockedOut(until: until) }
        guard logins[i].matches(password) else {
            logins[i].failedAttempts += 1
            if logins[i].failedAttempts >= Self.maxFailedAttempts {
                logins[i].failedAttempts = 0
                let until = now.addingTimeInterval(Self.lockoutSeconds)
                logins[i].lockedUntil = until
                return .lockedOut(until: until)
            }
            return .wrongCredentials
        }
        logins[i].failedAttempts = 0
        logins[i].lockedUntil = nil
        switch logins[i].role {
        case .owner:
            session = AppSession(role: .owner, startedAt: now)
            return .signedIn(.owner)
        case .employee:
            guard let id = logins[i].memberID, let m = team.firstIndex(where: { $0.id == id }), team[m].status != .disabled else { return .accessOff }
            if team[m].joinedAt == nil { team[m].joinedAt = now }
            team[m].status = .active
            session = AppSession(role: .employee, memberID: id, startedAt: now)
            return .signedIn(.employee)
        }
    }

    /// Opening the app as owner with no login at all. Only allowed while nothing protects the owner role.
    public mutating func startOwnerSessionWithoutLogin(now: Date) throws {
        guard !ownerIsProtected else { throw LoginError.ownerProtected }
        session = AppSession(role: .owner, startedAt: now)
    }

    /// Sign in with Apple as the owner. It must be the linked Apple account, and an email login cannot be skipped this way.
    public mutating func signInOwnerWithApple(appleUserID: String, displayName: String, email: String, now: Date) throws {
        if let existing = account {
            guard existing.appleUserID == appleUserID else { throw AccountError.differentAccount }
        } else {
            guard !hasOwnerLogin else { throw LoginError.ownerProtected }
        }
        try signIn(appleUserID: appleUserID, displayName: displayName, email: email, now: now)
        session = AppSession(role: .owner, startedAt: now)
    }
}
