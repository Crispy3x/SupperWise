#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Bill a client in a few taps: pick the client, tap what you did, create the invoice. Works with no server.
/// Once created, the sheet turns into the normal invoice screen (email, share the PDF, mark paid).
struct QuickInvoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var customerID: UUID?
    @State private var siteID: UUID?
    @State private var newAddress = ""
    /// How many of each service, by service id. Zero or missing means not picked.
    @State private var quantities: [UUID: Int] = [:]
    /// Price for this invoice only, in dollars, when changed from the price list.
    @State private var prices: [UUID: Double] = [:]
    @State private var note = ""
    @State private var problem: String?
    @State private var createdNumber: String?
    @State private var addingClient = false

    private var tint: Color { Theme.accent(model.data.profile.accentColor) }

    private var services: [ServicePrice] {
        model.data.priceList.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var clientSites: [Site] {
        guard let customerID else { return [] }
        return model.data.sites.filter { $0.customerID == customerID }
    }

    private var clientOptions: [(UUID?, String)] {
        let sorted = model.data.customers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [(nil, "Choose")] + sorted.map { (c: Customer) -> (UUID?, String) in (c.id, c.name) }
    }

    private var siteOptions: [(UUID?, String)] {
        clientSites.map { (s: Site) -> (UUID?, String) in (s.id, s.address) }
    }

    private var picks: [QuickInvoicePick] {
        services.compactMap { s in
            let qty = quantities[s.id] ?? 0
            guard qty > 0 else { return nil }
            var service = s
            if let dollars = prices[s.id] { service.price = Self.money(dollars) }
            return QuickInvoicePick(service: service, quantity: qty)
        }
    }

    private var total: Money { QuickInvoice.total(picks) }

    private var canCreate: Bool {
        customerID != nil && !picks.isEmpty && total.cents > 0
            && (!clientSites.isEmpty || !newAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var dueText: String {
        let days = model.data.profile.netDays
        return days <= 0 ? "On receipt" : "In \(days) day\(days == 1 ? "" : "s")"
    }

    static func money(_ dollars: Double) -> Money { Money(cents: Int((max(dollars, 0) * 100).rounded())) }

    var body: some View {
        if let createdNumber {
            InvoiceDetailSheet(number: createdNumber)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Quick invoice").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                clientCard
                servicesCard
                CardGroup(title: "Note") {
                    PillNotes(label: "Note on the invoice", placeholder: "Thanks for your business!", text: $note)
                }
                CardGroup(footer: "Next you can email it, share the PDF, or mark it paid.") {
                    FactRow(label: "Total", value: total.formatted)
                    RowDivider()
                    FactRow(label: "Due", value: dueText)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryActionButton(title: "Create invoice", icon: "doc.badge.plus") { create() }
                    .disabled(!canCreate).opacity(canCreate ? 1 : 0.4)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .onAppear {
            if customerID == nil, model.data.customers.count == 1 { customerID = model.data.customers.first?.id }
            siteID = clientSites.first?.id
        }
        .onChange(of: customerID) {
            siteID = clientSites.first?.id
            newAddress = ""
            problem = nil
        }
        .sheet(isPresented: $addingClient) {
            AddCustomerSheet(onCreated: { id in customerID = id })
        }
    }

    @ViewBuilder private var clientCard: some View {
        CardGroup(title: "Client") {
            if model.data.customers.isEmpty {
                Text(model.data.can(.editClients) ? "No clients yet. Add your first one here." : "No clients yet. Ask the owner to add one.")
                    .foregroundStyle(.secondary)
            } else {
                PillMenu(label: "Client", required: true, options: clientOptions, selection: $customerID)
            }
            if customerID != nil {
                if clientSites.count > 1 {
                    PillMenu(label: "Address", options: siteOptions, selection: $siteID)
                } else if clientSites.isEmpty {
                    PillField(label: "Service address", required: true, placeholder: "14 Elm Ave, Minneapolis", text: $newAddress)
                }
            }
            if model.data.can(.editClients) {
                SecondaryActionButton(title: "Add a new client", icon: "person.badge.plus") { addingClient = true }
            }
        }
    }

    @ViewBuilder private var servicesCard: some View {
        CardGroup(title: "What you did", footer: services.isEmpty ? nil : "Tap each service you did. Prices come from Settings > Your services and prices.") {
            if services.isEmpty {
                Text("No services on your price list yet. Add them in Settings > Your services and prices.").foregroundStyle(.secondary)
            }
            ForEach(Array(services.enumerated()), id: \.element.id) { index, s in
                if index > 0 { RowDivider() }
                serviceRow(s)
            }
        }
    }

    @ViewBuilder private func serviceRow(_ s: ServicePrice) -> some View {
        let on = (quantities[s.id] ?? 0) > 0
        Button {
            quantities[s.id] = on ? 0 : 1
            problem = nil
        } label: {
            HStack(spacing: 14) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(on ? tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(s.price.formatted) \(s.unit.title)").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if on, let qty = quantities[s.id], qty > 0 {
                    Text(Self.lineTotal(picks: picks, id: s.id).formatted).font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.primary).accessibilityLabel("\(qty) for \(Self.lineTotal(picks: picks, id: s.id).formatted)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        if on {
            PillStepper(label: "How many", value: quantityBinding(s.id), range: 1...99, step: 1, format: { "\(Int($0))" })
            PillStepper(label: "Price each", value: priceBinding(s), range: 0...20_000, step: 5, format: { Self.money($0).formatted })
        }
    }

    private static func lineTotal(picks: [QuickInvoicePick], id: UUID) -> Money {
        QuickInvoice.total(picks.filter { $0.service.id == id })
    }

    private func quantityBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { Double(quantities[id] ?? 1) }, set: { quantities[id] = max(Int($0.rounded()), 1) })
    }

    private func priceBinding(_ s: ServicePrice) -> Binding<Double> {
        Binding(get: { prices[s.id] ?? Double(s.price.cents) / 100 }, set: { prices[s.id] = max($0, 0) })
    }

    private func create() {
        guard let customerID else { problem = QuickInvoiceError.clientNotFound.message; return }
        let result = model.createQuickInvoice(customerID: customerID, siteID: siteID, newAddress: newAddress, picks: picks, note: note)
        if let number = result.number {
            createdNumber = number
        } else {
            problem = result.problem
        }
    }
}

/// Home: "Send your first invoice" until the first invoice exists, then a smaller Quick invoice row.
struct HomeInvoiceCard: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        Group {
            if model.data.can(.viewRevenue) {
                if model.data.needsFirstInvoice {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                IconTile(icon: "doc.text.fill", tint: tint, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Send your first invoice").font(.title3.bold())
                                    Text("Pick a client, tap what you did, and get a PDF to send. It takes about a minute.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            PrimaryActionButton(title: "Quick invoice", icon: "bolt.fill") { showing = true }
                        }
                    }
                } else {
                    Card {
                        Button { showing = true } label: {
                            CardLinkRow(icon: "bolt.fill", tint: tint, title: "Quick invoice", detail: "Bill a client in a few taps")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showing) { QuickInvoiceSheet() }
    }
}

/// The Quick invoice button at the top of the Invoices screen.
struct InvoicesQuickInvoiceButton: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        Group {
            if model.data.can(.viewRevenue) {
                PrimaryActionButton(title: "Quick invoice", icon: "bolt.fill") { showing = true }
            }
        }
        .sheet(isPresented: $showing) { QuickInvoiceSheet() }
    }
}

/// Settings card: the services the owner sells and what each costs. Quick invoice uses this list.
struct ServicePricesCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing: UUID?
    @State private var confirmingReset = false

    private var canEdit: Bool { model.data.can(.manageSettings) }

    var body: some View {
        if canEdit || model.data.can(.viewRevenue) {
            CardGroup(title: "Your services and prices",
                      footer: "Quick invoice uses these prices. You can still change the price on any one invoice.") {
                let list = model.data.priceList
                if list.isEmpty { Text("No services yet.").foregroundStyle(.secondary) }
                ForEach(Array(list.enumerated()), id: \.element.id) { index, s in
                    if index > 0 { RowDivider() }
                    if canEdit && editing == s.id { editor(s) } else { row(s) }
                }
                if canEdit {
                    RowDivider()
                    SecondaryActionButton(title: "Add a service", icon: "plus") {
                        editing = model.data.addService()
                        model.save()
                    }
                    if model.data.servicePrices != nil {
                        SecondaryActionButton(title: "Use the suggested prices", icon: "arrow.counterclockwise") { confirmingReset = true }
                    }
                }
            }
            .alert("Go back to the suggested prices?", isPresented: $confirmingReset) {
                Button("Use suggested prices", role: .destructive) {
                    editing = nil
                    model.data.resetPriceList()
                    model.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your own services and prices are replaced by the suggested list for the work you do.")
            }
        }
    }

    @ViewBuilder private func row(_ s: ServicePrice) -> some View {
        if canEdit {
            Button { editing = s.id } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name.isEmpty ? "Unnamed service" : s.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Text(s.unit.title).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(s.price.formatted).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change this service")
        } else {
            FactRow(label: s.name, value: "\(s.price.formatted) \(s.unit.title)")
        }
    }

    @ViewBuilder private func editor(_ s: ServicePrice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PillField(label: "Service", placeholder: "Driveway push", text: Binding(
                get: { current(s.id)?.name ?? "" },
                set: { value in model.updateService(id: s.id) { $0.name = value } }))
            PillStepper(label: "Price", value: Binding(
                get: { Double(current(s.id)?.price.cents ?? 0) / 100 },
                set: { value in model.updateService(id: s.id) { $0.price = QuickInvoiceSheet.money(value) } }),
                range: 0...20_000, step: 5, format: { QuickInvoiceSheet.money($0).formatted })
            PillMenu(label: "Charged", options: unitOptions, selection: Binding<PriceUnit>(
                get: { current(s.id)?.unit ?? PriceUnit.visit },
                set: { value in model.updateService(id: s.id) { $0.unit = value } }))
            HStack(spacing: 12) {
                SecondaryActionButton(title: "Remove", icon: "trash") {
                    editing = nil
                    model.data.removeService(id: s.id)
                    model.save()
                }
                PrimaryActionButton(title: "Done") { editing = nil }
            }
        }
    }

    private func current(_ id: UUID) -> ServicePrice? { model.data.priceList.first { $0.id == id } }

    /// "Per visit", "Per season" and so on.
    private var unitOptions: [(PriceUnit, String)] {
        PriceUnit.allCases.map { (u: PriceUnit) -> (PriceUnit, String) in (u, u.title.prefix(1).uppercased() + u.title.dropFirst()) }
    }
}
#endif
