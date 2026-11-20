import Foundation

/// Makes an invoice as a PDF file with no outside libraries, so it works the same on every device and can be tested.
/// The pay link is printed and also made tappable, so the client can pay straight from the PDF.
public enum InvoicePDF {
    public struct Content: Equatable, Sendable {
        public var company: String
        public var number: String
        public var issueDate: String
        public var dueDate: String
        public var billToName: String
        public var billToAddress: String
        /// Description and amount, already formatted, for example ("Push, Nov 18", "$60.00").
        public var lines: [(description: String, amount: String)]
        public var total: String
        public var paid: String?
        public var balance: String
        public var howToPay: String
        public var payLink: String?
        public var portalURL: String?
        public var notes: String

        public init(company: String, number: String, issueDate: String, dueDate: String, billToName: String, billToAddress: String,
                    lines: [(description: String, amount: String)], total: String, paid: String? = nil, balance: String,
                    howToPay: String = "", payLink: String? = nil, portalURL: String? = nil, notes: String = "") {
            self.company = company; self.number = number; self.issueDate = issueDate; self.dueDate = dueDate
            self.billToName = billToName; self.billToAddress = billToAddress; self.lines = lines; self.total = total
            self.paid = paid; self.balance = balance; self.howToPay = howToPay; self.payLink = payLink
            self.portalURL = portalURL; self.notes = notes
        }

        public static func == (a: Content, b: Content) -> Bool {
            a.company == b.company && a.number == b.number && a.total == b.total && a.balance == b.balance && a.lines.count == b.lines.count
        }
    }

    // MARK: text helpers

    /// The PDF's standard fonts only know basic Latin, so accents are folded away and anything else becomes "?".
    static func safe(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        return String(folded.unicodeScalars.map { s -> Character in
            s.value >= 32 && s.value < 127 ? Character(s) : (s == "\n" || s == "\t" ? " " : "?")
        })
    }

    static func escape(_ text: String) -> String {
        safe(text).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    }

    /// Breaks text into lines that fit, at spaces where possible. Helvetica is about half an em wide per character on average.
    static func wrap(_ text: String, maxChars: Int) -> [String] {
        let words = safe(text).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var lines: [String] = [], current = ""
        for var word in words {
            while word.count > maxChars { // a very long word (a web address) is cut rather than run off the page
                if !current.isEmpty { lines.append(current); current = "" }
                lines.append(String(word.prefix(maxChars))); word = String(word.dropFirst(maxChars))
            }
            if current.isEmpty { current = word }
            else if current.count + 1 + word.count <= maxChars { current += " " + word }
            else { lines.append(current); current = word }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: pages

    private struct Page {
        var ops = ""
        var links: [(rect: (Double, Double, Double, Double), url: String)] = []
        mutating func text(_ x: Double, _ y: Double, _ size: Double, _ font: String, _ s: String) {
            ops += "BT /\(font) \(size) Tf \(fmt(x)) \(fmt(y)) Td (\(InvoicePDF.escape(s))) Tj ET\n"
        }
        /// Amounts are set in Courier, where every character is exactly 0.6 em wide, so they line up on the right.
        mutating func amount(rightX: Double, _ y: Double, _ size: Double, _ s: String, bold: Bool = false) {
            let t = InvoicePDF.safe(s)
            text(rightX - Double(t.count) * size * 0.6, y, size, bold ? "F4" : "F3", t)
        }
        mutating func rule(_ y: Double, from: Double = 54, to: Double = 558) { ops += "0.8 w \(fmt(from)) \(fmt(y)) m \(fmt(to)) \(fmt(y)) l S\n" }
        mutating func fmt(_ v: Double) -> String { Self.f(v) }
        static func f(_ v: Double) -> String { String(format: "%.2f", v) }
    }
    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    public static let maxLines = 400

    public static func make(_ c: Content) -> Data {
        var pages: [Page] = []
        var page = Page()
        var y = 740.0
        let left = 54.0, right = 558.0

        func header() {
            page.text(left, y, 20, "F2", c.company.isEmpty ? "Invoice" : String(c.company.prefix(48)))
            page.text(right - 120, y, 24, "F2", "INVOICE")
            y -= 26
            page.text(right - 120, y, 11, "F1", "Number: \(c.number)")
            y -= 15
            page.text(right - 120, y, 11, "F1", "Issued: \(c.issueDate)")
            y -= 15
            page.text(right - 120, y, 11, "F1", "Due: \(c.dueDate)")
            y -= 20
            page.text(left, y + 20, 10, "F2", "BILL TO")
            page.text(left, y + 6, 12, "F1", String(c.billToName.prefix(60)))
            for l in wrap(c.billToAddress, maxChars: 55).prefix(3) { y -= 14; page.text(left, y + 6, 11, "F1", l) }
            y -= 28
            page.text(left, y, 10, "F2", "DESCRIPTION")
            page.text(right - 60, y, 10, "F2", "AMOUNT")
            y -= 6; page.rule(y); y -= 18
        }
        header()

        func newPage() {
            pages.append(page); page = Page(); y = 740
            page.text(left, y, 11, "F2", "Invoice \(c.number) (continued)")
            y -= 24
        }

        for line in c.lines.prefix(maxLines) {
            let parts = wrap(line.description, maxChars: 62)
            let needed = Double(max(parts.count, 1)) * 15 + 4
            if y - needed < 150 { newPage() }
            for (i, part) in parts.enumerated() {
                page.text(left, y, 11, "F1", part)
                if i == 0 { page.amount(rightX: right, y, 11, line.amount) }
                y -= 15
            }
            if parts.isEmpty { y -= 15 }
            y -= 4
        }
        if c.lines.count > maxLines { page.text(left, y, 10, "F1", "(\(c.lines.count - maxLines) more lines not shown)"); y -= 16 }

        if y < 250 { newPage() }
        page.rule(y); y -= 20
        page.text(right - 230, y, 12, "F2", "Total")
        page.amount(rightX: right, y, 12, c.total, bold: true)
        if let paid = c.paid { y -= 18; page.text(right - 230, y, 11, "F1", "Paid"); page.amount(rightX: right, y, 11, "-" + paid.replacingOccurrences(of: "-", with: "")) }
        y -= 20
        page.text(right - 230, y, 13, "F2", "Balance due")
        page.amount(rightX: right, y, 13, c.balance, bold: true)
        y -= 34

        if let link = c.payLink, !link.isEmpty {
            page.text(left, y, 12, "F2", "Pay online"); y -= 16
            let shown = safe(link)
            for (i, part) in wrap(shown, maxChars: 80).enumerated() {
                page.text(left, y, 10, "F1", part)
                if i == 0 { page.links.append((rect: (left, y - 3, right, y + 11), url: link)) }
                y -= 13
            }
            y -= 8
        }
        if !c.howToPay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            page.text(left, y, 12, "F2", "How to pay"); y -= 16
            for l in wrap(c.howToPay, maxChars: 90).prefix(5) { page.text(left, y, 10, "F1", l); y -= 13 }
            y -= 8
        }
        if let portal = c.portalURL, !portal.isEmpty {
            page.text(left, y, 12, "F2", "Your page: bills, visits and requests"); y -= 16
            for (i, part) in wrap(portal, maxChars: 80).enumerated() {
                page.text(left, y, 10, "F1", part)
                if i == 0 { page.links.append((rect: (left, y - 3, right, y + 11), url: portal)) }
                y -= 13
            }
            y -= 8
        }
        if !c.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            page.text(left, y, 10, "F2", "NOTES"); y -= 14
            for l in wrap(c.notes, maxChars: 95).prefix(6) { page.text(left, y, 10, "F1", l); y -= 13 }
        }
        pages.append(page)
        return assemble(pages)
    }

