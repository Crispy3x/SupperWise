#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct QuotesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if model.data.quotes.isEmpty {
                    Section {
                        Text("No quotes yet. Add one to send a price to a customer.")
                            .foregroundStyle(.secondary)
                        Button("New quote") { showingNew = true }
                    }
                }
                ForEach(model.data.quotes) { quote in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(quote.number).font(.headline)
                            Spacer()
                            Text(quote.status(now: Date()).rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.data.customers.first { $0.id == quote.customerID }?.name ?? "Unknown customer").font(.subheadline)
                        Text(quote.address).font(.subheadline)
                        Text(quote.terms.summary).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            if quote.status(now: Date()) == .draft {
                                Button("Mark sent") {
                                    message = model.edit { data in
                                        guard let i = data.quotes.firstIndex(where: { $0.id == quote.id }) else { throw OperationError.notFound }
                                        data.quotes[i].markSent(at: Date())
                                    }
                                }
                            }
                            if [.draft, .sent].contains(quote.status(now: Date())) {
                                Button("Accept") {
                                    message = model.edit { data in _ = try data.acceptQuote(id: quote.id, now: Date()) }
                                        ?? "Accepted. A site and a contract were created for this customer."
                                }
                                Button("Decline") {
                                    message = model.edit { data in
                                        guard let i = data.quotes.firstIndex(where: { $0.id == quote.id }) else { throw OperationError.notFound }
                                        try data.quotes[i].decline(at: Date())
                                    } ?? "Quote declined."
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                    }
                }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Quotes")
            .toolbar {
                Button { showingNew = true } label: { Label("New quote", systemImage: "plus") }
            }
            .sheet(isPresented: $showingNew) { NewQuoteSheet() }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    if model.data.customers.isEmpty {
                        Text("Add a customer first.").foregroundStyle(.secondary)
                    } else {
                        Picker("Customer", selection: $customerID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(model.data.customers) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    TextField("Service address", text: $address)
                }
                Section("Price") {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if kind == .perPush { Stepper("Price per push: $\(rate)", value: $rate, in: 10...2000, step: 5) }
                    if kind != .perPush { Stepper("Season price: $\(season)", value: $season, in: 50...50_000, step: 50) }
                    if kind == .hybrid {
                        Stepper("Pushes included: \(included)", value: $included, in: 1...60)
                        Stepper("Each push after that: $\(overage)", value: $overage, in: 10...2000, step: 5)
                    }
                    Stepper("Valid for \(validDays) days", value: $validDays, in: 1...120)
                }
                Section("What the customer could pay") {
                    Text("A mild winter (6 pushes): \(range.low.formatted). A heavy winter (16 pushes): \(range.high.formatted).")
                    Text("Estimates only. Real cost depends on how much it snows.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Notes") { TextField("Optional note", text: $notes) }
            }
            .navigationTitle("New quote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(customerID == nil || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
