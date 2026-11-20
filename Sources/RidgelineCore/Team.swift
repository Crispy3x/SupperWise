import Foundation

public enum TeamError: Error, Equatable {
    case emptyName
    case limitReached(limit: Int)
    case notFound
    case invalidCode
    case disabled
}

/// What a person can do in the app. The owner can do everything. Everyone else gets what the owner allows.
public enum Permission: String, Codable, CaseIterable, Sendable {
    case viewAllJobs, editJobs, logVisits, useTimeClock
    case viewClients, editClients, viewRequests, answerRequests
    case viewQuotes, editQuotes, viewRevenue
    case viewTeam, manageTeam, manageSettings

    public var title: String {
        switch self {
        case .viewAllJobs: return "See all jobs (not only their own)"
        case .editJobs: return "Create and change jobs"
        case .logVisits: return "Log visits and photos"
        case .useTimeClock: return "Use the time clock"
        case .viewClients: return "See clients"
        case .editClients: return "Add and change clients"
        case .viewRequests: return "See client requests"
        case .answerRequests: return "Answer client requests"
        case .viewQuotes: return "See quotes"
        case .editQuotes: return "Create quotes"
        case .viewRevenue: return "See revenue and invoices"
        case .viewTeam: return "See the team"
        case .manageTeam: return "Add people and change roles"
        case .manageSettings: return "Change settings"
        }
    }
}

/// Roles the owner can hand out. Each starts with sensible permissions that the owner can change one by one.
public enum TeamRole: String, Codable, CaseIterable, Sendable {
    case manager, dispatcher, crewLead, crewMember, office

    public var title: String {
        switch self {
        case .manager: return "Manager"
        case .dispatcher: return "Dispatcher"
        case .crewLead: return "Crew lead"
        case .crewMember: return "Crew member"
        case .office: return "Office"
        }
    }

    public var summary: String {
        switch self {
        case .manager: return "Runs the day. Everything except billing the plan and deleting the account."
        case .dispatcher: return "Plans routes, assigns jobs and answers requests."
        case .crewLead: return "Sees the whole route, logs visits and runs the crew's clock."
        case .crewMember: return "Sees only their own jobs, logs visits and clocks in."
        case .office: return "Clients, quotes, requests and invoices. No field tools."
        }
    }

    public var defaultPermissions: Set<Permission> {
        switch self {
        case .manager:
            return Set(Permission.allCases).subtracting([.manageSettings])
        case .dispatcher:
            return [.viewAllJobs, .editJobs, .logVisits, .viewClients, .viewRequests, .answerRequests, .viewTeam]
        case .crewLead:
            return [.viewAllJobs, .logVisits, .useTimeClock, .viewClients, .viewTeam]
        case .crewMember:
            return [.logVisits, .useTimeClock]
        case .office:
            return [.viewAllJobs, .editJobs, .viewClients, .editClients, .viewRequests, .answerRequests, .viewQuotes, .editQuotes, .viewRevenue]
        }
    }
}

public enum MemberStatus: String, Codable, Sendable {
    /// Added by the owner, has not joined yet.
    case invited
    case active
    /// Switched off by the owner. They can no longer sign in.
    case disabled
}

public struct TeamMember: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var phone: String
    public var email: String
    public var role: TeamRole
    public var permissions: Set<Permission>
    public var status: MemberStatus
    /// The one-time code the person types to join, for example "K7M2QX". It identifies them to this business only.
    public var inviteCode: String
    public var createdAt: Date
    public var joinedAt: Date?

    public init(id: UUID = UUID(), name: String, phone: String = "", email: String = "", role: TeamRole,
                permissions: Set<Permission>? = nil, status: MemberStatus = .invited, inviteCode: String,
                createdAt: Date, joinedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.role = role
        self.permissions = permissions ?? role.defaultPermissions
        self.status = status
        self.inviteCode = inviteCode
        self.createdAt = createdAt
        self.joinedAt = joinedAt
    }
}

/// Who is using the app on this device right now.
public enum SessionRole: String, Codable, Sendable {
    case owner, employee
}

public struct AppSession: Equatable, Codable, Sendable {
    public var role: SessionRole
    /// For an employee: which team member they are.
    public var memberID: UUID?
    public var startedAt: Date
    public init(role: SessionRole, memberID: UUID? = nil, startedAt: Date) {
        self.role = role
        self.memberID = memberID
        self.startedAt = startedAt
    }
}

public enum TeamRules {
    /// How many employees each plan allows. The owner and free office seats are not counted here.
    public static func employeeLimit(for tier: PlanTier) -> Int {
        switch tier {
        case .pro: return 5
        case .max: return 25
        }
    }

