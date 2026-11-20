#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// One line of the assistant chat.
public struct AssistantLine: Identifiable, Equatable {
    public enum Kind: Equatable { case user, assistant, note, problem }
    public let id = UUID()
    public let kind: Kind
    public var text: String
    /// Plain lines about changes the assistant made.
    public var actions: [String] = []
    /// Things it prepared that wait for the person to tap Send or Cancel.
    public var pending: [PendingAction] = []

    public init(kind: Kind, text: String, actions: [String] = [], pending: [PendingAction] = []) {
        self.kind = kind
        self.text = text
        self.actions = actions
        self.pending = pending
    }
}

/// What Apple Maps measured while planning, so the note under a route can say so.
private final class RouteReportBox: @unchecked Sendable { var report: SampledReport? }

extension AppModel {
    // MARK: route planning (the Smart route screen and the assistant use the same code)

    func planRoute(on day: Date) async -> (plan: RoutePlanResult?, note: String) {
        let stops = data.routeStops(on: day)
        guard !stops.isEmpty else { return (nil, "No jobs with a map location that day.") }
        let start = data.depot ?? stops.first?.coordinate ?? Coordinate(latitude: 0, longitude: 0)
        let box = RouteReportBox()
        let chosen = routePlanner(onReport: { box.report = $0 })
        if chosen.isLive {
            let result = await chosen.planner.plan(stops: stops, start: start, frozenPrefix: 0)
            if let r = box.report, r.measured == 0 { return (result, "\(chosen.label) gave no answers, so these drive times are an estimate.") }
            return (result, "Drive times from \(chosen.label). Ordered by drive time only.")
        }
        return (RouteOptimizer.optimize(stops: stops, start: start, frozenPrefix: 0, provider: HaversineDriveTime()),
                "Drive times are an offline estimate. Ordered by drive time only.")
    }

    // MARK: the assistant

    func assistantTransport() -> ServerAssistantTransport? {
        #if canImport(Security)
        guard let url = RoutingServerSettings.validatedURL(data.routingServerURL),
              let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty else { return nil }
        return ServerAssistantTransport(baseURL: url, token: token)
        #else
        return nil
        #endif
    }

    public func grantAssistantConsent() { edit { $0.grantAssistantConsent(now: Date()) } }

    public func turnOffAssistant() {
        assistantLines = []; assistantHistory = []; assistantUpdates = []
        edit { $0.revokeAssistantConsent() }
    }

    public func startNewAssistantChat() {
        guard !assistantBusy else { return }
        assistantLines = []; assistantHistory = []; assistantUpdates = []
    }

    public func refreshAssistantStatus() async {
        guard let t = assistantTransport(), let s = try? await t.status() else { return }
        assistantUsedPercent = s.usedPercent
    }

    public func askAssistant(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !assistantBusy, data.assistantConsented else { return }
        guard let transport = assistantTransport() else {
            assistantLines.append(AssistantLine(kind: .problem, text: "Set up your server in Settings to use the assistant."))
            return
        }
        assistantLines.append(AssistantLine(kind: .user, text: question))
        assistantBusy = true
        defer { assistantBusy = false }
        let updates = assistantUpdates
        assistantUpdates = []
        let prompt = updates.isEmpty ? question : updates.joined(separator: " ") + "\n\n" + question
        var history = assistantHistory            // a copy, so nothing else is locked while we wait for the answer
        do {
            let turn = try await AssistantRunner.ask(prompt, history: &history, tools: AssistantTools.definitions(for: data),
                                                     context: AssistantContext.make(data: data, now: Date()), transport: transport) { call in
                await self.runAssistantTool(call)
            }
            assistantHistory = history
            assistantLines.append(AssistantLine(kind: .assistant, text: turn.text, actions: turn.actions, pending: turn.pending))
        } catch let e as AssistantError {
            if e != .tooLong { assistantUpdates = updates }           // the question was not answered, so keep the updates for next time
            assistantLines.append(AssistantLine(kind: .problem, text: Self.describe(e)))
        } catch {
            assistantUpdates = updates
            assistantLines.append(AssistantLine(kind: .problem, text: "Could not reach your server. Check your connection and try again."))
        }
        await refreshAssistantStatus()
    }

    static func describe(_ e: AssistantError) -> String {
        switch e {
        case .notSignedIn, .notAllowed: return "Your server did not accept the access token. Check it in Settings."
        case .notSwitchedOn: return "The assistant is not switched on for your server yet."
        case .limit(let m), .busy(let m), .server(let m): return m
        case .unreadable: return "The assistant's answer could not be read. Try again."
        case .tooLong: return "This chat is getting long. Start a new chat to keep going."
        }
    }

