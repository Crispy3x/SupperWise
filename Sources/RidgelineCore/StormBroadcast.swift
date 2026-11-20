import Foundation

public enum BroadcastChannel: String, Codable, CaseIterable, Sendable {
    case email, sms
}

/// The private web page address for one site. The token is long and random, so the link cannot be guessed.
public struct PortalLink: Equatable, Codable, Sendable {
    public let siteID: UUID
    public let token: String
    public let createdAt: Date
}

public enum PortalToken {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    /// 24 random characters from 62, about 143 bits: far too many to guess.
    public static func generate(length: Int = 24) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<max(length, 22)).map { _ in alphabet.randomElement(using: &rng)! })
    }

    public static func isWellFormed(_ s: String) -> Bool {
        s.count >= 22 && s.count <= 64 && s.allSatisfy { alphabet.contains($0) }
    }
}

public enum SnowEstimateText {
    /// Plain words for a forecast, always a range, since forecasts are estimates.
    public static func describe(forecastInches x: Double) -> String {
        if x < 0.5 { return "little or no snow" }
        if x < 1 { return "an inch or less" }
        let low = max(1, Int((x * 0.75).rounded(.down)))
        let high = max(low + 1, Int((x * 1.25).rounded(.up)))
        return "around \(low) to \(high) inches"
    }
}

/// Hours when non-urgent messages wait. Wraps midnight (for example 9 pm to 6 am).
public struct QuietHours: Equatable, Codable, Sendable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int = 21, endHour: Int = 6) {
        self.startHour = min(max(startHour, 0), 23)
        self.endHour = min(max(endHour, 0), 23)
    }

    public func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let h = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        return startHour > endHour ? (h >= startHour || h < endHour) : (h >= startHour && h < endHour)
    }

    /// The moment a message may be sent: now if it is not quiet, otherwise when quiet hours end.
    public func nextAllowed(after date: Date, calendar: Calendar) -> Date {
        guard isQuiet(date, calendar: calendar) else { return date }
        return calendar.nextDate(after: date, matching: DateComponents(hour: endHour, minute: 0, second: 0), matchingPolicy: .nextTime) ?? date
    }
}

public struct BroadcastSettings: Equatable, Codable, Sendable {
    public var quietHours = QuietHours()
    /// Where clients open their page, for example https://portal.yourbusiness.com. Must be https.
    public var portalBaseURL = ""
    public init() {}
}

public struct BroadcastRecord: Equatable, Codable, Sendable {
    public let stormID: UUID
    public let siteID: UUID
    public let channel: BroadcastChannel
    public let sentAt: Date
}

/// A file sent with an email, for example the invoice as a PDF.
public struct EmailAttachment: Equatable, Sendable {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }
}

public struct PlannedMessage: Equatable, Sendable {
    public let siteID: UUID
    public let customerID: UUID
    public let channel: BroadcastChannel
    public let to: String
    public let subject: String
    public let body: String
    /// Not before this moment (it moves past quiet hours unless the message is marked urgent).
    public let sendAfter: Date
    public var attachment: EmailAttachment? = nil
}

public enum SkipReason: String, Equatable, Sendable {
    case optedOut, noConsent, noValidContact, alreadySent, noContract, noPortalLink
}

public struct SkippedClient: Equatable, Sendable {
    public let siteID: UUID
    public let customerName: String
    public let channel: BroadcastChannel
    public let reason: SkipReason
}

public struct BroadcastPlan: Equatable, Sendable {
    public let messages: [PlannedMessage]
    public let skipped: [SkippedClient]
}

extension ContractTerms {
    /// One sentence on what this storm means for the client's bill.
    public var stormCoverageLine: String {
        switch self {
        case .perPush(let rate, let c):
            return "Your price is \(rate.formatted) per push" + (c == .perStorm ? " (one push per storm)." : " (each visit counts as a push).")
        case .seasonal:
            return "This visit is included in your seasonal contract."
        case .perInch:
            return "You are charged by snow depth under your contract."
        case .hybrid(_, let included, _, _):
            return "This visit is covered by your seasonal contract, which includes \(included) pushes."
        case .timeAndMaterials:
            return "You are billed for time and materials under your contract."
        }
    }
}

/// Works out the storm-start message for every client: who gets one, what it says and when it may go out.
/// Nothing is sent from here. The caller shows the plan, then sends and records what actually went out.
public enum StormBroadcast {
    public static func plan(data: AppData, storm: StormEvent, forecastInches: Double, now: Date,
                            channels: Set<BroadcastChannel> = [.email], urgent: Bool = false,
                            calendar: Calendar = .current) -> BroadcastPlan {
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your snow crew" : data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = data.broadcastSettings
        let base = settings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/")
        let baseOK = RoutingServerSettings.validatedURL(base) != nil
        let sendAfter = urgent ? now : settings.quietHours.nextAllowed(after: now, calendar: calendar)
        let estimate = SnowEstimateText.describe(forecastInches: forecastInches)

        var messages: [PlannedMessage] = []
        var skipped: [SkippedClient] = []

        for site in data.sites.sorted(by: { ($0.address, $0.id.uuidString) < ($1.address, $1.id.uuidString) }) {
            guard let customer = data.customers.first(where: { $0.id == site.customerID }) else { continue }
            for channel in BroadcastChannel.allCases where channels.contains(channel) {
                func skip(_ r: SkipReason) { skipped.append(SkippedClient(siteID: site.id, customerName: customer.name, channel: channel, reason: r)) }
                if customer.optedOutAt != nil { skip(.optedOut); continue }
                let consent = channel == .email ? customer.emailConsent : customer.smsConsent
                if !consent { skip(.noConsent); continue }
                let address = channel == .email ? customer.email : customer.phone
                let valid = channel == .email ? ContactValidation.isValidEmail(address) : ContactValidation.isValidPhone(address)
                if !valid { skip(.noValidContact); continue }
                if data.broadcastLog.contains(where: { $0.stormID == storm.id && $0.siteID == site.id && $0.channel == channel }) { skip(.alreadySent); continue }
                guard let contract = data.contracts.last(where: { $0.siteID == site.id }) else { skip(.noContract); continue }
                guard baseOK, let link = data.portalLinks.first(where: { $0.siteID == site.id }) else { skip(.noPortalLink); continue }

                let url = "\(base)/c/\(link.token)"
                let willServe = forecastInches >= site.triggerInches
                let serveLine = willServe
                    ? "We expect to service your property."
                    : "The forecast is under your \(String(format: "%g", site.triggerInches)) inch trigger, so we may not come unless it snows more. You can ask for service on your page."
                let optOut = "You are getting this because you agreed to storm updates from \(company). To stop them, tell \(company) and they will turn them off."
                let body = [
                    "Hello \(customer.name),",
                    "",
                    "\(company) is watching the snow forecast. We expect \(estimate) at \(site.address). Forecasts can change.",
                    "",
                    serveLine,
                    contract.terms.stormCoverageLine,
                    "",
                    "Follow progress or ask for service here: \(url)",
                    "",
                    company,
                    optOut,
                ].joined(separator: "\n")
                let subject = clean(willServe ? "Snow expected: \(company) will service \(site.address)" : "Snow update from \(company)")
                messages.append(PlannedMessage(siteID: site.id, customerID: customer.id, channel: channel, to: address, subject: subject, body: body, sendAfter: sendAfter))
            }
        }
        return BroadcastPlan(messages: messages, skipped: skipped)
    }

    /// Keeps a value safe to use as a message subject: one line, no control characters.
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        var s = self
        while s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }
}
