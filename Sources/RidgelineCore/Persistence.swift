import Foundation

/// Everything the app stores. Kept as plain values so it is easy to sync later.
public struct AppData: Equatable, Codable, Sendable {
    public var schemaVersion: Int = SchemaMigrations.currentVersion
    public var companyName: String = ""
    public var customers: [Customer] = []
    public var sites: [Site] = []
    public var contracts: [SnowContract] = []
    public var crews: [Crew] = []
    public var routes: [Route] = []
    public var storms: [StormEvent] = []
    public var visitLog = VisitLog()
    public var timeEntries: [TimeEntry] = []
    public var subscription = Subscription()
    /// Where trucks start (the yard). Optional so older saved files still load.
    public var depot: Coordinate?
    public var invoices: [Invoice] = []
    /// Money spent: receipts, bills and mileage (see Expenses.swift). Used for the profit screen.
    public var expenses: [Expense] = []
    public var lateFeePolicy = LateFeePolicy()
    public var quotes: [Quote] = []
    /// What an hour of crew time costs you (wages and burden), for job costing. Zero until you set it.
    public var laborCostPerHour: Money = .zero
    public var saltCostPerPound: Money = .zero
    /// Address of the routing server (not secret). The access token lives in the Keychain, never in this file.
    public var routingServerURL: String = ""
    /// Where drive times come from. Apple Maps on the device by default (free, no key).
    public var routingProvider: RoutingProvider = .appleMaps
    public var portalLinks: [PortalLink] = []
    public var broadcastLog: [BroadcastRecord] = []
    public var serviceRequests: [ServiceRequest] = []
    public var broadcastSettings = BroadcastSettings()
    public var profile = BusinessProfile()
    public var account: AccountProfile?
    public var reminderLog: [ReminderRecord] = []
    /// People the owner added, with the role and permissions each one has.
    public var team: [TeamMember] = []
    /// The schedule: jobs at client sites, plus reminders and tasks.
    public var jobs: [Job] = []
    /// Who is signed in on this device. Saved, so the app stays signed in until someone signs out.
    public var session: AppSession?
    /// Logins: the owner's email and password, and the username and password the owner made for each employee. Hashes only.
    public var logins: [LoginCredential] = []
    /// Walkthroughs already shown, by role name ("owner", "employee").
    public var tutorialsSeen: [String] = []
    /// Tips the user closed, so they do not come back.
    public var dismissedHints: [String] = []
    /// When the owner agreed that the assistant may send their questions and the business details it looks up to our server and to Anthropic.
    public var assistantConsentAt: Date?
    /// Which clients were sent their season link, so nobody gets it twice in one season.
    public var seasonLinkLog: [SeasonLinkRecord] = []
    /// Storms started with Storm mode (see StormMode.swift).
    public var stormRuns: [StormRun] = []
    /// The owner's services and prices (see PriceList.swift). Nil until edited: the suggested list for the profile's services is used.
    public var servicePrices: [ServicePrice]? = nil
    /// Automatic check-in marks a job done when the crew leaves it (see AutoCheckIn.swift). Off: the app asks first.
    public var autoCheckInMarksDone: Bool = false
    /// Where routes start and finish, start time, break and default time per stop (see RoutePlan.swift).
    public var routeSettings = RouteSettings()
    /// One-off stops added in the route planner that are not client jobs.
    public var adHocStops: [AdHocStop] = []
    /// The driving order per day, optimized or dragged by hand.
    public var routeOrders: [SavedRouteOrder] = []
    /// Team sync link and what was last synced (see TeamSync.swift). Nil when team sync is off: the app works as before.
    public var teamSync: TeamSyncState? = nil
    /// Random value made once (32 hex characters) for the website tracker sign-in hashes (see PortalLookup.swift). Empty until first publish.
    public var portalLookupSalt: String = ""

    public init() {}

