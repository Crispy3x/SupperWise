#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct QuotesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false
    @State private var message: String?

    var body: some View {
        ScreenStack {
            AppPage {
                PrimaryActionButton(title: "New quote", icon: "plus") { showingNew = true }
                if model.data.quotes.isEmpty {
                    EmptyCard(icon: "doc.text", title: "No quotes yet", message: "Add one to send a price to a customer.")
                }
                ForEach(model.data.quotes) { quote in
                    quoteCard(quote)
                }
                if let message {
                    Card { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .sheet(isPresented: $showingNew) { NewQuoteSheet() }
        }
    }

    @ViewBuilder private func quoteCard(_ quote: Quote) -> some View {
        let status = quote.status(now: Date())
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(quote.number).font(.title3.weight(.semibold))
                    Spacer()
                    StatusPill(text: status.rawValue.capitalized)
                }
                Text(model.data.customers.first { $0.id == quote.customerID }?.name ?? "Unknown customer").font(.headline)
                Text(quote.address).font(.subheadline)
                Text(quote.terms.summary).font(.footnote).foregroundStyle(.secondary)
                if [.draft, .sent].contains(status) {
                    RowDivider()
                    PrimaryActionButton(title: "Accept") {
                        message = model.edit { data in _ = try data.acceptQuote(id: quote.id, now: Date()) }
                            ?? "Accepted. A site and a contract were created for this customer."
                    }
                    HStack(spacing: 10) {
                        if status == .draft {
                            SecondaryActionButton(title: "Mark sent") {
                                message = model.edit { data in
                                    guard let i = data.quotes.firstIndex(where: { $0.id == quote.id }) else { throw OperationError.notFound }
                                    data.quotes[i].markSent(at: Date())
                                }
                            }
                        }
                        SecondaryActionButton(title: "Decline") {
                            message = model.edit { data in
                                guard let i = data.quotes.firstIndex(where: { $0.id == quote.id }) else { throw OperationError.notFound }
                                try data.quotes[i].decline(at: Date())
                            } ?? "Quote declined."
                        }
                    }
                }
            }
        }
    }
}

struct NewQuoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable, Identifiable {
        case perPush = "Per push", seasonal = "Seasonal", hybrid = "Seasonal plus overage"
        var id: String { rawValue }
    }

    @State private var customerID: UUID?
    @State private var address = ""
    @State private var kind: Kind = .perPush
    @State private var rate = 60
    @State private var season = 900
    @State private var included = 8
    @State private var overage = 45
    @State private var validDays = 30
    @State private var notes = ""

    private var terms: ContractTerms {
        switch kind {
        case .perPush: return .perPush(rate: Money(dollars: rate))
        case .seasonal: return .seasonal(total: Money(dollars: season))
        case .hybrid: return .hybrid(seasonalBase: Money(dollars: season), includedPushes: included, overagePerPush: Money(dollars: overage))
        }
    }

    private var range: (low: Money, high: Money) {
        SeasonEstimate.range(terms, mild: .init(pushes: 6), heavy: .init(pushes: 16))
    }

    private var canSave: Bool {
        customerID != nil && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var customerOptions: [(UUID?, String)] {
        var options: [(UUID?, String)] = [(nil, "Choose")]
        options += model.data.customers.map { (c: Customer) -> (UUID?, String) in (c.id, c.name) }
        return options
    }

    private var kindOptions: [(Kind, String)] {
        Kind.allCases.map { (k: Kind) -> (Kind, String) in (k, k.rawValue) }
    }

    private func asDouble(_ value: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New quote").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(title: "Customer") {
                    if model.data.customers.isEmpty {
                        Text("Add a customer first.").foregroundStyle(.secondary)
                    } else {
                        PillMenu(label: "Customer", required: true, options: customerOptions, selection: $customerID)
                    }
                    PillField(label: "Service address", required: true, placeholder: "14 Elm Ave, Minneapolis", text: $address)
                }
                CardGroup(title: "Price") {
                    PillMenu(label: "Type", options: kindOptions, selection: $kind)
                    if kind == .perPush {
                        PillStepper(label: "Price per push", value: asDouble($rate), range: 10...2000, step: 5, format: { "$\(Int($0))" })
                    }
                    if kind != .perPush {
                        PillStepper(label: "Season price", value: asDouble($season), range: 50...50_000, step: 50, format: { "$\(Int($0))" })
                    }
                    if kind == .hybrid {
                        PillStepper(label: "Pushes included", value: asDouble($included), range: 1...60, step: 1, format: { "\(Int($0))" })
                        PillStepper(label: "Each push after that", value: asDouble($overage), range: 10...2000, step: 5, format: { "$\(Int($0))" })
                    }
                    PillStepper(label: "Valid for", value: asDouble($validDays), range: 1...120, step: 1, format: { "\(Int($0)) days" })
                }
                CardGroup(title: "What the customer could pay") {
                    Text("A mild winter (6 pushes): \(range.low.formatted). A heavy winter (16 pushes): \(range.high.formatted).")
                    Text("Estimates only. Real cost depends on how much it snows.").font(.footnote).foregroundStyle(.secondary)
                }
                CardGroup(title: "Notes") {
                    PillNotes(label: "Note", placeholder: "Optional note", text: $notes)
                }
                PrimaryActionButton(title: "Save quote") { save() }
                    .disabled(!canSave).opacity(canSave ? 1 : 0.4)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }

    private func save() {
        guard let customerID else { return }
        _ = model.edit { data in
            let number = InvoiceNumbering.next(existing: data.quotes.map(\.number), prefix: "Q-")
            data.quotes.append(Quote(number: number, customerID: customerID, address: address.trimmingCharacters(in: .whitespacesAndNewlines), season: AppModel.currentSeason(),
                                     terms: terms, createdAt: Date(), validDays: validDays, notes: notes))
        }
        dismiss()
    }
}
#endif
