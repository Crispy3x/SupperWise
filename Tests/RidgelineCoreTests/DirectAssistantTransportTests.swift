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
}