    /// Writes the objects and the cross-reference table the PDF format needs.
    private static func assemble(_ pages: [Page]) -> Data {
        // Fixed objects: 1 catalog, 2 page tree, 3..6 fonts. Then for each page: the page, its content, and one object per link.
        var objects: [String] = []
        objects.append("<< /Type /Catalog /Pages 2 0 R >>")
        objects.append("PAGES")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold /Encoding /WinAnsiEncoding >>")
        var kids: [String] = []
        for p in pages {
            let pageNumber = objects.count + 1
            let contentNumber = pageNumber + 1
            var annotRefs: [String] = []
            var annotObjects: [String] = []
            for (i, l) in p.links.enumerated() {
                annotRefs.append("\(contentNumber + 1 + i) 0 R")
                let r = l.rect
                annotObjects.append("<< /Type /Annot /Subtype /Link /Rect [\(fmt(r.0)) \(fmt(r.1)) \(fmt(r.2)) \(fmt(r.3))] /Border [0 0 0] /A << /S /URI /URI (\(escape(l.url))) >> >>")
            }
            let annots = annotRefs.isEmpty ? "" : " /Annots [\(annotRefs.joined(separator: " "))]"
            kids.append("\(pageNumber) 0 R")
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R /F4 6 0 R >> >> /Contents \(contentNumber) 0 R\(annots) >>")
            objects.append("<< /Length \(p.ops.utf8.count) >>\nstream\n\(p.ops)endstream")
            objects.append(contentsOf: annotObjects)
        }
        objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"

        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}

extension AppData {
    /// The invoice as a PDF, filled in from the saved data. Nil if the invoice or its client cannot be found.
    public func invoicePDF(number: String, calendar: Calendar = .current) -> (filename: String, data: Data)? {
        guard let invoice = invoices.first(where: { $0.number.caseInsensitiveCompare(number) == .orderedSame }),
              let customer = customers.first(where: { $0.id == invoice.customerID }),
              let site = sites.first(where: { $0.id == invoice.siteID }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = "MMM d, yyyy"
        let base = broadcastSettings.portalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = portalLinks.first { $0.siteID == site.id }?.token
        let portal = (RoutingServerSettings.validatedURL(base) != nil && token != nil) ? "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/c/\(token!)" : nil
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = InvoicePDF.Content(
            company: company, number: invoice.number, issueDate: f.string(from: invoice.issueDate), dueDate: f.string(from: invoice.dueDate),
            billToName: customer.name, billToAddress: site.address,
            lines: invoice.lines.map { ($0.description, $0.amount.formatted) }, total: invoice.total.formatted,
            paid: invoice.paid.cents > 0 ? invoice.paid.formatted : nil, balance: invoice.balance.formatted,
            howToPay: profile.paymentInstructions, payLink: profile.payLink.flatMap(PayLink.clean), portalURL: portal, notes: invoice.notes)
        let safeNumber = String(invoice.number.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(30))
        return ("Invoice-\(safeNumber.isEmpty ? "invoice" : safeNumber).pdf", InvoicePDF.make(content))
    }
}
