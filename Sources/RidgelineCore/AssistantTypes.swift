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
        r.timeoutInterval = 120                      // a thoughtful answer can take a while
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let deviceID { r.setValue(deviceID, forHTTPHeaderField: "X-Ridgeline-Device") }
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private static func message(from data: Data) -> String? {
        (try? JSONDecoder().decode([String: JSONValue].self, from: data))?["error"]?.string
    }

    public func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply {
        let body = JSONValue.object(["messages": .array(try messages.map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) }),
                                     "tools": .array(tools.map(\.wire)), "context": .string(context)])
        let (data, status) = try await client.send(request("POST", "v1/ai/chat", body: try JSONEncoder().encode(body)))
        switch status {
        case 200:
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let content = json["content"]?.array,
                  let stop = json["stop_reason"]?.string else { throw AssistantError.unreadable }
            return AssistantReply(content: content, stopReason: stop)
        case 401: throw AssistantError.notAllowed
        case 503: throw AssistantError.notSwitchedOn
        case 429:
            let text = Self.message(from: data) ?? "The assistant is busy. Try again in a minute."
            throw text.contains("allowance") || text.contains("limit") ? AssistantError.limit(text) : AssistantError.busy(text)
        default: throw AssistantError.server(Self.message(from: data) ?? "The assistant could not answer right now.")
        }
    }

    /// Whether the server's assistant is on, and how much of this month's allowance is used (a percent, never dollars).
    public func status() async throws -> (enabled: Bool, usedPercent: Int) {
        let (data, code) = try await client.send(request("GET", "v1/ai/status"))
        guard code == 200, let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw AssistantError.unreadable }
        return (json["enabled"]?.bool ?? false, json["usedPercent"]?.int ?? 0)
    }
}
