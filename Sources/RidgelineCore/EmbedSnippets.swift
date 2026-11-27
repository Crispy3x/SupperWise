import Foundation

/// The text an owner pastes into their own website (Wix, Squarespace, WordPress, GoDaddy, Shopify) to show the
/// "Track your service" box or the tips box, served by their server's /embed.js (see server/embed.mjs).
public enum EmbedSnippets {
    public enum Mode: String, CaseIterable, Sendable {
        case tracker, tips
    }

    /// The server root the snippets point at: the client page address, https only, without a trailing slash.
    /// Nil when it is empty, not https, or carries a query, fragment or login.
    public static func serverRoot(_ portalBaseURL: String) -> String? {
        guard let parts = httpsComponents(portalBaseURL), parts.query == nil else { return nil }
        let text = parts.string ?? ""
        let root = text.hasSuffix("/") ? String(text.dropLast()) : text
        return root.isEmpty ? nil : root
    }

    /// `<div data-ridgeline></div>` plus the script tag. The tips box adds `data-mode="tips"`.
    public static func script(portalBaseURL: String, mode: Mode = .tracker) -> String? {
        guard let root = serverRoot(portalBaseURL) else { return nil }
        let div = mode == .tips ? "<div data-ridgeline data-mode=\"tips\"></div>" : "<div data-ridgeline></div>"
        return div + "\n<script src=\"\(root)/embed.js\" async></script>"
    }

    /// For site builders that remove scripts: a plain iframe with a fixed height.
    public static func iframe(portalBaseURL: String, mode: Mode = .tracker) -> String? {
        guard let root = serverRoot(portalBaseURL) else { return nil }
        let title = mode == .tips ? "Tip the crew" : "Track your service"
        let height = mode == .tips ? 320 : 640
        return "<iframe src=\"\(root)/embed/\(mode.rawValue)\" title=\"\(title)\" loading=\"lazy\" referrerpolicy=\"no-referrer\" style=\"width:100%;height:\(height)px;border:0\"></iframe>"
    }

    /// The owner's tracking page on their own website, cleaned: https, a real host, no login or fragment.
    /// A query is kept (WordPress pages can be `?page_id=12`). Nil when it is not usable.
    public static func cleanWebsitePage(_ text: String) -> String? {
        guard let parts = httpsComponents(text) else { return nil }
        return parts.string
    }

    /// Why a typed website page cannot be used, or nil when it is fine or empty.
    public static func websitePageProblem(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || cleanWebsitePage(t) != nil { return nil }
        if t.lowercased().hasPrefix("http://") { return "Use the https:// address of the page." }
        return "Type the full address of the page, starting with https://"
    }

    /// A client's personal link to the owner's tracking page: https://site/track?code=TOKEN.
    /// Nil when there is no usable page or the token is not a page token, so callers fall back to the server page.
    public static func clientLink(websitePage: String?, token: String) -> String? {
        guard let page = websitePage, let clean = cleanWebsitePage(page), isToken(token),
              var parts = URLComponents(string: clean) else { return nil }
        var items = (parts.queryItems ?? []).filter { $0.name != "code" }
        items.append(URLQueryItem(name: "code", value: token))
        parts.queryItems = items
        return parts.string
    }

    /// The same shape the server accepts for a client page token.
    static func isToken(_ token: String) -> Bool {
        (22...64).contains(token.count) && token.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    private static func httpsComponents(_ text: String) -> URLComponents? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing that could break out of the HTML attribute the address is pasted into.
        guard !t.isEmpty, t.count <= 500, !t.contains(where: { $0.isWhitespace || "\"'<>\\`".contains($0) }),
              let parts = URLComponents(string: t), parts.scheme?.lowercased() == "https",
              let host = parts.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        return parts
    }
}

extension AppData {
    /// The link a client is sent for their page: the owner's website tracking page with ?code= when one is saved,
    /// otherwise the server page /c/<token>. Nil when no client page address is set up.
    public func clientPageLink(token: String) -> String? {
        let base = broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoutingServerSettings.validatedURL(base) != nil else { return nil }
        if let site = EmbedSnippets.clientLink(websitePage: profile.websiteTrackingPage, token: token) { return site }
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/c/" + token
    }
}
