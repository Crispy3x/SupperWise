import Foundation

/// Everything the app stores. Kept as plain values so it is easy to sync later.
public struct AppData: Equatable, Codable, Sendable {
    public var schemaVersion: Int = 1
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
    public var lateFeePolicy = LateFeePolicy()

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
        lateFeePolicy = try c.decodeIfPresent(LateFeePolicy.self, forKey: .lateFeePolicy) ?? LateFeePolicy()
    }
}

/// Offline-first local store: one JSON file, written atomically so a crash or low battery never leaves half a file.
public struct FileStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: data)
    }

    public func save(_ appData: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(appData)
        try data.write(to: url, options: .atomic)
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
