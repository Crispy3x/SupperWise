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
                       ["get_schedule", "list_clients", "add_client", "create_job", "update_job_status", "list_invoices", "create_invoice", "send_invoice", "plan_route", "get_weather",
                        "record_payment", "get_revenue", "send_reminders", "list_requests", "answer_request", "send_season_links", "bill_finished_jobs"])
        XCTAssertLessThanOrEqual(AssistantTools.definitions(for: d).count, 20)
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

    func testUpdateStatusChangesOnlyOneVisitOfAJobThatRepeats() throws {
        var d = world()
        let j = try d.addJob(title: "Mow", start: now, now: now)
        try d.setJobRepeat(RepeatRule(frequency: .weekly), id: j.id, calendar: utc)
        let id = JSONValue.string(j.id.uuidString)
        let nextWeek = now.addingTimeInterval(7 * 86_400), inTwoWeeks = now.addingTimeInterval(14 * 86_400)
        // Without a date nothing is guessed and nothing changes.
        XCTAssertEqual(run("update_job_status", ["job_id": id, "status": .string("done")], &d), .error("This job repeats. Give the visit's date."))
        XCTAssertNil(d.jobs[0].occurrenceStatuses); XCTAssertEqual(d.jobs[0].status, .scheduled)
        // With the visit's date, only that visit changes. The job as a whole and every other visit stay as they were.
        guard case .text(let done) = run("update_job_status", ["job_id": id, "status": .string("done"), "date": .string("2027-01-15")], &d) else { return XCTFail() }
        XCTAssertTrue(done.contains("visit"), done)
        XCTAssertEqual(d.jobs[0].status, .scheduled)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: now, calendar: utc), .done)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: nextWeek, calendar: utc), .scheduled)
        // Cancelling skips that one visit, not the whole job.
        guard case .text(let skipped) = run("update_job_status", ["job_id": id, "status": .string("cancelled"), "date": .string("2027-01-22")], &d) else { return XCTFail() }
        XCTAssertTrue(skipped.contains("Skipped"), skipped)
        XCTAssertEqual(d.jobs[0].status, .scheduled)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: nextWeek, calendar: utc), .cancelled)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: inTwoWeeks, calendar: utc), .scheduled)
        XCTAssertEqual(d.jobs[0].occurrenceStatus(on: now, calendar: utc), .done)
        // A day with no visit, or something that is not a date, gets the same plain error.
        for bad in ["2027-01-18", "soon", " "] {
            XCTAssertEqual(run("update_job_status", ["job_id": id, "status": .string("done"), "date": .string(bad)], &d), .error("This job repeats. Give the visit's date."), bad)
        }
        XCTAssertEqual(d.jobs[0].occurrenceStatuses?.count, 2)
        // A job that happens once needs no date, and a date given anyway is ignored.
        let once = try d.addJob(title: "Salt", start: now, now: now)
        guard case .text = run("update_job_status", ["job_id": .string(once.id.uuidString), "status": .string("done"), "date": .string("2030-01-01")], &d) else { return XCTFail() }
        XCTAssertEqual(d.jobs[1].status, .done)
        // The schedule tells the assistant which jobs repeat, so it knows to give the day.
        guard case .text(let list) = run("get_schedule", ["date": .string("2027-01-29")], &d) else { return XCTFail() }
        XCTAssertTrue(list.contains("(repeats)"), list)
    }

    func testEveryToolHasASchemaTheAPIAccepts() {
        let tools = AssistantTools.definitions(for: world())
        XCTAssertEqual(Set(tools.map(\.name)).count, tools.count)                                    // no name twice
        for tool in tools {
            XCTAssertNotNil(tool.name.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression), tool.name)
            XCTAssertFalse(tool.description.isEmpty, tool.name)
            XCTAssertEqual(tool.inputSchema["type"]?.string, "object", tool.name)
            guard case .object(let properties)? = tool.inputSchema["properties"] else { XCTFail(tool.name); continue }
            for (key, value) in properties {
                XCTAssertTrue(["string", "integer", "number", "boolean"].contains(value["type"]?.string ?? ""), "\(tool.name).\(key)")
            }
            for needed in tool.inputSchema["required"]?.array ?? [] { XCTAssertNotNil(properties[needed.string ?? ""], "\(tool.name) requires an unknown field") }
        }
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
        for n in ["plan_route", "get_weather", "create_invoice", "send_reminders", "answer_request", "send_season_links"] { XCTAssertEqual(run(n, [:], &d), .hostTool, n) }
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
        XCTAssertTrue(history.isEmpty)                    // an empty refused answer is not kept: it would break the next question
    }

    // MARK: things that used to make the assistant go quiet

    /// True when the messages are something the API accepts: the two sides take turns, it ends on the person's side,
    /// nothing is empty, and every tool call is answered at the start of the very next message.
    private func assertValid(_ messages: [AssistantMessage], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(messages.first?.role, "user", file: file, line: line)
        XCTAssertEqual(messages.last?.role, "user", file: file, line: line)
        for (i, m) in messages.enumerated() {
            XCTAssertFalse(m.content.isEmpty, "message \(i) is empty", file: file, line: line)
            if i > 0 { XCTAssertNotEqual(m.role, messages[i - 1].role, "two \(m.role) messages in a row at \(i)", file: file, line: line) }
            for block in m.content where block["type"]?.string == "text" {
                XCTAssertFalse((block["text"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "empty text in message \(i)", file: file, line: line)
            }
            let asked = m.content.compactMap { $0["type"]?.string == "tool_use" ? $0["id"]?.string : nil }
            guard m.role == "assistant", !asked.isEmpty else { continue }
            guard i + 1 < messages.count else { XCTFail("tool call with no result", file: file, line: line); continue }
            let answers = messages[i + 1].content.prefix(asked.count).compactMap { $0["type"]?.string == "tool_result" ? $0["tool_use_id"]?.string : nil }
            XCTAssertEqual(Set(answers), Set(asked), "tool results must come first in the next message", file: file, line: line)
            for result in messages[i + 1].content where result["type"]?.string == "tool_result" {
                XCTAssertFalse((result["content"]?.string ?? "").isEmpty, "empty tool result", file: file, line: line)
            }
        }
    }

    func testAnEmptyAnswerIsNeverKept() async throws {
        let transport = ScriptedTransport([.success(AssistantReply(content: [], stopReason: "end_turn")),
                                           .success(AssistantReply(content: [thinking], stopReason: "end_turn")),
                                           .success(AssistantReply(content: [text("Here you go.")], stopReason: "end_turn"))])
        var history: [AssistantMessage] = []
        let first = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertTrue(first.stoppedEarly); XCTAssertFalse(first.text.isEmpty); XCTAssertTrue(history.isEmpty)
        let second = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertTrue(second.stoppedEarly); XCTAssertTrue(history.isEmpty)        // thinking alone is not an answer either
        let third = try await AssistantRunner.ask("y", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertEqual(third.text, "Here you go.")
        assertValid(transport.sent[2])
        XCTAssertEqual(history.map(\.role), ["user", "assistant"])
    }

    func testEmptyTextBlocksAreLeftOutButThinkingIsKeptExactly() async throws {
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [thinking, text(""), toolUse("a", "get_schedule"), text("  ")], stopReason: "tool_use")),
            .success(AssistantReply(content: [thinking, text("Nothing today.")], stopReason: "end_turn")),
        ])
        var history: [AssistantMessage] = []
        _ = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .text("Nothing is scheduled for that day.") }
        XCTAssertEqual(history[1].content, [thinking, toolUse("a", "get_schedule")])
        assertValid(transport.sent[1])
        // Text that comes before a thinking block is part of what Claude signed, so it is never touched.
        XCTAssertEqual(AssistantRunner.cleaned([text(""), thinking, text("Hi")]), [text(""), thinking, text("Hi")])
    }

    func testACutOffAnswerIsDroppedWithAClearMessage() async throws {
        let transport = ScriptedTransport([.success(AssistantReply(content: [thinking], stopReason: "max_tokens"))])
        var history = [AssistantMessage.user("earlier"), AssistantMessage(role: "assistant", content: [text("ok")])]
        let turn = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertTrue(turn.stoppedEarly); XCTAssertTrue(turn.text.contains("smaller steps"))
        XCTAssertEqual(history.count, 2)
    }

    func testAFailureAfterAChangeKeepsTheChangeAndTheNextQuestionStillWorks() async throws {
        var d = world()
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [thinking, toolUse("tu_1", "create_job", ["title": .string("Plow"), "client_name": .string("Pat Miller"), "start": .string("2027-01-16 07:00")])], stopReason: "tool_use")),
            .failure(AssistantError.busy("Claude is busy right now. Try again in a minute.")),
            .success(AssistantReply(content: [text("Yes, the plow is booked.")], stopReason: "end_turn")),
        ])
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("Book a plow for Pat Miller", history: &history, tools: [], context: "", transport: transport) { call in
            AssistantTools.execute(call, data: &d, now: now, calendar: utc)
        }
        // The job exists, so the turn is reported (with what went wrong) instead of thrown away and asked again.
        XCTAssertEqual(d.jobs.count, 1)
        XCTAssertEqual(turn.problem, .busy("Claude is busy right now. Try again in a minute."))
        XCTAssertEqual(turn.actions.count, 1)
        XCTAssertEqual(history.map(\.role), ["user", "assistant", "user"])
        // The next question joins the unanswered tool results, after them, so the two sides still take turns.
        let next = try await AssistantRunner.ask("Did that work?", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertEqual(next.text, "Yes, the plow is booked.")
        let sent = transport.sent[2]
        assertValid(sent)
        XCTAssertEqual(sent.map(\.role), ["user", "assistant", "user"])
        XCTAssertEqual(sent[2].content.first?["type"]?.string, "tool_result")
        XCTAssertEqual(sent[2].content.last?["text"]?.string, "Did that work?")
        XCTAssertEqual(d.jobs.count, 1)                                                                   // nothing was done twice
        XCTAssertEqual(history.map(\.role), ["user", "assistant", "user", "assistant"])
    }

    func testAConversationClaudeNoLongerAcceptsIsSentOnceMoreWithoutThinking() async throws {
        let mismatch = "messages.1.content.0: Invalid `signature` in `thinking` block. The block is bound to a different conversation."
        let transport = ScriptedTransport([.failure(AssistantError.conversation(mismatch)),
                                           .success(AssistantReply(content: [thinking, text("Two jobs today.")], stopReason: "end_turn"))])
        var history = [AssistantMessage.user("earlier"), AssistantMessage(role: "assistant", content: [thinking, text("ok")]),
                       AssistantMessage.user("and"), AssistantMessage(role: "assistant", content: [thinking])]
        let turn = try await AssistantRunner.ask("What is on today?", history: &history, tools: [], context: "", transport: transport) { _ in .hostTool }
        XCTAssertEqual(turn.text, "Two jobs today.")
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertTrue(transport.sent[0].contains { $0.content.contains(thinking) })
        XCTAssertFalse(transport.sent[1].contains { $0.content.contains(thinking) })                       // the old thinking is gone
        XCTAssertEqual(transport.sent[1][1].content, [text("ok")])                                          // the words stay
        assertValid(transport.sent[1])
        XCTAssertEqual(history.last?.content, [thinking, text("Two jobs today.")])                          // new thinking is kept as usual
        // Any other refusal of the conversation is passed up (the screen then starts a fresh chat).
        let other = ScriptedTransport([.failure(AssistantError.conversation("messages: roles must alternate"))])
        do { _ = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: other) { _ in .hostTool }; XCTFail() }
        catch { XCTAssertEqual(error as? AssistantError, .conversation("messages: roles must alternate")) }
        XCTAssertEqual(other.sent.count, 1)
    }

    func testToolResultsAreNeverEmptyAndLongOnesAreCut() async throws {
        let transport = ScriptedTransport([
            .success(AssistantReply(content: [toolUse("a", "get_schedule"), toolUse("b", "list_clients"), .object(["type": .string("tool_use"), "id": .string("c")])], stopReason: "tool_use")),
            .success(AssistantReply(content: [text("ok")], stopReason: "end_turn")),
        ])
        var history: [AssistantMessage] = []
        _ = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { call in
            call.name == "get_schedule" ? .text("") : .text(String(repeating: "line\n", count: 5000))
        }
        let results = transport.sent[1].last!.content
        assertValid(transport.sent[1])                                                                     // the nameless call got an answer too
        XCTAssertEqual(results.count, 3)
        for r in results {
            let body = r["content"]?.string ?? ""
            XCTAssertFalse(body.isEmpty)
            XCTAssertLessThan(body.count, AssistantRunner.maxToolResultCharacters + 300)
        }
        XCTAssertTrue(results.contains { $0["tool_use_id"]?.string == "c" && $0["is_error"]?.bool == true })
    }

    func testAQuestionAlwaysFitsWhatTheServerAccepts() {
        // The server refuses more than 80 messages (older ones) and the runner refuses to start at maxMessages.
        XCTAssertLessThanOrEqual(AssistantRunner.maxMessages - 1 + 1 + 2 * AssistantRunner.maxSteps, 80)
    }

    func testALoopingAssistantIsStopped() async throws {
        let again = AssistantReply(content: [toolUse("a", "get_schedule")], stopReason: "tool_use")
        let transport = ScriptedTransport(Array(repeating: .success(again), count: 10))
        var history: [AssistantMessage] = []
        let turn = try await AssistantRunner.ask("x", history: &history, tools: [], context: "", transport: transport) { _ in .text("ok") }
        var ran = 0
        XCTAssertTrue(turn.stoppedEarly)
        XCTAssertEqual(transport.sent.count, AssistantRunner.maxSteps)
        XCTAssertTrue(turn.text.contains("ran out of steps"))                                             // said plainly, never silent
        // The assistant is warned before its last step, and nothing is run after the limit.
        let warned = transport.sent[AssistantRunner.maxSteps - 1].last!.content
        XCTAssertEqual(warned.first?["type"]?.string, "tool_result")                                      // results first, then the note
        XCTAssertTrue(warned.last?["text"]?.string?.contains("one step is left") ?? false)
        let again2 = AssistantReply(content: [toolUse("a", "create_job")], stopReason: "tool_use")
        let looping = ScriptedTransport(Array(repeating: .success(again2), count: 10))
        var h2: [AssistantMessage] = []
        _ = try await AssistantRunner.ask("x", history: &h2, tools: [], context: "", transport: looping) { _ in ran += 1; return .error("no") }
        XCTAssertEqual(ran, AssistantRunner.maxSteps - 1)
        XCTAssertEqual(h2.last?.content.first?["is_error"]?.bool, true)
        // What is left behind is still a conversation the API accepts once the next question is added.
        let after = ScriptedTransport([.success(AssistantReply(content: [text("ok")], stopReason: "end_turn"))])
        _ = try await AssistantRunner.ask("continue", history: &h2, tools: [], context: "", transport: after) { _ in .hostTool }
        assertValid(after.sent[0])
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
        let ctx = AssistantContext.make(data: d)
        XCTAssertTrue(ctx.contains("Ridge Plow")); XCTAssertTrue(ctx.contains("business owner"))
        for secret in ["Pat Miller", "pat@example.com", "612", "Elm"] { XCTAssertFalse(ctx.contains(secret)) }
        let m = try addMember(&d, "Dana")
        d.session = AppSession(role: .employee, memberID: m.id, startedAt: now)
        XCTAssertTrue(AssistantContext.make(data: d).contains("Crew member"))
    }

    func testTheTimeTravelsWithTheQuestionSoTheSystemPromptNeverChanges() throws {
        // Claude refuses a conversation whose system prompt changed after it answered, so nothing in it may depend on the clock.
        let ctx = AssistantContext.make(data: world())
        for clock in ["2027", "January", "Friday", "AM", "PM", "Now:"] { XCTAssertFalse(ctx.contains(clock), clock) }
        let q = AssistantContext.question("What is on tomorrow?", updates: ["[Update: the owner tapped Send and invoice INV-7 was emailed.]"], now: now, calendar: utc)
        XCTAssertEqual(q, "[Now: Friday, January 15, 2027, 8:00 AM (\(utc.timeZone.identifier))]\n[Update: the owner tapped Send and invoice INV-7 was emailed.]\nWhat is on tomorrow?")
        XCTAssertTrue(AssistantPrompt.system.contains("square brackets"))                                  // and the assistant is told what that line is
        // The same conversation is always sent as the same bytes, for the server and for a direct key.
        let messages = [AssistantMessage.user(q), AssistantMessage(role: "assistant", content: [thinking, toolUse("a", "create_job", ["title": .string("Plow"), "price": .number(45.5), "duration_minutes": .number(60)])])]
        let tools = AssistantTools.definitions(for: world())
        let server = ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: ScriptedHTTP())
        XCTAssertEqual(try server.body(messages: messages, tools: tools, context: ctx), try server.body(messages: messages, tools: tools, context: ctx))
        let direct = DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: ScriptedHTTP())
        let one = try direct.body(messages: messages, tools: tools, context: ctx), two = try direct.body(messages: messages, tools: tools, context: ctx)
        XCTAssertEqual(one, two)
        let sent = try JSONDecoder().decode(JSONValue.self, from: one)
        XCTAssertEqual(sent["system"]?.string, AssistantPrompt.withContext(ctx))
        XCTAssertEqual(sent["messages"]?.array?.last?["content"]?.array?.first, thinking)
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
        let c1 = await fail(503, #"{"error":"The assistant is not switched on for this server."}"#); XCTAssertEqual(c1, .notSwitchedOn)
        // A 503 that is not ours (the host is waking the server up) is "try again", never "not switched on".
        let c0 = await fail(503, "<html>Service Unavailable</html>")
        guard case .busy(let waking)? = c0 else { return XCTFail("\(String(describing: c0))") }
        XCTAssertTrue(waking.contains("minute"))
        let c5 = await fail(502, "<html>Bad Gateway</html>")
        guard case .busy? = c5 else { return XCTFail("\(String(describing: c5))") }
        let c6 = await fail(413, #"{"error":"Request too large"}"#); XCTAssertEqual(c6, .tooLong)
        let c7 = await fail(400, #"{"error":"messages must be a list of 1 to 120","tooLong":true}"#); XCTAssertEqual(c7, .tooLong)
        let c8 = await fail(400, #"{"error":"message content must be text or a list of blocks","conversation":true}"#)
        XCTAssertEqual(c8, .conversation("message content must be text or a list of blocks"))
        let c9 = await fail(404, #"{"error":"Not found"}"#)
        guard case .server(let missing)? = c9 else { return XCTFail("\(String(describing: c9))") }
        XCTAssertTrue(missing.contains("no assistant"))
        let c2 = await fail(401, "{}"); XCTAssertEqual(c2, .notAllowed)
        let c3 = await fail(502, #"{"error":"The assistant could not answer right now."}"#); XCTAssertEqual(c3, .server("The assistant could not answer right now."))
        let c4 = await fail(200, "not json"); XCTAssertEqual(c4, .unreadable)
    }

    func testAFailedConnectionSaysWhatHappened() async {
        func fail(_ code: URLError.Code) async -> String {
            do { _ = try await DirectAssistantTransport(apiKey: "sk-ant-test-0123456789abc", client: Offline(code: code)).send(messages: [.user("x")], tools: [], context: ""); return "" }
            catch { if case AssistantError.network(let m) = error { return m }; return "wrong error: \(error)" }
        }
        let offline = await fail(.notConnectedToInternet), slow = await fail(.timedOut)
        XCTAssertTrue(offline.contains("offline"), offline)
        XCTAssertTrue(slow.contains("too long"), slow)
        do { _ = try await ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: Offline(code: .cannotFindHost)).send(messages: [.user("x")], tools: [], context: ""); XCTFail() }
        catch { guard case AssistantError.network(let m) = error else { return XCTFail("\(error)") }; XCTAssertTrue(m.contains("assistant server"), m) }
    }

    func testStatusReportsAPercentNotDollars() async throws {
        let http = ScriptedHTTP()
        http.body = Data(#"{"enabled":true,"model":"x","usedPercent":42}"#.utf8)
        let s = try await ServerAssistantTransport(baseURL: URL(string: "https://example.com")!, token: "t", client: http).status()
        XCTAssertTrue(s.enabled); XCTAssertEqual(s.usedPercent, 42)
    }

    // MARK: money, requests

    private func invoiced(_ d: inout AppData, number: String = "INV-5", cents: Int = 10_000) throws {
        d.invoices.append(Invoice(number: number, customerID: d.customers[0].id, siteID: d.sites[0].id, issueDate: now, dueDate: now.addingTimeInterval(86_400),
                                  lines: [InvoiceLineItem(description: "Push", amount: Money(cents: cents))]))
    }

    func testRecordingAPaymentChecksTheAmountAndTheInvoice() throws {
        var d = world(); try invoiced(&d)
        guard case .text(let part) = run("record_payment", ["invoice_number": .string("inv-5"), "amount": .number(40.5), "method": .string("check")], &d) else { return XCTFail() }
        XCTAssertTrue(part.contains("$40.50")); XCTAssertTrue(part.contains("$59.50 is still owed"))
        XCTAssertEqual(d.invoices[0].payments.count, 1); XCTAssertEqual(d.invoices[0].payments[0].method, .check)
        guard case .error(let over) = run("record_payment", ["invoice_number": .string("INV-5"), "amount": .number(100)], &d) else { return XCTFail() }
        XCTAssertTrue(over.contains("$59.50"))
        guard case .error = run("record_payment", ["invoice_number": .string("INV-5"), "amount": .number(0)], &d) else { return XCTFail() }
        guard case .error = run("record_payment", ["invoice_number": .string("INV-5"), "amount": .number(-5)], &d) else { return XCTFail() }
        guard case .text(let full) = run("record_payment", ["invoice_number": .string("INV-5"), "method": .string("nonsense")], &d) else { return XCTFail() }
        XCTAssertTrue(full.contains("paid in full")); XCTAssertEqual(d.invoices[0].payments.last?.method, .other)
        guard case .error(let again) = run("record_payment", ["invoice_number": .string("INV-5")], &d) else { return XCTFail() }
        XCTAssertTrue(again.contains("already paid"))
        guard case .error = run("record_payment", ["invoice_number": .string("INV-404")], &d) else { return XCTFail() }
        var v = world(); try invoiced(&v); v.invoices[0].void()
        guard case .error(let voided) = run("record_payment", ["invoice_number": .string("INV-5")], &v) else { return XCTFail() }
        XCTAssertTrue(voided.contains("void"))
    }

    func testRevenueAnswersInPlainText() throws {
        var d = world(); try invoiced(&d)
        _ = run("record_payment", ["invoice_number": .string("INV-5"), "amount": .number(25)], &d)
        guard case .text(let t) = run("get_revenue", ["period": .string("allTime")], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("$25.00")); XCTAssertTrue(t.contains("INV-5"))
        guard case .text(let none) = run("get_revenue", ["period": .string("garbage")], &d) else { return XCTFail() }
        XCTAssertTrue(none.contains("This Month"))                                                          // an unknown period falls back to this month
    }

    func testRequestsAreListedWithTheirIds() {
        var d = world()
        guard case .text(let empty) = run("list_requests", [:], &d) else { return XCTFail() }
        XCTAssertEqual(empty, "Nothing is waiting.")
        let r = ServiceRequest(siteID: d.sites[0].id, kind: .thanks, note: "Thanks for the early plow!", createdAt: now)
        d.serviceRequests = [r]
        guard case .text(let t) = run("list_requests", [:], &d) else { return XCTFail() }
        XCTAssertTrue(t.contains("thanks")); XCTAssertTrue(t.contains("14 Elm Ave")); XCTAssertTrue(t.contains(r.id.uuidString))
    }

    func testRecordingPaymentsNeedsRevenuePermission() throws {
        var d = world(); try invoiced(&d)
        let crew = try addMember(&d, "Dana")
        d.session = AppSession(role: .employee, memberID: crew.id, startedAt: now)
        guard case .error = run("record_payment", ["invoice_number": .string("INV-5")], &d) else { return XCTFail() }
        XCTAssertTrue(d.invoices[0].payments.isEmpty)
        XCTAssertEqual(run("send_reminders", [:], &d), .error("This person is not allowed to do that. Say so and do not try another way."))
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

/// A connection that fails before any answer arrives.
private struct Offline: HTTPClient, @unchecked Sendable {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { throw URLError(code) }
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