    /// Letters and digits that are hard to mix up when read aloud (no 0/O, 1/I/L).
    static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    public static func makeCode<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<6).map { _ in codeAlphabet.randomElement(using: &generator)! })
    }

    public static func normalizedCode(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

extension AppData {
    /// The plan that sets the employee limit: the paid plan, else the one chosen at sign-up, else Pro.
    public var seatPlan: PlanTier { subscription.plan ?? profile.chosenPlan ?? .pro }
    public var employeeLimit: Int { TeamRules.employeeLimit(for: seatPlan) }
    /// People who count against the limit: everyone who is not switched off.
    public var employeeCount: Int { team.filter { $0.status != .disabled }.count }

    @discardableResult
    public mutating func addTeamMember<G: RandomNumberGenerator>(name: String, role: TeamRole, phone: String = "", email: String = "",
                                                                 now: Date, using generator: inout G) throws -> TeamMember {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TeamError.emptyName }
        guard employeeCount < employeeLimit else { throw TeamError.limitReached(limit: employeeLimit) }
        var code = TeamRules.makeCode(using: &generator)
        while team.contains(where: { $0.inviteCode == code }) { code = TeamRules.makeCode(using: &generator) }
        let member = TeamMember(name: String(clean.prefix(80)), phone: String(phone.prefix(40)), email: String(email.prefix(120)),
                                role: role, inviteCode: code, createdAt: now)
        team.append(member)
        return member
    }

    @discardableResult
    public mutating func addTeamMember(name: String, role: TeamRole, phone: String = "", email: String = "", now: Date) throws -> TeamMember {
        var g = SystemRandomNumberGenerator()
        return try addTeamMember(name: name, role: role, phone: phone, email: email, now: now, using: &g)
    }

    /// Changing the role resets the permissions to that role's starting set. The owner can then adjust them.
    public mutating func setRole(_ role: TeamRole, forMember id: UUID) throws {
        guard let i = team.firstIndex(where: { $0.id == id }) else { throw TeamError.notFound }
        team[i].role = role
        team[i].permissions = role.defaultPermissions
    }

    public mutating func setPermission(_ permission: Permission, allowed: Bool, forMember id: UUID) throws {
        guard let i = team.firstIndex(where: { $0.id == id }) else { throw TeamError.notFound }
        if allowed { team[i].permissions.insert(permission) } else { team[i].permissions.remove(permission) }
    }

    /// Switching a person off keeps their history. Switching back on counts against the plan's limit again.
    public mutating func setMemberEnabled(_ enabled: Bool, forMember id: UUID) throws {
        guard let i = team.firstIndex(where: { $0.id == id }) else { throw TeamError.notFound }
        if enabled && team[i].status == .disabled {
            guard employeeCount < employeeLimit else { throw TeamError.limitReached(limit: employeeLimit) }
            team[i].status = team[i].joinedAt == nil ? .invited : .active
        } else if !enabled {
            team[i].status = .disabled
            if session?.memberID == id { session = nil }
        }
    }

    public mutating func removeTeamMember(_ id: UUID) throws {
        guard team.contains(where: { $0.id == id }) else { throw TeamError.notFound }
        team.removeAll { $0.id == id }
        for i in jobs.indices { jobs[i].assigneeIDs.removeAll { $0 == id } }
        if session?.memberID == id { session = nil }
    }

    /// An employee joins with the code the owner gave them.
    @discardableResult
    public mutating func join(code: String, now: Date) throws -> TeamMember {
        let wanted = TeamRules.normalizedCode(code)
        guard wanted.count == 6, let i = team.firstIndex(where: { $0.inviteCode == wanted }) else { throw TeamError.invalidCode }
        guard team[i].status != .disabled else { throw TeamError.disabled }
        if team[i].joinedAt == nil { team[i].joinedAt = now }
        team[i].status = .active
        session = AppSession(role: .employee, memberID: team[i].id, startedAt: now)
        return team[i]
    }

    public var currentMember: TeamMember? {
        guard session?.role == .employee, let id = session?.memberID else { return nil }
        return team.first { $0.id == id }
    }

    public var isOwnerSession: Bool { session == nil || session?.role == .owner }

    /// The owner can do everything. An employee can do what the owner allowed.
    public func can(_ permission: Permission) -> Bool {
        if isOwnerSession { return true }
        guard let member = currentMember, member.status != .disabled else { return false }
        return member.permissions.contains(permission)
    }
}
