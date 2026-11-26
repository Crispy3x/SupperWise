import Foundation

public struct SetupItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let done: Bool
    /// Optional items never block anything and are shown last.
    public let optional: Bool
}

/// "Finish setup": the heavy steps that do not belong in the welcome questions. Shown on the Today screen until done.
public enum SetupChecklist {
    public static func items(for d: AppData, serverConfigured: Bool) -> [SetupItem] {
        let portalOK = RoutingServerSettings.validatedURL(d.broadcastSettings.portalBaseURL) != nil
        return [
            SetupItem(id: "client", title: "Add your first client", detail: "From the Clients tab, by hand or from a spreadsheet.", done: !d.customers.isEmpty, optional: false),
            SetupItem(id: "yard", title: "Set your yard location", detail: "Routes start here and the forecast is for this spot.", done: d.depot != nil, optional: false),
            SetupItem(id: "pay", title: "Say how clients should pay you", detail: "It goes on every invoice.", done: !d.profile.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || d.profile.payLink != nil, optional: false),
            SetupItem(id: "consent", title: "Record who agreed to messages", detail: "Open a client and turn on emails only if they said yes.", done: d.customers.contains { $0.emailConsent && $0.optedOutAt == nil }, optional: false),
            SetupItem(id: "server", title: "Turn on client pages and email", detail: "Lets clients see your truck, ask for service and get invoices by email. Needs your own server, set up once by someone technical. Its address goes in Settings, under Advanced.", done: serverConfigured, optional: true),
            SetupItem(id: "page", title: "Set your client page address", detail: "The web address clients open. Settings, Invoices and client messages.", done: portalOK, optional: true),
            SetupItem(id: "signin", title: "Sign in with Apple", detail: "Optional. Your records stay on this device either way.", done: d.account != nil, optional: true),
        ]
    }

    public static func progress(_ items: [SetupItem]) -> (done: Int, total: Int) {
        let required = items.filter { !$0.optional }
        return (required.filter(\.done).count, required.count)
    }
}
