import Foundation

/// The owner pastes a payment link from their own account (Stripe, Square, PayPal and so on).
/// The app never handles the money. It only checks the link is safe to put in front of a client.
public enum PayLink {
    /// Payment sites we accept. A host matches when it equals one of these or is a subdomain of it.
    public static let allowedHosts = [
        "stripe.com", "square.link", "square.site", "squareup.com", "paypal.com", "paypal.me",
        "venmo.com", "cash.app", "intuit.com", "quickbooks.com", "waveapps.com", "zellepay.com"
    ]

    /// Returns the cleaned link, or nil when it is empty or not acceptable.
    /// Rules: https only, no sign-in details or odd port in the address, and a host on the allowed list.
    public static func clean(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              let comps = URLComponents(string: text), comps.scheme?.lowercased() == "https",
              comps.user == nil, comps.password == nil, comps.port == nil,
              let host = comps.host?.lowercased(), !host.isEmpty, comps.fragment == nil else { return nil }
        guard allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return comps.string
    }

    /// What to tell the owner when a pasted link is turned down.
    public static func problem(for raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || clean(text) != nil { return nil }
        if text.count > 500 { return "That link is too long. Copy the short payment link instead." }
        if text.contains(where: { $0.isWhitespace || $0.isNewline }) { return "Take the spaces out of the link." }
        if !text.lowercased().hasPrefix("https://") { return "The link must start with https://" }
        // A payment site we accept, turned down for something else in the link.
        if let host = URLComponents(string: text)?.host?.lowercased(), allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return "Copy the plain link from the payment site, without sign-in details, a port or a # part."
        }
        return "That site is not on the list of payment sites we accept (Stripe, Square, PayPal, Venmo, Cash App, QuickBooks, Wave)."
    }
}
