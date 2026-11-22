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
        return try JSONEncoder().encode(JSONValue.object(params))
    }

    func request(body: Data) -> URLRequest {
        var r = URLRequest(url: Self.endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 120
        r.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = body
        return r
    }

    static func errorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.string
    }

    public func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply {
        let (data, status) = try await client.send(request(body: try body(messages: messages, tools: tools, context: context)))
        switch status {
        case 200:
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let content = json["content"]?.array,
                  let stop = json["stop_reason"]?.string else { throw AssistantError.unreadable }
            return AssistantReply(content: content, stopReason: stop)
        case 401, 403: throw AssistantError.server("Anthropic did not accept your key. Check it in Settings, Assistant.")
        case 429: throw AssistantError.busy("Too many questions at once, or your Anthropic account hit its limit. Try again in a minute.")
        case 529, 503: throw AssistantError.busy("Claude is busy right now. Try again in a minute.")
        case 400:
            let text = Self.errorMessage(data) ?? ""
            if text.lowercased().contains("credit") { throw AssistantError.limit("Your Anthropic account is out of credit. Add credit at console.anthropic.com.") }
            if text.lowercased().contains("too long") || text.lowercased().contains("prompt is too long") { throw AssistantError.tooLong }
            throw AssistantError.server(text.isEmpty ? "The assistant could not answer right now." : text)
        default: throw AssistantError.server(Self.errorMessage(data) ?? "The assistant could not answer right now.")
        }
    }
}
