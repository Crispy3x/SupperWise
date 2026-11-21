import Foundation

/// The owner pastes the link where clients leave a review (their Google review link, Yelp, Facebook or Nextdoor page).
/// Same style of check as `PayLink`: https only, no sign-in details or odd port, and a host on the list.
public enum ReviewLink {
    /// Review sites we accept. A host matches when it equals one of these or is a subdomain of it.
    public static let allowedHosts = [
        "g.page", "google.com", "maps.app.goo.gl", "search.google.com", "yelp.com", "facebook.com", "nextdoor.com"
    ]

    private enum Outcome { case empty, ok(String), bad(String) }

    private static func evaluate(_ raw: String) -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if text.count > 500 { return .bad("That link is too long. Copy the short review link instead.") }
        if text.contains(where: { $0.isWhitespace || $0.isNewline }) { return .bad("Take the spaces out of the link.") }
        guard text.lowercased().hasPrefix("https://"), let comps = URLComponents(string: text), comps.scheme?.lowercased() == "https" else {
            return .bad("The link must start with https://")
        }
        guard comps.user == nil, comps.password == nil, comps.port == nil else {
            return .bad("That link has sign-in details or a port in it. Copy the plain link from the review site.")
        }
        guard comps.fragment == nil else { return .bad("Take the part after # off the end of the link.") }
        guard let host = comps.host?.lowercased(), !host.isEmpty else { return .bad("That does not look like a full link.") }
        guard allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            return .bad("Use a review link from Google, Yelp, Facebook or Nextdoor. That site is not on the list.")
        }
        guard let clean = comps.string else { return .bad("That does not look like a full link.") }
        return .ok(clean)
    }

    /// Returns the cleaned link, or nil when it is empty or not acceptable.
    public static func clean(_ raw: String) -> String? {
        if case .ok(let link) = evaluate(raw) { return link }
        return nil
    }

    /// What to tell the owner when a pasted link is turned down. Nil for an empty or good link.
    public static func problem(for raw: String) -> String? {
        if case .bad(let why) = evaluate(raw) { return why }
        return nil
    }
}

/// Why the app will not ask this client for a review right now.
public enum ReviewAskBlocker: Error, Equatable, Sendable {
    case noLink
    case optedOut
    case notAClient
    case askedRecently(askedAt: Date, nextAllowed: Date)

    public var message: String {
        switch self {
        case .noLink: return "Add your review link in Settings first."
        case .optedOut: return "This client asked to stop messages, so we will not ask them for a review."
        case .notAClient: return "They are not a client yet. Ask once you have done work for them."
        case .askedRecently(let asked, let next):
            return "You asked on \(ReviewRequests.dayText(asked)). You can ask again after \(ReviewRequests.dayText(next))."
        }
    }
}

/// A ready-to-send review request. The owner sends it from their own phone or email; nothing goes through a server.
public struct ReviewRequestDraft: Equatable, Sendable {
    public let customerID: UUID
    public let text: String
    public let subject: String
    /// Opens Messages with the text filled in. Nil when the client has no usable phone number.
    public let smsURL: URL?
    /// Opens Mail with the text filled in. Nil when the client has no usable email.
    public let mailURL: URL?
}

public enum ReviewRequests {
    /// A client is asked at most once in this many days.
    public static let cooldownDays = 90
    /// A paid invoice or a thank-you message this recent makes the app suggest asking.
    public static let suggestionWindowDays = 14

    /// Words that mean the client is a business, so the greeting does not use the first word of its name.
    static let businessWords: Set<String> = [
        "llc", "inc", "inc.", "ltd", "ltd.", "corp", "corp.", "co.", "company", "hoa", "association", "assn",
        "church", "school", "plaza", "condos", "condo", "management", "properties", "property", "apartments",
        "group", "partners", "realty", "center", "centre", "clinic", "hospital", "the"
    ]

    /// "Sam Lee" gives "Sam". A business name or an empty name gives "there", as in "Hi there".
    public static func firstName(_ fullName: String) -> String {
        let words = fullName.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first else { return "there" }
        if words.contains(where: { businessWords.contains($0.lowercased()) }) { return "there" }
        let cleaned = first.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
        return cleaned.isEmpty ? "there" : cleaned
    }

