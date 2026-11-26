import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Any JSON value. The assistant's replies are kept exactly as received, so blocks the app does not understand (such as
/// the model's thinking blocks) can be sent back unchanged, which the API requires.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not JSON") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var double: Double? { if case .number(let n) = self { return n }; return nil }
    public var int: Int? { double.flatMap { $0.isFinite && abs($0) < 1e9 ? Int($0) : nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

/// One message in the conversation. `content` is a list of blocks (text, tool_use, tool_result, thinking...).
public struct AssistantMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: [JSONValue]

    public init(role: String, content: [JSONValue]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> AssistantMessage {
        AssistantMessage(role: "user", content: [.object(["type": .string("text"), "text": .string(text)])])
    }
}

public struct AssistantTool: Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    var wire: JSONValue { .object(["name": .string(name), "description": .string(description), "input_schema": inputSchema]) }
}

public struct AssistantReply: Equatable, Sendable {
    public var content: [JSONValue]
    public var stopReason: String

    public init(content: [JSONValue], stopReason: String) {
        self.content = content
        self.stopReason = stopReason
    }

    public var text: String {
        content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
    }
}

public enum AssistantError: Error, Equatable {
    case notSignedIn
    case notSwitchedOn
    case notAllowed
    case limit(String)
    case busy(String)
    case server(String)
    case unreadable
    case tooLong
    /// Claude turned down the conversation as sent (for example a cut-off earlier answer). A fresh chat usually fixes it.
    case conversation(String)
    /// The request never got an answer: offline, timed out, or the server could not be found. Carries a plain sentence.
    case network(String)
}

extension AssistantError {
    /// A plain sentence for a request that failed on the way. `service` is who was being asked, for example "Claude".
    static func connectionProblem(_ error: Error, service: String) -> AssistantError {
        if let known = error as? AssistantError { return known }
        guard let code = (error as? URLError)?.code else { return .network("Could not reach \(service). Check your connection and try again.") }
        switch code {
        case .timedOut:
            return .network("\(service) took too long to answer. Try again, or ask for one thing at a time.")
        case .notConnectedToInternet, .networkConnectionLost:
            return .network("This device is offline. Connect to the internet and ask again.")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .network("Could not find \(service). Check your connection, then try again in a minute.")
        case .secureConnectionFailed:
            return .network("Could not make a secure connection to \(service). Try again in a minute.")
        case .cancelled:
            return .network("The question was cancelled before it was answered.")
        default:
            return .network("Could not reach \(service). Check your connection and try again.")
        }
    }
}

public protocol AssistantTransport: Sendable {
    func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply
}

/// Talks to the Ridgeline server's assistant endpoint. The server holds the Anthropic key and the spending limit.
public struct ServerAssistantTransport: AssistantTransport {
    public let baseURL: URL
    public let token: String
    public let client: HTTPClient
    /// Sent with the app's built-in token so each phone gets its own allowance on the shared server.
    public let deviceID: String?

    public init(baseURL: URL, token: String, client: HTTPClient = URLSessionHTTPClient(), deviceID: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
        self.deviceID = deviceID
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = method == "GET" ? 20 : 200    // a thoughtful answer can take a while; the server gives up before this
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let deviceID { r.setValue(deviceID, forHTTPHeaderField: "X-Ridgeline-Device") }
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    /// The request body. Keys are written in a fixed order so the same conversation is always sent as the same bytes.
    func body(messages: [AssistantMessage], tools: [AssistantTool], context: String) throws -> Data {
        let body = JSONValue.object(["messages": .array(try messages.map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) }),
                                     "tools": .array(tools.map(\.wire)), "context": .string(context)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    public func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply {
        let outgoing = request("POST", "v1/ai/chat", body: try body(messages: messages, tools: tools, context: context))
        let answer: (data: Data, status: Int)
        do { answer = try await client.send(outgoing) } catch { throw AssistantError.connectionProblem(error, service: "the assistant server") }
        let data = answer.data, status = answer.status
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        let said = json?["error"]?.string ?? ""
        switch status {
        case 200:
            guard let content = json?["content"]?.array, let stop = json?["stop_reason"]?.string else { throw AssistantError.unreadable }
            return AssistantReply(content: content, stopReason: stop)
        case 401: throw AssistantError.notAllowed
        case 404: throw AssistantError.server("This server has no assistant. Check the server address in Settings, or update the server.")
        case 413: throw AssistantError.tooLong
        case 503:
            if said.contains("switched on") { throw AssistantError.notSwitchedOn }
            throw AssistantError.busy(said.isEmpty ? "The assistant server is starting up or busy. Try again in a minute." : said)
        case 429:
            let text = said.isEmpty ? "The assistant is busy. Try again in a minute." : said
            throw text.contains("allowance") || text.contains("limit") ? AssistantError.limit(text) : AssistantError.busy(text)
        default:
            if json?["tooLong"]?.bool == true { throw AssistantError.tooLong }
            if json?["conversation"]?.bool == true { throw AssistantError.conversation(json?["reason"]?.string ?? said) }
            if said.isEmpty {
                // No message of ours came back, so the answer is from the host in front of the server (asleep, restarting or overloaded).
                if status >= 500 { throw AssistantError.busy("The assistant server is not answering (error \(status)). It may be starting up. Try again in a minute.") }
                throw AssistantError.server("The assistant server gave an answer the app did not expect (error \(status)). Check the server address in Settings.")
            }
            throw AssistantError.server(said)
        }
    }

    /// Whether the server's assistant is on, and how much of this month's allowance is used (a percent, never dollars).
    public func status() async throws -> (enabled: Bool, usedPercent: Int) {
        let (data, code) = try await client.send(request("GET", "v1/ai/status"))
        guard code == 200, let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw AssistantError.unreadable }
        return (json["enabled"]?.bool ?? false, json["usedPercent"]?.int ?? 0)
    }
}
