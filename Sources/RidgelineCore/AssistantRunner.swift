import Foundation

/// What came back from one question: the assistant's words, anything it prepared that waits for a tap, and what it did.
public struct AssistantTurn: Equatable, Sendable {
    public var text: String
    public var pending: [PendingAction]
    /// Plain lines about changes the assistant made, for example "Created job ...". Shown under its answer.
    public var actions: [String]
    public var refused: Bool
    public var stoppedEarly: Bool

    public init(text: String, pending: [PendingAction] = [], actions: [String] = [], refused: Bool = false, stoppedEarly: Bool = false) {
        self.text = text
        self.pending = pending
        self.actions = actions
        self.refused = refused
        self.stoppedEarly = stoppedEarly
    }
}

public enum AssistantRunner {
    public static let maxSteps = 6
    public static let maxMessages = 70

    /// Asks one question and carries on until the assistant has an answer. When it asks for a tool, `runTool` runs it on
    /// the device and the result goes back. The conversation lives in `history`, kept exactly as received.
    public static func ask(_ question: String, history: inout [AssistantMessage], tools: [AssistantTool], context: String,
                           transport: AssistantTransport, runTool: (ToolCall) async -> ToolOutcome) async throws -> AssistantTurn {
        guard history.count < maxMessages else { throw AssistantError.tooLong }
        let startCount = history.count
        history.append(.user(question))
        var pending: [PendingAction] = []
        var actions: [String] = []
        var lastText = ""
        do {
            for _ in 0..<maxSteps {
                let reply = try await transport.send(messages: history, tools: tools, context: context)
                history.append(AssistantMessage(role: "assistant", content: reply.content))
                if reply.stopReason == "refusal" {
                    return AssistantTurn(text: "I can't help with that one. Try asking in a different way.", pending: pending, actions: actions, refused: true)
                }
                let calls = reply.content.compactMap { block -> ToolCall? in
                    guard block["type"]?.string == "tool_use", let id = block["id"]?.string, let name = block["name"]?.string else { return nil }
                    return ToolCall(id: id, name: name, input: block["input"] ?? .object([:]))
                }
                if !reply.text.isEmpty { lastText = reply.text }
                if calls.isEmpty { return AssistantTurn(text: reply.text.isEmpty ? "Done." : reply.text, pending: pending, actions: actions) }
                var results: [JSONValue] = []
                for call in calls {
                    let outcome = await runTool(call)
                    var body: String, isError = false
                    switch outcome {
                    case .text(let t):
                        body = t
                        if ["create_job", "add_client", "update_job_status", "create_invoice"].contains(call.name) { actions.append(String(t.split(separator: "\n").first ?? "")) }
                    case .error(let t): body = t; isError = true
                    case .needsConfirmation(let action, let t): body = t; pending.append(action)
                    case .hostTool: body = "That tool is not available right now."; isError = true
                    }
                    var block: [String: JSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(call.id), "content": .string(body)]
                    if isError { block["is_error"] = .bool(true) }
                    results.append(.object(block))
                }
                history.append(AssistantMessage(role: "user", content: results))
            }
            return AssistantTurn(text: lastText.isEmpty ? "That took more steps than I allow in one go. Ask again more simply." : lastText,
                                 pending: pending, actions: actions, stoppedEarly: true)
        } catch {
            // A failed question leaves no half-finished turn behind, so the next one starts cleanly.
            history.removeSubrange(startCount...)
            throw error
        }
    }
}

public enum AssistantContext {
    /// Facts the assistant needs to answer well. No client names, addresses or amounts: it asks the tools for those.
    public static func make(data: AppData, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE, MMMM d, yyyy, h:mm a"
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["Business: \(company.isEmpty ? "not named yet" : company).",
                     "Now: \(f.string(from: now)) (\(calendar.timeZone.identifier)). Use this to turn words like today, tomorrow or Friday into dates."]
        if let m = data.currentMember { lines.append("Speaking with: \(m.name), \(m.role.title) (an employee, limited to what the owner allowed).") }
        else { lines.append("Speaking with: the business owner.") }
        return lines.joined(separator: "\n")
    }
}

extension AppData {
    public var assistantConsented: Bool { assistantConsentAt != nil }
    public mutating func grantAssistantConsent(now: Date) { if assistantConsentAt == nil { assistantConsentAt = now } }
    public mutating func revokeAssistantConsent() { assistantConsentAt = nil }
}