    // Older saved files lack newer fields, so every field falls back to its default when missing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        customers = try c.decodeIfPresent([Customer].self, forKey: .customers) ?? []
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
        contracts = try c.decodeIfPresent([SnowContract].self, forKey: .contracts) ?? []
        crews = try c.decodeIfPresent([Crew].self, forKey: .crews) ?? []
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? []
        storms = try c.decodeIfPresent([StormEvent].self, forKey: .storms) ?? []
        visitLog = try c.decodeIfPresent(VisitLog.self, forKey: .visitLog) ?? VisitLog()
        timeEntries = try c.decodeIfPresent([TimeEntry].self, forKey: .timeEntries) ?? []
        subscription = try c.decodeIfPresent(Subscription.self, forKey: .subscription) ?? Subscription()
        depot = try c.decodeIfPresent(Coordinate.self, forKey: .depot)
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        lateFeePolicy = try c.decodeIfPresent(LateFeePolicy.self, forKey: .lateFeePolicy) ?? LateFeePolicy()
        quotes = try c.decodeIfPresent([Quote].self, forKey: .quotes) ?? []
        laborCostPerHour = try c.decodeIfPresent(Money.self, forKey: .laborCostPerHour) ?? .zero
        saltCostPerPound = try c.decodeIfPresent(Money.self, forKey: .saltCostPerPound) ?? .zero
        routingServerURL = try c.decodeIfPresent(String.self, forKey: .routingServerURL) ?? ""
        routingProvider = try c.decodeIfPresent(RoutingProvider.self, forKey: .routingProvider) ?? .appleMaps
        portalLinks = try c.decodeIfPresent([PortalLink].self, forKey: .portalLinks) ?? []
        broadcastLog = try c.decodeIfPresent([BroadcastRecord].self, forKey: .broadcastLog) ?? []
        serviceRequests = try c.decodeIfPresent([ServiceRequest].self, forKey: .serviceRequests) ?? []
        broadcastSettings = try c.decodeIfPresent(BroadcastSettings.self, forKey: .broadcastSettings) ?? BroadcastSettings()
        profile = try c.decodeIfPresent(BusinessProfile.self, forKey: .profile) ?? BusinessProfile()
        account = try c.decodeIfPresent(AccountProfile.self, forKey: .account)
        reminderLog = try c.decodeIfPresent([ReminderRecord].self, forKey: .reminderLog) ?? []
        team = try c.decodeIfPresent([TeamMember].self, forKey: .team) ?? []
        jobs = try c.decodeIfPresent([Job].self, forKey: .jobs) ?? []
        session = try c.decodeIfPresent(AppSession.self, forKey: .session)
        logins = try c.decodeIfPresent([LoginCredential].self, forKey: .logins) ?? []
        tutorialsSeen = try c.decodeIfPresent([String].self, forKey: .tutorialsSeen) ?? []
        dismissedHints = try c.decodeIfPresent([String].self, forKey: .dismissedHints) ?? []
        assistantConsentAt = try c.decodeIfPresent(Date.self, forKey: .assistantConsentAt)
        seasonLinkLog = try c.decodeIfPresent([SeasonLinkRecord].self, forKey: .seasonLinkLog) ?? []
        stormRuns = try c.decodeIfPresent([StormRun].self, forKey: .stormRuns) ?? []
        servicePrices = try c.decodeIfPresent([ServicePrice].self, forKey: .servicePrices) ?? nil
        autoCheckInMarksDone = try c.decodeIfPresent(Bool.self, forKey: .autoCheckInMarksDone) ?? false
        routeSettings = try c.decodeIfPresent(RouteSettings.self, forKey: .routeSettings) ?? RouteSettings()
        adHocStops = try c.decodeIfPresent([AdHocStop].self, forKey: .adHocStops) ?? []
        routeOrders = try c.decodeIfPresent([SavedRouteOrder].self, forKey: .routeOrders) ?? []
        teamSync = try c.decodeIfPresent(TeamSyncState.self, forKey: .teamSync)
        portalLookupSalt = try c.decodeIfPresent(String.self, forKey: .portalLookupSalt) ?? ""
    }
}

/// Offline-first local store: one JSON file, written atomically so a crash or low battery never leaves half a file.
public struct FileStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: SchemaMigrations.migrate(data))
    }

    public func save(_ appData: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(appData)
        try data.write(to: url, options: .atomic)
    }

    public struct Recovery: Sendable {
        public let data: AppData
        /// Shown to the user when the saved file could not be read.
        public let notice: String?
        /// False when the unreadable file could not be set aside: saving then would overwrite it.
        public let safeToSave: Bool
        /// The file name of the saved copy that was opened instead, if any.
        public var restoredCopy: String? = nil
    }

    /// Moves an unreadable data file out of the way (kept for recovery) and returns where it went.
    public func moveAsideUnreadable(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(Int(now.timeIntervalSince1970)).json"
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    /// Loads the data and keeps rolling copies of it (see SavedCopies.swift). If the file cannot be read it is set aside, never
    /// overwritten, and the app opens the newest readable copy (data.json.bak, then daily copies), or starts empty, with a notice.
    public func loadOrRecover(now: Date = Date()) -> Recovery {
        let mainExists = FileManager.default.fileExists(atPath: url.path)
        do {
            let loaded = try load()
            if mainExists {
                keepCopies(of: loaded, now: now)
            } else if let found = firstReadableCopy() {
                try? save(found.data)
                return Recovery(data: found.data, notice: "Your data file was missing, so the app opened \(found.copy.describe()).", safeToSave: true, restoredCopy: found.copy.id)
            }
            return Recovery(data: loaded, notice: nil, safeToSave: true)
        } catch {
            let found = firstReadableCopy()
            if let kept = try? moveAsideUnreadable(now: now) {
                if let found {
                    try? save(found.data)
                    return Recovery(data: found.data, notice: "Your saved data could not be read, so the app opened \(found.copy.describe()). The unreadable file was kept as \(kept.lastPathComponent).", safeToSave: true, restoredCopy: found.copy.id)
                }
                return Recovery(data: AppData(), notice: "Your saved data could not be read, so the app started empty. The unreadable file was kept as \(kept.lastPathComponent) so it can be recovered.", safeToSave: true)
            }
            if let found {
                return Recovery(data: found.data, notice: "Your saved data could not be read or set aside, so the app is showing \(found.copy.describe()). Changes are not being saved. Close the app and open it again. If this message comes back, share a backup from Settings, delete the account and data in Profile, then restore the backup.", safeToSave: false, restoredCopy: found.copy.id)
            }
            return Recovery(data: AppData(), notice: "Your saved data could not be read and could not be set aside. Changes are not being saved. Close the app and open it again. If this message comes back, delete the account and data in Profile to start again.", safeToSave: false)
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
