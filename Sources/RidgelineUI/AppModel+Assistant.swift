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

    /// The assistant server built into the app at build time (Info.plist), so it works with no setup.
    static var builtInAssistant: (url: URL, token: String)? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let raw = info["RidgelineAIServerURL"] as? String, let token = info["RidgelineAIAppToken"] as? String,
              !token.trimmingCharacters(in: .whitespaces).isEmpty, !token.contains("$("),
              let url = RoutingServerSettings.validatedURL(raw) else { return nil }
        return (url, token.trimmingCharacters(in: .whitespaces))
    }

    /// A random id for this phone, kept in the Keychain. It is not tied to the person; it only splits the allowance.
    func assistantDeviceID() -> String {
        #if canImport(Security)
        if let id = KeychainStore.load(Self.assistantDeviceKey), id.count >= 16 { return id }
        let id = UUID().uuidString
        _ = KeychainStore.save(id, for: Self.assistantDeviceKey)
        return id
        #else
        return UUID().uuidString
        #endif
    }

    func builtInAssistantTransport() -> ServerAssistantTransport? {
        guard let b = Self.builtInAssistant else { return nil }
        return ServerAssistantTransport(baseURL: b.url, token: b.token, deviceID: assistantDeviceID())
    }

    /// True once the owner's own server has said its assistant is not switched on (a server set up only for client
    /// pages and email). The assistant built into the app is used instead, until that server says it is on.
    private static var ownServerHasNoAssistant = false
    /// Who the chat on screen belongs to, so it is never shown to the next person who signs in on this device.
    private static var assistantChatPerson: String?

    /// Order: the owner's own Anthropic key (chosen on purpose), then the owner's own server, then the one built into the app.
    func assistantTransport() -> AssistantTransport? {
        #if canImport(Security)
        if let key = KeychainStore.load(Self.assistantKeyKey), !key.isEmpty { return DirectAssistantTransport(apiKey: key) }
        #endif
        if Self.ownServerHasNoAssistant, let builtIn = builtInAssistantTransport() { return builtIn }
        return serverAssistantTransport() ?? builtInAssistantTransport()
    }

    /// Clears the chat when a different person is signed in than the one who had it. An employee must never open the
    /// assistant and read the owner's questions about invoices. Called when the assistant opens and before each question.
    public func keepAssistantChatPrivate() {
        let person = data.currentMember?.id.uuidString ?? (data.session == nil ? "nobody" : "owner")
        guard Self.assistantChatPerson != person else { return }
        if Self.assistantChatPerson != nil, !assistantBusy { assistantLines = []; assistantHistory = []; assistantUpdates = [] }
        Self.assistantChatPerson = person
    }

    /// Whether the assistant can answer on this device.
    var assistantReady: Bool { ownAssistantKeySet || serverConfigured || Self.builtInAssistant != nil }

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
        } catch let e as AssistantError { return Self.describe(e) }
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
        guard !ownAssistantKeySet else { return }
        if Self.ownServerHasNoAssistant, let own = serverAssistantTransport(), let s = try? await own.status(), s.enabled {
            Self.ownServerHasNoAssistant = false          // the owner has since added the key on their server
        }
        let chosen = (Self.ownServerHasNoAssistant ? nil : serverAssistantTransport()) ?? builtInAssistantTransport()
        guard let t = chosen, let s = try? await t.status() else { return }
        assistantUsedPercent = s.usedPercent
    }

    /// `again` is true only when the same question is asked a second time by the app itself (see the end of this function).
    public func askAssistant(_ text: String, again: Bool = false) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !assistantBusy, data.assistantConsented else { return }
        keepAssistantChatPrivate()
        guard let transport = assistantTransport() else {
            assistantLines.append(AssistantLine(kind: .problem, text: "Add your Anthropic key in Settings, Assistant, to use the assistant."))
            return
        }
        if !again { assistantLines.append(AssistantLine(kind: .user, text: question)) }
        assistantBusy = true
        defer { assistantBusy = false }
        let updates = assistantUpdates
        assistantUpdates = []
        // The time and the updates travel with the question. The system prompt (house rules, business name, who is
        // speaking) and the tool list stay the same for the whole chat: Claude refuses a conversation whose start has changed.
        let prompt = AssistantContext.question(question, updates: updates, now: Date())
        let tools = AssistantTools.definitions(for: data)
        let context = AssistantContext.make(data: data)
        let before = data
        var history = assistantHistory            // a copy, so nothing else is locked while we wait for the answer
        do {
            let turn: AssistantTurn
            do {
                turn = try await AssistantRunner.ask(prompt, history: &history, tools: tools, context: context, transport: transport) { call in
                    await self.runAssistantTool(call)
                }
            } catch let e as AssistantError where AssistantRunner.retryInFreshChat(e) && !history.isEmpty && data == before {
                // Claude turned down the conversation so far, or it grew too long. Nothing was changed, so it is safe to ask
                // once more in a fresh chat, with the last few lines as a reminder. The old conversation is let go either
                // way: keeping it would only make the next question fail the same way.
                history = []
                assistantHistory = []
                let recap = assistantLines.dropLast().suffix(6).filter { $0.kind == .user || $0.kind == .assistant }
                    .map { ($0.kind == .user ? "Me: " : "You: ") + String($0.text.prefix(600)) }.joined(separator: "\n")
                let fresh = AssistantContext.question(recap.isEmpty ? question : "Earlier in this chat:\n\(recap)\n\nNow: \(question)", updates: updates, now: Date())
                turn = try await AssistantRunner.ask(fresh, history: &history, tools: tools, context: context, transport: transport) { call in
                    await self.runAssistantTool(call)
                }
                if e == .tooLong {
                    assistantLines.append(AssistantLine(kind: .note, text: "This chat got long, so I started a fresh one and kept the last few messages in mind."))
                }
            }
            assistantHistory = history
            var words = turn.text
            if words.isEmpty, turn.problem != nil { words = "Here is what I got done before the answer was interrupted." }
            assistantLines.append(AssistantLine(kind: .assistant, text: words.isEmpty ? "Done." : words, actions: turn.actions, pending: turn.pending))
            if let problem = turn.problem {
                assistantLines.append(AssistantLine(kind: .problem, text: "What is listed above was done, but the answer was interrupted. \(Self.describe(problem)) Do not ask for the same change again; ask what is left instead."))
            }
        } catch AssistantError.notSwitchedOn where !again && !Self.ownServerHasNoAssistant && Self.builtInAssistant != nil {
            // The owner's own server is there for client pages and email but has no Anthropic key. That used to leave the
            // assistant dead even though the one built into the app works, so ask the same question there instead.
            Self.ownServerHasNoAssistant = true
            assistantUpdates = updates + assistantUpdates
            assistantBusy = false
            await askAssistant(question, again: true)
            return
        } catch let e as AssistantError {
            assistantUpdates = updates + assistantUpdates             // the question was not answered, so keep the updates for next time
            assistantLines.append(AssistantLine(kind: .problem, text: Self.describe(e)))
        } catch {
            assistantUpdates = updates + assistantUpdates
            assistantLines.append(AssistantLine(kind: .problem, text: "Something went wrong while asking the assistant. Your question was not answered. Try again."))
        }
        await refreshAssistantStatus()
    }

    static func describe(_ e: AssistantError) -> String {
        switch e {
        case .notSignedIn, .notAllowed:
            return "The assistant server did not accept this app's access token. If you use your own server, check the token in Settings. Otherwise update the app."
        case .notSwitchedOn:
            return "The assistant is not switched on for your server yet (it has no Anthropic key). Add the key on the server, or paste your own key in Settings, Assistant."
        case .limit(let m), .busy(let m), .server(let m), .network(let m): return m
        case .unreadable: return "The assistant's answer could not be read. Try again."
        case .tooLong: return "This chat is too long to continue. Tap the new-chat button at the top and ask again."
        case .conversation(let why):
            let detail = why.trimmingCharacters(in: .whitespacesAndNewlines)
            return "The assistant could not continue this chat. Tap the new-chat button at the top and ask again." + (detail.isEmpty ? "" : " (Claude said: \(detail.prefix(160)))")
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
        // A long route is listed up to 60 stops, so one answer cannot fill the whole conversation.
        var lines = plan.planned.prefix(60).enumerated().map { "\($0.offset + 1). \($0.element.stop.name) (about \(Int($0.element.arrivalOffsetSeconds / 60)) min from the start)" }
        if plan.planned.count > 60 { lines.append("(\(plan.planned.count - 60) more stops are not listed here. The full order is on the Home map.)") }
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
        guard let idText = input["request_id"]?.string, let id = UUID(uuidString: idText.trimmingCharacters(in: .whitespaces)), let decision = input["decision"]?.string,
              ["accept", "decline", "read"].contains(decision) else { return .error("Give the request id from list_requests and a decision of accept, decline or read.") }
        guard let request = data.serviceRequests.first(where: { $0.id == id && $0.status == .pending }) else { return .error("That request is not waiting any more.") }
        if request.kind == .thanks {
            // A kind message has nothing to accept or decline: it is marked read, and the client's page only shows that it was read.
            let result = await decideRequest(id, accept: true, message: "")
            return .text(result.hasPrefix("Accepted") ? "Marked the message as read." : result)
        }
        guard decision != "read" else { return .error("Only a kind message can be marked read. This one is a request: use accept or decline.") }
        let accept = decision == "accept"
        var note = String((input["message"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if note.isEmpty {                                  // the same words the Requests screen uses
            if !accept { note = "We can't take this one right now." }
            else if request.kind == .urgent { note = "You are near the top of our list." }
            else if request.kind == .skip { note = "We will skip your property this storm." }
            else { note = "We will come as soon as we can." }
        }
        let place = data.sites.first { $0.id == request.siteID }?.address ?? "this client"
        let action = PendingAction(kind: .answerRequest(id: id, accept: accept, message: note),
                                   title: "\(accept ? "Accept" : "Decline") the request from \(place)?",
                                   detail: "The client will see on their page: \"\(note)\"")
        return .needsConfirmation(action, "Prepared the answer (\(accept ? "accept" : "decline")) for \(place). It has NOT been sent. The person must tap Send in the app to confirm. Tell them it is ready and waiting.")
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
        case .answerRequest(let id, let accept, let message):
            let result = await decideRequest(id, accept: accept, message: message)
            assistantLines.append(AssistantLine(kind: .note, text: result))
            assistantUpdates.append("[Update: the person tapped Send on the answer to a client request. Result: \(result)]")
        }
    }

    public func cancelPending(_ action: PendingAction) {
        removePending(action)
        switch action.kind {
        case .sendInvoice(let number):
            assistantLines.append(AssistantLine(kind: .note, text: "Cancelled. Invoice \(number) was not sent."))
            assistantUpdates.append("[Update: the owner cancelled sending invoice \(number). It was not sent.]")
        case .sendReminders, .sendSeasonLinks, .answerRequest:
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
        // Take the truck off the map under the name it was shared with, even if the name box was edited since.
        let label = truckSharer.sharedLabel
        truckSharer.stop()
        if let client = portalClient() { Task { try? await client.publishTrucks([], remove: [label]) } }
        #endif
    }
}
#endif
