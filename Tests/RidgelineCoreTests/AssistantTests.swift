import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class ScriptedTransport: AssistantTransport, @unchecked Sendable {
    var replies: [Result<AssistantReply, Error>]
    private(set) var sent: [[AssistantMessage]] = []
    private(set) var toolNames: [[String]] = []
    init(_ replies: [Result<AssistantReply, Error>]) { self.replies = replies }
    func send(messages: [AssistantMessage], tools: [AssistantTool], context: String) async throws -> AssistantReply {
        sent.append(messages); toolNames.append(tools.map(\.name))
        return try replies.removeFirst().get()
    }
}

private final class ScriptedHTTP: HTTPClient, @unchecked Sendable {
    var status = 200
    var body = Data("{}".utf8)
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { requests.append(request); return (body, status) }
}

private func toolUse(_ id: String, _ name: String, _ input: [String: JSONValue] = [:]) -> JSONValue {
    .object(["type": .string("tool_use"), "id": .string(id), "name": .string(name), "input": .object(input)])
}
private func text(_ t: String) -> JSONValue { .object(["type": .string("text"), "text": .string(t)]) }
private let thinking: JSONValue = .object(["type": .string("thinking"), "thinking": .string(""), "signature": .string("sig-123")])

final class AssistantTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)       // 2027-01-15 08:00 UTC
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func world() -> AppData {
        var d = AppData()
        d.companyName = "Ridge Plow"
        let pat = Customer(name: "Pat Miller", phone: "612-555-0100", email: "pat@example.com", emailConsent: true)
        let sam = Customer(name: "Sam Lee", email: "sam@example.com")                          // has not agreed to emails
        let two = Customer(name: "Pat Jones")
        d.customers = [pat, sam, two]
        d.sites = [Site(customerID: pat.id, address: "14 Elm Ave", latitude: 44.9, longitude: -93.2),
                   Site(customerID: sam.id, address: "2 Oak St"),
                   Site(customerID: two.id, address: "1 First St"), Site(customerID: two.id, address: "9 Ninth St")]
        d.ensurePortalLinks(now: now)
        return d
    }

    @discardableResult
    private func addMember(_ d: inout AppData, _ name: String, role: TeamRole = .crewMember, user: String = "dana") throws -> TeamMember {
        var g = SeededGenerator(state: 5)
        return try d.addTeamMember(name: name, role: role, username: user, password: "Plow-2027-ok", now: now, iterations: 2, using: &g)
    }

    private func run(_ name: String, _ input: [String: JSONValue], _ d: inout AppData) -> ToolOutcome {
        AssistantTools.execute(ToolCall(id: "t", name: name, input: .object(input)), data: &d, now: now, calendar: utc)
    }

    // MARK: JSON

    func testJSONRoundTripKeepsUnknownBlocksExactly() throws {
        let msg = AssistantMessage(role: "assistant", content: [thinking, text("Hi"), toolUse("a", "x", ["n": .number(2.5), "ok": .bool(true), "list": .array([.null, .string("s")])])])
        let back = try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(msg))
        XCTAssertEqual(back, msg)
        XCTAssertEqual(back.content[0]["signature"]?.string, "sig-123")
    }

    // MARK: permissions

    func testEachPersonIsOfferedOnlyTheToolsTheyMayUse() throws {
        var d = world()
        XCTAssertEqual(Set(AssistantTools.definitions(for: d).map(\.name)),
                       ["get_schedule", "list_clients", "add_client", "create_job", "update_job_status", "list_invoices", "create_invoice", "send_invoice", "plan_route", "get_weather"])
        let crew = try addMember(&d, "Dana")
        d.session = AppSession(role: .employee, memberID: crew.id, startedAt: now)
        XCTAssertEqual(Set(AssistantTools.definitions(for: d).map(\.name)), ["get_schedule", "update_job_status", "plan_route", "get_weather"])
        // Even if the assistant names a tool it was not offered, the app refuses.
        guard case .error(let why) = run("send_invoice", ["invoice_number": .string("INV-1")], &d) else { return XCTFail() }
        XCTAssertTrue(why.contains("not allowed"))
        guard case .error = run("add_client", ["name": .string("X")], &d) else { return XCTFail() }
        XCTAssertEqual(d.customers.count, 3)
        guard case .error(let unknown) = run("delete_everything", [:], &d) else { return XCTFail() }
        XCTAssertTrue(unknown.contains("no tool"))
    }

    // MARK: reading

    func testScheduleListsJobsWithIds() throws {
        var d = world()
        let j = try d.addJob(title: "Plow", customerID: d.customers[0].id, siteID: d.sites[0].id, start: now, now: now)
        guard case .text(let t) = run("get_schedule", [:], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("Plow")); XCTAssertTrue(t.contains("Pat Miller")); XCTAssertTrue(t.contains(j.id.uuidString))
        guard case .text(let none) = run("get_schedule", ["date": .string("2027-02-01")], &d) else { return XCTFail() }
        XCTAssertEqual(none, "Nothing is scheduled for that day.")
        guard case .error = run("get_schedule", ["date": .string("tomorrow")], &d) else { return XCTFail() }
    }

    func testListClientsLeavesOutContactDetails() {
        var d = world()
        guard case .text(let t) = run("list_clients", ["query": .string("miller")], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("Pat Miller")); XCTAssertTrue(t.contains("14 Elm Ave"))
        XCTAssertFalse(t.contains("612")); XCTAssertFalse(t.contains("pat@example.com"))          // phone and email never go to the AI
        guard case .text(let byAddress) = run("list_clients", ["query": .string("oak")], &d) else { return XCTFail() }
        XCTAssertTrue(byAddress.contains("Sam Lee"))
    }

    func testInvoiceListFilters() throws {
        var d = world()
        var sent = Invoice(number: "INV-1", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now.addingTimeInterval(-86_400),
                           lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])
        try sent.markSent(at: now.addingTimeInterval(-10 * 86_400))
        let draft = Invoice(number: "INV-2", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now, lines: [InvoiceLineItem(description: "x", amount: Money(cents: 100))])
        d.invoices = [sent, draft]
        guard case .text(let unpaid) = run("list_invoices", [:], &d) else { return XCTFail() }
        XCTAssertTrue(unpaid.contains("INV-1")); XCTAssertFalse(unpaid.contains("INV-2"))
        guard case .text(let drafts) = run("list_invoices", ["filter": .string("draft")], &d) else { return XCTFail() }
        XCTAssertTrue(drafts.contains("INV-2"))
        guard case .text(let overdue) = run("list_invoices", ["filter": .string("overdue")], &d) else { return XCTFail() }
        XCTAssertTrue(overdue.contains("INV-1"))
    }

    // MARK: changing things

    func testCreateJobMatchesTheClientAndSiteAndParsesTheTime() throws {
        var d = world()
        guard case .text(let t) = run("create_job", ["title": .string("Plow and salt"), "client_name": .string("pat miller"), "start": .string("2027-01-16 07:30"), "duration_minutes": .number(45)], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("14 Elm Ave")); XCTAssertEqual(d.jobs.count, 1)
        XCTAssertEqual(d.jobs[0].siteID, d.sites[0].id); XCTAssertEqual(d.jobs[0].durationMinutes, 45)
        XCTAssertEqual(utc.component(from: d.jobs[0].start), 7)
        _ = run("create_job", ["title": .string("Visit"), "start": .string("2027-01-17")], &d)
        XCTAssertEqual(utc.component(from: d.jobs[1].start), 8)                                    // a date alone means 8:00
        guard case .error = run("create_job", ["title": .string("x"), "start": .string("next friday")], &d) else { return XCTFail() }
        guard case .error = run("create_job", ["title": .string(" "), "start": .string("2027-01-17")], &d) else { return XCTFail() }
        XCTAssertEqual(d.jobs.count, 2)
    }

    func testCreateJobAsksWhenTheClientOrAddressIsAmbiguous() throws {
        var d = world()
        guard case .error(let e1) = run("create_job", ["title": .string("Plow"), "client_name": .string("Pat"), "start": .string("2027-01-16")], &d) else { return XCTFail() }
        XCTAssertTrue(e1.contains("Pat Miller") && e1.contains("Pat Jones"))                        // two Pats: it asks, never guesses
        guard case .error(let e2) = run("create_job", ["title": .string("Plow"), "client_name": .string("Pat Jones"), "start": .string("2027-01-16")], &d) else { return XCTFail() }
        XCTAssertTrue(e2.contains("1 First St") && e2.contains("9 Ninth St"))
        guard case .text = run("create_job", ["title": .string("Plow"), "client_name": .string("Pat Jones"), "address": .string("ninth"), "start": .string("2027-01-16")], &d) else { return XCTFail() }
        XCTAssertEqual(d.address(forJob: d.jobs[0]), "9 Ninth St")
        guard case .error = run("create_job", ["title": .string("Plow"), "client_name": .string("Nobody"), "start": .string("2027-01-16")], &d) else { return XCTFail() }
        XCTAssertEqual(d.jobs.count, 1)
    }

    func testCreateJobCanAssignATeamMemberAndMakeATask() throws {
        var d = world()
        try addMember(&d, "Dana Cole")
        _ = run("create_job", ["title": .string("Plow"), "client_name": .string("Sam Lee"), "assignee": .string("dana"), "start": .string("2027-01-16")], &d)
        XCTAssertEqual(d.jobs[0].assigneeIDs, [d.team[0].id])
        guard case .error = run("create_job", ["title": .string("Plow"), "assignee": .string("zed"), "start": .string("2027-01-16")], &d) else { return XCTFail() }
        _ = run("create_job", ["title": .string("Call the county"), "start": .string("2027-01-16 09:00"), "is_task": .bool(true)], &d)
        XCTAssertTrue(d.jobs[1].isTask)
    }

    func testUpdateStatus() throws {
        var d = world()
        let j = try d.addJob(title: "Plow", start: now, now: now)
        guard case .text = run("update_job_status", ["job_id": .string(j.id.uuidString), "status": .string("done")], &d) else { return XCTFail() }
        XCTAssertEqual(d.jobs[0].status, .done)
        guard case .error = run("update_job_status", ["job_id": .string(j.id.uuidString), "status": .string("exploded")], &d) else { return XCTFail() }
        guard case .error = run("update_job_status", ["job_id": .string(UUID().uuidString), "status": .string("done")], &d) else { return XCTFail() }
    }

    func testAddClientNeverAssumesConsentAndChecksTheEmail() {
        var d = world()
        guard case .error = run("add_client", ["name": .string("Pat Miller")], &d) else { return XCTFail() }     // already a client
        guard case .error = run("add_client", ["name": .string("Kim"), "email": .string("not an email")], &d) else { return XCTFail() }
        guard case .text(let t) = run("add_client", ["name": .string("Kim Park"), "email": .string("kim@example.com"), "address": .string("5 Fifth Ave")], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("not agreed"))
        let kim = d.customers.first { $0.name == "Kim Park" }!
        XCTAssertFalse(kim.emailConsent); XCTAssertNil(kim.consentRecordedAt); XCTAssertFalse(kim.isLead)
        let site = d.sites.first { $0.customerID == kim.id }!
        XCTAssertNotNil(d.portalLinks.first { $0.siteID == site.id })                                   // their page link exists
        _ = run("add_client", ["name": .string("Lee Lead"), "is_lead": .bool(true)], &d)
        XCTAssertTrue(d.customers.first { $0.name == "Lee Lead" }!.isLead)
    }

    // MARK: sending needs a tap

    func testSendingAnInvoiceIsPreparedNeverDone() throws {
        var d = world()
        let inv = Invoice(number: "INV-7", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now.addingTimeInterval(86_400 * 14),
                          lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])
        d.invoices = [inv]
        let before = d
        guard case .needsConfirmation(let action, let said) = run("send_invoice", ["invoice_number": .string("inv-7")], &d) else { return XCTFail() }
        XCTAssertEqual(action.kind, .sendInvoice(number: "INV-7"))
        XCTAssertTrue(action.title.contains("Pat Miller")); XCTAssertTrue(action.detail.contains("pat@example.com"))
        XCTAssertTrue(said.contains("NOT been sent"))
        XCTAssertEqual(d, before)                                                                         // nothing changed: still a draft
        XCTAssertNil(d.invoices[0].sentAt)
    }

    func testSendingIsRefusedWhenTheClientDidNotAgreeOrThereIsNothingToSend() throws {
        var d = world()
        func make(_ n: String, _ c: Customer, _ s: Site) -> Invoice {
            Invoice(number: n, customerID: c.id, siteID: s.id, issueDate: now, dueDate: now, lines: [InvoiceLineItem(description: "x", amount: Money(cents: 500))])
        }
        var paid = make("INV-1", d.customers[0], d.sites[0])
        try paid.record(ManualPayment(amount: Money(cents: 500), date: now, method: .cash))
        var voided = make("INV-2", d.customers[0], d.sites[0]); voided.void()
        d.invoices = [paid, voided, make("INV-3", d.customers[1], d.sites[1])]             // Sam never agreed to emails
        for (n, words) in [("INV-1", "paid"), ("INV-2", "void"), ("INV-3", "agreed"), ("INV-99", "no invoice")] {
            guard case .error(let why) = run("send_invoice", ["invoice_number": .string(n)], &d) else { return XCTFail(n) }
            XCTAssertTrue(why.lowercased().contains(words), "\(n): \(why)")
        }
        d.customers[0].optedOutAt = now
        var again = make("INV-4", d.customers[0], d.sites[0]); again.notes = ""
        d.invoices.append(again)
        guard case .error = run("send_invoice", ["invoice_number": .string("INV-4")], &d) else { return XCTFail() }   // opted out always wins
    }

    func testHostToolsAreLeftToTheScreen() {
        var d = world()
        for n in ["plan_route", "get_weather", "create_invoice"] { XCTAssertEqual(run(n, [:], &d), .hostTool, n) }
    }

    // MARK: the conversation loop

    func testToolRoundTripKeepsThinkingBlocksAndReportsWhatWasDone() async throws {
        var d = world()
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [thinking, text("Let me set that up."), toolUse("tu_1", "create_job", ["title": .string("Plow"), "client_name": .string("Pat Miller"), "start": .string("2027-01-16 07:00")])], stopReason: "tool_use")),
            .success(AssistantReply(content: [thinking, text("Done. Plow is booked for Saturday at 7.")], stopReason: "end_turn")),
        ])
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("Book a plow for Pat Miller tomorrow at 7", history: &history, tools: AssistantTools.definitions(for: d),
                                                 context: "ctx", transport: transport) { call in AssistantTools.execute(call, data: &d, now: now, calendar: utc) }
        XCTAssertEqual(turn.text, "Done. Plow is booked for Saturday at 7.")
        XCTAssertEqual(d.jobs.count, 1)
        XCTAssertEqual(turn.actions.count, 1); XCTAssertTrue(turn.actions[0].hasPrefix("Created job"))
        // The second request carried the first answer back unchanged, thinking block and all, plus the tool result.
        let second = transport.sent[1]
        XCTAssertEqual(second.map(\.role), ["user", "assistant", "user"])
        XCTAssertEqual(second[1].content.first?["signature"]?.string, "sig-123")
        XCTAssertEqual(second[2].content.first?["type"]?.string, "tool_result")
        XCTAssertEqual(second[2].content.first?["tool_use_id"]?.string, "tu_1")
        XCTAssertEqual(history.count, 4)
    }

    func testAnInvoiceSendWaitsForAConfirmation() async throws {
        var d = world()
        d.invoices = [Invoice(number: "INV-7", customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now.addingTimeInterval(86_400),
                              lines: [InvoiceLineItem(description: "Push", amount: Money(cents: 6000))])]
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [toolUse("a", "send_invoice", ["invoice_number": .string("INV-7")])], stopReason: "tool_use")),
            .success(AssistantReply(content: [text("It is ready. Tap Send to email it to Pat.")], stopReason: "end_turn")),
        ])
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("Send INV-7", history: &history, tools: [], context: "", transport: transport) { call in
            AssistantTools.execute(call, data: &d, now: now, calendar: utc)
        }
        XCTAssertEqual(turn.pending.count, 1)
        XCTAssertEqual(turn.pending[0].kind, .sendInvoice(number: "INV-7"))
        XCTAssertNil(d.invoices[0].sentAt)
        let result = transport.sent[1].last!.content[0]["content"]?.string ?? ""
        XCTAssertTrue(result.contains("NOT been sent"))
    }

    func testRefusalsAreHandledPolitely() async throws {
        let transport = ScriptedTransport([.success(AssistantReply(content: [], stopReason: "refusal"))])
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertTrue(turn.refused); XCTAssertFalse(turn.text.isEmpty)
    }

    func testALoopingAssistantIsStopped() async throws {
        let again = AssistantReply(content: [toolUse("a", "get_schedule")], stopReason: "tool_use")
        let transport = ScriptedTransport(Array(repeating: .success(again), count: 10))
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .text("ok") }
        XCTAssertTrue(turn.stoppedEarly)
        XCTAssertEqual(transport.sent.count, AssistantRunner.maxSteps)
    }

    func testAFailedQuestionLeavesNoHalfFinishedTurn() async {
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [toolUse("a", "get_schedule")], stopReason: "tool_use")),
            .failure(AssistantError.busy("busy")),
        ])
        var history = [AssistantMessage.user("earlier"), AssistantMessage(role: "assistant", content: [text("ok")])]
        do { _ = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .text("ok") }; XCTFail() }
        catch { XCTAssertEqual(error as? AssistantError, .busy("busy")) }
        XCTAssertEqual(history.count, 2)                                                                  // back to how it was
    }

    func testAVeryLongChatAsksForAFreshOne() async {
        var history = Array(repeating: AssistantMessage.user("x"), count: AssistantRunner.maxMessages)
        do { _ = try await AssistantRunner.ask("y", history: &history, tools: [], context: "", transport: ScriptedTransport([])) { _ in .hostTool }; XCTFail() }
        catch { XCTAssertEqual(error as? AssistantError, .tooLong) }
    }

    func testContextHasNoClientDetails() throws {
        var d = world()
        let ctx = AssistantContext.make(data: d, now: now, calendar: utc)
        XCTAssertTrue(ctx.contains("Ridge Plow")); XCTAssertTrue(ctx.contains("Friday, January 15, 2027")); XCTAssertTrue(ctx.contains("business owner"))
        for secret in ["Pat Miller", "pat@example.com", "612", "Elm"] { XCTAssertFalse(ctx.contains(secret)) }
        let m = try addMember(&d, "Dana")
        d.session = AppSession(role: .employee, memberID: m.id, startedAt: now)
        XCTAssertTrue(AssistantContext.make(data: d, now: now, calendar: utc).contains("Crew member"))
    }

    // MARK: the server

    func testServerTransportSendsMessagesAndToolsAndReadsTheReply() async throws {
        let http = ScriptedHTTP()
        http.body = Data(#"{"content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","model":"m"}"#.utf8)
        let t = ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "tok", client: http)
        let reply = try await t.send(messages: [.user("Hi"), AssistantMessage(role: "assistant", content: [thinking])], tools: AssistantTools.definitions(for: world()), context: "ctx")
        XCTAssertEqual(reply.text, "Hello"); XCTAssertEqual(reply.stopReason, "end_turn")
        let req = http.requests[0]
        XCTAssertEqual(req.url?.path, "/v1/ai/chat"); XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = String(data: req.httpBody!, encoding: .utf8)!
        for needle in ["input_schema", "get_schedule", "sig-123", "\"context\":\"ctx\"", "\"role\":\"user\""] { XCTAssertTrue(body.contains(needle), needle) }
    }

    func testServerErrorsBecomeClearAssistantErrors() async {
        let http = ScriptedHTTP()
        let t = ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "tok", client: http)
        func fail(_ status: Int, _ body: String) async -> AssistantError? {
            http.status = 0
            let h = ScriptedHTTP(); h.status = status; h.body = Data(body.utf8)
            do { _ = try await ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: StatusHTTP(h)).send(messages: [.user("x")], tools: [], context: ""); return nil }
            catch { return error as? AssistantError }
        }
        _ = t
        let a = await fail(429, #"{"error":"The assistant has used this month's allowance. It starts again on the 1st."}"#)
        XCTAssertEqual(a, .limit("The assistant has used this month's allowance. It starts again on the 1st."))
        let b = await fail(429, #"{"error":"The assistant is busy. Try again in a minute."}"#)
        XCTAssertEqual(b, .busy("The assistant is busy. Try again in a minute."))
        let c1 = await fail(503, "{}"); XCTAssertEqual(c1, .notSwitchedOn)
        let c2 = await fail(401, "{}"); XCTAssertEqual(c2, .notAllowed)
        let c3 = await fail(502, #"{"error":"The assistant could not answer right now."}"#); XCTAssertEqual(c3, .server("The assistant could not answer right now."))
        let c4 = await fail(200, "not json"); XCTAssertEqual(c4, .unreadable)
    }

    func testStatusReportsAPercentNotDollars() async throws {
        let http = ScriptedHTTP()
        http.body = Data(#"{"enabled":true,"model":"x","usedPercent":42}"#.utf8)
        let s = try await ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: http).status()
        XCTAssertTrue(s.enabled); XCTAssertEqual(s.usedPercent, 42)
    }

    // MARK: consent

    func testConsentIsRecordedRevokedAndSurvivesSaving() throws {
        var d = AppData()
        XCTAssertFalse(d.assistantConsented)
        d.grantAssistantConsent(now: now)
        let again = now.addingTimeInterval(500)
        d.grantAssistantConsent(now: again)
        XCTAssertEqual(d.assistantConsentAt, now)                                                         // the first agreement stays on record
        let back = try JSONDecoder.iso.decode(AppData.self, from: JSONEncoder.iso.encode(d))
        XCTAssertTrue(back.assistantConsented)
        d.revokeAssistantConsent()
        XCTAssertFalse(d.assistantConsented)
        XCTAssertFalse(d.erasedCopy().assistantConsented)
    }
}

/// Lets a test reuse one scripted answer for a fresh transport.
private struct StatusHTTP: HTTPClient {
    let inner: ScriptedHTTP
    init(_ inner: ScriptedHTTP) { self.inner = inner }
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { try await inner.send(request) }
}

private extension Calendar {
    func component(from date: Date) -> Int { component(.hour, from: date) }
}
