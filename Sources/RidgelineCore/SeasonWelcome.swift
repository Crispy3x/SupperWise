import Foundation

public struct SeasonLinkRecord: Codable, Equatable, Sendable {
    public let siteID: UUID
    public let season: String
    public let sentAt: Date
}

public struct SeasonWelcomePlan: Equatable, Sendable {
    public let season: String
    public let messages: [PlannedMessage]
    public let skipped: [SkippedClient]
    /// Why nothing can be sent at all, such as no page address set up. Empty when messages are ready.
    public let problem: String
}

/// At the start of winter each client gets one email with their private page link, which works all season:
/// live truck map and arrival time, a way to ask for service, their bills, and a way to say thanks.
public enum SeasonWelcome {
    /// "2026-27" for any day from July 2026 to June 2027.
    public static func season(for date: Date, calendar: Calendar = .current) -> String {
        let y = calendar.component(.year, from: date), m = calendar.component(.month, from: date)
        let start = m >= 7 ? y : y - 1
        return "\(start)-\(String(format: "%02d", (start + 1) % 100))"
    }

    public static func plan(data: AppData, now: Date, calendar: Calendar = .current) -> SeasonWelcomePlan {
        let season = season(for: now, calendar: calendar)
        let base = data.broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoutingServerSettings.validatedURL(base) != nil else {
            return SeasonWelcomePlan(season: season, messages: [], skipped: [], problem: "Add your client page address in Settings first. It is the address of your server.")
        }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your snow crew" : data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        var messages: [PlannedMessage] = [], skipped: [SkippedClient] = []
        for site in data.sites.sorted(by: { ($0.address, $0.id.uuidString) < ($1.address, $1.id.uuidString) }) {
            guard let customer = data.customers.first(where: { $0.id == site.customerID }), !customer.isLead else { continue }
            func skip(_ r: SkipReason) { skipped.append(SkippedClient(siteID: site.id, customerName: customer.name, channel: .email, reason: r)) }
            guard customer.optedOutAt == nil else { skip(.optedOut); continue }
            guard customer.emailConsent else { skip(.noConsent); continue }
            guard ContactValidation.isValidEmail(customer.email) else { skip(.noValidContact); continue }
            guard let link = data.portalLinks.first(where: { $0.siteID == site.id }) else { skip(.noPortalLink); continue }
            guard !data.seasonLinkLog.contains(where: { $0.siteID == site.id && $0.season == season }) else { skip(.alreadySent); continue }
            let url = "\(root)/c/\(link.token)"
            let body = [
                "Hello \(customer.name),", "",
                "\(company) will be clearing snow at \(site.address) this winter. This is your private page for the whole season. Bookmark it, or add it to your phone's home screen:", "",
                url, "",
                "On your page you can:",
                "- see when we are on the way, with a live map and an estimated arrival time",
                "- ask us to come, skip a storm, or tell us you need to get out soon",
                "- see your bills and pay them online",
                "- say thanks to your driver with a message, a coffee or a donut", "",
                "The link is only for your property, so please do not share it.", "",
                company,
                "You are getting this because you agreed to messages from \(company). To stop them, tell \(company) and they will turn them off.",
            ].joined(separator: "\n")
            messages.append(PlannedMessage(siteID: site.id, customerID: customer.id, channel: .email, to: customer.email,
                                           subject: StormBroadcast.clean("Your \(company) snow page for this winter"), body: body, sendAfter: now))
        }
        return SeasonWelcomePlan(season: season, messages: messages, skipped: skipped, problem: "")
    }
}

extension AppData {
    /// Records only the links that really went out.
    public mutating func recordSeasonLinks(_ sent: [PlannedMessage], season: String, at date: Date) {
        for m in sent where !seasonLinkLog.contains(where: { $0.siteID == m.siteID && $0.season == season }) {
            seasonLinkLog.append(SeasonLinkRecord(siteID: m.siteID, season: season, sentAt: date))
        }
    }
}