    /// Runs one tool the assistant asked for. The same permission rules as the screens apply.
    func runAssistantTool(_ call: ToolCall) async -> ToolOutcome {
        var copy = data
        let outcome = AssistantTools.execute(call, data: &copy, now: Date())
        if copy != data { data = copy; save() }
        guard outcome == .hostTool else { return outcome }
        switch call.name {
        case "plan_route": return await assistantPlanRoute(call.input)
        case "get_weather": return await assistantWeather()
        case "create_invoice": return assistantCreateInvoice(call.input)
        default: return .error("That tool is not available.")
        }
    }

    private func assistantPlanRoute(_ input: JSONValue) async -> ToolOutcome {
        guard let day = AssistantTools.day(from: input["date"]?.string, now: Date(), calendar: .current) else { return .error("Use a date like 2026-11-20.") }
        let result = await planRoute(on: day)
        guard let plan = result.plan else { return .text(result.note) }
        if Calendar.current.isDateInToday(day) { plannedRoute = plan }
        let lines = plan.planned.enumerated().map { "\($0.offset + 1). \($0.element.stop.name) (about \(Int($0.element.arrivalOffsetSeconds / 60)) min from the start)" }
        return .text(lines.joined(separator: "\n") + "\nTotal driving: about \(Int(plan.totalDriveSeconds / 60)) min. \(result.note) The order is saved on the Home map.")
    }

    private func assistantWeather() async -> ToolOutcome {
        if forecast == nil { await refreshWeather(hours: 24) }
        guard let w = PortalWeather.make(from: forecast, alerts: winterAlerts) else { return .text(weatherStatus ?? "No forecast is loaded. Set the yard location in the Storm planner first.") }
        return .text(([w.summary] + w.alerts.map { "Alert: \($0)" }).joined(separator: "\n"))
    }

    private func assistantCreateInvoice(_ input: JSONValue) -> ToolOutcome {
        let (client, problem) = AssistantTools.client(named: input["client_name"]?.string ?? "", in: data)
        guard let client else { return .error(problem ?? "No such client.") }
        let contracts = data.sites.filter { $0.customerID == client.id }.compactMap { site in data.contracts.last { $0.siteID == site.id } }
        guard !contracts.isEmpty else { return .error("\(client.name) has no contract, so there is nothing to bill.") }
        return .text(contracts.map { createInvoice(for: $0) }.joined(separator: " "))
    }

    // MARK: the person's tap

    /// The person tapped Send on something the assistant prepared. Only now does anything leave the phone.
    public func confirmPending(_ action: PendingAction) async {
        defer { removePending(action) }
        switch action.kind {
        case .sendInvoice(let number):
            guard let client = portalClient() else {
                assistantLines.append(AssistantLine(kind: .problem, text: "Set up your server in Settings first."))
                return
            }
            switch data.invoiceEmail(number: number) {
            case .problem(let why):
                assistantLines.append(AssistantLine(kind: .problem, text: why))
            case .ready(let message):
                await sendInvoiceEmail(message, number: number, client: client)
                let sent = data.invoices.first { $0.number == number }?.sentAt != nil
                assistantLines.append(AssistantLine(kind: .note, text: sent ? "Invoice \(number) was emailed." : "Invoice \(number) could not be emailed. It stays a draft."))
                assistantUpdates.append(sent ? "[Update: the owner tapped Send and invoice \(number) was emailed.]" : "[Update: the owner tapped Send but invoice \(number) could not be emailed.]")
            }
        }
    }

    public func cancelPending(_ action: PendingAction) {
        removePending(action)
        if case .sendInvoice(let number) = action.kind {
            assistantLines.append(AssistantLine(kind: .note, text: "Cancelled. Invoice \(number) was not sent."))
            assistantUpdates.append("[Update: the owner cancelled sending invoice \(number). It was not sent.]")
        }
    }

    private func removePending(_ action: PendingAction) {
        for i in assistantLines.indices { assistantLines[i].pending.removeAll { $0.id == action.id } }
    }

    // MARK: sharing the truck's position

    public func startSharing() {
        #if canImport(CoreLocation)
        let label = sharingLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Truck" : String(sharingLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        truckSharer.start(label: label) { [weak self] truck in
            guard let self, let client = self.portalClient() else { return false }
            return (try? await client.publishTrucks([truck])) != nil
        }
        #endif
    }

    public func stopSharing() {
        #if canImport(CoreLocation)
        guard truckSharer.isSharing else { return }
        truckSharer.stop()
        let label = sharingLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Truck" : String(sharingLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        if let client = portalClient() { Task { try? await client.publishTrucks([], remove: [label]) } }
        #endif
    }
}
#endif
