import Foundation

public struct ToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    public let input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Something the assistant prepared that only a person can finish, such as emailing an invoice to a client.
public struct PendingAction: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case sendInvoice(number: String) }
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let detail: String

    public init(id: UUID = UUID(), kind: Kind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public enum ToolOutcome: Equatable, Sendable {
    case text(String)
    case error(String)
    /// Prepared, not done. The text goes back to the assistant; the action waits for the person to confirm.
    case needsConfirmation(PendingAction, String)
    /// This tool needs the screen's own machinery (route planning, weather, invoice creation).
    case hostTool
}

public enum InvoiceEmailPlan: Equatable, Sendable {
    case ready(PlannedMessage)
    case problem(String)
}

extension AppData {
    /// The email for an invoice, or the plain reason it cannot be sent. Same rules as automatic invoices: the client
    /// must have agreed to messages, must not have opted out, and needs a valid address.
    public func invoiceEmail(number: String, calendar: Calendar = .current) -> InvoiceEmailPlan {
        guard let invoice = invoices.first(where: { $0.number.caseInsensitiveCompare(number) == .orderedSame }) else { return .problem("There is no invoice \(number).") }
        guard !invoice.isVoid else { return .problem("Invoice \(invoice.number) is void.") }
        guard invoice.balance.cents > 0 else { return .problem("Invoice \(invoice.number) is already paid.") }
        guard let customer = customers.first(where: { $0.id == invoice.customerID }), let site = sites.first(where: { $0.id == invoice.siteID }) else {
            return .problem("Invoice \(invoice.number) has no client on file.")
        }
        guard customer.optedOutAt == nil, customer.emailConsent else { return .problem("\(customer.name) has not agreed to emails, so it cannot be emailed. You can send it another way and mark it sent in Invoices.") }
        guard ContactValidation.isValidEmail(customer.email) else { return .problem("\(customer.name) has no valid email address.") }
        let base = broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = portalLinks.first { $0.siteID == site.id }?.token
        let portal = (RoutingServerSettings.validatedURL(base) != nil && token != nil) ? "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/c/\(token!)" : nil
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your snow crew" : companyName
        return .ready(InvoiceMessage.compose(invoice: invoice, customer: customer, site: site, company: company, portalURL: portal,
                                             howToPay: profile.paymentInstructions, payLink: profile.payLink, calendar: calendar))
    }
}

/// The things the assistant can do. Each tool checks what the signed-in person is allowed to do, so the assistant can
/// never do more than the person could do themselves. Anything that reaches a client waits for a tap.
public enum AssistantTools {
    private static func schema(_ props: [String: (String, String)], required: [String] = []) -> JSONValue {
        .object(["type": .string("object"),
                 "properties": .object(props.mapValues { .object(["type": .string($0.0), "description": .string($0.1)]) }),
                 "required": .array(required.map { .string($0) }),
                 "additionalProperties": .bool(false)])
    }

    private static let all: [(tool: AssistantTool, needs: Permission?)] = [
        (AssistantTool(name: "get_schedule", description: "List the jobs and tasks scheduled for one day, with their ids.",
                       inputSchema: schema(["date": ("string", "The day as YYYY-MM-DD. Leave out for today.")])), nil),
        (AssistantTool(name: "list_clients", description: "Find clients by name or address. Returns names, addresses and whether they are leads. Contact details are not included.",
                       inputSchema: schema(["query": ("string", "Part of a name or address. Leave out to list the first few.")])), .viewClients),
        (AssistantTool(name: "add_client", description: "Add a client or lead. Nobody is assumed to have agreed to messages.",
                       inputSchema: schema(["name": ("string", "Full name"), "phone": ("string", "Phone number"), "email": ("string", "Email address"),
                                            "address": ("string", "Service address"), "is_lead": ("boolean", "True if they are only asking about service")], required: ["name"])), .editClients),
        (AssistantTool(name: "create_job", description: "Schedule a job, or a reminder or task. The job goes on the route only if its site has a map location.",
                       inputSchema: schema(["title": ("string", "What to do, for example Plow and salt"),
                                            "client_name": ("string", "An existing client's name"), "address": ("string", "Which of the client's addresses, if they have more than one"),
                                            "start": ("string", "When, as YYYY-MM-DD HH:mm in local time (24 hour). A date alone means 8:00 AM."),
                                            "duration_minutes": ("integer", "How long, default 60"), "assignee": ("string", "A team member's name"),
                                            "notes": ("string", "Extra instructions"), "is_task": ("boolean", "True for a reminder or task with no site")], required: ["title", "start"])), .editJobs),
        (AssistantTool(name: "update_job_status", description: "Change a job's status. Get the id from get_schedule.",
                       inputSchema: schema(["job_id": ("string", "The job id"), "status": ("string", "scheduled, inProgress, done or cancelled")], required: ["job_id", "status"])), .logVisits),
        (AssistantTool(name: "list_invoices", description: "List invoices with client, total, balance and due date.",
                       inputSchema: schema(["filter": ("string", "unpaid, overdue, draft or all. Default unpaid.")])), .viewRevenue),
        (AssistantTool(name: "create_invoice", description: "Create a draft invoice for a client's storms that have not been billed yet. It is a draft and is not sent.",
                       inputSchema: schema(["client_name": ("string", "An existing client's name")], required: ["client_name"])), .viewRevenue),
        (AssistantTool(name: "send_invoice", description: "Prepare to email an invoice to the client. The person must confirm in the app before anything is sent, so never say it was sent.",
                       inputSchema: schema(["invoice_number": ("string", "For example INV-0003")], required: ["invoice_number"])), .viewRevenue),
        (AssistantTool(name: "plan_route", description: "Put one day's jobs in the quickest driving order using Apple Maps drive times. Returns the order and the total driving time.",
                       inputSchema: schema(["date": ("string", "The day as YYYY-MM-DD. Leave out for today.")])), nil),
        (AssistantTool(name: "get_weather", description: "The latest forecast for the yard: snowfall, low temperature, wind and any winter alerts. Says if it has not been loaded.",
                       inputSchema: schema([:])), nil),
    ]

    /// Only the tools this person may use, so the assistant is never offered something it would be refused.
    public static func definitions(for data: AppData) -> [AssistantTool] {
        all.filter { $0.needs.map(data.can) ?? true }.map(\.tool)
    }

    static func permission(for name: String) -> Permission?? {
        all.first { $0.tool.name == name }.map { $0.needs }
    }

    // MARK: running a tool

    public static func execute(_ call: ToolCall, data: inout AppData, now: Date, calendar: Calendar = .current) -> ToolOutcome {
        guard let needs = permission(for: call.name) else { return .error("There is no tool called \(call.name).") }
        if let needs, !data.can(needs) { return .error("This person is not allowed to do that. Say so and do not try another way.") }
        switch call.name {
        case "get_schedule": return schedule(call.input, data, now, calendar)
        case "list_clients": return listClients(call.input, data)
        case "add_client": return addClient(call.input, &data, now)
        case "create_job": return createJob(call.input, &data, now, calendar)
        case "update_job_status": return updateStatus(call.input, &data)
        case "list_invoices": return listInvoices(call.input, data, now)
        case "send_invoice": return prepareSend(call.input, data, calendar)
        default: return .hostTool                  // plan_route, get_weather, create_invoice
        }
    }

    // MARK: pieces

    public static func day(from text: String?, now: Date, calendar: Calendar) -> Date? {
        guard let text, !text.isEmpty else { return now }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }

    static func moment(from text: String, calendar: Calendar) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: text.trimmingCharacters(in: .whitespaces)) {
                return format == "yyyy-MM-dd" ? calendar.date(bySettingHour: 8, minute: 0, second: 0, of: d) : d
            }
        }
        return nil
    }

    static func describe(_ d: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE MMM d, h:mm a"
        return f.string(from: d)
    }

    static func schedule(_ input: JSONValue, _ data: AppData, _ now: Date, _ calendar: Calendar) -> ToolOutcome {
        guard let d = day(from: input["date"]?.string, now: now, calendar: calendar) else { return .error("Use a date like 2026-11-20.") }
        let jobs = data.jobs(on: d, calendar: calendar)
        if jobs.isEmpty { return .text("Nothing is scheduled for that day.") }
        let lines = jobs.prefix(30).map { j -> String in
            let who = data.customerName(forJob: j), place = data.address(forJob: j)
            let people = data.team.filter { j.assigneeIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
            return "- \(describe(j.start, calendar: calendar)) | \(j.title)\(j.isTask ? " (task)" : "") | \(j.status.rawValue)"
                + (who.isEmpty ? "" : " | client: \(who)") + (place.isEmpty ? "" : " | \(place)") + (people.isEmpty ? "" : " | team: \(people)") + " | id: \(j.id.uuidString)"
        }
        return .text(lines.joined(separator: "\n"))
    }

    static func listClients(_ input: JSONValue, _ data: AppData) -> ToolOutcome {
        let q = (input["query"]?.string ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let list = data.customers.filter { c in
            q.isEmpty || c.name.lowercased().contains(q) || data.sites.contains { $0.customerID == c.id && $0.address.lowercased().contains(q) }
        }
        if list.isEmpty { return .text("No clients match.") }
        let lines = list.prefix(15).map { c -> String in
            let places = data.sites.filter { $0.customerID == c.id }.map(\.address).joined(separator: "; ")
            return "- \(c.name)\(c.isLead ? " (lead)" : "")" + (places.isEmpty ? " | no address yet" : " | \(places)")
        }
        return .text(lines.joined(separator: "\n") + (list.count > 15 ? "\n(\(list.count - 15) more not shown.)" : ""))
    }

    /// Finds one client by name. Ambiguity is an answer, not a guess.
    public static func client(named name: String, in data: AppData) -> (Customer?, String?) {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return (nil, "Which client?") }
        if let exact = data.customers.filter({ $0.name.lowercased() == q }).onlyElement { return (exact, nil) }
        let partial = data.customers.filter { $0.name.lowercased().contains(q) }
        if partial.count == 1 { return (partial[0], nil) }
        if partial.isEmpty { return (nil, "No client is called \(name).") }
        return (nil, "More than one client matches \(name): \(partial.prefix(5).map(\.name).joined(separator: ", ")). Ask which one.")
    }

    static func addClient(_ input: JSONValue, _ data: inout AppData, _ now: Date) -> ToolOutcome {
        let name = (input["name"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .error("A name is needed.") }
        guard !data.customers.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return .error("\(name) is already a client.") }
        let email = (input["email"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        guard email.isEmpty || ContactValidation.isValidEmail(email) else { return .error("That email address does not look right.") }
        let c = Customer(name: String(name.prefix(80)), phone: String((input["phone"]?.string ?? "").prefix(40)), email: email,
                         isLead: input["is_lead"]?.bool ?? false)
        data.customers.append(c)
        let address = (input["address"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            data.sites.append(Site(customerID: c.id, address: String(address.prefix(200)), priority: 3, triggerInches: data.profile.defaultTriggerInches))
            data.ensurePortalLinks(now: now)
        }
        return .text("Added \(c.name)\(c.isLead ? " as a lead" : "")." + (address.isEmpty ? "" : " The address has no map location or pricing yet; the owner sets those in Clients.")
                     + " They have not agreed to messages.")
    }

    static func createJob(_ input: JSONValue, _ data: inout AppData, _ now: Date, _ calendar: Calendar) -> ToolOutcome {
        guard let title = input["title"]?.string, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return .error("A job title is needed.") }
        guard let startText = input["start"]?.string, let start = moment(from: startText, calendar: calendar) else { return .error("Give the start as YYYY-MM-DD HH:mm.") }
        let isTask = input["is_task"]?.bool ?? false
        var customerID: UUID?, siteID: UUID?
        if !isTask, let n = input["client_name"]?.string, !n.isEmpty {
            let (c, problem) = client(named: n, in: data)
            guard let c else { return .error(problem ?? "No such client.") }
            customerID = c.id
            let sites = data.sites.filter { $0.customerID == c.id }
            if let a = input["address"]?.string, !a.isEmpty {
                let matches = sites.filter { AppData.normalizedAddress($0.address).contains(AppData.normalizedAddress(a)) }
                guard let s = matches.onlyElement else { return .error(matches.isEmpty ? "\(c.name) has no address like \(a)." : "More than one address matches. Ask which.") }
                siteID = s.id
            } else if let only = sites.onlyElement {
                siteID = only.id
            } else if sites.count > 1 {
                return .error("\(c.name) has \(sites.count) addresses: \(sites.map(\.address).joined(separator: "; ")). Ask which one.")
            }
        }
        var assignees: [UUID] = []
        if let a = input["assignee"]?.string, !a.isEmpty {
            let matches = data.team.filter { $0.status != .disabled && $0.name.lowercased().contains(a.lowercased()) }
            guard let m = matches.onlyElement else { return .error(matches.isEmpty ? "No team member is called \(a)." : "More than one team member matches \(a).") }
            assignees = [m.id]
        }
        do {
            let job = try data.addJob(title: title, kind: .other, customerID: customerID, siteID: siteID, start: start,
                                      durationMinutes: input["duration_minutes"]?.int ?? 60, assigneeIDs: assignees,
                                      notes: input["notes"]?.string ?? "", isTask: isTask, now: now)
            let place = data.address(forJob: job)
            return .text("Created \(isTask ? "task" : "job") \"\(job.title)\" for \(describe(job.start, calendar: calendar))"
                         + (place.isEmpty ? "" : " at \(place)") + (isTask || siteID != nil ? "" : ". It has no site, so it will not appear on the route") + ". id: \(job.id.uuidString)")
        } catch { return .error("The job could not be created.") }
    }

    static func updateStatus(_ input: JSONValue, _ data: inout AppData) -> ToolOutcome {
        guard let idText = input["job_id"]?.string, let id = UUID(uuidString: idText), let raw = input["status"]?.string, let status = JobStatus(rawValue: raw) else {
            return .error("Give the job id from get_schedule and a status of scheduled, inProgress, done or cancelled.")
        }
        guard data.visibleJobs.contains(where: { $0.id == id }) else { return .error("That job was not found.") }
        do { try data.setJobStatus(status, id: id); return .text("Marked it \(status.title.lowercased()).") } catch { return .error("That job was not found.") }
    }

    static func listInvoices(_ input: JSONValue, _ data: AppData, _ now: Date) -> ToolOutcome {
        let filter = input["filter"]?.string ?? "unpaid"
        let list = data.invoices.filter { inv in
            guard !inv.isVoid else { return false }
            switch filter {
            case "all": return true
            case "draft": return inv.sentAt == nil
            case "overdue": return inv.sentAt != nil && inv.status(now: now) == .overdue
            default: return inv.sentAt != nil && inv.balance.cents > 0
            }
        }
        if list.isEmpty { return .text("No \(filter == "all" ? "" : filter + " ")invoices.") }
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.locale = Locale(identifier: "en_US_POSIX")
        let lines = list.prefix(20).map { inv in
            "- \(inv.number) | \(data.customers.first { $0.id == inv.customerID }?.name ?? "?") | total \(inv.total.formatted) | balance \(inv.balance.formatted) | due \(f.string(from: inv.dueDate)) | \(inv.sentAt == nil ? "draft" : inv.status(now: now).rawValue)"
        }
        return .text(lines.joined(separator: "\n") + (list.count > 20 ? "\n(\(list.count - 20) more not shown.)" : ""))
    }

    static func prepareSend(_ input: JSONValue, _ data: AppData, _ calendar: Calendar) -> ToolOutcome {
        guard let number = input["invoice_number"]?.string, !number.isEmpty else { return .error("Which invoice number?") }
        switch data.invoiceEmail(number: number, calendar: calendar) {
        case .problem(let why): return .error(why)
        case .ready(let message):
            let inv = data.invoices.first { $0.number.caseInsensitiveCompare(number) == .orderedSame }!
            let who = data.customers.first { $0.id == inv.customerID }?.name ?? "the client"
            let action = PendingAction(kind: .sendInvoice(number: inv.number), title: "Email invoice \(inv.number) to \(who)?",
                                       detail: "\(inv.total.formatted) due \(DateFormatter.shortDate(inv.dueDate)). Goes to \(message.to).")
            return .needsConfirmation(action, "Prepared invoice \(inv.number) for \(who). It has NOT been sent. The owner must tap Send in the app to confirm. Tell them it is ready and waiting.")
        }
    }
}

extension Array {
    var onlyElement: Element? { count == 1 ? self[0] : nil }
}

extension DateFormatter {
    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"; return f.string(from: d)
    }
}
