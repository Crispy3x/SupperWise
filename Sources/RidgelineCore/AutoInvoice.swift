import Foundation

public struct AutoInvoiceOutcome: Equatable, Sendable {
    /// The invoice created (also saved in the data), or nil if nothing was due.
    public let invoice: Invoice?
    /// The email to send, only in "send" mode for a client who agreed to messages. After it really goes out, call `markInvoiceSent`.
    public let message: PlannedMessage?
    /// A plain sentence for the owner about what happened.
    public let note: String
}

public enum InvoiceMessage {
    /// The invoice email. It says how to pay in the owner's own words and, if set, adds the owner's own payment link.
    public static func compose(invoice: Invoice, customer: Customer, site: Site, company: String, portalURL: String?,
                               howToPay: String, payLink: String? = nil, calendar: Calendar = .current) -> PlannedMessage {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        var lines = ["Hello \(customer.name),", "", "Here is your invoice from \(company) for \(site.address).", ""]
        for l in invoice.lines { lines.append("\(l.description): \(l.amount.formatted)") }
        lines.append("")
        lines.append("Total due: \(invoice.total.formatted) by \(f.string(from: invoice.dueDate)). A PDF copy of this invoice is attached.")
        let pay = howToPay.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pay.isEmpty { lines.append("How to pay: \(pay)") }
        if let link = payLink.flatMap(PayLink.clean) { lines.append("Pay online: \(link)") }
        if let portalURL { lines.append(""); lines.append("See all your bills and this winter's visits: \(portalURL)") }
        lines.append("")
        lines.append(company)
        lines.append("You are getting this because you agreed to messages from \(company). To stop them, tell \(company) and they will turn them off.")
        let subject = StormBroadcast.clean("Invoice \(invoice.number) from \(company): \(invoice.total.formatted) due \(f.string(from: invoice.dueDate))")
        return PlannedMessage(siteID: site.id, customerID: customer.id, channel: .email, to: customer.email, subject: subject,
                              body: lines.joined(separator: "\n"), sendAfter: Date())
    }
}

extension AppData {
    /// Call after a visit is recorded. Depending on the owner's choice it makes a draft invoice, or a draft plus an
    /// email to send. It bills only storms not yet billed, never a skipped visit, and never the whole season at the
    /// first push (a seasonal base is billed on its own, not when a stop is completed).
    public mutating func autoInvoice(afterVisit record: VisitRecord, now: Date, calendar: Calendar = .current) -> AutoInvoiceOutcome {
        let mode = profile.invoiceAutomation
        guard mode != .off else { return AutoInvoiceOutcome(invoice: nil, message: nil, note: "Automatic invoices are off.") }
        guard record.status == .completed else { return AutoInvoiceOutcome(invoice: nil, message: nil, note: "This visit was skipped, so nothing is billed.") }
        guard let site = sites.first(where: { $0.id == record.siteID }), let contract = contracts.last(where: { $0.siteID == site.id }),
              let customer = customers.first(where: { $0.id == site.customerID }) else {
            return AutoInvoiceOutcome(invoice: nil, message: nil, note: "This site has no contract, so nothing was invoiced.")
        }
        let visits = visitLog.records(forSite: site.id).map { $0.asBillingVisit() }
        let next = InvoicePlanner.nextBilling(terms: contract.terms, visits: visits, existing: invoices.filter { $0.siteID == site.id }, includeSeasonalBase: false)
        let number = InvoiceNumbering.next(existing: invoices.map(\.number))
        let invoice = Invoice.fromBilling(next.result, number: number, customerID: customer.id, siteID: site.id, issueDate: now, netDays: profile.netDays)
        guard !invoice.lines.isEmpty, invoice.total.cents > 0 else {
            return AutoInvoiceOutcome(invoice: nil, message: nil, note: "Nothing to bill for this stop under this contract.")
        }
        invoices.append(invoice)
        guard mode == .send else {
            return AutoInvoiceOutcome(invoice: invoice, message: nil, note: "Draft invoice \(number) created for \(invoice.total.formatted).")
        }
        let optedOut = customer.optedOutAt != nil
        guard !optedOut, customer.emailConsent, ContactValidation.isValidEmail(customer.email) else {
            return AutoInvoiceOutcome(invoice: invoice, message: nil, note: "Draft invoice \(number) created. It was not emailed because this client has not agreed to messages or has no valid email.")
        }
        let base = broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = portalLinks.first { $0.siteID == site.id }?.token
        let portal = (RoutingServerSettings.validatedURL(base) != nil && token != nil) ? "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/c/\(token!)" : nil
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your snow crew" : companyName
        var message = InvoiceMessage.compose(invoice: invoice, customer: customer, site: site, company: company, portalURL: portal,
                                             howToPay: profile.paymentInstructions, payLink: profile.payLink, calendar: calendar)
        if let pdf = invoicePDF(number: number, calendar: calendar) { message.attachment = EmailAttachment(filename: pdf.filename, data: pdf.data) }
        return AutoInvoiceOutcome(invoice: invoice, message: message, note: "Invoice \(number) is ready to email to the client.")
    }

    /// Call once the invoice email has really gone out. A failed send leaves the invoice a draft.
    public mutating func markInvoiceSent(number: String, at date: Date) throws {
        guard let i = invoices.firstIndex(where: { $0.number == number }) else { throw OperationError.notFound }
        try invoices[i].markSent(at: date)
    }
}
