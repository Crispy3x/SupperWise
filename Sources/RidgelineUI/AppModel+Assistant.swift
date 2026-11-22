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

    /// Finds map locations for client addresses that have none yet, using Apple's geocoder. Returns how many it found.
    @discardableResult
    func fillMissingLocations() async -> Int {
        #if canImport(CoreLocation)
        var found = 0
        for site in data.sites where site.latitude == nil || site.longitude == nil {
            guard let c = await AddressGeocoder.coordinate(for: site.address),
                  let i = data.sites.firstIndex(where: { $0.id == site.id }) else { continue }
            data.sites[i].latitude = c.latitude
            data.sites[i].longitude = c.longitude
            found += 1
        }
        if found > 0 { save() }
        return found
        #else
        return 0
        #endif
    }

    /// The first day from `day` (looking a week ahead) that has a job the route can use.
    func nextRouteDay(from day: Date) -> Date {
        let cal = Calendar.current
        for offset in 0..<8 {
            if let d = cal.date(byAdding: .day, value: offset, to: day), !data.routeStops(on: d).isEmpty { return d }
        }
        return day
    }

    func planRoute(on day: Date) async -> (plan: RoutePlanResult?, note: String) {
        await fillMissingLocations()
        let stops = data.routeStops(on: day)
        guard !stops.isEmpty else {
            let open = data.jobs(on: day).filter { !$0.isTask && $0.status.isOpen }
            if open.isEmpty { return (nil, "No jobs scheduled that day. Add a job for a client and it will appear here.") }
            return (nil, "These jobs need a client site with an address Apple Maps can find. Open the client and check the address.")
        }
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

    func serverAssistantTransport() -> ServerAssistantTransport? {
        #if canImport(Security)
        guard let url = RoutingServerSettings.validatedURL(data.routingServerURL),
              let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty else { return nil }
        return ServerAssistantTransport(baseURL: url, token: token)
        #else
        return nil
        #endif
    }

    /// The owner's own Anthropic key wins when set (they chose it on purpose); otherwise the server.
    func assistantTransport() -> AssistantTransport? {
        #if canImport(Security)
        if let key = KeychainStore.load(Self.assistantKeyKey), !key.isEmpty { return DirectAssistantTransport(apiKey: key) }
        #endif
        return serverAssistantTransport()
    }

    /// Whether the assistant can answer on this device: the owner's own key or a server.
    var assistantReady: Bool { ownAssistantKeySet || serverConfigured }

    /// Saves or clears the owner's own Anthropic key in the Keychain. Returns a note for the screen.
    @discardableResult
    func saveAssistantKey(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(Security)
        if key.isEmpty {
            _ = KeychainStore.save("", for: Self.assistantKeyKey)
            refreshServerFlag()
            return serverConfigured ? "Removed. The assistant uses your server now." : "Removed."
        }
        guard DirectAssistantTransport.looksLikeKey(key) else { return "That doesn't look like an Anthropic key. It starts with sk-ant-." }
        guard KeychainStore.save(key, for: Self.assistantKeyKey) else { return "Could not save the key on this device." }
        refreshServerFlag()
        return "Saved. The assistant is on."
        #else
        return "Keys can't be saved on this device."
        #endif
    }

    /// Sends a tiny test question to check the key works.
    func testAssistantKey() async -> String {
        guard let t = assistantTransport() else { return "No key or server set." }
        do {
            let reply = try await t.send(messages: [.user("Reply with the single word: ready")], tools: [], context: "")
            return reply.text.isEmpty ? "Connected." : "Connected. Claude says: \(reply.text.prefix(60))"
        } catch AssistantError.server(let m) { return m }
        catch AssistantError.busy(let m) { return m }
        catch AssistantError.limit(let m) { return m }
        catch { return "Could not reach Claude. Check your connection." }
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
        guard !ownAssistantKeySet, let t = serverAssistantTransport(), let s = try? await t.status() else { return }
        assistantUsedPercent = s.usedPercent
    }

    public func askAssistant(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !assistantBusy, data.assistantConsented else { return }
        guard let transport = assistantTransport() else {
            assistantLines.append(AssistantLine(kind: .problem, text: "Add your Anthropic key in Settings, Assistant, to use the assistant."))
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
        case "send_reminders": return assistantPrepareReminders()
        case "send_season_links": return assistantPrepareSeasonLinks()
        case "answer_request": return await assistantAnswerRequest(call.input)
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

    private func assistantPrepareReminders() -> ToolOutcome {
        let plan = reminderPlan()
        let due = plan.messages.filter { $0.sendAfter <= Date() }
        if due.isEmpty { return .text(plan.messages.isEmpty ? "No reminders are due." : "Reminders are waiting for quiet hours to end.") }
        let action = PendingAction(kind: .sendReminders(count: due.count), title: "Send \(due.count) friendly reminder\(due.count == 1 ? "" : "s")?",
                                   detail: "Only clients who agreed to emails get one, at most three per invoice, a week apart.")
        return .needsConfirmation(action, "Prepared \(due.count) reminder\(due.count == 1 ? "" : "s"). They have NOT been sent. The owner must tap Send in the app to confirm.")
    }

    private func assistantPrepareSeasonLinks() -> ToolOutcome {
        let plan = SeasonWelcome.plan(data: data, now: Date())
        if !plan.problem.isEmpty { return .error(plan.problem) }
        if plan.messages.isEmpty { return .text("No one is waiting for a link. Everyone who agreed to emails already has theirs for \(plan.season), or has not agreed yet.") }
        let action = PendingAction(kind: .sendSeasonLinks(count: plan.messages.count), title: "Email \(plan.messages.count) client\(plan.messages.count == 1 ? "" : "s") their \(plan.season) page link?",
                                   detail: "Each client gets their private page for the whole season: map, arrival time, requests, bills and a way to say thanks.")
        return .needsConfirmation(action, "Prepared \(plan.messages.count) season link email\(plan.messages.count == 1 ? "" : "s"). They have NOT been sent. The owner must tap Send in the app to confirm.")
    }

    private func assistantAnswerRequest(_ input: JSONValue) async -> ToolOutcome {
        guard let idText = input["request_id"]?.string, let id = UUID(uuidString: idText), let decision = input["decision"]?.string,
              ["accept", "decline", "read"].contains(decision) else { return .error("Give the request id from list_requests and a decision of accept, decline or read.") }
        guard data.serviceRequests.contains(where: { $0.id == id && $0.status == .pending }) else { return .error("That request is not waiting any more.") }
        let note = String((input["message"]?.string ?? "").prefix(200))
        return .text(await decideRequest(id, accept: decision != "decline", message: note))
    }

    // MARK: sending the invoice PDF, reminders and season links

    /// Emails the invoice as a PDF, with the owner's pay links, to the client. Only the real result is reported.
    public func emailInvoice(number: String) async -> String {
        guard let client = portalClient() else { return "Set up your server in Settings first." }
        switch data.invoiceEmail(number: number) {
        case .problem(let why): return why
        case .ready(let message):
            await sendInvoiceEmail(message, number: number, client: client)
            return data.invoices.first { $0.number == number }?.sentAt != nil ? "Invoice \(number) was emailed with its PDF." : "Invoice \(number) could not be emailed. It stays a draft."
        }
    }

    /// Puts every client's page online for the winter, so the link works before the first storm.
    func publishSeasonPages() async -> String? {
        guard let client = portalClient() else { return "Set up your server in Settings first." }
        let season = SeasonWelcome.season(for: Date())
        let name = "Winter \(season)"
        edit { $0.ensurePortalLinks(now: Date()); if !$0.storms.contains(where: { $0.name == name }) { $0.storms.append(StormEvent(name: name, start: Date(), forecastInches: 0)) } }
        guard let storm = data.storms.first(where: { $0.name == name }) else { return "Could not set up the winter pages." }
        do { try await client.publish(portalSnapshot(storm: storm, inches: 0, routeStart: nil, offsets: [:])); return nil }
        catch { return "Could not put the client pages online. Check your server." }
    }

    public func seasonLinkPlan() -> SeasonWelcomePlan { SeasonWelcome.plan(data: data, now: Date()) }

    public func sendSeasonLinks() async -> String {
        guard let client = portalClient() else { return "Set up your server in Settings first." }
        let plan = seasonLinkPlan()
        if !plan.problem.isEmpty { return plan.problem }
        guard !plan.messages.isEmpty else { return "No one is waiting for a link." }
        if let problem = await publishSeasonPages() { return problem }
        do {
            let ok = try await client.sendEmails(plan.messages)
            let sent = zip(plan.messages, ok).filter { $0.1 }.map { $0.0 }
            edit { $0.recordSeasonLinks(sent, season: plan.season, at: Date()) }
            var text = "Sent \(sent.count) page link\(sent.count == 1 ? "" : "s") for \(plan.season)."
            if sent.count < plan.messages.count { text += " \(plan.messages.count - sent.count) failed and can be tried again." }
            return text
        } catch {
            return "Could not send the links. Nothing was recorded as sent."
        }
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
                assistantLines.append(AssistantLine(kind: .note, text: sent ? "Invoice \(number) was emailed with its PDF and pay links." : "Invoice \(number) could not be emailed. It stays a draft."))
                assistantUpdates.append(sent ? "[Update: the owner tapped Send and invoice \(number) was emailed.]" : "[Update: the owner tapped Send but invoice \(number) could not be emailed.]")
            }
        case .sendReminders:
            let result = await sendReminders()
            assistantLines.append(AssistantLine(kind: .note, text: result))
            assistantUpdates.append("[Update: the owner tapped Send on the reminders. Result: \(result)]")
        case .sendSeasonLinks:
            let result = await sendSeasonLinks()
            assistantLines.append(AssistantLine(kind: .note, text: result))
            assistantUpdates.append("[Update: the owner tapped Send on the season links. Result: \(result)]")
        }
    }

    public func cancelPending(_ action: PendingAction) {
        removePending(action)
        switch action.kind {
        case .sendInvoice(let number):
            assistantLines.append(AssistantLine(kind: .note, text: "Cancelled. Invoice \(number) was not sent."))
            assistantUpdates.append("[Update: the owner cancelled sending invoice \(number). It was not sent.]")
        case .sendReminders, .sendSeasonLinks:
            assistantLines.append(AssistantLine(kind: .note, text: "Cancelled. Nothing was sent."))
            assistantUpdates.append("[Update: the owner cancelled. Nothing was sent.]")
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
