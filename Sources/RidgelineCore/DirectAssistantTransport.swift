import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The house rules the assistant follows. The same text lives in server/ai.mjs, so both paths behave alike.
public enum AssistantPrompt {
    public static let system = [
        "You are the Ridgeline Ops assistant, built into an app for snow removal and landscaping business owners and their crews.",
        "Help with the work in the app: today's jobs, routes, clients, quotes and invoices. Use the tools to read the business's data and to make changes; never invent clients, jobs, invoices or amounts.",
        "Only say something was done after a tool result confirms it. Sending an invoice or message to a client is never done by you alone: the tool asks the person to confirm in the app, so say you have prepared it and that they need to tap Send.",
        "If a tool says the person is not allowed to do something, say so plainly and do not try another way around it.",
        "Ask one short question when a request is unclear or could match more than one client or job. Keep answers brief and plain, with no markdown headings.",
        "Routes are ordered by drive time only. You are not a weather or safety authority: for road conditions or safety, tell people to use their own judgement.",
        "Each message from the person starts with a line in square brackets that the app adds: the current date and time. Use it to turn words like today, tomorrow or Friday into dates. Lines that start with [Update: are also from the app and say what the person tapped since your last answer.",
    ].joined(separator: "\n")

    public static func withContext(_ context: String) -> String {
        context.isEmpty ? system : "\(system)\n\nAbout this business and person (from the app):\n\(context)"
    }
}

/// Talks to the Claude API straight from the device with the owner's own Anthropic key (kept in the Keychain).
/// Used when no server is set up. The owner pays Anthropic directly for what they use.
public struct DirectAssistantTransport: AssistantTransport {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-haiku-5-5"
    public static let apiVersion = "2026-10-21"

    public let apiKey: String
    public let model: String
    public let client: HTTPClient

    public init(apiKey: String, model: String = DirectAssistantTransport.defaultModel, client: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.client = client
    }

    /// A key looks like "sk-ant-..." and has no spaces.
    public static func looksLikeKey(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("sk-ant-") && t.count >= 20 && t.count <= 300 && !t.contains(where: { $0.isWhitespace })
    }

    func body(messages: [AssistantMessage], tools: [AssistantTool], context: String) throws -> Data {
        var params: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(16000),
            "thinking": .object(["type": .string("adaptive")]),
            "output_config": .object(["effort": .string("medium")]),
            "system": .string(AssistantPrompt.withContext(context)),
            "messages": .array(try messages.map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) }),
        ]
        if !tools.isEmpty { params["tools"] = .array(tools.map(\.wire)) }
        // Keys in a fixed order, so the same conversation is always sent as the same bytes (Claude checks earlier turns are unchanged).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONValue.object(params))
    }

    func request(body: Data) -> URLRequest {
        var r = URLRequest(url: Self.endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 180
        r.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = body
        return r
    }

    static func errorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.string
    }

    /// Turns an answer that is not a success into a specific, plain error.
    static func failure(status: Int, data: Data) -> AssistantError {
        let text = errorMessage(data) ?? ""
        let low = text.lowercased()
        switch status {
        case 401: return .server("Anthropic did not accept your key. Check it in Settings, Assistant.")
        case 403: return .server("Your Anthropic key is not allowed to use the assistant's model. Check the key and its workspace at console.anthropic.com.")
        case 404: return .server("Anthropic does not offer the assistant's model to your key. Check your account at console.anthropic.com.")
        case 413: return .tooLong
        case 429: return .busy("Too many questions at once, or your Anthropic account hit its limit. Try again in a minute.")
        case 529, 503: return .busy("Claude is busy right now. Try again in a minute.")
        case 400:
            if low.contains("credit") || low.contains("billing") { return .limit("Your Anthropic account is out of credit. Add credit at console.anthropic.com.") }
            if low.contains("too long") || low.contains("too large") || low.contains("context window") { return .tooLong }
            return .conversation(text.isEmpty ? "Claude did not accept the request." : text)
        default:
            if status >= 500 { return .busy("Claude had a problem on its side (error \(status)). Try again in a minute.") }
            return .server(text.isEmpty ? "Claude gave an answer the app did not expect (error \(status)). Try again." : text)
        }
    }

    public func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply {
        let outgoing = request(body: try body(messages: messages, tools: tools, context: context))
        let answer: (data: Data, status: Int)
        do { answer = try await client.send(outgoing) } catch { throw AssistantError.connectionProblem(error, service: "Claude") }
        guard answer.status == 200 else { throw Self.failure(status: answer.status, data: answer.data) }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: answer.data), let content = json["content"]?.array,
              let stop = json["stop_reason"]?.string else { throw AssistantError.unreadable }
        return AssistantReply(content: content, stopReason: stop)
    }
}
