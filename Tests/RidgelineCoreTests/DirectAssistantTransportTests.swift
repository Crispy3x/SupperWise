import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class FakeClient: HTTPClient, @unchecked Sendable {
    var last: URLRequest?
    let status: Int
    let data: Data
    init(status: Int, json: String) { self.status = status; self.data = Data(json.utf8) }
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { last = request; return (data, status) }
}

final class DirectAssistantTransportTests: XCTestCase {
    func testKeyShape() {
        XCTAssertTrue(DirectAssistantTransport.looksLikeKey("sk-ant-api03-abcdefghijklmnop"))
        XCTAssertFalse(DirectAssistantTransport.looksLikeKey("hello"))
        XCTAssertFalse(DirectAssistantTransport.looksLikeKey("sk-ant-api03 with spaces in it"))
    }

    func testRequestShapeAndReply() async throws {
        let fake = FakeClient(status: 200, json: #"{"content":[{"type":"text","text":"Hi"}],"stop_reason":"end_turn"}"#)
        let t = DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: fake)
        let tool = AssistantTool(name: "list_jobs", description: "Jobs", inputSchema: .object(["type": .string("object")]))
        let reply = try await t.send(messages: [.user("What's today?")], tools: [tool], context: "Company: Ridge Plow")
        XCTAssertEqual(reply.text, "Hi")
        XCTAssertEqual(reply.stopReason, "end_turn")
        let r = try XCTUnwrap(fake.last)
        XCTAssertEqual(r.url, DirectAssistantTransport.endpoint)
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-0123456789abc")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(r.httpBody))
        XCTAssertEqual(body["model"]?.string, "claude-haiku-5-5")
        XCTAssertEqual(body["thinking"]?["type"]?.string, "adaptive")
        XCTAssertEqual(body["output_config"]?["effort"]?.string, "medium")
        XCTAssertEqual(body["tools"]?.array?.count, 1)
        XCTAssertTrue(body["system"]?.string?.contains("Company: Ridge Plow") ?? false)
        XCTAssertNil(body["temperature"])
    }

    func testErrorsAreFriendly() async {
        let t = DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: FakeClient(status: 401, json: #"{"error":{"message":"invalid x-api-key"}}"#))
        do { _ = try await t.send(messages: [.user("x")], tools: [], context: ""); XCTFail() } catch {
            guard case AssistantError.server(let m) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(m.contains("key"))
        }
        let broke = DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: FakeClient(status: 400, json: #"{"error":{"message":"Your credit balance is too low"}}"#))
        do { _ = try await broke.send(messages: [.user("x")], tools: [], context: ""); XCTFail() } catch {
            guard case AssistantError.limit = error else { return XCTFail("\(error)") }
        }
    }

    func testEveryFailureHasItsOwnPlainMessage() {
        func failure(_ status: Int, _ message: String) -> AssistantError {
            DirectAssistantTransport.failure(status: status, data: Data(#"{"type":"error","error":{"type":"x","message":"\#(message)"}}"#.utf8))
        }
        XCTAssertEqual(failure(400, "prompt is too long: 1200000 tokens > 1000000 maximum"), .tooLong)
        XCTAssertEqual(failure(413, "Request exceeds the maximum allowed number of bytes"), .tooLong)
        // A conversation Claude turns down keeps Claude's reason, so the runner can tell what kind it is.
        let bound = "messages.3.content.0: Invalid signature in thinking block. The block is bound to a different conversation."
        XCTAssertEqual(failure(400, bound), .conversation(bound))
        XCTAssertTrue(AssistantRunner.isThinkingMismatch(bound))
        XCTAssertFalse(AssistantRunner.isThinkingMismatch("messages: roles must alternate"))
        for status in [500, 502, 504, 529, 503, 429] {
            guard case .busy(let m) = failure(status, "") else { XCTFail("\(status)"); continue }
            XCTAssertTrue(m.contains("minute"), m)
        }
        guard case .server(let model) = failure(404, "model: claude-haiku-5-5") else { return XCTFail() }
        XCTAssertTrue(model.contains("model"))
        // Nothing falls through to a bare "could not answer right now".
        for status in [400, 401, 403, 404, 409, 413, 418, 429, 500, 503, 529] {
            let text: String
            switch failure(status, "") {
            case .server(let m), .busy(let m), .limit(let m), .conversation(let m), .network(let m): text = m
            case .tooLong: text = "too long"
            default: text = ""
            }
            XCTAssertFalse(text.isEmpty, "\(status)"); XCTAssertFalse(text.contains("could not answer right now"), "\(status)")
        }
    }

    func testRoomForThinkingPlusAToolCall() throws {
        let t = DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: FakeClient(status: 200, json: "{}"))
        let body = try JSONDecoder().decode(JSONValue.self, from: t.body(messages: [.user("x")], tools: [], context: ""))
        XCTAssertGreaterThanOrEqual(body["max_tokens"]?.int ?? 0, 16000)
        XCTAssertNil(body["tools"])                                  // an empty tool list is left out, which the API prefers
        XCTAssertNil(body["tool_choice"])                            // never forced: a forced call skips thinking and some models refuse it
    }
}

final class AssistantRecoveryTests: XCTestCase {
    func testFreshChatRetryOnlyForConversationProblems() {
        XCTAssertTrue(AssistantRunner.retryInFreshChat(.conversation("x")))
        XCTAssertTrue(AssistantRunner.retryInFreshChat(.unreadable))
        XCTAssertFalse(AssistantRunner.retryInFreshChat(.busy("x")))
        XCTAssertFalse(AssistantRunner.retryInFreshChat(.limit("x")))
        XCTAssertTrue(AssistantRunner.retryInFreshChat(.tooLong))               // a chat that grew too long rolls over on its own
        XCTAssertFalse(AssistantRunner.retryInFreshChat(.network("x")))
    }

    func testServerMarksConversationProblems() async {
        let fake = FakeClient(status: 502, json: #"{"error":"The assistant could not answer right now.","reason":"bad history","conversation":true}"#)
        let t = ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: fake)
        do { _ = try await t.send(messages: [.user("x")], tools: [], context: ""); XCTFail() } catch {
            guard case AssistantError.conversation(let m) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(m, "bad history")
        }
    }
}