    private static func oneLine(_ s: String) -> String {
        s.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The message: short, friendly, with the client's first name, the company and the review link.
    public static func message(clientName: String, company: String, link: String) -> String {
        let name = firstName(oneLine(clientName))
        let biz = oneLine(company)
        let thanks = biz.isEmpty ? "thanks for choosing us." : "thanks for choosing \(biz)."
        return "Hi \(name), \(thanks) If you were happy with our work, would you leave us a quick review? It really helps a small local business.\n\n\(link)\n\nThank you!"
    }

    public static func subject(company: String) -> String {
        let biz = oneLine(company)
        return biz.isEmpty ? "A quick favor" : "A quick favor from \(biz)"
    }

    /// Why this client cannot be asked now, or nil when they can.
    public static func blocker(for customer: Customer, link: String?, now: Date) -> ReviewAskBlocker? {
        if customer.optedOutAt != nil { return .optedOut }
        if customer.isLead { return .notAClient }
        if let asked = customer.reviewAskedAt {
            let next = asked.addingTimeInterval(Double(cooldownDays) * 86_400)
            if now < next { return .askedRecently(askedAt: asked, nextAllowed: next) }
        }
        guard let link, ReviewLink.clean(link) != nil else { return .noLink }
        return nil
    }

    /// Only plain letters, digits and - . _ ~ stay as they are; everything else is percent-encoded.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String, keeping extra: String = "") -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: extra))) ?? ""
    }

    /// An sms: link that opens Messages with the text filled in. Nil when the phone number is not usable.
    public static func smsURL(phone: String, body: String) -> URL? {
        guard ContactValidation.isValidPhone(phone) else { return nil }
        let digits = phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)&body=\(encode(body))")
    }

    /// A mailto: link that opens Mail with the subject and text filled in. Nil when the email is not usable.
    public static func mailURL(email: String, subject: String, body: String) -> URL? {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContactValidation.isValidEmail(address) else { return nil }
        return URL(string: "mailto:\(encode(address, keeping: "@+"))?subject=\(encode(subject))&body=\(encode(body))")
    }

    static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

extension BusinessProfile {
    public var reviewSuggestionsOn: Bool { reviewSuggestionsEnabled ?? true }
}

extension AppData {
    /// The review request for one client, or why they cannot be asked now.
    public func reviewDraft(customerID: UUID, now: Date) -> Result<ReviewRequestDraft, ReviewAskBlocker>? {
        guard let c = customers.first(where: { $0.id == customerID }) else { return nil }
        if let b = ReviewRequests.blocker(for: c, link: profile.reviewLink, now: now) { return .failure(b) }
        guard let link = profile.reviewLink.flatMap(ReviewLink.clean) else { return .failure(.noLink) }
        let text = ReviewRequests.message(clientName: c.name, company: companyName, link: link)
        let subject = ReviewRequests.subject(company: companyName)
        return .success(ReviewRequestDraft(customerID: c.id, text: text, subject: subject,
                                           smsURL: ReviewRequests.smsURL(phone: c.phone, body: text),
                                           mailURL: ReviewRequests.mailURL(email: c.email, subject: subject, body: text)))
    }

    /// Records that the client was asked, so they are not asked again for 90 days. Refuses a client who cannot be asked.
    public mutating func recordReviewAsked(customerID: UUID, now: Date) throws {
        guard let i = customers.firstIndex(where: { $0.id == customerID }) else { throw OperationError.notFound }
        if let b = ReviewRequests.blocker(for: customers[i], link: profile.reviewLink, now: now) { throw b }
        customers[i].reviewAskedAt = now
    }

    /// When the client last showed they were happy: an invoice paid in full, or a thank-you message from their page.
    public func lastHappyMoment(customerID: UUID, now: Date) -> Date? {
        let paid = invoices
            .filter { $0.customerID == customerID && $0.status(now: now) == .paid }
            .compactMap { $0.payments.map(\.date).max() }
        let siteIDs = Set(sites.filter { $0.customerID == customerID }.map(\.id))
        let thanks = serviceRequests.filter { $0.kind == .thanks && siteIDs.contains($0.siteID) }.map(\.createdAt)
        return (paid + thanks).filter { $0 <= now }.max()
    }

    /// True when Settings allows suggestions, the client can be asked, and they paid in full or sent thanks in the last 14 days.
    public func shouldSuggestReview(customerID: UUID, now: Date) -> Bool {
        guard profile.reviewSuggestionsOn, case .success? = reviewDraft(customerID: customerID, now: now),
              let happy = lastHappyMoment(customerID: customerID, now: now) else { return false }
        return now.timeIntervalSince(happy) <= Double(ReviewRequests.suggestionWindowDays) * 86_400
    }

    /// The client behind a thank-you message, if the site still exists.
    public func customerID(forRequest request: ServiceRequest) -> UUID? {
        sites.first { $0.id == request.siteID }?.customerID
    }
}
