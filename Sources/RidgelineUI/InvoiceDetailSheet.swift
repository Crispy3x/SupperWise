#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import RidgelineCore

/// The invoice as a PDF file that can be shared from the share sheet, built only when someone shares it.
struct InvoiceFile: Transferable {
    let name: String
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.name }
    }
}

/// One invoice: what it says, who it is for, and the steps that take it from created to paid.
/// Emailing sends the invoice as a PDF with the owner's pay links, and only after a tap on Send.
struct InvoiceDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let number: String
    @State private var message: String?
    @State private var confirming = false
    @State private var working = false

    private var invoice: Invoice? { model.data.invoices.first { $0.number == number } }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
                Spacer()
                Text(number).font(.title3.weight(.semibold))
                Spacer()
                Color.clear.frame(width: 50, height: 50)
            }
            if let inv = invoice { content(inv) } else { Text("This invoice no longer exists.").foregroundStyle(.secondary); Spacer() }
        }
        .padding(.horizontal, 18).padding(.top, 16)
        .background(Look.sheet.ignoresSafeArea())
    }

    @ViewBuilder private func content(_ inv: Invoice) -> some View {
        let client = model.data.customers.first { $0.id == inv.customerID }
        let place = model.data.sites.first { $0.id == inv.siteID }?.address ?? ""
        let plan = model.data.invoiceEmail(number: inv.number)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(client?.name ?? "Client").font(.title2.bold()); Spacer(); StatusPill(text: inv.isVoid ? "Void" : inv.status(now: Date()).rawValue.capitalized, color: inv.isVoid ? .gray : .blue) }
                        if !place.isEmpty { Text(place).font(.callout).foregroundStyle(.secondary) }
                        Divider()
                        ForEach(inv.lines) { l in HStack(alignment: .top) { Text(l.description).font(.callout); Spacer(); Text(l.amount.formatted).font(.callout.monospacedDigit()) } }
                        Divider()
                        HStack { Text("Total").font(.headline); Spacer(); Text(inv.total.formatted).font(.headline) }
                        if inv.paid.cents > 0 { HStack { Text("Paid").foregroundStyle(.secondary); Spacer(); Text("-" + inv.paid.formatted).foregroundStyle(.green) } }
                        HStack { Text("Balance due").font(.headline); Spacer(); Text(inv.balance.formatted).font(.headline) }
                        Text("Due \(inv.dueDate.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.data.profile.payLink == nil {
                    Label("Add your payment link in Settings so this invoice carries a Pay online link.", systemImage: "link").font(.callout).foregroundStyle(.orange)
                } else {
                    Label("The emailed PDF and message include your pay link.", systemImage: "link").font(.callout).foregroundStyle(.secondary)
                }
                if !inv.isVoid && inv.balance.cents > 0 {
                    switch plan {
                    case .ready(let m):
                        Button { confirming = true } label: {
                            Label(working ? "Sending..." : "Email invoice as PDF", systemImage: "paperplane.fill").font(.title3.weight(.semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 18).background(Theme.accent(model.data.profile.accentColor), in: Capsule())
                        }
                        .buttonStyle(.plain).disabled(working)
                        .alert("Email invoice \(inv.number)?", isPresented: $confirming) {
                            Button("Send") { send(inv.number) }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("It goes to \(m.to) as a PDF with your pay links.") }
                    case .problem(let why):
                        Label(why, systemImage: "info.circle").font(.callout).foregroundStyle(.orange)
                    }
                    if let pdf = model.data.invoicePDF(number: inv.number) {
                        ShareLink(item: InvoiceFile(name: pdf.filename, data: pdf.data), preview: SharePreview(pdf.filename)) {
                            Label("Share the PDF another way", systemImage: "square.and.arrow.up").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Look.pill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 12) {
                        if inv.sentAt == nil {
                            smallButton("Mark sent") { message = model.updateInvoice(id: inv.id) { try $0.markSent(at: Date()) } }
                        }
                        smallButton("Record payment in full") {
                            message = model.updateInvoice(id: inv.id) { try $0.record(ManualPayment(amount: $0.balance, date: Date(), method: .other)) }
                        }
                    }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(.bottom, 30)
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.callout.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14).background(Look.field, in: Capsule()).overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1)) }
            .buttonStyle(.plain)
    }

    private func send(_ number: String) {
        working = true
        Task { message = await model.emailInvoice(number: number); working = false }
    }
}
#endif
