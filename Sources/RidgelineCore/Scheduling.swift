import Foundation

public struct Crew: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// A repeating route: an ordered list of sites for one crew, optionally on one weekday (1 = Sunday ... 7 = Saturday).
public struct Route: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var crewID: UUID?
    public var weekday: Int?
    public var stopSiteIDs: [UUID]

    public init(id: UUID = UUID(), name: String, crewID: UUID? = nil, weekday: Int? = nil, stopSiteIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.crewID = crewID
        self.weekday = weekday
        self.stopSiteIDs = stopSiteIDs
    }
}

/// Bulk operations that owners say competitors force them to do one customer at a time.
public enum RouteBook {
    /// Move many routes to another crew in one action.
    public static func move(_ routes: [Route], ids: Set<UUID>, toCrew crewID: UUID) -> [Route] {
        routes.map { r in
            guard ids.contains(r.id) else { return r }
            var copy = r
            copy.crewID = crewID
            return copy
        }
    }

    /// Move many routes to another weekday (1...7) in one action.
    public static func move(_ routes: [Route], ids: Set<UUID>, toWeekday weekday: Int) -> [Route] {
        precondition((1...7).contains(weekday), "weekday must be 1...7")
        return routes.map { r in
            guard ids.contains(r.id) else { return r }
            var copy = r
            copy.weekday = weekday
            return copy
        }
    }

    /// Swap everything between two crews (for example when one is out sick).
    public static func swapCrews(_ routes: [Route], _ a: UUID, _ b: UUID) -> [Route] {
        routes.map { r in
            var copy = r
            if r.crewID == a { copy.crewID = b } else if r.crewID == b { copy.crewID = a }
            return copy
        }
    }

    /// Move sites to another route. Each site is removed from any route that has it and appended once to the target.
    public static func moveSites(_ routes: [Route], siteIDs: [UUID], toRoute routeID: UUID) -> [Route] {
        let moving = Set(siteIDs)
        return routes.map { r in
            var copy = r
            copy.stopSiteIDs.removeAll { moving.contains($0) }
            if r.id == routeID {
                var seen = Set(copy.stopSiteIDs)
                for id in siteIDs where !seen.contains(id) {
                    copy.stopSiteIDs.append(id)
                    seen.insert(id)
                }
            }
            return copy
        }
    }
}
