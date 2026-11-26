import Foundation

/// What came back from one question: the assistant's words, anything it prepared that waits for a tap, and what it did.
public struct AssistantTurn: Equatable, Sendable {
    public var text: String
    public var pending: [PendingAction]
    /// Plain lines about changes the assistant made, for example "Created job ...". Shown under its answer.
    public var actions: [String]
    public var refused: Bool
    public var stoppedEarly: Bool
    /// Set when the assistant had already changed or prepared something and then the answer failed. The changes stand,
    /// so the turn is returned (never thrown away) and the screen says what went wrong.
    public var problem: AssistantError?

    public init(text: String, pending: [PendingAction] = [], actions: [String] = [], refused: Bool = false, stoppedEarly: Bool = false,
                problem: AssistantError? = nil) {
        self.text = text
        self.pending = pending
        self.actions = actions
        self.refused = refused
        self.stoppedEarly = stoppedEarly
        self.problem = problem
    }
}

public enum AssistantRunner {
    /// Errors a fresh chat is likely to fix (the conversation itself was turned down or has grown too long, or the
    /// answer could not be read).
    public static func retryInFreshChat(_ e: AssistantError) -> Bool {
        switch e {
        case .conversation, .unreadable, .tooLong: return true
        default: return false
        }
    }

    /// Requests per question. The assistant is told when one step is left, so it can answer instead of stopping silently.
    public static let maxSteps = 8
    /// A question can add 1 + 2 x maxSteps messages, and the server accepts 80 (older servers) or more, so stop below that.
    public static let maxMessages = 60
    /// Longer tool results are cut, so one long list cannot fill the conversation or the server's size limit.
    public static let maxToolResultCharacters = 6000
    /// Tools whose result means something was changed. Their first line is shown under the answer.
    static let changingTools: Set<String> = ["create_job", "add_client", "update_job_status", "create_invoice", "bill_finished_jobs", "record_payment", "answer_request"]

    static func textBlock(_ text: String) -> JSONValue { .object(["type": .string("text"), "text": .string(text)]) }

    static func isThinking(_ block: JSONValue) -> Bool {
        let type = block["type"]?.string
        return type == "thinking" || type == "redacted_thinking"
    }

