import XCTest
@testable import RidgelineCore

final class InvoicePDFTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func world(lines: Int = 2) -> AppData {
        var d = AppData()
        d.companyName = "Ridge Plow & Salt (LLC)"
        let c = Customer(name: "José Müller", email: "jose@example.com", emailConsent: true)
        let s = Site(customerID: c.id, address: "14 Elm Ave, Apt 2, Minneapolis, MN 55401")
        d.customers = [c]; d.sites = [s]
        d.profile.payLink = "https://buy.stripe.com/abc123"
        d.profile.paymentInstructions = "Check to Ridge Plow, or Zelle to pay@ridgeplow.com"
        d.broadcastSettings.portalBaseURL = "https://track.ridgeplow.com"
        d.ensurePortalLinks(now: now)
        d.invoices = [Invoice(number: "INV-0007", customerID: c.id, siteID: s.id, issueDate: now, dueDate: now.addingTimeInterval(14 * 86_400),
                              lines: (1...lines).map { InvoiceLineItem(description: "Push, storm \($0): driveway and walk, salt applied (twice)", amount: Money(cents: 6000 + $0)) })]
        return d
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    func testItIsAValidPDFWithCorrectOffsets() throws {
        let (name, data) = try XCTUnwrap(world().invoicePDF(number: "inv-0007"))
        XCTAssertEqual(name, "Invoice-INV-0007.pdf")
        let t = text(data)
        XCTAssertTrue(t.hasPrefix("%PDF-1.4")); XCTAssertTrue(t.hasSuffix("%%EOF\n"))
        // Every object starts exactly where the cross-reference table says it does.
        let lines = t.components(separatedBy: "\n")
        let xrefIndex = try XCTUnwrap(lines.firstIndex(of: "xref"))
        let count = Int(try XCTUnwrap(lines[xrefIndex + 1].split(separator: " ").last))!
        let bytes = Array(data)
        for n in 1..<count {
            let entry = lines[xrefIndex + 2 + n]
            let offset = Int(entry.prefix(10))!
            let head = String(decoding: bytes[offset..<min(offset + 12, bytes.count)], as: UTF8.self)
            XCTAssertTrue(head.hasPrefix("\(n) 0 obj"), "object \(n) at \(offset): \(head)")
        }
        let start = Int(try XCTUnwrap(lines.firstIndex(of: "startxref").map { lines[$0 + 1] }))!
        XCTAssertEqual(String(decoding: bytes[start..<start + 4], as: UTF8.self), "xref")
    }

    func testItCarriesTheDetailsAndATappablePayLink() throws {
        let t = text(try XCTUnwrap(world().invoicePDF(number: "INV-0007")).data)
        for needle in ["INV-0007", "Jose Muller", "14 Elm Ave", "$60.01", "$60.02", "$120.03", "Balance due", "Pay online", "https://buy.stripe.com/abc123",
                       "How to pay", "https://track.ridgeplow.com/c/", "/Subtype /Link", "/URI (https://buy.stripe.com/abc123)"] {
            XCTAssertTrue(t.contains(needle), needle)
        }
        XCTAssertTrue(t.contains("Ridge Plow & Salt \\(LLC\\)"))                      // brackets are escaped so they cannot break the file
    }

    func testAPaymentShowsOnTheInvoice() throws {
        var d = world()
        try d.invoices[0].record(ManualPayment(amount: Money(cents: 5000), date: now, method: .cash))
        let t = text(try XCTUnwrap(d.invoicePDF(number: "INV-0007")).data)
        XCTAssertTrue(t.contains("Paid")); XCTAssertTrue(t.contains("-$50.00")); XCTAssertTrue(t.contains("$70.03"))
    }

    func testNoPayLinkMeansNoLinkSection() throws {
        var d = world(); d.profile.payLink = nil; d.broadcastSettings.portalBaseURL = ""
        let t = text(try XCTUnwrap(d.invoicePDF(number: "INV-0007")).data)
        XCTAssertFalse(t.contains("Pay online")); XCTAssertFalse(t.contains("/Subtype /Link"))
        d.profile.payLink = "https://evil.example.com/pay"                            // an unsafe link is never put in a PDF
        XCTAssertFalse(text(try XCTUnwrap(d.invoicePDF(number: "INV-0007")).data).contains("evil.example.com"))
    }

    func testManyLinesRunOntoMorePages() throws {
        let t = text(try XCTUnwrap(world(lines: 120).invoicePDF(number: "INV-0007")).data)
        let pages = t.components(separatedBy: "/Type /Page ").count - 1
        XCTAssertGreaterThan(pages, 3)
        XCTAssertTrue(t.contains("/Count \(pages)"))
        XCTAssertTrue(t.contains("continued"))
    }

    func testTextIsKeptSafe() {
        XCTAssertEqual(InvoicePDF.safe("Café \u{1F600} naïve\nline"), "Cafe ? naive line")
        XCTAssertEqual(InvoicePDF.escape("a(b)c\\d"), "a\\(b\\)c\\\\d")
        XCTAssertEqual(InvoicePDF.wrap("aaaa bbbb cccc", maxChars: 9), ["aaaa bbbb", "cccc"])
        XCTAssertEqual(InvoicePDF.wrap(String(repeating: "x", count: 25), maxChars: 10).count, 3)               // a very long word is cut
        XCTAssertEqual(InvoicePDF.wrap("", maxChars: 10), [])
    }

    func testUnknownInvoiceGivesNothing() { XCTAssertNil(world().invoicePDF(number: "INV-9999")) }

    /// Writes a sample file when asked, so an outside PDF reader can check it: PDF_OUT=/path swift test --filter testWriteSample
    func testWriteSample() throws {
        guard let path = ProcessInfo.processInfo.environment["PDF_OUT"] else { return }
        var d = world(lines: 70)
        try d.invoices[0].record(ManualPayment(amount: Money(cents: 5000), date: now, method: .cash))
        try XCTUnwrap(d.invoicePDF(number: "INV-0007")).data.write(to: URL(fileURLWithPath: path))
    }
}