    /// The API refuses a text block with nothing in it, so those are left out before an answer is kept. Blocks up to
    /// the last thinking block are never touched: Claude needs them back exactly as it wrote them.
    static func cleaned(_ content: [JSONValue]) -> [JSONValue] {
        let lastThinking = content.lastIndex(where: isThinking) ?? -1
        var kept: [JSONValue] = []
        for (index, block) in content.enumerated() {
            if index > lastThinking, block["type"]?.string == "text",
               (block["text"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            kept.append(block)
        }
        return kept
    }

    /// Claude ties each thinking block to the conversation before it. If it says a block no longer fits, the documented
    /// way out is to send the conversation once more without the thinking blocks; the words and tool calls stay.
    static func isThinkingMismatch(_ reason: String) -> Bool {
        let r = reason.lowercased()
        return r.contains("thinking") && (r.contains("signature") || r.contains("different conversation") || r.contains("block_binding"))
    }

    static func withoutThinking(_ history: [AssistantMessage]) -> [AssistantMessage] {
        history.map { message -> AssistantMessage in
            guard message.role == "assistant" else { return message }
            let kept = message.content.filter { !isThinking($0) }
            return AssistantMessage(role: message.role, content: kept.isEmpty ? [textBlock("(no text)")] : kept)
        }
    }

    /// Adds what the person said. If the conversation already ends on the person's side (tool results the assistant
    /// never got to answer), the words join that message after the results: the API wants the two sides to take turns,
    /// and tool results to come first in a message.
    static func appendUser(_ blocks: [JSONValue], to history: inout [AssistantMessage]) {
        if let last = history.last, last.role == "user" {
            history[history.count - 1].content.append(contentsOf: blocks)
        } else {
            history.append(AssistantMessage(role: "user", content: blocks))
        }
    }

    static func clipped(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Done." }                    // an empty result is refused by the API
        guard t.count > maxToolResultCharacters else { return t }
        return String(t.prefix(maxToolResultCharacters)) + "\n(The rest was cut off because it was too long. Ask for a smaller list, for example one day or one client.)"
    }

    private static func send(_ history: inout [AssistantMessage], strippedThinking: inout Bool, tools: [AssistantTool], context: String,
                             transport: AssistantTransport) async throws -> AssistantReply {
        do {
            return try await transport.send(messages: history, tools: tools, context: context)
        } catch AssistantError.conversation(let why) where !strippedThinking && isThinkingMismatch(why) {
            strippedThinking = true
            history = withoutThinking(history)
            return try await transport.send(messages: history, tools: tools, context: context)
        }
    }

    /// Asks one question and carries on until the assistant has an answer. When it asks for a tool, `runTool` runs it on
    /// the device and the result goes back. The conversation lives in `history`: it only ever grows at the end, and what
    /// the assistant wrote is sent back as it was, because Claude checks that nothing earlier has changed.
    ///
    /// If the question fails before anything was changed, it throws and `history` is exactly as it was. If it fails
    /// after the assistant changed or prepared something, the turn comes back with `problem` set and the conversation
    /// keeps what was done, so nothing is done twice.
    public static func ask(_ question: String, history: inout [AssistantMessage], tools: [AssistantTool], context: String,
                           transport: AssistantTransport, runTool: (ToolCall) async -> ToolOutcome) async throws -> AssistantTurn {
        guard history.count < maxMessages else { throw AssistantError.tooLong }
        let saved = history
        appendUser([textBlock(question)], to: &history)
        var pending: [PendingAction] = []
        var actions: [String] = []
        var lastText = ""
        var strippedThinking = false

        for step in 0..<maxSteps {
            let didSomething = !actions.isEmpty || !pending.isEmpty
            let reply: AssistantReply
            do {
                reply = try await send(&history, strippedThinking: &strippedThinking, tools: tools, context: context, transport: transport)
            } catch {
                guard didSomething else { history = saved; throw error }
                let problem = (error as? AssistantError) ?? AssistantError.network("The connection was lost before the assistant finished its answer.")
                return AssistantTurn(text: lastText, pending: pending, actions: actions, stoppedEarly: true, problem: problem)
            }
            let content = cleaned(reply.content)
            let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch reply.stopReason {
            case "max_tokens", "pause_turn":
                // A cut-off answer can end in the middle of thinking or a tool call; keeping it would break the next question.
                if !didSomething { history = saved }
                let why = reply.stopReason == "pause_turn" ? "The assistant paused before it finished. Ask again."
                                                           : "That one needed more room than I have. Try asking in smaller steps."
                return AssistantTurn(text: text.isEmpty ? why : text + "\n\n(This answer was cut short. Ask again in smaller steps for the rest.)",
                                     pending: pending, actions: actions, stoppedEarly: true)
            case "model_context_window_exceeded":
                guard didSomething else { history = saved; throw AssistantError.tooLong }
                return AssistantTurn(text: lastText, pending: pending, actions: actions, stoppedEarly: true, problem: .tooLong)
            case "refusal":
                // A declined question is not kept: its answer is often empty, and an empty message would break the next one.
                if !didSomething { history = saved }
                return AssistantTurn(text: "I can't help with that one. Try asking in a different way.", pending: pending, actions: actions, refused: true)
            default:
                break
            }

            var calls: [ToolCall] = []
            var results: [JSONValue] = []
            var unreadable = false
            for block in content where block["type"]?.string == "tool_use" {
                guard let id = block["id"]?.string, !id.isEmpty else { unreadable = true; continue }
                if let name = block["name"]?.string, !name.isEmpty {
                    calls.append(ToolCall(id: id, name: name, input: block["input"] ?? .object([:])))
                } else {
                    // Every tool call must get an answer, even one that cannot be read.
                    results.append(.object(["type": .string("tool_result"), "tool_use_id": .string(id),
                                            "content": .string("That tool call could not be read. Try again."), "is_error": .bool(true)]))
                }
            }
            if unreadable {
                // A tool call with no id cannot be answered, so this reply cannot be kept.
                guard didSomething else { history = saved; throw AssistantError.unreadable }
                return AssistantTurn(text: lastText, pending: pending, actions: actions, stoppedEarly: true, problem: .unreadable)
            }
            if !text.isEmpty { lastText = text }

            if calls.isEmpty && results.isEmpty {
                if text.isEmpty {
                    // Nothing to show, and an assistant message with no words is refused the next time it is sent. Do not keep it.
                    if !didSomething {
                        history = saved
                        return AssistantTurn(text: "I did not get an answer that time. Please ask again.", stoppedEarly: true)
                    }
                    return AssistantTurn(text: "Done.", pending: pending, actions: actions)
                }
                history.append(AssistantMessage(role: "assistant", content: content))
                return AssistantTurn(text: text, pending: pending, actions: actions)
            }

            history.append(AssistantMessage(role: "assistant", content: content))
            let lastStep = step == maxSteps - 1
            for call in calls {
                var body: String, isError = false
                if lastStep {
                    // Out of steps: nothing more is run, and the assistant is told so it can pick up from here next time.
                    body = "Not run: this question used all of its steps. Tell the person what is left and ask whether to continue."
                    isError = true
                } else {
                    switch await runTool(call) {
                    case .text(let t):
                        body = t
                        if changingTools.contains(call.name) { actions.append(String(t.split(separator: "\n").first ?? "")) }
                    case .error(let t): body = t; isError = true
                    case .needsConfirmation(let action, let t): body = t; pending.append(action)
                    case .hostTool: body = "That tool is not available right now."; isError = true
                    }
                }
                var block: [String: JSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(call.id), "content": .string(clipped(body))]
                if isError { block["is_error"] = .bool(true) }
                results.append(.object(block))
            }
            if step == maxSteps - 2 {
                // Said after the tool results (the order the API wants) and left in the conversation for good.
                results.append(textBlock("[From the app: one step is left for this question. Answer now with what you have. If more is needed, say what is left and ask the person to say \"continue\".]"))
            }
            history.append(AssistantMessage(role: "user", content: results))
        }
        let note = "I ran out of steps before finishing. Say \"continue\" and I will carry on from here, or ask for one thing at a time."
        return AssistantTurn(text: lastText.isEmpty ? note : lastText + "\n\n" + note, pending: pending, actions: actions, stoppedEarly: true)
    }
}

public enum AssistantContext {
    /// Facts that stay the same for a whole chat. They become part of the system prompt, and Claude checks that the
    /// system prompt has not changed since its earlier answers, so nothing that changes by the minute may go here.
    /// The time goes in front of each question instead (see `question`). No client names, addresses or amounts:
    /// the assistant asks the tools for those.
    public static func make(data: AppData) -> String {
        let company = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["Business: \(company.isEmpty ? "not named yet" : company)."]
        if let m = data.currentMember { lines.append("Speaking with: \(m.name), \(m.role.title) (an employee, limited to what the owner allowed).") }
        else { lines.append("Speaking with: the business owner.") }
        return lines.joined(separator: "\n")
    }

    /// The line in front of every question, for example "[Now: Friday, January 15, 2027, 8:00 AM (America/Chicago)]".
    public static func stamp(now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE, MMMM d, yyyy, h:mm a"
        return "[Now: \(f.string(from: now)) (\(calendar.timeZone.identifier))]"
    }

    /// What is sent for one question: the time, anything that happened outside the chat (the person tapped Send), then the words.
    public static func question(_ text: String, updates: [String] = [], now: Date, calendar: Calendar = .current) -> String {
        ([stamp(now: now, calendar: calendar)] + updates + [text]).joined(separator: "\n")
    }
}

extension AppData {
    public var assistantConsented: Bool { assistantConsentAt != nil }
    public mutating func grantAssistantConsent(now: Date) { if assistantConsentAt == nil { assistantConsentAt = now } }
    public mutating func revokeAssistantConsent() { assistantConsentAt = nil }
}
